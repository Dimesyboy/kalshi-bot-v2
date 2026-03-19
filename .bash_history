
cat << 'EOF' > /root/confidence_model.py
#!/usr/bin/env python3
"""
confidence_model.py
─────────────────────────────────────────────────────────────────
Data-driven confidence scoring for value_fade and other strategies.
Replaces the flat 0.65 hardcoded confidence.

Score is built from available signals:
  - Kalshi market signals (price stability, volume, spread)
  - ESPN team quality (win rate vs market price)
  - ESPN game context (home/away, back-to-back)
  - Injury report (star player missing)
  - Tennis API (ranking gap, H2H, surface)

Final confidence is clamped to [0.55, 0.78].
Below 0.55 = no edge, don't trade.
Above 0.78 = overconfident, cap it.
"""

import os
import re
import time
import logging
import requests
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict

log = logging.getLogger("kalshi_bot.confidence")

# ── Cache for back-to-back schedule ──────────────────────────────────────────
_b2b_cache: Dict = {}
_b2b_cache_ts: float = 0.0
B2B_CACHE_TTL = 3600  # refresh once per hour

# ── Cache for injury report ───────────────────────────────────────────────────
_injury_cache: Dict = {}
_injury_cache_ts: float = 0.0
INJURY_CACHE_TTL = 1800  # 30 min

# ── Price stability tracker ───────────────────────────────────────────────────
# ticker -> list of (timestamp, yes_bid) tuples
_price_history: Dict = {}
PRICE_HISTORY_MAX = 10


def record_price(ticker: str, yes_bid: float):
    """Call each cycle to build price history."""
    if ticker not in _price_history:
        _price_history[ticker] = []
    _price_history[ticker].append((time.time(), yes_bid))
    if len(_price_history[ticker]) > PRICE_HISTORY_MAX:
        _price_history[ticker].pop(0)


def _get_b2b_teams() -> set:
    """Return set of team abbreviations playing back-to-back today."""
    global _b2b_cache, _b2b_cache_ts
    now = time.time()
    if _b2b_cache and now - _b2b_cache_ts < B2B_CACHE_TTL:
        return _b2b_cache

    try:
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime('%Y%m%d')
        r = requests.get(
            f'http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard'
            f'?dates={yesterday}',
            timeout=6
        )
        r.raise_for_status()
        events = r.json().get('events', [])
        played = set()
        for e in events:
            comp = e.get('competitions', [{}])[0]
            for c in comp.get('competitors', []):
                abbr = c.get('team', {}).get('abbreviation', '')
                if abbr:
                    played.add(abbr.upper())
        _b2b_cache = played
        _b2b_cache_ts = now
        log.debug(f"[B2B] {len(played)} teams played yesterday")
        return played
    except Exception as e:
        log.debug(f"[B2B] fetch failed: {e}")
        return _b2b_cache or set()


def _get_injuries() -> Dict:
    """Return injury report dict {team_abbr: [{"name":..,"status":..}]}"""
    global _injury_cache, _injury_cache_ts
    now = time.time()
    if _injury_cache and now - _injury_cache_ts < INJURY_CACHE_TTL:
        return _injury_cache
    try:
        from nba_injuries import get_injury_report
        injuries = get_injury_report()
        _injury_cache = injuries
        _injury_cache_ts = now
        return injuries
    except Exception as e:
        log.debug(f"[Injuries] fetch failed: {e}")
        return _injury_cache or {}


def _win_rate(wins: int, losses: int) -> float:
    total = wins + losses
    return wins / total if total > 0 else 0.5


def _price_is_stable(ticker: str, min_cycles: int = 3) -> bool:
    """True if yes_bid has been at current level for min_cycles."""
    history = _price_history.get(ticker, [])
    if len(history) < min_cycles:
        return False
    recent = [h[1] for h in history[-min_cycles:]]
    return max(recent) - min(recent) < 0.02  # within 2c


def _price_trend(ticker: str) -> float:
    """
    Returns price velocity over last 3 cycles.
    Positive = price moving up (favorite getting stronger).
    Negative = price moving down (favorite weakening = better fade).
    """
    history = _price_history.get(ticker, [])
    if len(history) < 3:
        return 0.0
    old = history[-3][1]
    new = history[-1][1]
    return round((new - old) * 100, 2)  # in cents


def score_nba_mlb(
    ticker: str,
    yes_bid: float,
    espn_ctx,
    volume: float,
    spread: float,
) -> tuple:
    """
    Score a value_fade (buy NO) opportunity on NBA/MLB.
    Returns (confidence: float, reasons: list[str])
    """
    score = 0.60
    reasons = []

    if espn_ctx is None:
        reasons.append("no ESPN context — base confidence")
        return round(score, 3), reasons

    # ── Team quality vs market price ─────────────────────────────────────────
    # Which team is the favorite? The YES side.
    # We need to figure out which team corresponds to this ticker side
    fav_wr = None

    # Parse team from ticker
    from nba_context import parse_prop_ticker
    parsed = parse_prop_ticker(ticker)
    team1 = parsed.get("team1", "")
    team2 = parsed.get("team2", "")

    # Identify favorite team from ESPN context
    home_abbr = espn_ctx.home.abbreviation.upper()
    away_abbr = espn_ctx.away.abbreviation.upper()

    # Match ticker team to ESPN home/away
    fav_team = None
    if team1 and team1.upper() in (home_abbr, away_abbr):
        if team1.upper() == home_abbr:
            fav_team = "home"
            fav_wr = _win_rate(espn_ctx.home.record_wins, espn_ctx.home.record_loss)
        else:
            fav_team = "away"
            fav_wr = _win_rate(espn_ctx.away.record_wins, espn_ctx.away.record_loss)

    if fav_wr is not None:
        implied_prob = yes_bid  # market implied probability
        if fav_wr < implied_prob - 0.10:
            # Market significantly overpricing this team
            adj = min(0.07, (implied_prob - fav_wr) * 0.5)
            score += adj
            reasons.append(f"team overpriced: win_rate={fav_wr:.0%} vs market={implied_prob:.0%} (+{adj:.2f})")
        elif fav_wr < implied_prob - 0.05:
            score += 0.03
            reasons.append(f"team slightly overpriced: wr={fav_wr:.0%} (+0.03)")
        else:
            reasons.append(f"team pricing reasonable: wr={fav_wr:.0%}")

    # ── Home/away adjustment ──────────────────────────────────────────────────
    # Fading a road favorite is better than fading a home favorite
    if fav_team == "away":
        score += 0.02
        reasons.append("fading road favorite (+0.02)")
    elif fav_team == "home":
        score -= 0.01
        reasons.append("fading home favorite (-0.01)")

    # ── Back-to-back ─────────────────────────────────────────────────────────
    b2b_teams = _get_b2b_teams()
    fav_abbr = team1.upper() if team1 else ""
    if fav_abbr in b2b_teams:
        score += 0.04
        reasons.append(f"favorite on back-to-back (+0.04)")

    # ── Injury report ────────────────────────────────────────────────────────
    injuries = _get_injuries()
    fav_injuries = injuries.get(fav_abbr, [])

    STAR_NAMES = ["JAMES","CURRY","DURANT","GIANNIS","EMBIID","JOKIC",
                  "DONCIC","TATUM","BUTLER","EDWARDS","BRUNSON"]

    for inj in fav_injuries:
        name_upper = inj.get("name","").upper()
        status = inj.get("status","").upper()
        for star in STAR_NAMES:
            if star in name_upper:
                if "OUT" in status:
                    score += 0.06
                    reasons.append(f"star OUT: {inj['name']} (+0.06)")
                elif "QUESTIONABLE" in status:
                    score += 0.03
                    reasons.append(f"star questionable: {inj['name']} (+0.03)")
                elif "DOUBTFUL" in status:
                    score += 0.04
                    reasons.append(f"star doubtful: {inj['name']} (+0.04)")

    # ── Price stability ───────────────────────────────────────────────────────
    if _price_is_stable(ticker, min_cycles=3):
        score += 0.02
        reasons.append("price stable 3+ cycles (+0.02)")

    trend = _price_trend(ticker)
    if trend < -2:
        # Price moving down = favorite weakening = better fade
        score += 0.02
        reasons.append(f"price weakening {trend:+.1f}c (+0.02)")
    elif trend > 2:
        # Price moving up = momentum against us
        score -= 0.02
        reasons.append(f"price rising {trend:+.1f}c (-0.02)")

    # ── Volume ───────────────────────────────────────────────────────────────
    if volume >= 20000:
        score += 0.02
        reasons.append("high volume >20k (+0.02)")
    elif volume < 8000:
        score -= 0.01
        reasons.append("thin volume (-0.01)")

    # ── Extreme price boost ───────────────────────────────────────────────────
    if yes_bid >= 0.98:
        score += 0.02
        reasons.append("extreme 98c+ overconfidence (+0.02)")
    elif yes_bid >= 0.97:
        score += 0.01
        reasons.append("97c+ overconfidence (+0.01)")

    # ── Clamp ────────────────────────────────────────────────────────────────
    score = round(max(0.55, min(0.78, score)), 3)
    return score, reasons


def score_tennis(
    ticker: str,
    yes_bid: float,
    tctx,
    volume: float,
    spread: float,
) -> tuple:
    """
    Score a value_fade on tennis.
    Returns (confidence: float, reasons: list[str])
    """
    score = 0.60
    reasons = []

    if tctx is None:
        reasons.append("no tennis context — base confidence")
        return round(score, 3), reasons

    # ── Ranking gap ───────────────────────────────────────────────────────────
    # Small ranking gap = upset more realistic
    try:
        r1 = getattr(tctx, 'p1_rank', 999)
        r2 = getattr(tctx, 'p2_rank', 999)
        gap = abs(r1 - r2)
        if gap < 20:
            score += 0.04
            reasons.append(f"close ranking gap {gap} (+0.04)")
        elif gap < 50:
            score += 0.02
            reasons.append(f"moderate ranking gap {gap} (+0.02)")
        else:
            reasons.append(f"large ranking gap {gap}")
    except: pass

    # ── H2H ──────────────────────────────────────────────────────────────────
    try:
        h2h = getattr(tctx, 'h2h', '')
        if h2h and h2h != '?':
            # Parse "Player 1-0 Opponent" format
            parts = h2h.split()
            if len(parts) >= 3:
                record = parts[-1]
                wins_losses = record.split('-')
                if len(wins_losses) == 2:
                    fav_h2h_wins = int(wins_losses[0])
                    und_h2h_wins = int(wins_losses[1])
                    total_h2h = fav_h2h_wins + und_h2h_wins
                    if total_h2h >= 3:
                        und_rate = und_h2h_wins / total_h2h
                        if und_rate >= 0.40:
                            score += 0.03
                            reasons.append(f"H2H balanced {record} (+0.03)")
                        elif und_rate == 0:
                            score -= 0.02
                            reasons.append(f"H2H dominated by favorite {record} (-0.02)")
    except: pass

    # ── Match completion ──────────────────────────────────────────────────────
    try:
        pct = tctx.pct_complete if not callable(tctx.pct_complete) else tctx.pct_complete()
        if pct > 0.85:
            score -= 0.03
            reasons.append(f"match nearly over {pct:.0%} (-0.03)")
        elif pct > 0.60:
            score -= 0.01
            reasons.append(f"late match {pct:.0%} (-0.01)")
    except: pass

    # ── Price signals ─────────────────────────────────────────────────────────
    if _price_is_stable(ticker, min_cycles=3):
        score += 0.02
        reasons.append("price stable (+0.02)")

    if yes_bid >= 0.97:
        score += 0.02
        reasons.append("extreme 97c+ (+0.02)")

    if volume >= 8000:
        score += 0.01
        reasons.append("good volume (+0.01)")

    # ── Clamp ────────────────────────────────────────────────────────────────
    score = round(max(0.55, min(0.78, score)), 3)
    return score, reasons


def score_value_fade(item, espn_cache=None) -> tuple:
    """
    Main entry point. Call from strategy_value_fade instead of using flat 0.65.
    Returns (confidence: float, reason_str: str)
    """
    m = item["market"]
    sport = item.get("sport", "")
    ticker = m.ticker
    yes_bid = m.yes_bid
    volume = m.volume
    spread = m.spread

    # Record price for stability tracking
    record_price(ticker, yes_bid)

    if sport in ("NBA", "MLB"):
        from nba_context import find_game_for_ticker
        ctx = find_game_for_ticker(ticker, espn_cache) if espn_cache else None
        conf, reasons = score_nba_mlb(ticker, yes_bid, ctx, volume, spread)
    elif sport == "Tennis":
        tctx = None
        try:
            from tennis_context import get_tennis_context
            tctx = get_tennis_context(ticker, espn_cache)
        except: pass
        conf, reasons = score_tennis(ticker, yes_bid, tctx, volume, spread)
    else:
        conf = 0.65
        reasons = ["unknown sport — base confidence"]

    reason_str = " | ".join(reasons)
    log.debug(f"[Confidence] {ticker} -> {conf} | {reason_str}")
    return conf, reason_str
EOF

echo "confidence_model.py written"
python3 -c "import ast; ast.parse(open('/root/confidence_model.py').read()); print('Syntax OK')"
grep -n "conf=0.65\|ctx_reason\|Pre-game fade\|pre-game no ESPN" /root/strategies.py | head -20
sed -n '360,430p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    conf=0.65
    ctx_reason="no context"

    if _is_nba_mlb(m.ticker):
        if _is_prop(m.ticker): return None
        if live:
            if not _NBA_CTX or not espn_cache:
                return None
            ctx=find_game_for_ticker(m.ticker, espn_cache)
            if not ctx:
                return None
            if not ctx.is_live:
                return None
            # Only Q1 or Q2
            if ctx.nba_quarter > 2:
                return None
            # Tightened: lead must be < 5, not < 8
            # Lead of 8 in Q1 is already meaningful in NBA — don't fade it
            if abs(ctx.lead) > 5:
                return None
            conf=0.66
            ctx_reason=f"Live Q{ctx.nba_quarter} lead={ctx.lead} — early game fade"
        else:
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
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None
                conf=min(0.68, tctx.underdog_conf)
                ctx_reason=f"Tennis live fade: {tctx.summary()}"
            else:
                conf=0.65; ctx_reason="tennis live no ctx"
        else:
            conf=0.65; ctx_reason="tennis pre-game"

    # Hard confidence floor — must clear 0.63 to proceed
    if conf < 0.63:
        return None

    base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.no_bid,0.15)),Config.MAX_CONTRACTS))
    contracts=_scale_contracts(base_contracts, conf)

    if m.yes_bid>=0.98: conf=min(conf+0.02, 0.72)
    if m.yes_bid>=0.99: conf=min(conf+0.02, 0.74)

    ev=_ev(contracts,no_bid_cents,conf,is_maker=True)
    # Raised EV gate from 0.08 to 0.12 — filters marginal fades
    if ev < 2.0: return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side="no", action="buy", price=no_bid_cents, contracts=contracts,
        strategy="value_fade",
        reason=f"Fade {int(m.yes_bid*100)}c | NO={no_bid_cents}c vol={int(m.volume)} sprd={m.spread}c | {ctx_reason}",
        confidence=conf,
    )'''

new = '''    # ── Data-driven confidence scoring ──────────────────────────────────────
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
                ctx_reason = f"Tennis live | {ctx_reason}"

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
    )'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("strategy_value_fade wired to confidence_model")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'PYEOF'
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache
from confidence_model import score_value_fade, record_price

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

print("CONFIDENCE MODEL TEST")
print("="*80)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append((sig, item))
                break
        except Exception as e:
            pass

print(f"Signals fired: {len(fired)}")
print()
for sig, item in fired:
    print(f"  {sig.market_ticker}")
    print(f"  {sig.side} @ {sig.price}c x{sig.contracts} conf={sig.confidence}")
    print(f"  {sig.reason}")
    print()

# Also show confidence scores for top markets even if not fired
print("="*80)
print("CONFIDENCE SCORES — top bid markets:")
top = sorted(watchlist, key=lambda x: x['market'].yes_bid, reverse=True)[:8]
for item in top:
    m = item['market']
    if m.yes_bid < 0.85: continue
    record_price(m.ticker, m.yes_bid)
    conf, reason = score_value_fade(item, espn_cache=espn_cache)
    print(f"  {m.ticker}")
    print(f"  bid={int(m.yes_bid*100)}c conf={conf} | {reason}")
    print()
PYEOF

python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import strategy_value_fade, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for item in watchlist:
    m = item['market']
    if 'BOS' not in m.ticker: continue
    print(f'Market: {m.ticker}')
    print(f'  yes_bid={m.yes_bid} no_bid={m.no_bid} volume={m.volume} spread={m.spread}')
    print(f'  status={item[\"market_status\"]}')
    sig = strategy_value_fade(item, espn_cache=espn_cache)
    print(f'  signal={sig}')
    if not sig:
        # trace why
        no_bid_c = int(m.no_bid*100)
        print(f'  no_bid_cents={no_bid_c}')
        print(f'  volume check: {m.volume} >= 5000? {m.volume >= 5000}')
        print(f'  spread check: {m.spread} <= 3? {m.spread <= 3}')
        print(f'  yes_bid check: {m.yes_bid} >= 0.92? {m.yes_bid >= 0.92}')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()
old = '    if m.yes_bid < 0.92: return None  # lowered from 0.95 — EV positive at 92c+, BE% < 9%'
new = '    if m.yes_bid < 0.90: return None  # lowered from 0.92 — confidence model handles quality filter'
if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Threshold lowered to 90c")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append(sig)
                break
        except: pass

print(f'Signals: {len(fired)}')
for sig in fired:
    print(f'  {sig.market_ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence}')
    print(f'  {sig.reason}')
    print()
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import strategy_value_fade, ESPNContextCache
from confidence_model import score_value_fade, record_price

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for item in watchlist:
    m = item['market']
    if 'BOS' not in m.ticker: continue
    print(f'{m.ticker} bid={int(m.yes_bid*100)}c vol={int(m.volume)}')
    record_price(m.ticker, m.yes_bid)
    conf, reason = score_value_fade(item, espn_cache)
    print(f'  conf={conf} reason={reason}')
    sig = strategy_value_fade(item, espn_cache=espn_cache)
    print(f'  signal={sig is not None}')
    if not sig:
        print(f'  no_bid={m.no_bid} no_bid_cents={int(m.no_bid*100)}')
        from strategies import _is_stale_high
        print(f'  stale_high={_is_stale_high(m.ticker, m.yes_bid)}')
        print(f'  volume>={5000}: {m.volume>=5000}')
        print(f'  spread<=3: {m.spread<=3}')
        print(f'  yes_bid>=0.90: {m.yes_bid>=0.90}')
    print()
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from strategies import _ev
import math

# BOS: NO @ 8c, 12 contracts (MAX_POSITION_USD/0.08 = 3.35/0.08 = 41 contracts, capped by MAX_CONTRACTS=100)
# Actually: int(3.35/0.08) = 41 contracts
contracts = 41
price_c = 8
conf = 0.69

ev = _ev(contracts, price_c, conf, is_maker=True)
print(f'contracts={contracts} price={price_c}c conf={conf}')
print(f'EV={ev}')
print(f'EV >= 2.0? {ev >= 2.0}')
print()

# Check what _scale_contracts does
from strategies import _scale_contracts
base = 41
scaled = _scale_contracts(base, conf)
print(f'base_contracts={base} scaled={scaled}')
ev2 = _ev(scaled, price_c, conf, is_maker=True)
print(f'EV with scaled contracts={ev2}')
"
grep -n "def _scale_contracts" /root/strategies.py
sed -n '/def _scale_contracts/,/^def /p' /root/strategies.py | head -10
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''def _scale_contracts(base_contracts, confidence, max_contracts=20):
    """Scale position size by confidence above 0.63 floor.
    Tighter floor than before — only meaningful confidence gets a boost."""
    scale = 1.0 + max(0.0, (confidence - 0.63) / 0.10) * 0.5
    return max(1, min(int(base_contracts * scale), max_contracts))'''

new = '''def _scale_contracts(base_contracts, confidence, max_contracts=None):
    """Scale position size by confidence above 0.60 floor.
    Uses Config.MAX_CONTRACTS as ceiling unless overridden."""
    if max_contracts is None:
        try:
            from models import Config
            max_contracts = Config.MAX_CONTRACTS
        except:
            max_contracts = 100
    scale = 1.0 + max(0.0, (confidence - 0.60) / 0.10) * 0.5
    return max(1, min(int(base_contracts * scale), max_contracts))'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("_scale_contracts fixed — uses Config.MAX_CONTRACTS")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append(sig)
                break
        except: pass

print(f'Signals: {len(fired)}')
for sig in fired:
    print(f'  {sig.market_ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence}')
    print(f'  {sig.reason[:100]}')
    print()
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import strategy_value_fade, ESPNContextCache, _scale_contracts, _ev
from confidence_model import score_value_fade, record_price
from models import Config

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for item in watchlist:
    m = item['market']
    if 'BOSMEM-BOS' not in m.ticker: continue
    print(f'MAX_POSITION_USD={Config.MAX_POSITION_USD}')
    print(f'MAX_CONTRACTS={Config.MAX_CONTRACTS}')
    no_bid = m.no_bid
    print(f'no_bid={no_bid}')
    base = max(1, min(int(Config.MAX_POSITION_USD / max(no_bid, 0.01)), Config.MAX_CONTRACTS))
    print(f'base_contracts={base}')
    record_price(m.ticker, m.yes_bid)
    conf, reason = score_value_fade(item, espn_cache)
    print(f'conf={conf}')
    scaled = _scale_contracts(base, conf)
    print(f'scaled_contracts={scaled}')
    ev = _ev(scaled, int(no_bid*100), conf)
    print(f'ev={ev} >= 2.0? {ev >= 2.0}')
    sig = strategy_value_fade(item, espn_cache=espn_cache)
    print(f'signal={sig}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import ESPNContextCache, _allowed, _is_prop, _is_nba_mlb, _is_stale_high
from nba_context import find_game_for_ticker

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for item in watchlist:
    m = item['market']
    if 'BOSMEM-BOS' not in m.ticker: continue
    print('--- Tracing BOSMEM-BOS ---')
    print(f'_allowed: {_allowed(m.ticker)}')
    print(f'_is_prop: {_is_prop(m.ticker)}')
    print(f'_is_nba_mlb: {_is_nba_mlb(m.ticker)}')
    print(f'_is_stale_high: {_is_stale_high(m.ticker, m.yes_bid)}')
    print(f'yes_bid >= 0.90: {m.yes_bid >= 0.90}')
    print(f'no_bid_cents: {int(m.no_bid*100)}')
    print(f'no_bid >= 5: {int(m.no_bid*100) >= 5}')
    ctx = find_game_for_ticker(m.ticker, espn_cache)
    print(f'ESPN ctx: {ctx}')
    if ctx:
        print(f'  is_final={ctx.is_final} is_live={ctx.is_live}')
"
python3 << 'EOF'
content = open('/root/nba_context.py').read()

old = '''def find_game_for_ticker(ticker: str, espn_cache) -> Optional[object]:
    """Find ESPN GameContext matching a Kalshi NBA ticker."""
    if not espn_cache: return None
    parsed = parse_prop_ticker(ticker)
    team1 = parsed.get("team1","")
    team2 = parsed.get("team2","")
    if not team1 or not team2: return None

    # Match on abbreviation directly (LAL, GSW etc.) — name substring fails for 3-letter codes
    nba_col = espn_cache._all.get("NBA")
    if nba_col:
        for ctx in nba_col:
            if ctx.home.abbreviation in (team1, team2) or ctx.away.abbreviation in (team1, team2):
                return ctx
    # fallback: name substring
    for team in [team1, team2]:
        ctx = espn_cache.find("NBA", team)
        if ctx: return ctx
    return None'''

new = '''def find_game_for_ticker(ticker: str, espn_cache) -> Optional[object]:
    """Find ESPN GameContext matching a Kalshi NBA ticker.
    Prefers live/pre-game matches over final games.
    Falls back to final games only if no active game found.
    """
    if not espn_cache: return None
    parsed = parse_prop_ticker(ticker)
    team1 = parsed.get("team1","")
    team2 = parsed.get("team2","")
    if not team1 or not team2: return None

    nba_col = espn_cache._all.get("NBA")
    if not nba_col:
        return None

    # First pass — find live or pre-game match (not final)
    for ctx in nba_col:
        if ctx.is_final:
            continue
        if ctx.home.abbreviation in (team1, team2) or ctx.away.abbreviation in (team1, team2):
            return ctx

    # Second pass — match both teams simultaneously (more precise)
    for ctx in nba_col:
        home = ctx.home.abbreviation
        away = ctx.away.abbreviation
        if (home in (team1, team2)) and (away in (team1, team2)):
            return ctx

    # Final fallback — any match including finished games
    for ctx in nba_col:
        if ctx.home.abbreviation in (team1, team2) or ctx.away.abbreviation in (team1, team2):
            return ctx

    return None'''

if old in content:
    content = content.replace(old, new)
    open('/root/nba_context.py', 'w').write(content)
    print("find_game_for_ticker fixed — prefers live/pre-game over final")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/nba_context.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append(sig)
                break
        except: pass

print(f'Signals: {len(fired)}')
for sig in fired:
    print(f'  {sig.market_ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence}')
    print(f'  {sig.reason[:110]}')
    print()
"
grep -n "is_final\|_ctx and _ctx" /root/strategies.py | head -10
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import strategy_value_fade, ESPNContextCache
from nba_context import find_game_for_ticker

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for item in watchlist:
    m = item['market']
    if 'BOSMEM-BOS' not in m.ticker: continue
    ctx = find_game_for_ticker(m.ticker, espn_cache)
    print(f'ctx after fix: {ctx}')
    print(f'yes_bid={m.yes_bid} in watchlist: {item[\"flag\"]}')
    sig = strategy_value_fade(item, espn_cache=espn_cache)
    print(f'signal={sig}')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    # never enter a position on a game ESPN has already marked as finished
    if espn_cache is not None and _is_nba_mlb(m.ticker):
        from nba_context import find_game_for_ticker
        _ctx = find_game_for_ticker(m.ticker, espn_cache)
        if _ctx and _ctx.is_final:
            return None'''

new = '''    # never enter a position on a game ESPN has already marked as finished
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
                return None  # confirmed same game, it's final'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("is_final guard fixed — requires both teams to match")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append(sig)
                break
        except: pass

print(f'Signals: {len(fired)}')
for sig in fired:
    print(f'  {sig.market_ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence}')
    print(f'  {sig.reason[:110]}')
    print()
"
cd /root && git add -A && git commit -m "feat: confidence_model.py — data-driven scoring (team wr, b2b, injuries, price stability, H2H), is_final guard fixed, find_game_for_ticker prefers live/pre-game, _scale_contracts uses Config.MAX_CONTRACTS, threshold 90c | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
screen -S kalshi -X quit
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
sleep 8
tail -20 /root/kalshi_bot.log
screen -r
tail -50 /root/kalshi_bot.log | grep -E "PLACED|Position recorded|SIGNAL|value_fade|conf"
cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
print(f'Open positions: {len(p)}')
for t,v in p.items():
    print(f'  {t}')
    print(f'    {v[\"side\"]} @ {v[\"entry_price\"]}c x{v[\"contracts\"]} conf={v.get(\"confidence\",\"?\")} [{v[\"strategy\"]}]')
"
grep -E "DET|GEA|Reconcile|Removed|resting" /root/kalshi_bot.log | tail -20
cat /root/bot_orders.json
grep -A 15 "DET\|GEA" /root/kalshi_bot.log | grep -A 10 "Position recorded" | head -30
grep -n "order_id.*order\|\"order_id\"" /root/kalshi_bot.py | head -10
sed -n '258,278p' /root/strategies.py
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python, json

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)
resting = [(o.order_id, o.ticker, o.status) for o in (resp.orders or [])]
print(f'Total orders returned: {len(resting)}')
print('Resting orders:')
for oid, ticker, status in resting:
    if status in ('resting','pending'):
        print(f'  {ticker} | {oid} | {status}')

bot_orders = set(json.load(open('/root/bot_orders.json')))
print(f'\nbot_orders.json has {len(bot_orders)} IDs')
for oid, ticker, status in resting:
    if status in ('resting','pending'):
        print(f'  {oid[:8]}... in bot_orders: {oid in bot_orders}')
"
python3 -c "
import json
orders = json.load(open('/root/bot_orders.json'))
nyk_id = '83a6b4aa-8f2b-4fc6-86d6-1fc6cf4a9d97'
if nyk_id not in orders:
    orders.append(nyk_id)
    json.dump(orders, open('/root/bot_orders.json','w'), indent=2)
    print(f'Added NYK order ID. Total: {len(orders)}')
else:
    print('Already present')
"
tail -20 /root/kalshi_bot.log | grep -E "Reconcile|resting|keeping|Removed|position"
cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
print(f'Positions: {len(p)}')
for t,v in p.items():
    print(f'  {t}')
    print(f'    side={v[\"side\"]} entry={v[\"entry_price\"]}c x{v[\"contracts\"]} strategy={v[\"strategy\"]} is_bot={v.get(\"is_bot\")}')
"
python3 /root/kalshi_bot.py -status
cd /root && git add -A && git commit -m "feat: confidence_model wired, is_final guard fixed, find_game_for_ticker pre-game priority, _scale_contracts uses Config, resting order recovery, b2b detection, injury report | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
screen -r
python3 -c "
import requests
r = requests.get('https://api.elections.kalshi.com/trade-api/v2/markets/KXATPCHALLENGERMATCH-26MAR19MICGEA-MIC', timeout=6)
m = r.json().get('market',{})
print('status:', m.get('status'))
print('result:', m.get('result'))
print('yes_bid:', float(m.get('yes_bid_dollars',0) or 0)*100, 'c')
print('no_bid:', float(m.get('no_bid_dollars',0) or 0)*100, 'c')
"
grep -n "sets_down\|pct_complete\|live.*tennis\|tennis.*live" /root/strategies.py | head -15
grep "MICGEA" /root/kalshi_bot.log | head -10
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    elif _is_tennis(m.ticker):
        if live and _TENNIS_CTX and espn_cache:
            tctx = get_tennis_context(m.ticker, espn_cache)
            if tctx:
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None
                ctx_reason = f"Tennis live | {ctx_reason}"'''

new = '''    elif _is_tennis(m.ticker):
        if live and _TENNIS_CTX and espn_cache:
            tctx = get_tennis_context(m.ticker, espn_cache)
            if tctx:
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None
                # Don't fade a favorite who is already winning sets
                # YES side = favorite. If favorite leads in sets, price is correct
                if tctx.sets_down == 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):
                    return None  # favorite already won a set — not a fade
                ctx_reason = f"Tennis live | {ctx_reason}"
        elif live:
            return None  # never enter live tennis without context'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Tennis live fade guard added")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from tennis_context import get_tennis_context
from strategies import ESPNContextCache

espn_cache = ESPNContextCache()

# Simulate what the context looks like for GEA ticker
# MICGEA-GEA means YES=GEA wins, NO=Michalski wins
# sets_down should be from GEA's perspective
for ticker in ['KXATPCHALLENGERMATCH-26MAR19MICGEA-GEA',
               'KXATPCHALLENGERMATCH-26MAR19MICGEA-MIC']:
    try:
        ctx = get_tennis_context(ticker, espn_cache)
        if ctx:
            print(f'{ticker}')
            print(f'  live={ctx.is_live} sets_down={ctx.sets_down}')
            print(f'  p1_sets={ctx.p1_sets} p2_sets={ctx.p2_sets}')
            print(f'  summary: {ctx.summary()}')
        else:
            print(f'{ticker} -> no context (match over)')
    except Exception as e:
        print(f'{ticker} -> error: {e}')
"
grep -n "sets_down\|def.*sets\|p1_sets\|p2_sets" /root/tennis_context.py | head -20
sed -n '220,270p' /root/tennis_context.py
sed -n '270,330p' /root/tennis_context.py
sed -n '330,380p' /root/tennis_context.py
grep -n "_parse_ticker_players" /root/tennis_context.py
sed -n '/def _parse_ticker_players/,/^def /p' /root/tennis_context.py | head -30
python3 << 'EOF'
content = open('/root/tennis_context.py').read()

old = '''        sets_down  = abs(p1_sets - p2_sets)'''

new = '''        # sets_down = sets the YES/ticker player (p1) has lost
        # positive means p1 is behind, negative means p1 is ahead
        # we keep it as p2_sets - p1_sets so positive = p1 losing
        sets_down  = p2_sets - p1_sets  # positive = YES player losing (underdog situation)'''

if old in content:
    content = content.replace(old, new)
    open('/root/tennis_context.py', 'w').write(content)
    print("sets_down fixed — now direction-aware (positive = YES player losing)")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/tennis_context.py').read()); print('Syntax OK')"
echo "Done"
grep -n "sets_down" /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

# value_fade guard — don't fade if YES player (p1) is already ahead (sets_down <= 0)
old = '''                total_sets = tctx.p1_sets + tctx.p2_sets
                if total_sets > 0 and tctx.sets_down == 0:
                    return None  # favorite is leading in sets — price is correct, don't fade'''

new = '''                total_sets = tctx.p1_sets + tctx.p2_sets
                if total_sets > 0 and tctx.sets_down <= 0:
                    return None  # YES player leading or tied — price is correct, don't fade'''

if old in content:
    content = content.replace(old, new)
    print("value_fade sets_down guard updated")
else:
    print("value_fade pattern not found")

# tennis_underdog guard — sets_down >= 2 means YES player down 2 sets (match nearly over)
old2 = '    if tctx.sets_down >= 2:'
new2 = '    if tctx.sets_down >= 2:  # YES player down 2 sets — match nearly lost'
content = content.replace(old2, new2)
print("tennis_underdog guard updated")

open('/root/strategies.py', 'w').write(content)
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
grep -n "sets_down\|total_sets\|leading in sets\|price is correct" /root/strategies.py
sed -i 's/                if tctx.sets_down == 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):/                if tctx.sets_down <= 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):/' /root/strategies.py
echo "Fixed"
grep -n "sets_down" /root/strategies.py
python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
grep -n "sets_down\|p1_sets\|p2_sets" /root/confidence_model.py
screen -S kalshi -X quit
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
cd /root && git add -A && git commit -m "fix: sets_down direction-aware (positive=YES player losing), tennis fade blocked when favorite leading, both-team is_final check | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
python3 << 'PYEOF'
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market, TradeSignal
from strategies import strategy_exit
from datetime import datetime, timezone, timedelta

def make_pos(side, entry, peak, strategy='value_fade', minutes_ago=45):
    entry_time = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    return {
        'side': side, 'entry_price': entry, 'peak_price': peak,
        'contracts': 20, 'strategy': strategy,
        'entry_time': entry_time, 'event_ticker': 'KXATPMATCH-TEST',
        'entry_fee': 0.02, 'is_bot': True
    }

def make_tennis_item(yes_bid, no_bid, ticker='KXATPMATCH-TEST-FAV'):
    m = Market(
        ticker=ticker, title='Test Tennis',
        yes_bid=yes_bid/100, yes_ask=(yes_bid+2)/100,
        no_bid=no_bid/100, no_ask=(no_bid+2)/100,
        last_price=yes_bid/100, volume=10000, liquidity=500,
        close_time=None, series='KXATPMATCH', label='ATP Match',
        market_status='active'
    )
    return {
        'sport': 'Tennis', 'event_ticker': 'KXATPMATCH-TEST',
        'game_title': 'Test Match', 'market': m,
        'flag': 'SIGNAL', 'reason': 'test', 'market_status': 'active'
    }

scenarios = [
    # Description, side, entry, peak, yes_bid, no_bid, expect_exit
    # NO positions (fading favorite)
    ("NO@9c entry, fav moves to 95c (no momentum yet)",         'no', 9,  9,  95,  4,  False),
    ("NO@9c entry, underdog wins set 1 → NO spikes to 20c",     'no', 9,  20, 80,  18, False),  # not at 3x yet
    ("NO@9c entry, underdog leads → NO spikes to 28c (3x hit)", 'no', 9,  28, 72,  26, True),   # trail activates at 27c, stop=22c
    ("NO@9c entry, match tied → NO at 30c, drops to 22c",       'no', 9,  30, 78,  22, True),   # trail stop = 24c, 22<=24
    ("NO@9c hard stop — fav dominating, NO drops to 5c",        'no', 9,  9,  95,  5,  True),   # 5 <= 9*0.6=5.4
    ("NO@9c hard stop — fav at 99c, NO at 1c",                  'no', 9,  9,  99,  1,  True),   # 1 <= 5.4
    # YES positions (bought underdog YES)
    ("YES@25c entry, underdog winning → spikes to 50c",         'yes',25, 50, 48,  50, False),  # 48 < 25*1.5=37.5? No 48>37.5, trail=40, 48>40 hold
    ("YES@25c peak=50c, drops to 38c (trail stop)",             'yes',25, 50, 38,  60, True),   # 38 <= 50*0.8=40 TRAIL
    ("YES@25c hard stop — drops to 14c",                        'yes',25, 25, 14,  84, True),   # 14 <= 25*0.6=15
    ("YES@25c holding — at 30c, below activation",              'yes',25, 30, 30,  68, False),  # 30 < 37.5 activation
]

print(f"{'Pass':<5} {'Exit':<6} {'Scenario':<55} {'Reason'}")
print('-'*110)
all_pass = True
for desc, side, entry, peak, yes_bid, no_bid, expect in scenarios:
    pos = make_pos(side, entry, peak)
    item = make_tennis_item(yes_bid, no_bid)
    sig = strategy_exit(item, pos)
    exited = sig is not None
    passed = exited == expect
    if not passed: all_pass = False
    mark = 'OK  ' if passed else 'FAIL'
    reason = sig.reason[:45] if sig else 'HOLD'
    print(f"{mark}  {str(exited):<6} {desc:<55} {reason}")

print()
print('All passed ✅' if all_pass else 'SOME FAILED ❌')
PYEOF

python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market
from strategies import strategy_exit
from datetime import datetime, timezone, timedelta

entry_time = (datetime.now(timezone.utc) - timedelta(minutes=45)).isoformat()
pos = {
    'side': 'no', 'entry_price': 9, 'peak_price': 30,
    'contracts': 20, 'strategy': 'value_fade',
    'entry_time': entry_time, 'event_ticker': 'KXATPMATCH-TEST',
    'entry_fee': 0.02, 'is_bot': True
}
m = Market(
    ticker='KXATPMATCH-TEST-FAV', title='Test',
    yes_bid=0.78, yes_ask=0.80,
    no_bid=0.22, no_ask=0.24,
    last_price=0.78, volume=10000, liquidity=500,
    close_time=None, series='KXATPMATCH', label='ATP',
    market_status='active'
)
item = {
    'sport':'Tennis','event_ticker':'KXATPMATCH-TEST',
    'game_title':'Test','market':m,
    'flag':'SIGNAL','reason':'test','market_status':'active'
}

# Manual trace
bid = max(1, int(m.no_bid*100))
print(f'bid={bid}')
print(f'entry=9, peak=30')
print(f'trail_mult=3.0 (no, entry<=15)')
print(f'trail_active: {bid} >= {9*3.0} = {bid >= 9*3.0}')
trail_stop = int(30 * 0.80)
print(f'trail_stop={trail_stop}')
print(f'bid<=trail_stop: {bid} <= {trail_stop} = {bid <= trail_stop}')
hard_stop = int(9 * 0.60)
print(f'hard_stop={hard_stop}')

sig = strategy_exit(item, pos)
print(f'signal={sig}')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    # Trail activates as soon as position is profitable after fees
    # Break-even = entry + (2 * fee / contracts)
    import math as _math
    entry_fee_per = _math.ceil(0.0175 * contracts * (entry/100) * (1-entry/100) * 100) / 100
    exit_fee_per  = _math.ceil(0.0175 * contracts * (entry/100) * (1-entry/100) * 100) / 100
    total_fees    = entry_fee_per + exit_fee_per
    breakeven_c   = entry + int(_math.ceil(total_fees / contracts * 100)) + 1
    trail_active  = bid >= breakeven_c
    trail_stop    = int(peak * 0.80)'''

new = '''    # Trail activates once position shows at least $0.10 net profit
    import math as _math
    entry_fee_per = _math.ceil(0.0175 * contracts * (entry/100) * (1-entry/100) * 100) / 100
    exit_fee_per  = _math.ceil(0.0175 * contracts * (entry/100) * (1-entry/100) * 100) / 100
    total_fees    = entry_fee_per + exit_fee_per
    # cents needed above entry to net $0.10 after fees
    cents_for_dime = int(_math.ceil((0.10 + total_fees) / contracts * 100)) + 1
    trail_activation_c = entry + cents_for_dime
    trail_active  = bid >= trail_activation_c
    trail_stop    = int(peak * 0.80)'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Trail activation set to $0.10 minimum profit")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
python3 << 'EOF'
content = open('/root/price_watcher.py').read()

old = '''            # Trail activates as soon as position is profitable after fees
            import math as _math
            entry_fee_per = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            exit_fee_per  = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            total_fees    = entry_fee_per + exit_fee_per
            breakeven_c   = entry + int(_math.ceil(total_fees/contracts*100)) + 1
            trail_active  = bid >= breakeven_c'''

new = '''            # Trail activates once position shows at least $0.10 net profit
            import math as _math
            entry_fee_per = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            exit_fee_per  = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            total_fees    = entry_fee_per + exit_fee_per
            cents_for_dime = int(_math.ceil((0.10 + total_fees)/contracts*100)) + 1
            trail_activation_c = entry + cents_for_dime
            trail_active  = bid >= trail_activation_c'''

if old in content:
    content = content.replace(old, new)
    open('/root/price_watcher.py', 'w').write(content)
    print("price_watcher trail activation updated")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/price_watcher.py').read()); print('Syntax OK')"
echo "Done"
grep -n "trail_active\|trail_activation\|breakeven\|cents_for" /root/strategies.py | head -10
grep -n "trail_active\|trail_activation\|breakeven\|cents_for" /root/price_watcher.py | head -10
sed -n '655,670p' /root/strategies.py
sed -n '380,395p' /root/price_watcher.py
python3 << 'EOF'
import math

# Fix strategies.py
content = open('/root/strategies.py').read()
old = '''    # Trail activation threshold — side and price aware
    # NO positions at low prices need more room (3x) to avoid noise exits
    # YES positions trail tighter (1.5x) since they move faster
    if side == "no" and entry <= 15:
        trail_mult = 3.0   # low-price NO: wait for real underdog momentum
    elif side == "no":
        trail_mult = 2.0   # higher-price NO: tighter activation
    else:
        trail_mult = 1.5   # YES positions: standard activation

    trail_active = bid >= entry * trail_mult
    trail_stop   = int(peak * 0.80)'''

new = '''    # Trail activates once position shows at least $0.10 net profit
    import math as _math
    _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
    _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
    _fees = _ef + _xf
    _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
    trail_active = bid >= entry + _cents
    trail_stop   = int(peak * 0.80)'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("strategies.py fixed")
else:
    print("strategies.py pattern not found")

# Fix price_watcher.py
content = open('/root/price_watcher.py').read()
old = '''            if side == "no" and entry <= 15:
                trail_mult = 3.0   # low-price NO: wait for real momentum
            elif side == "no":
                trail_mult = 2.0   # higher-price NO
            else:
                trail_mult = 1.5   # YES positions

            trail_active = bid >= entry * trail_mult
            trail_stop   = int(peak * 0.80)
            hard_stop    = int(entry * 0.60)'''

new = '''            import math as _math
            _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            _fees = _ef + _xf
            _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
            trail_active = bid >= entry + _cents
            trail_stop   = int(peak * 0.80)
            hard_stop    = int(entry * 0.60)'''

if old in content:
    content = content.replace(old, new)
    open('/root/price_watcher.py', 'w').write(content)
    print("price_watcher.py fixed")
else:
    print("price_watcher.py pattern not found")
EOF

python3 -c "
import ast
for f in ['strategies.py','price_watcher.py']:
    ast.parse(open(f'/root/{f}').read())
    print(f'{f}: Syntax OK')
"
python3 -c "
import math, sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')

print(f'Trail activation at \$0.10 profit minimum:')
print(f'{\"Entry\":<8} {\"Contracts\":<10} {\"Cost\":<8} {\"Activates@\":<12} {\"+cents\":<8} {\"Fees\"}')
print('-'*55)
for entry_c, contracts in [(5,67),(6,55),(8,41),(9,20),(12,27),(25,13),(40,8),(50,6)]:
    ef = math.ceil(0.0175*contracts*(entry_c/100)*(1-entry_c/100)*100)/100
    xf = math.ceil(0.0175*contracts*(entry_c/100)*(1-entry_c/100)*100)/100
    fees = ef + xf
    cents = int(math.ceil((0.10 + fees)/contracts*100)) + 1
    activation = entry_c + cents
    cost = entry_c * contracts / 100
    print(f'{entry_c}c      {contracts:<10} \${cost:.2f}   {activation}c          +{cents}c      \${fees:.3f}')
"
python3 << 'PYEOF'
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market
from strategies import strategy_exit
from datetime import datetime, timezone, timedelta

def make_pos(side, entry, peak, contracts=20, minutes_ago=45):
    entry_time = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    return {'side':side,'entry_price':entry,'peak_price':peak,
            'contracts':contracts,'strategy':'value_fade',
            'entry_time':entry_time,'event_ticker':'KXATPMATCH-TEST',
            'entry_fee':0.02,'is_bot':True}

def make_item(yes_bid, no_bid):
    m = Market(ticker='KXATPMATCH-TEST-FAV',title='Test',
               yes_bid=yes_bid/100,yes_ask=(yes_bid+2)/100,
               no_bid=no_bid/100,no_ask=(no_bid+2)/100,
               last_price=yes_bid/100,volume=10000,liquidity=500,
               close_time=None,series='KXATPMATCH',label='ATP',
               market_status='active')
    return {'sport':'Tennis','event_ticker':'KXATPMATCH-TEST',
            'game_title':'Test','market':m,'flag':'SIGNAL',
            'reason':'test','market_status':'active'}

tests = [
    # side  entry peak  yes  no   expect  desc
    ('no',  9,  9,  95,  4,  True,  'NO@9c NO=4c hard stop (4<=5)'),
    ('no',  9,  9,  95,  6,  False, 'NO@9c NO=6c above hard stop, below activation HOLD'),
    ('no',  9,  9,  95, 11,  True,  'NO@9c NO=11c trail active(11>=11) peak=11 stop=8 TRAIL'),
    ('no',  9, 20,  80, 15,  True,  'NO@9c peak=20 NO=15c trail active stop=16 — 15<=16 TRAIL'),
    ('no',  9, 20,  80, 17,  False, 'NO@9c peak=20 NO=17c above trail stop=16 HOLD'),
    ('no',  9,  9,  99,  1,  True,  'NO@9c NO=1c hard stop'),
    ('yes',25, 25,  25, 73,  False, 'YES@25c no profit yet HOLD'),
    ('yes',25, 25,  28, 70,  True,  'YES@25c bid=28 trail active stop=20 — 28>20 HOLD... wait'),
    ('yes',25, 40,  30, 68,  True,  'YES@25c peak=40 bid=30 trail active stop=32 — 30<=32 TRAIL'),
    ('yes',25, 25,  14, 84,  True,  'YES@25c hard stop bid=14<=15'),
]

print(f'{"Pass":<5} {"Exit":<6} {"Desc":<52} {"Reason"}')
print('-'*100)
all_pass = True
for side, entry, peak, yes_bid, no_bid, expect, desc in tests:
    pos = make_pos(side, entry, peak)
    item = make_item(yes_bid, no_bid)
    sig = strategy_exit(item, pos)
    exited = sig is not None
    passed = exited == expect
    if not passed: all_pass = False
    mark = 'OK  ' if passed else 'FAIL'
    reason = sig.reason[:40] if sig else 'HOLD'
    print(f'{mark}  {str(exited):<6} {desc:<52} {reason}')
print()
print('All passed' if all_pass else 'SOME FAILED')
PYEOF

python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''            if age > stale_min_age and abs(bid-entry) < 4 and pnl < 0.10:'''
new = '''            if age > stale_min_age and abs(bid-entry) < 4 and pnl < -0.20:'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Stale threshold raised: requires >$0.20 loss before stale exit")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
python3 << 'PYEOF'
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market
from strategies import strategy_exit
from datetime import datetime, timezone, timedelta

def make_pos(side, entry, peak, contracts=20, minutes_ago=45):
    entry_time = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    return {'side':side,'entry_price':entry,'peak_price':peak,
            'contracts':contracts,'strategy':'value_fade',
            'entry_time':entry_time,'event_ticker':'KXATPMATCH-TEST',
            'entry_fee':0.02,'is_bot':True}

def make_item(yes_bid, no_bid):
    m = Market(ticker='KXATPMATCH-TEST-FAV',title='Test',
               yes_bid=yes_bid/100,yes_ask=(yes_bid+2)/100,
               no_bid=no_bid/100,no_ask=(no_bid+2)/100,
               last_price=yes_bid/100,volume=10000,liquidity=500,
               close_time=None,series='KXATPMATCH',label='ATP',
               market_status='active')
    return {'sport':'Tennis','event_ticker':'KXATPMATCH-TEST',
            'game_title':'Test','market':m,'flag':'SIGNAL',
            'reason':'test','market_status':'active'}

tests = [
    ('no',  9,  9,  95,  4, True,  'NO@9c bid=4c hard stop'),
    ('no',  9,  9,  95,  6, False, 'NO@9c bid=6c no trigger HOLD'),
    ('no',  9, 11,  89, 11, False, 'NO@9c peak=11 bid=11c trail active but above stop(8) HOLD'),
    ('no',  9, 20,  80, 15, True,  'NO@9c peak=20 bid=15c trail stop=16 TRAIL'),
    ('no',  9, 20,  80, 17, False, 'NO@9c peak=20 bid=17c above stop HOLD'),
    ('no',  9,  9,  99,  1, True,  'NO@9c bid=1c hard stop'),
    ('yes',25, 25,  25, 73, False, 'YES@25c no profit no trigger HOLD'),
    ('yes',25, 25,  28, 70, False, 'YES@25c bid=28 trail active peak=25 stop=20 bid>stop HOLD'),
    ('yes',25, 40,  30, 68, True,  'YES@25c peak=40 bid=30 stop=32 TRAIL'),
    ('yes',25, 25,  14, 84, True,  'YES@25c hard stop'),
]

print(f'{"Pass":<5} {"Exit":<6} {"Desc":<55} {"Reason"}')
print('-'*100)
all_pass = True
for side, entry, peak, yes_bid, no_bid, expect, desc in tests:
    pos = make_pos(side, entry, peak)
    item = make_item(yes_bid, no_bid)
    sig = strategy_exit(item, pos)
    exited = sig is not None
    passed = exited == expect
    if not passed: all_pass = False
    mark = 'OK  ' if passed else 'FAIL'
    reason = sig.reason[:40] if sig else 'HOLD'
    print(f'{mark}  {str(exited):<6} {desc:<55} {reason}')
print()
print('All passed' if all_pass else 'SOME FAILED')
PYEOF

screen -S kalshi -X quit
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
cd /root && git add -A && git commit -m "feat: trail activates at \$0.10 profit, stale requires -\$0.20 loss, tennis sets_down direction-aware, all exit tests passing | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
cat << 'PYEOF' > /root/price_recorder.py
#!/usr/bin/env python3
"""
Records Kalshi market prices every 5 minutes for open positions.
Builds historical price data for backtesting exit strategies.
Run in background: screen -dmS recorder python3 /root/price_recorder.py
"""
import json, time, requests, csv, os
from datetime import datetime, timezone

KALSHI_BASE = "https://api.elections.kalshi.com/trade-api/v2"
OUTPUT_FILE = "/root/price_history.csv"
INTERVAL    = 300  # 5 minutes

def get_price(ticker, side):
    try:
        r = requests.get(f"{KALSHI_BASE}/markets/{ticker}", timeout=6)
        if r.ok:
            m = r.json().get("market", {})
            return {
                "yes_bid": float(m.get("yes_bid_dollars", 0) or 0) * 100,
                "no_bid":  float(m.get("no_bid_dollars",  0) or 0) * 100,
                "volume":  float(m.get("volume_fp", 0) or 0),
            }
    except: pass
    return None

fieldnames = ["timestamp","ticker","side","entry_price","yes_bid","no_bid","volume","pnl_if_exit_now"]

if not os.path.exists(OUTPUT_FILE):
    with open(OUTPUT_FILE, 'w', newline='') as f:
        csv.DictWriter(f, fieldnames=fieldnames).writeheader()

print(f"Price recorder started. Writing to {OUTPUT_FILE}")

while True:
    try:
        positions = json.load(open("/root/positions.json"))
        now = datetime.now(timezone.utc).isoformat()
        rows = []
        for ticker, pos in positions.items():
            if not pos.get("is_bot"): continue
            prices = get_price(ticker, pos["side"])
            if not prices: continue
            entry = pos.get("entry_price", 0)
            side  = pos.get("side", "yes")
            contracts = pos.get("contracts", 0)
            bid = prices["no_bid"] if side == "no" else prices["yes_bid"]
            pnl = (bid - entry) * contracts / 100 if entry else 0
            rows.append({
                "timestamp":    now,
                "ticker":       ticker,
                "side":         side,
                "entry_price":  entry,
                "yes_bid":      prices["yes_bid"],
                "no_bid":       prices["no_bid"],
                "volume":       prices["volume"],
                "pnl_if_exit_now": round(pnl, 4),
            })
        if rows:
            with open(OUTPUT_FILE, 'a', newline='') as f:
                w = csv.DictWriter(f, fieldnames=fieldnames)
                for row in rows:
                    w.writerow(row)
            print(f"{now[:19]} — recorded {len(rows)} positions")
    except Exception as e:
        print(f"Error: {e}")
    time.sleep(INTERVAL)
PYEOF

echo "price_recorder.py written"
screen -dmS recorder python3 /root/price_recorder.py
echo "Recorder started"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python, json

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)

positions = json.load(open('/root/positions.json'))

print('RESTING ORDERS:')
print('-'*70)
for o in (resp.orders or []):
    if o.status in ('resting','pending'):
        in_pos = o.ticker in positions
        print(f'  {o.ticker}')
        print(f'    side={o.side} status={o.status} in_positions={in_pos}')

print()
print('POSITIONS.JSON:')
print('-'*70)
for t,v in positions.items():
    print(f'  {t}')
    print(f'    side={v[\"side\"]} entry={v[\"entry_price\"]}c x{v[\"contracts\"]} is_bot={v.get(\"is_bot\")}')

print()
print(f'Resting orders: {sum(1 for o in (resp.orders or []) if o.status in (\"resting\",\"pending\"))}')
print(f'Positions tracked: {len(positions)}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python, requests

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)

KALSHI_BASE = 'https://api.elections.kalshi.com/trade-api/v2'

print('ALL RESTING ORDERS WITH AMOUNTS:')
print('-'*80)
for o in (resp.orders or []):
    if o.status not in ('resting','pending'): continue
    # fetch market for current price and payout info
    try:
        r = requests.get(f'{KALSHI_BASE}/markets/{o.ticker}', timeout=6)
        m = r.json().get('market',{})
        no_bid = float(m.get('no_bid_dollars',0) or 0)*100
        no_ask = float(m.get('no_ask_dollars',0) or 0)*100
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)*100
        status = m.get('status','?')
    except:
        no_bid = no_ask = yes_bid = 0
        status = '?'

    # estimate contracts from order (SDK doesnt return count)
    # use positions.json if available
    side = o.side
    entry_price = no_ask if side=='no' else yes_bid
    contracts = 20  # bot default

    cost = contracts * entry_price / 100
    max_payout = contracts * (100 - entry_price) / 100 if side == 'no' else contracts * (100 - entry_price) / 100

    print(f'  {o.ticker}')
    print(f'    {side.upper()} | market_status={status}')
    print(f'    current NO: bid={no_bid:.0f}c ask={no_ask:.0f}c | YES: bid={yes_bid:.0f}c')
    print(f'    est cost=\${cost:.2f} | max_payout=\${max_payout:.2f}')
    print()
"
cat /root/cooldown.json
echo "---"
grep "DETWAS\|NYKBKN\|MLBST\|NYY" /root/kalshi_bot.log | grep -E "cooldown|SIGNAL|PLACED" | tail -20
python3 -c "
import time
from datetime import datetime, timezone
now = time.time()
stored = 1773928960.174723
print(f'Now: {now:.0f}')
print(f'Stored: {stored:.0f}')
print(f'Stored date: {datetime.fromtimestamp(stored, timezone.utc)}')
print(f'Expired: {stored < now}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
# Check why Yankees fired
import requests
r = requests.get('https://api.elections.kalshi.com/trade-api/v2/markets/KXMLBSTGAME-26MAR191305BALNYY-NYY', timeout=6)
m = r.json().get('market',{})
print('yes_bid:', float(m.get('yes_bid_dollars',0) or 0)*100)
print('no_bid:', float(m.get('no_bid_dollars',0) or 0)*100)
print('volume:', m.get('volume_fp'))
print('status:', m.get('status'))
print('series:', m.get('ticker','')[:15])
"
grep -n "def strategy_mlb_underdog" /root/strategies.py
sed -n '/def strategy_mlb_underdog/,/^def /p' /root/strategies.py | head -30
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
# Check the BAL side of this game
import requests
for ticker in ['KXMLBSTGAME-26MAR191305BALNYY-NYY',
               'KXMLBSTGAME-26MAR191305BALNYY-BAL']:
    r = requests.get(f'https://api.elections.kalshi.com/trade-api/v2/markets/{ticker}', timeout=6)
    if r.ok:
        m = r.json().get('market',{})
        print(f'{ticker}')
        print(f'  yes_bid={float(m.get(\"yes_bid_dollars\",0) or 0)*100:.0f}c no_bid={float(m.get(\"no_bid_dollars\",0) or 0)*100:.0f}c vol={m.get(\"volume_fp\")}')
    else:
        print(f'{ticker}: {r.status_code}')
"
grep "BALNYY\|MLBST" /root/kalshi_bot.log | grep -E "PLACED|SIGNAL|value_fade|Strategy"
cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
for t,v in p.items():
    if 'BALNYY' in t or 'MLBST' in t:
        print(f'{t}')
        print(f'  entry={v[\"entry_price\"]}c peak={v.get(\"peak_price\",0)}c contracts={v[\"contracts\"]}')
        print(f'  order_id={v.get(\"order_id\",\"none\")}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)

# Cancel duplicates and stale orders
seen_tickers = {}
cancel_ids = []

for o in (resp.orders or []):
    if o.status not in ('resting','pending'): continue
    ticker = o.ticker
    if ticker in seen_tickers:
        # duplicate — cancel the older one (keep most recent)
        cancel_ids.append(seen_tickers[ticker])
        seen_tickers[ticker] = o.order_id
    else:
        seen_tickers[ticker] = o.order_id

print(f'Duplicate orders to cancel: {len(cancel_ids)}')
for oid in cancel_ids:
    try:
        pa.cancel_order(order_id=oid)
        print(f'  Cancelled: {oid[:8]}...')
    except Exception as e:
        print(f'  Failed {oid[:8]}: {e}')

print('Done')
"
grep -n "def execute_signal\|LIVE ORDER PLACED\|portfolio_api.create_order" /root/kalshi_bot.py | head -10
sed -n '1045,1070p' /root/kalshi_bot.py
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''            with _tt.step("order_placement"):
                order    = portfolio_api.create_order(
                    ticker          = signal.market_ticker,
                    action          = signal.action,
                    side            = signal.side,
                    type            = "limit",
                    yes_price       = _yes_p,
                    no_price        = _no_p,
                    count           = int(signal.contracts),
                    client_order_id = str(uuid.uuid4()),
                )
                order_id = order.order.order_id'''

new = '''            with _tt.step("order_placement"):
                # Cancel any existing resting order on same ticker before placing new one
                try:
                    _existing = portfolio_api.get_orders(limit=50)
                    for _o in (_existing.orders or []):
                        if _o.ticker == signal.market_ticker and _o.status in ("resting","pending"):
                            portfolio_api.cancel_order(order_id=_o.order_id)
                            log.info(f"[Execute] Cancelled stale resting order {_o.order_id[:8]} on {signal.market_ticker}")
                except Exception as _ce:
                    log.debug(f"[Execute] Stale order cancel failed: {_ce}")

                order    = portfolio_api.create_order(
                    ticker          = signal.market_ticker,
                    action          = signal.action,
                    side            = signal.side,
                    type            = "limit",
                    yes_price       = _yes_p,
                    no_price        = _no_p,
                    count           = int(signal.contracts),
                    client_order_id = str(uuid.uuid4()),
                )
                order_id = order.order.order_id'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("Duplicate order cancellation added")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import json, requests
positions = json.load(open('/root/positions.json'))
ticker = 'KXMLBSTGAME-26MAR191305BALNYY-NYY'
if ticker not in positions:
    # Add it with correct current price so watcher can manage it
    r = requests.get(f'https://api.elections.kalshi.com/trade-api/v2/markets/{ticker}', timeout=6)
    m = r.json().get('market',{})
    no_bid = int(float(m.get('no_bid_dollars',0) or 0)*100)
    from datetime import datetime, timezone
    positions[ticker] = {
        'side': 'no', 'entry_price': 8, 'peak_price': no_bid,
        'contracts': 20, 'strategy': 'value_fade',
        'entry_time': datetime.now(timezone.utc).isoformat(),
        'event_ticker': ticker.rsplit('-',1)[0],
        'reason': 'recovered', 'entry_fee': 0.02,
        'is_bot': True, 'last_bid': no_bid,
    }
    json.dump(positions, open('/root/positions.json','w'), indent=2)
    print(f'Added {ticker} entry=8c current_no={no_bid}c')
    print(f'Trail should activate immediately (23c >> 8c+2c)')
else:
    print('Already in positions')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)

for o in (resp.orders or []):
    if 'BALNYY' in o.ticker:
        print(f'order_id={o.order_id}')
        print(f'ticker={o.ticker}')
        print(f'status={o.status}')
        print(f'side={o.side}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
pa.cancel_order(order_id='01fa8997-4591-465b-a95d-c0aa2f117005')
print('Cancelled resting BALNYY order')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from strategies import _fetch_fills_raw_single
from kalshi_bot import _get_kalshi_client

client = _get_kalshi_client()
fills = _fetch_fills_raw_single(client)
balnyy = [f for f in fills if 'BALNYY' in str(f.get('ticker',''))]
print(f'BALNYY fills: {len(balnyy)}')
for f in balnyy:
    print(f'  action={f.get(\"action\")} side={f.get(\"side\")} count={f.get(\"count_fp\")} price={f.get(\"yes_price_dollars\") or f.get(\"no_price_dollars\")}')
"
screen -S kalshi -X quit
sleep 1
# Clean up positions to only what we know is real
python3 -c "
import json, sys
sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python, requests

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)
resting = {o.ticker: o.order_id for o in (resp.orders or []) if o.status in ('resting','pending')}
print(f'Resting orders: {list(resting.keys())}')

# Rebuild positions from resting orders only
positions = {}
KALSHI_BASE = 'https://api.elections.kalshi.com/trade-api/v2'
from datetime import datetime, timezone
bot_orders = set(json.load(open('/root/bot_orders.json')))

for ticker, oid in resting.items():
    if oid not in bot_orders:
        continue
    r = requests.get(f'{KALSHI_BASE}/markets/{ticker}', timeout=6)
    m = r.json().get('market',{})
    no_ask = int(float(m.get('no_ask_dollars',0) or 0)*100)
    positions[ticker] = {
        'side': 'no', 'entry_price': no_ask,
        'peak_price': no_ask, 'last_bid': no_ask,
        'contracts': 20, 'strategy': 'value_fade',
        'entry_time': datetime.now(timezone.utc).isoformat(),
        'event_ticker': ticker.rsplit('-',1)[0],
        'reason': 'resting order', 'entry_fee': 0.02,
        'order_id': oid, 'is_bot': True,
    }
    print(f'Added {ticker} @ {no_ask}c')

json.dump(positions, open('/root/positions.json','w'), indent=2)
print(f'Positions rebuilt: {len(positions)}')
"
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
sleep 8
tail -15 /root/kalshi_bot.log
screen -r
tail -20 /root/kalshi_bot.log
cat /root/cooldown.json
python3 -c "
import time, json
from datetime import datetime, timezone
cd = json.load(open('/root/cooldown.json'))
now = time.time()
for ticker, exp in cd.items():
    remaining = exp - now
    print(f'{ticker[-20:]}: expires in {remaining/60:.1f} min')
"
cd /root && git add -A && git commit -m "fix: cancel stale resting orders before re-entry, cleanup BALNYY, positions rebuilt from resting orders | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
python kalshi_bot.py
