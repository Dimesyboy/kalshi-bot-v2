#!/usr/bin/env python3
"""
nba_context.py
Maps Kalshi NBA market tickers to ESPN game context.
Provides smart entry/exit decisions based on live game state.
"""
import re
import logging
from typing import Optional
log = logging.getLogger("kalshi_bot.nba")

# Team abbreviation mapping — Kalshi uses 3-letter codes in tickers
TEAM_MAP = {
    # Kalshi code -> ESPN abbreviation
    "ATL": "ATL", "BOS": "BOS", "BKN": "BKN", "CHA": "CHA",
    "CHI": "CHI", "CLE": "CLE", "DAL": "DAL", "DEN": "DEN",
    "DET": "DET", "GSW": "GSW", "HOU": "HOU", "IND": "IND",
    "LAC": "LAC", "LAL": "LAL", "MEM": "MEM", "MIA": "MIA",
    "MIL": "MIL", "MIN": "MIN", "NOP": "NOP", "NYK": "NYK",
    "OKC": "OKC", "ORL": "ORL", "PHI": "PHI", "PHX": "PHX",
    "POR": "POR", "SAC": "SAC", "SAS": "SAS", "TOR": "TOR",
    "UTA": "UTA", "WAS": "WAS",
}

# Player name fragments in Kalshi prop tickers -> full name keywords
# KXNBAPTS-26MAR17MIACHA-CHALBALL1-25 = Bam Adebayo? No — CHA = Charlotte, BALL = LaMelo Ball
# Format: EVENT-TEAM1TEAM2-TEAM+PLAYERNAME+STAT-THRESHOLD
def parse_prop_ticker(ticker: str) -> dict:
    """
    Parse a Kalshi NBA prop ticker into components.
    Example: KXNBAPTS-26MAR17MIACHA-CHALBALL1-25
    -> stat=PTS, date=26MAR17, teams=MIA+CHA, team=CHA, player=BALL, threshold=25
    """
    result = {"stat": None, "team1": None, "team2": None,
              "prop_team": None, "player": None, "threshold": None}
    try:
        # Extract stat type from series
        for stat, key in [("NBAPTS","PTS"),("NBAREB","REB"),("NBAAST","AST"),
                          ("NBA3PT","3PT"),("NBAPRA","PRA"),("NBASTL","STL"),
                          ("NBABLK","BLK")]:
            if stat in ticker:
                result["stat"] = key
                break

        # Parse: KXNBAPTS-26MAR17MIACHA-CHALBALL1-25
        parts = ticker.split("-")
        if len(parts) >= 3:
            # Event part: 26MAR17MIACHA -> teams are last 6 chars
            event = parts[1]  # e.g. 26MAR17MIACHA
            # Extract team codes (last 6 chars of event = two 3-letter codes)
            if len(event) >= 6:
                result["team1"] = event[-6:-3].upper()
                result["team2"] = event[-3:].upper()

            # Market part: CHALBALL1 -> team=CHA, player=BALL, game=1
            market = parts[2]  # e.g. CHALBALL1
            if len(market) >= 3:
                result["prop_team"] = market[:3].upper()
                # Player name is between team code and threshold number
                player_raw = re.sub(r'\d+$', '', market[3:])
                result["player"] = player_raw.upper()

            # Threshold
            if len(parts) >= 4:
                result["threshold"] = int(parts[3])
    except Exception as e:
        log.debug(f"Prop parse error {ticker}: {e}")
    return result


def find_game_for_ticker(ticker: str, espn_cache) -> Optional[object]:
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
    return None


def should_enter_prop(ticker: str, yes_bid: float, espn_cache) -> tuple:
    """
    Returns (should_enter: bool, confidence: float, reason: str)
    Uses ESPN context to validate prop entry.
    """
    parsed = parse_prop_ticker(ticker)
    stat      = parsed.get("stat")
    player    = parsed.get("player","")
    threshold = parsed.get("threshold")
    prop_team = parsed.get("prop_team","")

    # If we couldn't parse the ticker at all, don't enter blind
    if not stat or not player:
        return False, 0.0, "Could not parse prop ticker — skipping"

    # No ESPN context available — use base confidence only for pre-game
    if not espn_cache:
        return True, 0.65, "No ESPN context"

    ctx = find_game_for_ticker(ticker, espn_cache)
    if not ctx:
        return True, 0.65, "Game not found in ESPN"

    conf = 0.65
    reasons = []

    # Boost if home team prop — home teams generally perform better
    is_home_team = (prop_team == ctx.home.abbreviation or
                    prop_team in ctx.home.name.upper())
    if is_home_team:
        conf += 0.02
        reasons.append("home team")

    # Check pace — high rebounds = faster pace = more scoring opportunities
    try:
        home_reb = int(ctx.nba_home_stats.get("rebounds","0") or 0)
        away_reb = int(ctx.nba_away_stats.get("rebounds","0") or 0)
        total_reb = home_reb + away_reb
        if total_reb > 85:  # high pace game
            if stat in ("PTS","PRA","AST"):
                conf += 0.02
                reasons.append(f"high pace ({total_reb} reb)")
    except: pass

    # Pre-game: opening spread context
    if ctx.open_spread is not None:
        spread = abs(ctx.open_spread)
        if spread >= 10:
            # Blowout expected — star player on winning team gets more minutes
            # but may sit in Q4. Mixed signal.
            reasons.append(f"big spread ({ctx.open_spread})")
        elif spread <= 4:
            # Close game — player may not get garbage time boost
            # but gets full minutes
            conf += 0.01
            reasons.append(f"close game expected")

    reason = f"ESPN: {ctx.home.name} vs {ctx.away.name}" + (f" | {', '.join(reasons)}" if reasons else "")
    return True, round(conf, 3), reason


def nba_value_fade_check(ticker: str, yes_bid: float, espn_cache) -> tuple:
    """
    For value_fade on NBA markets.
    Returns (should_enter, confidence, reason)
    Pre-game only — checks opening spread to validate edge.
    """
    if not espn_cache: return True, 0.65, "No ESPN"

    ctx = find_game_for_ticker(ticker, espn_cache)
    if not ctx: return True, 0.65, "Not found"

    # If game is live — should already be blocked, but double-check
    if ctx.is_live: return False, 0.0, "Game is live — skip"

    # Opening spread: if favorite is -5 or less, they might not cover
    # The market at 95c might be overconfident on a close game
    conf = 0.65
    reason = f"Pre-game fade"

    if ctx.open_spread is not None:
        spread = ctx.open_spread  # negative = home favored
        abs_spread = abs(spread)
        if abs_spread <= 4:
            # Very close game — 95c YES is overconfident
            conf = 0.70
            reason = f"Tight spread ({spread}) — {int(yes_bid*100)}c YES overconfident"
        elif abs_spread >= 15:
            # Big spread — favorite probably wins but 95c+ is still useful to fade
            conf = 0.63
            reason = f"Large spread ({spread}) — some upset risk"
        else:
            reason = f"Spread {spread} | fade {int(yes_bid*100)}c YES"

    return True, conf, reason
