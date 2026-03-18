from __future__ import annotations
import os
import logging,time,math,requests,functools
from typing import Optional
log=logging.getLogger("kalshi_bot.strategies")
try:
    from espn_data import ESPNClient,GameContext,ContextCollection
    STATUS_LIVE="STATUS_IN_PROGRESS"; STATUS_FINAL="STATUS_FINAL"; _ESPN=True
except ImportError:
    _ESPN=False; GameContext=None; log.warning("[Strategies] espn_data not found")
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
def _fetch_fills_raw_single(client):
    """Fetch only most recent page of fills (100) for cycle reconcile."""
    import urllib3, json as _json
    import kalshi_python
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
        pa=kalshi_python.PortfolioApi(api_client=client)
        pa.get_fills()
    except: pass
    finally: urllib3.PoolManager.urlopen=orig
    return fills

def _fetch_fills_raw(client):
    """
    Fetch ALL fills via urllib3 intercept, paginating through cursor.
    SDK Pydantic models are broken so we intercept at HTTP level.
    """
    import urllib3, json as _json
    import kalshi_python

    all_fills = []
    cursor    = None
    page      = 0
    max_pages = 20  # safety cap — 20 * 100 = 2000 fills max

    while page < max_pages:
        page_fills = []
        next_cursor = [None]

        orig = urllib3.PoolManager.urlopen
        def cap(self, method, url, **kw):
            r = orig(self, method, url, **kw)
            if 'fills' in url:
                try:
                    d = _json.loads(r.data)
                    page_fills.extend(d.get('fills', []) or [])
                    next_cursor[0] = d.get('cursor', '') or ''
                except: pass
            return r
        urllib3.PoolManager.urlopen = cap
        try:
            pa = kalshi_python.PortfolioApi(api_client=client)
            if cursor:
                pa.get_fills(cursor=cursor)
            else:
                pa.get_fills()
        except: pass
        finally:
            urllib3.PoolManager.urlopen = orig

        all_fills.extend(page_fills)
        log.debug(f"[Fills] Page {page+1}: {len(page_fills)} fills, cursor={next_cursor[0][:20] if next_cursor[0] else 'none'}")

        if not next_cursor[0] or len(page_fills) == 0:
            break
        cursor = next_cursor[0]
        page  += 1

    log.info(f"[Fills] Total fetched: {len(all_fills)} fills across {page+1} page(s)")
    return all_fills

_settled_cache = set()  # tickers confirmed settled — never re-add
_fills_bootstrapped = False  # full paginated fetch done at least once

def reconcile_positions(open_positions,kalshi_base,client,save_fn,pnl_log,current_date,save_pnl_fn,bot_orders=None):
    """
    Reconstructs open positions from fills.
    First cycle: full paginated fetch to bootstrap all history.
    Subsequent cycles: single page (100 fills) for recent activity only.
    """
    global _fills_bootstrapped
    if client is None: return 0.0
    pnl_delta=0.0
    from datetime import datetime,timezone
    try:
        if not _fills_bootstrapped:
            fills=_fetch_fills_raw(client)  # full paginated
            _fills_bootstrapped=True
            # Filter to last 7 days only — older fills are settled history
            from datetime import datetime,timezone,timedelta
            cutoff=(datetime.now(timezone.utc)-timedelta(days=7)).isoformat()
            fills=[f for f in fills if f.get('created_time','') >= cutoff]
            log.info(f"[Reconcile] Bootstrap: {len(fills)} fills (last 7 days)")
        else:
            # Single page — only recent fills needed for cycle updates
            fills=_fetch_fills_raw_single(client)
            log.info(f"[Reconcile] Cycle: fetched {len(fills)} recent fills")
    except Exception as e:
        log.warning(f"[Reconcile] fills fetch failed:{e}"); return 0.0

    # Reconstruct net position per ticker from fills
    # Tag each ticker as bot-placed or manual based on order_ids
    bot_orders = bot_orders or set()
    net={}  # ticker -> {side, net_contracts, avg_entry, fees, entry_time, event_ticker, is_bot}
    for f in sorted(fills, key=lambda x: x.get('created_time','')):
        try:
            ticker   = f.get('ticker') or f.get('market_ticker','')
            if not ticker: continue
            side     = f.get('side','yes')
            action   = f.get('action','buy')
            count    = int(float(f.get('count_fp',0) or 0))
            price_d  = float(f.get('yes_price_dollars') or f.get('no_price_dollars') or 0)
            price_c  = round(price_d*100)
            fee      = float(f.get('fee_cost',0) or 0)
            etime    = f.get('created_time','')
            eticker  = ticker.rsplit('-',1)[0] if '-' in ticker else ticker
            order_id = f.get('order_id','')
            is_bot   = order_id in bot_orders if bot_orders else None  # None = unknown
            if ticker not in net:
                net[ticker]={'side':side,'net':0,'avg_entry':price_c,
                             'fees':0.0,'entry_time':etime,'event_ticker':eticker,
                             'is_bot':is_bot,'order_ids':set()}
            if order_id:
                net[ticker]['order_ids'].add(order_id)
                # If ANY fill on this ticker is a bot order, tag as bot
                if is_bot:
                    net[ticker]['is_bot']=True
                elif net[ticker]['is_bot'] is None:
                    net[ticker]['is_bot']=False
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
        except Exception as e:
            log.debug(f"[Reconcile] fill parse error:{e}")

    # Build set of tickers with open positions
    kt=set(t for t,v in net.items() if v['net']>0)
    log.info(f"[Reconcile] {len(kt)} tickers with net open position")

    # Add/update positions — verify market is still active before adding
    for ticker,v in net.items():
        if v['net']<=0: continue
        side=v['side']; contracts=v['net']
        entry=v['avg_entry']; fees=v['fees']
        if ticker not in open_positions:
            # Skip if already confirmed settled
            if ticker in _settled_cache: continue
            # Verify market is actually still active or open
            try:
                r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8)
                r.raise_for_status()
                ms=r.json().get("market",{}).get("status","")
                if ms in("settled","finalized"):
                    log.debug(f"[Reconcile] SKIP {ticker} — market {ms}")
                    _settled_cache.add(ticker)
                    continue
            except Exception as e:
                log.warning(f"[Reconcile] market check failed {ticker}:{e}")
                continue  # skip this cycle but don't cache — retry next cycle
            is_bot   = v.get('is_bot')
            strategy = 'reconciled' if is_bot else ('manual' if is_bot is False else 'unknown')
            tag      = 'BOT' if is_bot else ('MANUAL' if is_bot is False else 'UNKNOWN')
            log.info(f"[Reconcile] ADDED [{tag}] {ticker} {side.upper()} @ {entry}c x{contracts}")
            open_positions[ticker]={
                'side':side,'entry_price':entry,'contracts':contracts,
                'strategy':strategy,'entry_time':v['entry_time'],
                'event_ticker':v['event_ticker'],'reason':'From fills','entry_fee':fees,
                'is_bot':is_bot,
            }
        else:
            lc=open_positions[ticker].get('contracts',contracts)
            if lc!=contracts:
                log.info(f"[Reconcile] {ticker} contracts {lc}->{contracts}")
                open_positions[ticker]['contracts']=contracts

    # Remove positions no longer open on Kalshi
    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        # Check if settled
        try:
            r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8); r.raise_for_status()
            d=r.json().get("market",{}); ms=d.get("status","")
            if ms in("settled","finalized"):
                result=d.get("result","").lower()
                ep=pos.get("entry_price",0); c=pos.get("contracts",0); ef=pos.get("entry_fee",0.0)
                if ep>0 and c>0:
                    pc=(100-ep)*c if result==pos["side"].lower() else -ep*c
                    pd=pc/100.0-ef; pnl_delta+=pd
                    pnl_log[current_date]=pnl_log.get(current_date,0.0)+pd
                    log.info(f"[Reconcile] SETTLED {ticker} {result.upper()} PNL ${pd:.4f}")
            else:
                log.info(f"[Reconcile] CLOSED externally: {ticker}")
        except Exception as e:
            log.warning(f"[Reconcile] {ticker}:{e}")
        rm.append(ticker)

    for t in rm:
        if t in open_positions: del open_positions[t]
        _settled_cache.add(t)
    if rm or kt:
        save_fn(open_positions)
    if pnl_delta!=0.0:
        save_pnl_fn(pnl_log)
    if rm:
        log.info(f"[Reconcile] Removed {len(rm)} closed position(s)")
    return pnl_delta
def _ev(contracts,price_cents,confidence,is_maker=True):
    pd=price_cents/100.0; payout=(1.0-pd)*contracts; stake=pd*contracts
    fee=math.ceil((0.0175 if is_maker else 0.07)*contracts*pd*(1.0-pd)*100)/100.0
    return round(confidence*payout-(1.0-confidence)*stake-fee*2,4)
def _ctx(item,cache):
    if not cache or not _ESPN: return None
    sport=item.get("sport",""); title=item.get("game_title","")
    if not title: return None
    for part in title.replace(" vs "," ").replace(" at "," ").split():
        if len(part)>=4:
            c=cache.find(sport,part)
            if c: return c
    return None
def strategy_value_fade(item,espn_cache=None):
    from kalshi_bot import TradeSignal,Config
    m=item["market"]
    sport=item.get("sport","")
    status=item.get("market_status","active")
    # Tennis uses 'open' even when live
    live=(status=="active") or (sport=="Tennis" and status=="open")
    if not live:
        if m.yes_bid<0.96 or m.volume<5000: return None
    elif m.yes_bid<0.93 or m.volume<1000: return None
    npc=int(m.no_ask*100)
    if npc<Config.MIN_NO_PRICE: return None
    conf=0.65; c=_ctx(item,espn_cache)
    if c and c.is_live:
        pct=c.pct_complete()
        if pct<0.20: return None
        if c.blowout: return None
        if c.is_close and pct>=0.70: conf=0.72
    contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.no_ask,0.01)),Config.MAX_CONTRACTS))
    if _ev(contracts,npc,conf)<=0: return None
    return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="no",action="buy",
        price=npc,contracts=contracts,strategy="value_fade",
        reason=f"Fading fav: yes_bid={int(m.yes_bid*100)}c"+(f" | {c.score_str()} {c.status_detail}" if c else ""),
        confidence=conf)
def strategy_momentum(item,espn_cache=None):
    from kalshi_bot import TradeSignal,Config
    m=item["market"]
    if item.get("market_status","active")!="active": return None
    try: drift=(m.last_price-m.yes_bid)*100
    except: return None
    c=_ctx(item,espn_cache); min_drift=10.0 if(c and c.is_live) else 15.0
    if drift<min_drift or m.volume<5000: return None
    conf=0.62
    if c and c.is_live:
        pct=c.pct_complete()
        if pct>=0.85: return None
        if c.is_close and pct>=0.60: return None
        ms=c.momentum_score()
        if ms>5: conf=min(0.72,conf+ms*0.008)
    price=int(m.yes_ask*100); contracts=max(1,min(int(Config.MAX_POSITION_USD/(m.yes_ask or 0.01)),Config.MAX_CONTRACTS))
    if _ev(contracts,price,conf)<=0: return None
    return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="yes",action="buy",
        price=price,contracts=contracts,strategy="momentum",
        reason=f"Momentum +{drift:.1f}c"+(f" | {c.score_str()} {c.status_detail}" if c else ""),
        confidence=round(conf,2))
def strategy_custom(item,espn_cache=None):
    """
    Tightened underdog — LIVE games only, must have ESPN context confirming
    the underdog is still genuinely in it. No pre-game entries.
    """
    from kalshi_bot import TradeSignal,Config
    m=item["market"]
    # Live markets only — tennis uses 'open' status even during live play
    sport=item.get("sport","")
    status=item.get("market_status","active")
    if sport=="Tennis":
        if status not in("active","open"): return None
    else:
        if status!="active": return None
    # Price range
    if m.yes_bid<0.28 or m.yes_bid>0.33: return None
    # Higher volume requirement
    if m.volume<8000: return None
    if m.spread>3: return None
    conf=0.63
    c=_ctx(item,espn_cache)
    # Require ESPN context for NBA/MLB but allow tennis without it
    if sport!="Tennis" and (not c or not c.is_live): return None
    # If no ESPN context (tennis), use simplified logic
    if not c or not c.is_live:
        if m.yes_bid<0.28 or m.yes_bid>0.33: return None
        price=int(m.yes_ask*100); contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
        if _ev(contracts,price,conf)<0.15: return None
        return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="yes",action="buy",
            price=price,contracts=contracts,strategy="underdog",
            reason=f"Tennis underdog: bid={int(m.yes_bid*100)}c spread={m.spread}c vol={int(m.volume)}",
            confidence=conf)
    pct=c.pct_complete()
    # Only enter between 20% and 80% of game — sweet spot for momentum
    if pct<0.20 or pct>=0.80: return None
    # No blowouts
    if c.blowout: return None
    # Underdog must be within striking distance
    sport=item.get("sport","")
    max_deficit={"NBA":8,"MLB":2,"Tennis":1}.get(sport,8)
    if abs(c.lead)>max_deficit: return None
    # Boost confidence for close mid-game
    if c.is_close and 0.35<=pct<=0.65: conf=0.70
    # MLB bases loaded
    if sport=="MLB" and len(c.mlb_on_base)>=2: conf=min(0.75,conf+0.05)
    price=int(m.yes_ask*100); contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    if _ev(contracts,price,conf)<=0: return None
    return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="yes",action="buy",
        price=price,contracts=contracts,strategy="underdog",
        reason=f"Underdog YES: bid={int(m.yes_bid*100)}c spread={m.spread}c vol={int(m.volume)} | {c.score_str()} {c.status_detail}",
        confidence=round(conf,2))


def strategy_comeback(item,espn_cache=None):
    """
    Late-game comeback scalp — the highest-probability quick profit setup.
    Enters when underdog is close late-game and market hasn't fully repriced.
    Target: 35% gain in 2-4 cycles. Exit if no movement in 3 cycles.
    """
    from kalshi_bot import TradeSignal,Config
    m=item["market"]
    if item.get("market_status","active")!="active": return None
    # Price range: underdog but not hopeless
    if m.yes_bid<0.25 or m.yes_bid>0.48: return None
    if m.volume<10000: return None
    if m.spread>4: return None
    c=_ctx(item,espn_cache)
    sport=item.get("sport","")
    # Tennis without ESPN — allow but use conservative confidence
    # Tennis uses wider price range since matches progress to extremes
    if sport=="Tennis" and (not c or not c.is_live):
        if m.yes_bid<0.20 or m.yes_bid>0.48: return None
        if m.volume<15000: return None
        conf=0.66
        price=int(m.yes_ask*100)
        contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
        if _ev(contracts,price,conf)<0.15: return None
        return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="yes",action="buy",
            price=price,contracts=contracts,strategy="comeback",
            reason=f"Tennis comeback (no ESPN): bid={int(m.yes_bid*100)}c vol={int(m.volume)}",
            confidence=conf)
    if not c or not c.is_live: return None
    pct=c.pct_complete()
    # Late game only — this is a comeback play
    late_gate={"NBA":0.65,"MLB":0.60,"Tennis":0.55}.get(sport,0.65)
    if pct<late_gate or pct>=0.92: return None
    # Must be close — within comeback range
    max_deficit={"NBA":6,"MLB":1,"Tennis":1}.get(sport,6)
    if abs(c.lead)>max_deficit: return None
    # No blowout
    if c.blowout: return None
    conf=0.68
    if c.is_close and pct>=0.75: conf=0.74
    if sport=="NBA" and c.nba_quarter==4 and c.is_close: conf=0.76
    if sport=="MLB" and c.period>=7 and len(c.mlb_on_base)>=1: conf=min(0.78,conf+0.05)
    price=int(m.yes_ask*100); contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    if _ev(contracts,price,conf)<=0: return None
    return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,side="yes",action="buy",
        price=price,contracts=contracts,strategy="comeback",
        reason=f"Late comeback: {c.score_str()} | {pct:.0%} done | {c.status_detail} | bid={int(m.yes_bid*100)}c",
        confidence=round(conf,2))
def strategy_exit(item,pos,espn_cache=None):
    from kalshi_bot import TradeSignal,Config
    from datetime import datetime,timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None
    bid=max(1,int((m.no_bid if side=="no" else m.yes_bid)*100))
    tp=bid>=entry*(1+Config.TAKE_PROFIT_PCT)
    sl=bid<=entry*(1-Config.STOP_LOSS_PCT)
    c=_ctx(item,espn_cache); force=c is not None and c.is_final
    # Time-based exit: if open > 4 cycles (~4 min) and price moved < 5c, cut it loose
    stale=False
    try:
        from datetime import timezone
        et=pos.get("entry_time","")
        if et:
            age_secs=(datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            price_move=abs(bid-entry)
            if age_secs>240 and price_move<5 and strategy in("underdog","comeback"):
                stale=True
    except: pass
    if not tp and not sl and not force and not stale: return None
    if force and not tp and not sl:   reason=f"ESPN final — exit @ {bid}c"; strat=f"exit_espn_{strategy}"
    elif tp:                          reason=f"Take profit: {bid}c >= {entry}c +{int(Config.TAKE_PROFIT_PCT*100)}%"; strat=f"exit_tp_{strategy}"
    elif stale and not sl:            reason=f"Stale exit: {age_secs:.0f}s open, only {price_move}c move"; strat=f"exit_stale_{strategy}"
    else:                             reason=f"Stop loss: {bid}c <= {entry}c -{int(Config.STOP_LOSS_PCT*100)}%"; strat=f"exit_sl_{strategy}"
    return TradeSignal(event_ticker=item["event_ticker"],market_ticker=m.ticker,
        side=side,action="sell",price=bid,contracts=contracts,strategy=strat,reason=reason,confidence=0.80)
def _wrap(fn):
    @functools.wraps(fn)
    def w(item,espn_cache=None): return fn(item,espn_cache=espn_cache)
    return w
STRATEGIES=[_wrap(strategy_comeback),_wrap(strategy_custom),_wrap(strategy_value_fade),_wrap(strategy_momentum)]
