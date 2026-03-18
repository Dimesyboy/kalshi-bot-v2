from __future__ import annotations
try:
    from nba_context import should_enter_prop, nba_value_fade_check, find_game_for_ticker
    _NBA_CTX=True
except ImportError:
    _NBA_CTX=False
import logging, time, math, requests, functools, os
from typing import Optional
log = logging.getLogger("kalshi_bot.strategies")

try:
    from nba_props import get_nba_prop_context
    _NBA_PROPS = True
except ImportError:
    _NBA_PROPS = False

try:
    from mlb_props import get_mlb_context
    _MLB_PROPS = True
except ImportError:
    _MLB_PROPS = False

try:
    from espn_data import ESPNClient, GameContext, ContextCollection
    STATUS_LIVE="STATUS_IN_PROGRESS"; STATUS_FINAL="STATUS_FINAL"; _ESPN=True
except ImportError:
    _ESPN=False; GameContext=None

try:
    from tennis_context import get_tennis_context
    _TENNIS_CTX=True
except ImportError:
    _TENNIS_CTX=False

ALLOWED_SERIES = [
    "KXNBAGAME","KXNBASPREAD",
    "KXMLBGAME","KXMLBSPREAD","KXMLBSTGAME",
    "KXATPMATCH","KXWTAMATCH","KXATPGAME","KXWTAGAME",
    "KXATPCHALLENGERMATCH","KXWTACHALLENGERMATCH",
    "KXNBAPTS","KXNBAREB","KXNBAAST","KXNBA3PT",
    "KXNBAPRA","KXNBASTL","KXNBABLK","KXMLBHIT",
    "KXNBA1HWINNER","KXNBA2HWINNER",
    "KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER",
]

def _allowed(ticker):
    return any(ticker.startswith(s) for s in ALLOWED_SERIES)

def _is_prop(ticker):
    return any(ticker.startswith(s) for s in [
        "KXNBAPTS","KXNBAREB","KXNBAAST","KXNBA3PT",
        "KXNBAPRA","KXNBASTL","KXNBABLK","KXMLBHIT",
    ])

def _is_nba_mlb(ticker):
    return any(ticker.startswith(x) for x in ["KXNBA","KXMLB","KXMLBST"])

def _is_tennis(ticker):
    return any(ticker.startswith(x) for x in [
        "KXATPMATCH","KXWTAMATCH","KXATPGAME","KXWTAGAME",
        "KXATPCHALLENGERMATCH","KXWTACHALLENGERMATCH",
    ])

def _is_live(status, sport, ticker):
    if status == "active": return True
    if sport == "Tennis" and status == "open": return True
    return False

def _scale_contracts(base_contracts, confidence, max_contracts=20):
    """Scale position size by confidence above 0.60 floor.
    Cap is applied AFTER scaling so MAX_CONTRACTS is always respected."""
    scale = 1.0 + max(0.0, (confidence - 0.60) / 0.10) * 0.5
    return max(1, min(int(base_contracts * scale), max_contracts))

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

_settled_cache = set()
_fills_bootstrapped = False

def _fetch_fills_raw_single(client):
    import urllib3, json as _j, kalshi_python
    fills=[]
    orig=urllib3.PoolManager.urlopen
    def cap(self,method,url,**kw):
        r=orig(self,method,url,**kw)
        if 'fills' in url:
            try: fills.extend(_j.loads(r.data).get('fills',[]) or [])
            except: pass
        return r
    urllib3.PoolManager.urlopen=cap
    try:
        pa=kalshi_python.PortfolioApi(api_client=client); pa.get_fills()
    except: pass
    finally: urllib3.PoolManager.urlopen=orig
    return fills

def _fetch_fills_raw(client):
    import urllib3, json as _j, kalshi_python
    all_fills=[]; cursor=None; page=0
    while page < 20:
        page_fills=[]; next_cursor=[None]
        orig=urllib3.PoolManager.urlopen
        def cap(self,method,url,**kw):
            r=orig(self,method,url,**kw)
            if 'fills' in url:
                try:
                    d=_j.loads(r.data)
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
        if not next_cursor[0] or len(page_fills)==0: break
        cursor=next_cursor[0]; page+=1
    log.info(f"[Fills] Total fetched: {len(all_fills)} fills across {page+1} page(s)")
    return all_fills

def reconcile_positions(open_positions,kalshi_base,client,save_fn,pnl_log,current_date,save_pnl_fn,bot_orders=None):
    global _fills_bootstrapped
    if client is None: return 0.0
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
    except Exception as e: log.warning(f"[Reconcile] failed:{e}"); return 0.0

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
                net[ticker]['net']+=count; net[ticker]['fees']+=fee
            elif action=='sell':
                net[ticker]['net']-=count; net[ticker]['fees']+=fee
        except Exception as e: log.debug(f"[Reconcile] {e}")

    kt=set(t for t,v in net.items() if v['net']>0)
    log.info(f"[Reconcile] {len(kt)} tickers with net open position")

    for ticker,v in net.items():
        if v['net']<=0 or ticker in _settled_cache: continue
        side=v['side']; contracts=v['net']; entry=v['avg_entry']; fees=v['fees']
        if ticker not in open_positions:
            try:
                r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8)
                r.raise_for_status()
                ms=r.json().get("market",{}).get("status","")
                if ms in("settled","finalized"): _settled_cache.add(ticker); continue
            except Exception as e: log.warning(f"[Reconcile] {ticker}:{e}"); continue
            is_bot=v.get('is_bot')
            strategy='reconciled' if is_bot else ('manual' if is_bot is False else 'unknown')
            tag='BOT' if is_bot else ('MANUAL' if is_bot is False else 'UNK')
            log.info(f"[Reconcile] ADDED [{tag}] {ticker} {side.upper()} @ {entry}c x{contracts}")
            open_positions[ticker]={
                'side':side,'entry_price':entry,'peak_price':entry,'last_bid':entry,
                'contracts':contracts,'strategy':strategy,'entry_time':v['entry_time'],
                'event_ticker':v['event_ticker'],'reason':'From fills','entry_fee':fees,
                'is_bot':is_bot,
            }
        else:
            lc=open_positions[ticker].get('contracts',contracts)
            if lc!=contracts:
                open_positions[ticker]['contracts']=contracts

    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        try:
            r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8); r.raise_for_status()
            ms=r.json().get("market",{}).get("status","")
            log.info(f"[Reconcile] {'SETTLED' if ms in ('settled','finalized') else 'CLOSED'}: {ticker}")
        except Exception as e: log.warning(f"[Reconcile] {ticker}:{e}")
        rm.append(ticker)

    for t in rm:
        if t in open_positions: del open_positions[t]
        _settled_cache.add(t)
    if rm or kt: save_fn(open_positions)
    if rm: log.info(f"[Reconcile] Removed {len(rm)} position(s)")
    return 0.0

def _ev(contracts, price_cents, confidence, is_maker=True):
    pd=price_cents/100.0; payout=(1.0-pd)*contracts; stake=pd*contracts
    fee=math.ceil((0.0175 if is_maker else 0.07)*contracts*pd*(1-pd)*100)/100.0
    return round(confidence*payout-(1.0-confidence)*stake-fee*2,4)

# =============================================================================
# STRATEGY 1: Value Fade
# Buy NO on heavy favorites (97c+)
# Pre-game: NBA, MLB, Tennis
# Live NBA/MLB: ALLOWED if ESPN confirms close game (lead < 8, Q1/Q2 only)
# Live Tennis: ALLOWED if ESPN confirms match competitive
# =============================================================================
def strategy_value_fade(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m=item["market"]
    if not _allowed(m.ticker): return None

    sport=item.get("sport","")
    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker)

    if m.yes_bid < 0.95: return None  # lowered from 0.97 — matches manual trading edge
    # Volume gates by market type
    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 3000   # Q/H winner markets
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 400    # Spring training — lower liquidity is normal
    else:
        min_vol = 8000   # Full season NBA/MLB game markets
    if m.volume < min_vol: return None
    if m.spread > 3: return None

    no_bid_cents=max(1,int(m.no_bid*100))
    if no_bid_cents < 5: return None

    conf=0.65
    ctx_reason="no context"

    if _is_nba_mlb(m.ticker):
        if _is_prop(m.ticker): return None  # never fade props
        if live:
            # Live NBA/MLB fade — only if ESPN confirms game is still close
            if not _NBA_CTX or not espn_cache:
                return None  # refuse live NBA/MLB without context
            ctx=find_game_for_ticker(m.ticker, espn_cache)
            if not ctx:
                return None
            if not ctx.is_live:
                return None
            # Only fade in Q1 or Q2 — Q3/Q4 blowouts are real
            if ctx.nba_quarter > 2:
                return None
            # Only fade if lead is small — big lead means price is correct
            if abs(ctx.lead) > 8:
                return None
            conf=0.66
            ctx_reason=f"Live Q{ctx.nba_quarter} lead={ctx.lead} — early game fade"
        else:
            # Pre-game NBA/MLB
            if not _NBA_CTX or not espn_cache:
                conf=0.65; ctx_reason="pre-game no ESPN"
            else:
                enter,ctx_conf,ctx_reason=nba_value_fade_check(m.ticker,m.yes_bid,espn_cache)
                if not enter: return None
                conf=max(conf,ctx_conf)

    elif _is_tennis(m.ticker):
        if live and _TENNIS_CTX and espn_cache:
            tctx=get_tennis_context(m.ticker, espn_cache)
            if tctx:
                # Only fade if match is competitive — not if one player is winning easily
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None  # match nearly over, price is correct
                conf=min(0.68, tctx.underdog_conf)
                ctx_reason=f"Tennis live fade: {tctx.summary()}"
            else:
                conf=0.65; ctx_reason="tennis live no ctx"
        else:
            conf=0.65; ctx_reason="tennis pre-game"

    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.no_bid,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)

    if m.yes_bid>=0.98: conf=min(conf+0.02, 0.72)
    if m.yes_bid>=0.99: conf=min(conf+0.02, 0.74)

    ev=_ev(contracts,no_bid_cents,conf,is_maker=True)
    if ev < 0.08: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="no", action="buy", price=no_bid_cents, contracts=contracts,
        strategy="value_fade",
        reason=f"Fade {int(m.yes_bid*100)}c | NO={no_bid_cents}c vol={int(m.volume)} sprd={m.spread}c | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 2: NBA/MLB Prop YES
# Buy YES on player props where Kalshi price is below implied probability
# Uses player season average vs threshold to find underpriced markets
# Pre-game and early live (Q1/Q2, innings 1-3) only
# =============================================================================
def strategy_prop_yes(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m=item["market"]
    if not _is_prop(m.ticker): return None

    sport=item.get("sport","")
    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker)

    # Price range: 62-78c — avoids fee-heavy 50c zone and overpriced locks
    if m.yes_bid < 0.62 or m.yes_bid > 0.78: return None
    if m.volume < 5000 or m.spread > 4: return None

    # For live props, only enter in early game
    if live and espn_cache and _NBA_CTX:
        ctx=find_game_for_ticker(m.ticker, espn_cache)
        if ctx and ctx.is_live:
            if ctx.nba_quarter > 2:
                return None  # too late — stat window closing
            # Enough game elapsed to have meaningful stats — at least 3 min into Q1
            try:
                if ctx.clock_secs > 660:  # more than 11 min left in Q1 = too early
                    return None
            except: pass

    conf=0.65
    ctx_reason="pre-game prop"

    if _NBA_CTX and espn_cache:
        enter,ctx_conf,ctx_reason=should_enter_prop(m.ticker, m.yes_bid, espn_cache)
        if not enter: return None
        conf=max(conf, ctx_conf)
    else:
        if live: return None  # no live props without context
        ctx_reason="pre-game no ESPN"

    # Require meaningful edge — price must suggest real probability
    if m.yes_bid < 0.62 and conf < 0.68: return None

    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)

    ev=_ev(contracts,price_cents,conf)
    if ev < 0.10: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="prop_yes",
        reason=f"Prop YES: bid={int(m.yes_bid*100)}c vol={int(m.volume)} | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 3: Tennis Live Underdog
# Buy YES on underdog at 20-40c when ESPN confirms match still competitive
# Requires tennis context — no blind entries
# =============================================================================
def strategy_tennis_underdog(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m=item["market"]
    sport=item.get("sport","")
    if sport != "Tennis": return None
    if not _is_tennis(m.ticker): return None

    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker)
    if not live: return None  # live only — pre-game underdogs have no edge

    if m.yes_bid < 0.20 or m.yes_bid > 0.38: return None
    if m.volume < 8000 or m.spread > 3: return None

    # Require ESPN context — no blind underdog entries
    if not _TENNIS_CTX or not espn_cache:
        return None

    tctx=get_tennis_context(m.ticker, espn_cache)
    if not tctx or not tctx.is_live:
        return None

    # Match must still be winnable — not down 2 sets in best of 3
    if tctx.sets_down >= 2:
        return None
    # Not in a blowout set — current set must be close
    if abs(tctx.p1_games - tctx.p2_games) > 3:
        return None

    conf=tctx.underdog_conf
    if conf < 0.60: return None  # context says no edge

    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)

    ev=_ev(contracts,price_cents,conf)
    if ev < 0.10: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="tennis_underdog",
        reason=f"Tennis underdog: {tctx.summary()} | sets_down={tctx.sets_down} conf={conf}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 4: Quarter/Half Winner
# Pre-game only, contested markets 40-60c
# Less efficient than full-game — better odds on same information
# =============================================================================
def strategy_quarter_winner(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m=item["market"]
    if not any(m.ticker.startswith(s) for s in [
        "KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER",
        "KXNBA1HWINNER","KXNBA2HWINNER",
    ]): return None

    status=item.get("market_status","active")
    if status != "open": return None  # pre-game only

    # Truly contested — not a clear favorite
    if m.yes_bid < 0.40 or m.yes_bid > 0.60: return None
    # Lower volume gate for Q/H markets — naturally less liquid than full game
    if m.volume < 2000 or m.spread > 5: return None

    conf=0.60
    ctx_reason="pre-game Q/H"

    if _NBA_CTX and espn_cache:
        enter,ctx_conf,ctx_reason=nba_value_fade_check(m.ticker, m.yes_bid, espn_cache)
        if not enter: return None
        conf=max(conf, ctx_conf)

    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)

    ev=_ev(contracts,price_cents,conf)
    if ev < 0.10: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="quarter_winner",
        reason=f"Q/H winner: bid={int(m.yes_bid*100)}c vol={int(m.volume)} | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 5: NBA Player Props (Points + 3PT)
# Uses season averages + hit rate model + pace adjustment
# Pre-game and early live (Q1/Q2) only
# =============================================================================
def strategy_prop_nba(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m = item["market"]

    # Only PTS and 3PT series
    if not any(m.ticker.startswith(s) for s in ["KXNBAPTS", "KXNBA3PT"]):
        return None

    status = item.get("market_status", "active")
    sport  = item.get("sport", "")

    # Price range: 55-80c — genuine probability zone
    if m.yes_bid < 0.55 or m.yes_bid > 0.80: return None
    if m.volume < 5000 or m.spread > 5: return None

    # Require NBA props module
    if not _NBA_PROPS: return None

    ctx = get_nba_prop_context(m.ticker, m.yes_bid, espn_cache)
    if not ctx or not ctx.should_enter:
        return None

    conf        = ctx.confidence
    price_cents = int(m.yes_ask * 100)
    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.01)), Config.MAX_CONTRACTS))
    contracts   = _scale_contracts(base_contracts, conf)

    ev = _ev(contracts, price_cents, conf)
    if ev < 0.08: return None

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "yes",
        action        = "buy",
        price         = price_cents,
        contracts     = contracts,
        strategy      = "prop_nba",
        reason        = f"NBA {ctx.stat_type}: {ctx.reason} | edge={ctx.edge:+.2f}",
        confidence    = conf,
    )


# =============================================================================
# STRATEGY 6: MLB Spring Training Underdog
# Buy cheaper side when spring training record supports it
# Pre-game only, volume >= 400, spread <= 3c, YES bid 33-48c
# =============================================================================
def strategy_mlb_underdog(item, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    m = item["market"]

    if not m.ticker.startswith("KXMLBSTGAME"):
        return None

    status = item.get("market_status", "active")
    if status != "open":
        return None  # pre-game only

    # Accept both sides — context will determine which has edge
    # Underdog (33-48c) OR slight favorite (52-65c) if record supports it
    if m.yes_bid < 0.33 or m.yes_bid > 0.65: return None
    if m.volume < 400 or m.spread > 3: return None

    if not _MLB_PROPS: return None

    ctx = get_mlb_context(m.ticker, m.yes_bid)
    if not ctx or not ctx.should_enter:
        return None

    conf        = ctx.confidence
    price_cents = int(m.yes_ask * 100)
    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.01)), Config.MAX_CONTRACTS))
    contracts   = _scale_contracts(base_contracts, conf)

    ev = _ev(contracts, price_cents, conf)
    if ev < 0.06: return None  # lower EV bar for spring training

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "yes",
        action        = "buy",
        price         = price_cents,
        contracts     = contracts,
        strategy      = "mlb_underdog",
        reason        = f"MLB ST: {ctx.summary()}",
        confidence    = conf,
    )


# =============================================================================
# EXIT STRATEGY
# YES positions: trail stop + stale exit
# NO positions: hold to settlement always
# =============================================================================
def strategy_exit(item, pos, espn_cache=None):
    from kalshi_bot import TradeSignal, Config
    from datetime import datetime, timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None
    if side=="no": return None  # NO positions settle naturally

    bid=max(1,int(m.yes_bid*100))
    peak=max(bid,pos.get("peak_price",entry))
    pos["peak_price"]=peak

    fee_mult=0.0175
    entry_fee=pos.get("entry_fee",0.0)
    exit_fee=math.ceil(fee_mult*contracts*(bid/100)*(1-bid/100)*100)/100
    pnl=(bid-entry)*contracts/100.0-entry_fee-exit_fee

    if entry<=15:   stop=max(1,peak-max(3,int(peak*0.50)))
    elif pnl>=2.00: stop=int(peak*0.88)
    elif pnl>=0.50: stop=int(peak*0.82)
    else:           stop=int(entry*0.70)

    stale=False
    try:
        et=pos.get("entry_time","")
        if et:
            age=(datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            strategy_name=pos.get("strategy","")
            # Tennis matches run 1-3hrs — never stale-exit while match could still be live
            # NBA: 48min real time, MLB: ~3hrs. Use sport-aware minimums.
            if "tennis" in strategy_name.lower():
                stale_min_age = 7200   # 2 hours — a full tennis match
            elif "mlb" in strategy_name.lower():
                stale_min_age = 10800  # 3 hours
            else:
                stale_min_age = 1800   # 30 min for NBA
            if age > stale_min_age and abs(bid-entry) < 4 and pnl < 0.10:
                stale=True
    except: pass

    if not (bid<=stop or stale): return None

    if stale and bid>stop:
        reason=f"Stale: {int(age)}s, {abs(bid-entry)}c move, PNL=${pnl:.2f}"
        strat=f"exit_stale_{strategy}"
    elif pnl>=0.10:
        reason=f"Trail stop: {bid}c peak={peak}c PNL=${pnl:.2f}"
        strat=f"exit_trail_{strategy}"
    else:
        reason=f"Stop loss: {bid}c<={stop}c entry={entry}c PNL=${pnl:.2f}"
        strat=f"exit_sl_{strategy}"

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )

def _wrap(fn):
    @functools.wraps(fn)
    def w(item, espn_cache=None): return fn(item, espn_cache=espn_cache)
    return w

STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    _wrap(strategy_tennis_underdog),
    _wrap(strategy_quarter_winner),
]
