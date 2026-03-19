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
