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

def _is_live(status, sport, ticker, espn_cache=None):
    """
    Determine if a game is currently in progress.
    Kalshi 'active' just means the market is open for trading — not that the game is live.
    We use ESPN ctx.is_live as the source of truth when available.
    Falls back to False (pre-game assumed) if no ESPN context.
    """
    if espn_cache is not None:
        if _is_nba_mlb(ticker) and _NBA_CTX:
            ctx = find_game_for_ticker(ticker, espn_cache)
            if ctx is not None:
                return ctx.is_live
        if _is_tennis(ticker) and _TENNIS_CTX:
            from tennis_context import get_tennis_context
            tctx = get_tennis_context(ticker, espn_cache)
            if tctx is not None:
                return tctx.is_live
    return False  # assume pre-game if no ESPN context

def _scale_contracts(base_contracts, confidence, max_contracts=None):
    """Scale position size by confidence above 0.60 floor.
    Uses Config.MAX_CONTRACTS as ceiling unless overridden."""
    if max_contracts is None:
        try:
            from models import Config
            max_contracts = Config.MAX_CONTRACTS
        except:
            max_contracts = 100
    scale = 1.0 + max(0.0, (confidence - 0.60) / 0.10) * 0.5
    return max(1, min(int(base_contracts * scale), max_contracts))

# =============================================================================
# Price history cache — used to detect stale 95c+ markets
# Markets that have been at 95c+ for > 2 cycles are likely correctly priced
# and should not be faded.
# =============================================================================
_price_history: dict = {}  # ticker -> {"first_seen_high": float, "last_price": float}
_FADE_STALE_SECS = 120  # if market has been at 95c+ for 2+ minutes, skip

def _record_price(ticker: str, yes_bid: float):
    now = time.time()
    if ticker not in _price_history:
        _price_history[ticker] = {"first_seen_high": now if yes_bid >= 0.95 else None, "last_price": yes_bid}
        return
    h = _price_history[ticker]
    if yes_bid >= 0.95:
        if h["first_seen_high"] is None:
            h["first_seen_high"] = now  # just crossed up
    else:
        h["first_seen_high"] = None  # dropped below — reset
    h["last_price"] = yes_bid

def _is_stale_high(ticker: str, yes_bid: float) -> bool:
    """Returns True if this market has been at 95c+ for too long — price is correct, don't fade."""
    _record_price(ticker, yes_bid)
    h = _price_history.get(ticker)
    if not h or h["first_seen_high"] is None:
        return False
    age = time.time() - h["first_seen_high"]
    return age > _FADE_STALE_SECS

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

        # RECONCILE GUARD: skip NO positions entered above 20c — these are data errors
        # (a NO at 92c means the YES was already at 92c — position was already lost)
        if side == "no" and entry > 20:
            log.warning(f"[Reconcile] SKIPPING {ticker} — NO entry at {entry}c is likely a data error")
            continue
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
        # Check if there is a resting (unfilled) bot order for this ticker
        # If so, keep the position — the order just hasn't filled yet
        order_id = pos.get("order_id","")
        if order_id and bot_orders and order_id in bot_orders:
            try:
                import kalshi_python
                pa = kalshi_python.PortfolioApi(api_client=client)
                resp = pa.get_orders(limit=50)
                resting = {o.order_id for o in (resp.orders or []) if o.status in ("resting","pending")}
                if order_id in resting:
                    log.info(f"[Reconcile] {ticker} order {order_id} still resting — keeping position")
                    continue
            except Exception as e:
                log.debug(f"[Reconcile] order check {ticker}: {e}")
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
    pd=price_cents/100.0
    # payout per contract if win, stake per contract if loss (in dollars)
    payout_per = (1.0 - pd)          # win: collect (1-p) per contract
    stake_per  = pd                   # loss: lose p per contract
    fee=math.ceil((0.0175 if is_maker else 0.07)*contracts*pd*(1-pd)*100)/100.0
    gross_ev = confidence*payout_per - (1.0-confidence)*stake_per
    net_ev   = gross_ev*contracts - fee*2
    return round(net_ev, 4)

def _ratio_ok(price_cents, min_ratio=1.5):
    """Payout must be at least min_ratio x stake.
    40c: payout=60c/stake=40c = 1.5 OK
    65c: payout=35c/stake=65c = 0.54 FAIL
    """
    pd = price_cents / 100.0
    if pd <= 0: return False
    return (1.0 - pd) / pd >= min_ratio


def _ratio_ok(price_cents, min_ratio=1.5):
    """Payout must be at least min_ratio times the stake.
    e.g. at 40c: payout=60c, stake=40c, ratio=1.5 — just passes
    at 65c: payout=35c, stake=65c, ratio=0.54 — fails
    """
    pd = price_cents / 100.0
    return (1.0 - pd) / pd >= min_ratio

# =============================================================================
# STRATEGY 1: Value Fade
# Buy NO on heavy favorites (95c+)
# Guards:
#   - Market must NOT have been at 95c+ for > 2 minutes (stale = correctly priced)
#   - Live NBA/MLB: lead < 5 (tightened from 8), Q1/Q2 only
#   - EV gate raised to 0.12 (from 0.08)
#   - Confidence gate raised to 0.63 minimum
# =============================================================================
def strategy_value_fade(item, espn_cache=None):
    from models import TradeSignal, Config
    m=item["market"]
    if not _allowed(m.ticker): return None

    sport=item.get("sport","")
    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)

    # never enter a position on a game ESPN has already marked as finished
    # only block if BOTH teams in the ticker match the final game (date-specific)
    if espn_cache is not None and _is_nba_mlb(m.ticker):
        from nba_context import find_game_for_ticker, parse_prop_ticker
        _ctx = find_game_for_ticker(m.ticker, espn_cache)
        if _ctx and _ctx.is_final:
            # verify it's the same game — both teams must match
            _parsed = parse_prop_ticker(m.ticker)
            _t1 = _parsed.get("team1","").upper()
            _t2 = _parsed.get("team2","").upper()
            _home = _ctx.home.abbreviation.upper()
            _away = _ctx.away.abbreviation.upper()
            _both_match = (_t1 in (_home,_away)) and (_t2 in (_home,_away))
            if _both_match:
                return None  # confirmed same game, it's final

    if m.yes_bid < 0.82 or m.yes_bid > 0.88: return None  # zone: YES 82-88c = NO 12-18c, confirmed edge zone

    # Volume gates by market type — at $1-10 position sizes, 3000 vol is ample liquidity
    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 2000
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 300
    elif any(m.ticker.startswith(s) for s in ["KXWTAMATCH","KXWTAGAME","KXWTACHALLENGERMATCH"]):
        min_vol = 4000  # WTA less liquid than ATP
    else:
        min_vol = 5000  # NBA/MLB/ATP full game markets

    if m.volume < min_vol: return None
    if m.spread > 3: return None

    no_bid_cents=max(1,int(m.no_bid*100))
    if no_bid_cents < 12: return None  # floor: YES 82-88c band requires NO >= 12c

    # Stale price guard — if market has been pinned at 95c+ for >2 min,
    # the price is likely correct (blowout, game over, etc). Skip it.
    if _is_stale_high(m.ticker, m.yes_bid):
        log.debug(f"[value_fade] SKIP {m.ticker} — stale 95c+ price, not a fade opportunity")
        return None

    # ── Data-driven confidence scoring ──────────────────────────────────────
    try:
        from confidence_model import score_value_fade, record_price
        record_price(m.ticker, m.yes_bid)
        conf, ctx_reason = score_value_fade(item, espn_cache=espn_cache)
    except Exception as _e:
        log.debug(f"[value_fade] confidence_model failed: {_e} — using base")
        conf = 0.65
        ctx_reason = "base confidence"

    # Live NBA/MLB gates — still apply regardless of confidence score
    if _is_nba_mlb(m.ticker):
        if _is_prop(m.ticker): return None
        if live:
            if not _NBA_CTX or not espn_cache:
                return None
            ctx = find_game_for_ticker(m.ticker, espn_cache)
            if not ctx or not ctx.is_live:
                return None
            if ctx.nba_quarter > 2:
                return None
            if abs(ctx.lead) > 5:
                return None
            ctx_reason = f"Live Q{ctx.nba_quarter} lead={ctx.lead} | {ctx_reason}"

    elif _is_tennis(m.ticker):
        if live and _TENNIS_CTX and espn_cache:
            tctx = get_tennis_context(m.ticker, espn_cache)
            if tctx:
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None
                # Don't fade a favorite who is already winning sets
                # YES side = favorite. If favorite leads in sets, price is correct
                if tctx.sets_down <= 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):
                    return None  # favorite already won a set — not a fade
                ctx_reason = f"Tennis live | {ctx_reason}"
        elif live:
            return None  # never enter live tennis without context

    # Hard confidence floor
    if conf < 0.60:
        log.debug(f"[value_fade] SKIP {m.ticker} — confidence {conf} below floor")
        return None

    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.no_bid, 0.01)),
                                Config.MAX_CONTRACTS))
    contracts = _scale_contracts(base_contracts, conf)

    ev = _ev(contracts, no_bid_cents, conf, is_maker=True)
    if ev < 2.0: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="no", action="buy", price=no_bid_cents, contracts=contracts,
        strategy="value_fade",
        reason=f"Fade {int(m.yes_bid*100)}c | NO={no_bid_cents}c vol={int(m.volume)} "
               f"sprd={m.spread}c conf={conf} | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 2: NBA/MLB Prop YES (disabled — kept for reference)
# =============================================================================
def strategy_prop_yes(item, espn_cache=None):  # DISABLED: fake confidence, replaced by strategy_prop_edge
    return None
    from models import TradeSignal, Config
    m=item["market"]
    if not _is_prop(m.ticker): return None
    sport=item.get("sport","")
    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)
    if m.yes_bid < 0.62 or m.yes_bid > 0.78: return None
    if m.volume < 5000 or m.spread > 4: return None
    if live and espn_cache and _NBA_CTX:
        ctx=find_game_for_ticker(m.ticker, espn_cache)
        if ctx and ctx.is_live:
            if ctx.nba_quarter > 2:
                return None
            try:
                if ctx.clock_secs > 660:
                    return None
            except: pass
    conf=0.65
    ctx_reason="pre-game prop"
    if _NBA_CTX and espn_cache:
        enter,ctx_conf,ctx_reason=should_enter_prop(m.ticker, m.yes_bid, espn_cache)
        if not enter: return None
        conf=max(conf, ctx_conf)
    else:
        if live: return None
        ctx_reason="pre-game no ESPN"
    if conf < 0.63: return None
    if m.yes_bid < 0.62 and conf < 0.68: return None
    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)
    ev=_ev(contracts,price_cents,conf)
    if ev < 2.0: return None
    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="prop_yes",
        reason=f"Prop YES: bid={int(m.yes_bid*100)}c vol={int(m.volume)} | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 3: Tennis Live Underdog
# =============================================================================
def strategy_tennis_underdog(item, espn_cache=None):
    from models import TradeSignal, Config
    m=item["market"]
    sport=item.get("sport","")
    if sport != "Tennis": return None
    if not _is_tennis(m.ticker): return None
    status=item.get("market_status","active")
    live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)
    if not live: return None
    if m.yes_bid < 0.20 or m.yes_bid > 0.38: return None
    if m.volume < 8000 or m.spread > 3: return None
    if not _TENNIS_CTX or not espn_cache:
        return None
    tctx=get_tennis_context(m.ticker, espn_cache)
    if not tctx or not tctx.is_live:
        return None
    if tctx.sets_down >= 2:  # YES player down 2 sets — match nearly lost
        return None
    if abs(tctx.p1_games - tctx.p2_games) > 3:
        return None
    conf=tctx.underdog_conf
    # Hard floor — context must actually support the trade
    if conf < 0.63: return None
    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)
    ev=_ev(contracts,price_cents,conf)
    if ev < 2.0: return None
    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="tennis_underdog",
        reason=f"Tennis underdog: {tctx.summary()} | sets_down={tctx.sets_down} conf={conf}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 4: Quarter/Half Winner
# =============================================================================
def strategy_quarter_winner(item, espn_cache=None):  # DISABLED: 40-60c is most efficient zone, no edge possible
    return None
    from models import TradeSignal, Config
    m=item["market"]
    if not any(m.ticker.startswith(s) for s in [
        "KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER",
        "KXNBA1HWINNER","KXNBA2HWINNER",
    ]): return None
    status=item.get("market_status","active")
    if status != "open": return None
    if m.yes_bid < 0.40 or m.yes_bid > 0.60: return None
    if m.volume < 2000 or m.spread > 5: return None
    conf=0.60
    ctx_reason="pre-game Q/H"
    if _NBA_CTX and espn_cache:
        enter,ctx_conf,ctx_reason=nba_value_fade_check(m.ticker, m.yes_bid, espn_cache)
        if not enter: return None
        conf=max(conf, ctx_conf)
    # Hard floor
    if conf < 0.63: return None
    price_cents=int(m.yes_ask*100)
    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.yes_ask,0.01)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)
    ev=_ev(contracts,price_cents,conf)
    if ev < 2.0: return None
    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="yes", action="buy", price=price_cents, contracts=contracts,
        strategy="quarter_winner",
        reason=f"Q/H winner: bid={int(m.yes_bid*100)}c vol={int(m.volume)} | {ctx_reason}",
        confidence=conf,
    )

# =============================================================================
# STRATEGY 5: NBA Player Props (Points + 3PT)
# =============================================================================
def strategy_prop_nba(item, espn_cache=None):  # DISABLED: 55-62c too narrow, normal dist model invalid
    return None
    from models import TradeSignal, Config
    m = item["market"]
    if not any(m.ticker.startswith(s) for s in ["KXNBAPTS", "KXNBA3PT"]):
        return None
    status = item.get("market_status", "active")
    sport = item.get("sport", "")
    if m.yes_bid < 0.55 or m.yes_bid > 0.62: return None
    if m.volume < 5000 or m.spread > 5: return None
    if not _NBA_PROPS: return None
    ctx = get_nba_prop_context(m.ticker, m.yes_bid, espn_cache)
    if not ctx or not ctx.should_enter:
        return None
    conf = ctx.confidence
    # Hard floor
    if conf < 0.63: return None
    price_cents = int(m.yes_ask * 100)
    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.15)), Config.MAX_CONTRACTS))
    contracts = _scale_contracts(base_contracts, conf)
    ev = _ev(contracts, price_cents, conf)
    if ev < 2.0: return None
    return TradeSignal(
        event_ticker = item["event_ticker"],
        market_ticker = m.ticker,
        side = "yes",
        action = "buy",
        price = price_cents,
        contracts = contracts,
        strategy = "prop_nba",
        reason = f"NBA {ctx.stat_type}: {ctx.reason} | edge={ctx.edge:+.2f}",
        confidence = conf,
    )

# =============================================================================
# STRATEGY 6: MLB Spring Training Underdog
# =============================================================================
def strategy_mlb_underdog(item, espn_cache=None):  # DISABLED: spring training records near-zero predictive value
    return None
    from models import TradeSignal, Config
    m = item["market"]
    if not m.ticker.startswith("KXMLBSTGAME"):
        return None
    status = item.get("market_status", "active")
    if status != "open":
        return None
    if m.yes_bid < 0.33 or m.yes_bid > 0.65: return None
    if m.volume < 400 or m.spread > 3: return None
    if not _MLB_PROPS: return None
    ctx = get_mlb_context(m.ticker, m.yes_bid)
    if not ctx or not ctx.should_enter:
        return None
    conf = ctx.confidence
    if conf < 0.63: return None
    price_cents = int(m.yes_ask * 100)
    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.15)), Config.MAX_CONTRACTS))
    contracts = _scale_contracts(base_contracts, conf)
    ev = _ev(contracts, price_cents, conf)
    if ev < 1.0: return None  # spring training lower bar
    return TradeSignal(
        event_ticker = item["event_ticker"],
        market_ticker = m.ticker,
        side = "yes",
        action = "buy",
        price = price_cents,
        contracts = contracts,
        strategy = "mlb_underdog",
        reason = f"MLB ST: {ctx.summary()}",
        confidence = conf,
    )

# =============================================================================
# EXIT STRATEGY
# =============================================================================
def strategy_exit(item, pos, espn_cache=None):
    from models import TradeSignal, Config
    from datetime import datetime, timezone

    m        = item["market"]
    side     = pos["side"]
    entry    = pos["entry_price"]
    contracts = pos["contracts"]
    strategy = pos["strategy"]

    if entry == 0: return None
    if pos.get("is_bot") is False: return None  # never auto-exit manual positions

    # Current bid — side-aware
    if side == "yes":
        bid = max(1, int(m.yes_bid * 100))
    else:
        bid = max(1, int(m.no_bid * 100))

    # P&L in cents from our perspective (positive = winning)
    move = bid - entry  # YES: up is good. NO: no_bid rising is good.

    # Fee estimate for logging
    fee_mult  = 0.0175
    entry_fee = pos.get("entry_fee", 0.0)
    exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
    pnl       = move * contracts / 100.0 - entry_fee - exit_fee

    # ── Fixed-cent exits ──────────────────────────────────────────
    TAKE_PROFIT_CENTS = 12
    STOP_LOSS_CENTS   = 6

    reason = None
    strat  = None

    if move >= TAKE_PROFIT_CENTS:
        reason = f"TP: +{move}c >= +{TAKE_PROFIT_CENTS}c | PNL=${pnl:.4f}"
        strat  = f"exit_tp_{strategy}"

    elif move <= -STOP_LOSS_CENTS:
        reason = f"SL: {move}c <= -{STOP_LOSS_CENTS}c | PNL=${pnl:.4f}"
        strat  = f"exit_sl_{strategy}"

    else:
        # ── Time stop ─────────────────────────────────────────────
        try:
            et = pos.get("entry_time", "")
            if et:
                age = (datetime.now(timezone.utc) -
                       datetime.fromisoformat(et)).total_seconds()
                strategy_name = pos.get("strategy", "")
                if "tennis" in strategy_name.lower():
                    max_age = 7200
                elif "mlb" in strategy_name.lower():
                    max_age = 10800
                else:
                    max_age = 5400  # 90 min NBA/other
                if age > max_age:
                    reason = f"TIME: {int(age/60)}min > {max_age//60}min | PNL=${pnl:.4f}"
                    strat  = f"exit_time_{strategy}"
        except:
            pass

    if reason is None:
        return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )

def _wrap(fn):
    @functools.wraps(fn)
    def w(item, espn_cache=None): return fn(item, espn_cache=espn_cache)
    return w

try:
    from strategy_momentum_reversal import strategy_momentum_reversal as _momentum_reversal
    _MOMENTUM = True
except ImportError:
    _MOMENTUM = False
    log.warning("[Strategies] strategy_momentum_reversal not found")

STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades
    # strategy_quarter_winner disabled — 40-60c zone has no edge
] + ([_wrap(_momentum_reversal)] if _MOMENTUM else [])
