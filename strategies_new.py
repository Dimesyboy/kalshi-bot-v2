from __future__ import annotations
import logging, time, math, requests, functools, os
from typing import Optional
log = logging.getLogger("kalshi_bot.strategies")

try:
    from espn_data import ESPNClient, GameContext, ContextCollection
    STATUS_LIVE="STATUS_IN_PROGRESS"; STATUS_FINAL="STATUS_FINAL"; _ESPN=True
except ImportError:
    _ESPN=False; GameContext=None; log.warning("[Strategies] espn_data not found")

# ---------------------------------------------------------------------------
# Markets the bot is allowed to trade — moneyline and spread only
# No props, totals, halves, quarters, or player stats
# ---------------------------------------------------------------------------
ALLOWED_SERIES = [
    "KXNBAGAME", "KXNBASPREAD",
    "KXMLBGAME", "KXMLBSPREAD",
    "KXATPMATCH", "KXWTAMATCH",
    "KXATPGAME",  "KXWTAGAME",
    "KXATPCHALLENGERMATCH", "KXWTACHALLENGERMATCH",
]

def _allowed(ticker: str) -> bool:
    return any(ticker.startswith(s) for s in ALLOWED_SERIES)

# ---------------------------------------------------------------------------
# ESPN cache
# ---------------------------------------------------------------------------
class ESPNContextCache:
    def __init__(self): self._client=ESPNClient() if _ESPN else None; self._all={}; self._fetched=0.0
    def refresh(self,max_age=50.0):
        if not self._client or time.time()-self._fetched<max_age: return
        try: self._all=self._client.get_all(); self._fetched=time.time()
        except Exception as e: log.warning(f"[ESPN Cache] {e}")
    def find(self,sport,name):
        if not self._client: return None
        col=self._all.get(sport); return col.find_by_name(name) if col else None
    def live_games(self,sport):
        col=self._all.get(sport); return col.live() if col else []
    def summary_log(self):
        for s,c in self._all.items(): log.info(f"[ESPN] {s}: {len(c.live()) if c else 0}/{len(c) if c else 0} live")

# ---------------------------------------------------------------------------
# Portfolio reconciliation
# ---------------------------------------------------------------------------
_settled_cache    = set()
_fills_bootstrapped = False

def _fetch_fills_raw_single(client):
    import urllib3, json as _json, kalshi_python
    fills=[]
    orig=urllib3.PoolManager.urlopen
    def cap(self,method,url,**kw):
        r=orig(self,method,url,**kw)
        if 'fills' in url:
            try: fills.extend(_json.loads(r.data).get('fills',[]) or [])
            except: pass
        return r
    urllib3.PoolManager.urlopen=cap
    try:
        pa=kalshi_python.PortfolioApi(api_client=client); pa.get_fills()
    except: pass
    finally: urllib3.PoolManager.urlopen=orig
    return fills

def _fetch_fills_raw(client):
    import urllib3, json as _json, kalshi_python
    all_fills=[]; cursor=None; page=0; max_pages=20
    while page < max_pages:
        page_fills=[]; next_cursor=[None]
        orig=urllib3.PoolManager.urlopen
        def cap(self,method,url,**kw):
            r=orig(self,method,url,**kw)
            if 'fills' in url:
                try:
                    d=_json.loads(r.data)
                    page_fills.extend(d.get('fills',[]) or [])
                    next_cursor[0]=d.get('cursor','') or ''
                except: pass
            return r
        urllib3.PoolManager.urlopen=cap
        try:
            pa=kalshi_python.PortfolioApi(api_client=client)
            if cursor: pa.get_fills(cursor=cursor)
            else: pa.get_fills()
        except: pass
        finally: urllib3.PoolManager.urlopen=orig
        all_fills.extend(page_fills)
        log.debug(f"[Fills] Page {page+1}: {len(page_fills)} fills")
        if not next_cursor[0] or len(page_fills)==0: break
        cursor=next_cursor[0]; page+=1
    log.info(f"[Fills] Total fetched: {len(all_fills)} fills across {page+1} page(s)")
    return all_fills

def reconcile_positions(open_positions,kalshi_base,client,save_fn,pnl_log,current_date,save_pnl_fn,bot_orders=None):
    global _fills_bootstrapped
    if client is None: return 0.0
    pnl_delta=0.0
    from datetime import datetime,timezone,timedelta
    try:
        if not _fills_bootstrapped:
            fills=_fetch_fills_raw(client)
            _fills_bootstrapped=True
            cutoff=(datetime.now(timezone.utc)-timedelta(days=3)).isoformat()
            fills=[f for f in fills if f.get('created_time','')>=cutoff]
            log.info(f"[Reconcile] Bootstrap: {len(fills)} fills (last 3 days)")
        else:
            fills=_fetch_fills_raw_single(client)
            log.info(f"[Reconcile] Cycle: {len(fills)} recent fills")
    except Exception as e: log.warning(f"[Reconcile] fills fetch failed:{e}"); return 0.0

    bot_orders=bot_orders or set()
    net={}
    for f in sorted(fills,key=lambda x:x.get('created_time','')):
        try:
            ticker=f.get('ticker') or f.get('market_ticker','')
            if not ticker or not _allowed(ticker): continue
            side=f.get('side','yes'); action=f.get('action','buy')
            count=int(float(f.get('count_fp',0) or 0))
            price_d=float(f.get('yes_price_dollars') or f.get('no_price_dollars') or 0)
            price_c=round(price_d*100)
            fee=float(f.get('fee_cost',0) or 0)
            etime=f.get('created_time','')
            eticker=ticker.rsplit('-',1)[0] if '-' in ticker else ticker
            order_id=f.get('order_id','')
            is_bot=order_id in bot_orders if bot_orders else None
            if ticker not in net:
                net[ticker]={'side':side,'net':0,'avg_entry':price_c,
                             'fees':0.0,'entry_time':etime,'event_ticker':eticker,
                             'is_bot':is_bot,'order_ids':set()}
            if order_id:
                net[ticker]['order_ids'].add(order_id)
                if is_bot: net[ticker]['is_bot']=True
                elif net[ticker]['is_bot'] is None: net[ticker]['is_bot']=False
            if action=='buy':
                prev=net[ticker]['net']
                net[ticker]['side']=side
                if prev>=0:
                    total=prev+count
                    net[ticker]['avg_entry']=(net[ticker]['avg_entry']*prev+price_c*count)//max(total,1)
                net[ticker]['net']+=count
                net[ticker]['fees']+=fee
            elif action=='sell':
                net[ticker]['net']-=count
                net[ticker]['fees']+=fee
        except Exception as e: log.debug(f"[Reconcile] fill parse:{e}")

    kt=set(t for t,v in net.items() if v['net']>0)
    log.info(f"[Reconcile] {len(kt)} tickers with net open position")

    for ticker,v in net.items():
        if v['net']<=0: continue
        if ticker in _settled_cache: continue
        side=v['side']; contracts=v['net']
        entry=v['avg_entry']; fees=v['fees']
        if ticker not in open_positions:
            try:
                r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8)
                r.raise_for_status()
                ms=r.json().get("market",{}).get("status","")
                if ms in("settled","finalized"):
                    _settled_cache.add(ticker); continue
            except Exception as e:
                log.warning(f"[Reconcile] market check {ticker}:{e}"); continue
            is_bot=v.get('is_bot'); tag='BOT' if is_bot else ('MANUAL' if is_bot is False else 'UNKNOWN')
            strategy='reconciled' if is_bot else ('manual' if is_bot is False else 'unknown')
            log.info(f"[Reconcile] ADDED [{tag}] {ticker} {side.upper()} @ {entry}c x{contracts}")
            open_positions[ticker]={
                'side':side,'entry_price':entry,'peak_price':entry,'last_bid':entry,
                'contracts':contracts,'strategy':strategy,'entry_time':v['entry_time'],
                'event_ticker':eticker,'reason':'From fills','entry_fee':fees,'is_bot':is_bot,
            }
        else:
            lc=open_positions[ticker].get('contracts',contracts)
            if lc!=contracts:
                log.info(f"[Reconcile] {ticker} contracts {lc}->{contracts}")
                open_positions[ticker]['contracts']=contracts

    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        try:
            r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8); r.raise_for_status()
            ms=r.json().get("market",{}).get("status","")
            if ms in("settled","finalized"): log.info(f"[Reconcile] SETTLED {ticker}")
            else: log.info(f"[Reconcile] CLOSED externally: {ticker}")
        except Exception as e: log.warning(f"[Reconcile] {ticker}:{e}")
        rm.append(ticker)

    for t in rm:
        if t in open_positions: del open_positions[t]
        _settled_cache.add(t)
    if rm or kt: save_fn(open_positions)
    if pnl_delta!=0.0: save_pnl_fn(pnl_log)
    if rm: log.info(f"[Reconcile] Removed {len(rm)} position(s)")
    return pnl_delta

# ---------------------------------------------------------------------------
# EV calculator — maker fees only
# ---------------------------------------------------------------------------
def _ev(contracts, price_cents, confidence, is_maker=True):
    pd=price_cents/100.0; payout=(1.0-pd)*contracts; stake=pd*contracts
    fee=math.ceil((0.0175 if is_maker else 0.07)*contracts*pd*(1-pd)*100)/100.0
    return round(confidence*payout-(1.0-confidence)*stake-fee*2,4)

# ---------------------------------------------------------------------------
# STRATEGY: Value Fade (maker limit orders only)
# Buy NO on heavy favorites at 93c+
# Entry: LIMIT order at NO bid (maker fee), not market order
# ---------------------------------------------------------------------------
def strategy_value_fade(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m=item["market"]

    # Allowed series only
    if not _allowed(m.ticker): return None

    sport=item.get("sport","")
    status=item.get("market_status","active")
    live=(status=="active") or (sport=="Tennis" and status=="open")

    if not live:
        if m.yes_bid<0.96 or m.volume<10000: return None
    elif m.yes_bid<0.93 or m.volume<3000: return None

    no_bid_cents = max(1, int(m.no_bid * 100))  # MAKER: use bid not ask
    no_ask_cents = max(1, int(m.no_ask * 100))

    # Only enter if there's a real bid (liquidity exists)
    if no_bid_cents < 2: return None

    # Use bid price for limit order (maker)
    price_cents = no_bid_cents
    contracts   = max(1, min(int(Config.MAX_POSITION_USD / max(m.no_bid, 0.01)),
                             Config.MAX_CONTRACTS))
    conf        = 0.65

    # Boost confidence for very heavy favorites
    if m.yes_bid >= 0.97: conf = 0.68
    if m.yes_bid >= 0.99: conf = 0.72

    ev = _ev(contracts, price_cents, conf, is_maker=True)
    if ev < 0.05: return None

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "no",
        action        = "buy",
        price         = price_cents,   # limit at bid = maker order
        contracts     = contracts,
        strategy      = "value_fade",
        reason        = (f"Fade {int(m.yes_bid*100)}c favorite | "
                        f"NO bid={no_bid_cents}c ask={no_ask_cents}c | "
                        f"vol={int(m.volume)} | MAKER"),
        confidence    = conf,
    )

# ---------------------------------------------------------------------------
# Exit strategy — unchanged logic, NO positions skip early exit
# ---------------------------------------------------------------------------
def strategy_exit(item, pos, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    from datetime import datetime, timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None

    # NO positions: never exit early — hold to settlement
    # Collateral cost of selling NO makes early exit uneconomical
    if side=="no": return None

    bid=max(1,int(m.yes_bid*100))
    peak=max(bid,pos.get("peak_price",entry))
    pos["peak_price"]=peak

    fee_mult=0.0175
    entry_fee=pos.get("entry_fee",0.0)
    exit_fee=math.ceil(fee_mult*contracts*(bid/100)*(1-bid/100)*100)/100
    pnl=(bid-entry)*contracts/100.0-entry_fee-exit_fee

    # Trail stop tiers
    if entry<=15:
        stop=max(1,peak-max(3,int(peak*0.50)))
    elif pnl>=2.00: stop=int(peak*0.88)
    elif pnl>=0.50: stop=int(peak*0.82)
    else:           stop=int(entry*0.70)

    # Stale exit — no movement after 5 minutes
    stale=False
    try:
        et=pos.get("entry_time","")
        if et:
            age=(datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            if age>300 and abs(bid-entry)<4 and pnl<0.05:
                stale=True
    except: pass

    force=(espn_cache is not None and hasattr(espn_cache,'find') and False)  # placeholder

    if not (bid<=stop or stale): return None

    if stale and bid>stop:
        reason=f"Stale: {int(age)}s, {abs(bid-entry)}c move, PNL=${pnl:.2f}"
        strat=f"exit_stale_{strategy}"
    else:
        if pnl>=0.05:
            reason=f"Trail stop: {bid}c<=>{stop}c peak={peak}c PNL=${pnl:.2f}"
            strat=f"exit_trail_{strategy}"
        else:
            reason=f"Stop loss: {bid}c<={stop}c entry={entry}c PNL=${pnl:.2f}"
            strat=f"exit_sl_{strategy}"

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )

# ---------------------------------------------------------------------------
# STRATEGIES list — value_fade only for now
# ---------------------------------------------------------------------------
def _wrap(fn):
    import functools
    @functools.wraps(fn)
    def w(item, espn_cache=None): return fn(item, espn_cache=espn_cache)
    return w

STRATEGIES = [_wrap(strategy_value_fade)]
