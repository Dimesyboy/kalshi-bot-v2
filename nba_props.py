#!/usr/bin/env python3
"""
nba_props.py
NBA player prop context for points and 3-pointers.

Data source: api.server.nbaapi.com (free, no auth)
Cached: player stats 4hr, team pace 4hr

Flow:
  get_nba_prop_context(ticker) ->
    1. Parse ticker -> player name + threshold + stat type
    2. Fetch player season stats (cached)
    3. Calculate hit rate: games where player exceeded threshold / total games
    4. Fetch team pace data for matchup adjustment
    5. Check ESPN context for injury report / game state
    6. Return NBAProContext with confidence + reason

Ticker format examples:
  KXNBAPTS-26MAR17PHXMIN-PHXDBOOKER1-25   -> Booker 25+ pts
  KXNBA3PT-26MAR17MIACHA-CHALBALL1-3      -> LaMelo 3+ threes
"""

import re
import time
import logging
import requests
from dataclasses import dataclass
from typing import Optional, Dict, Tuple

log = logging.getLogger("kalshi_bot.nba_props")

try:
    from nba_injuries import get_injury_report, get_teammate_boost
    _INJURIES = True
except ImportError:
    _INJURIES = False

BASE_URL  = "https://api.pbpstats.com/get-totals/nba"
TIMEOUT   = 10

# Cache
_player_cache: Dict = {}   # name -> {stats, ts}
_pace_cache:   Dict = {}   # {data: [...], ts: float}
_all_players:  Dict = {}   # name_upper -> stats dict
_all_players_ts: float = 0.0

PLAYER_TTL = 14400   # 4 hours
PACE_TTL   = 14400   # 4 hours

# Kalshi team code -> NBA team abbreviation
TEAM_MAP = {
    "ATL":"ATL","BOS":"BOS","BKN":"BKN","CHA":"CHA","CHI":"CHI",
    "CLE":"CLE","DAL":"DAL","DEN":"DEN","DET":"DET","GSW":"GSW",
    "HOU":"HOU","IND":"IND","LAC":"LAC","LAL":"LAL","MEM":"MEM",
    "MIA":"MIA","MIL":"MIL","MIN":"MIN","NOP":"NOP","NYK":"NYK",
    "OKC":"OKC","ORL":"ORL","PHI":"PHI","PHX":"PHX","POR":"POR",
    "SAC":"SAC","SAS":"SAS","TOR":"TOR","UTA":"UTA","WAS":"WAS",
}

# League average pace for comparison
LEAGUE_AVG_PACE = 99.0


@dataclass
class NBAProContext:
    ticker:       str
    player_name:  str
    stat_type:    str      # "PTS" or "3PT"
    threshold:    int
    season_avg:   float    # per-game average for this stat
    hit_rate:     float    # historical rate of exceeding threshold
    games_sample: int      # games used for hit rate
    confidence:   float    # final confidence for YES
    edge:         float    # confidence - market_price
    reason:       str
    should_enter: bool

    def summary(self) -> str:
        return (
            f"{self.player_name} {self.stat_type}>{self.threshold} "
            f"avg={self.season_avg:.1f} hit={self.hit_rate:.0%} "
            f"conf={self.confidence:.2f} edge={self.edge:+.2f}"
        )


def _fetch_all_players() -> Dict:
    """Fetch all player season totals, cache for 4 hours.
    Primary: pbpstats. Fallback: basketball-reference."""
    global _all_players, _all_players_ts
    now = time.time()
    if _all_players and now - _all_players_ts < PLAYER_TTL:
        return _all_players

    # ── Primary: pbpstats ────────────────────────────────────────
    try:
        r = requests.get(BASE_URL, params={
            "Season":     "2024-25",
            "SeasonType": "Regular Season",
            "Type":       "Player",
            "sortBy":     "points",
            "pageSize":   500,
        }, timeout=8)
        r.raise_for_status()
        data = r.json().get("multi_row_table_data", [])
        if data:
            out = {}
            for p in data:
                name = p.get("Name", "")
                if name:
                    out[name.upper()] = p
            _all_players    = out
            _all_players_ts = now
            log.info(f"[NBA Props] pbpstats: {len(out)} players loaded")
            return out
    except Exception as e:
        log.warning(f"[NBA Props] pbpstats failed: {e} — trying fallback")

    # ── Fallback: basketball-reference ───────────────────────────
    try:
        from io import StringIO
        import pandas as pd
        r = requests.get(
            "https://www.basketball-reference.com/leagues/NBA_2025_per_game.html",
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        r.raise_for_status()
        tables = pd.read_html(StringIO(r.text))
        df = tables[0]
        df = df[df["Player"] != "Player"].copy()  # remove repeated headers
        df = df.dropna(subset=["Player"])

        out = {}
        for _, row in df.iterrows():
            name = str(row.get("Player", "")).strip()
            if not name:
                continue
            # Normalise to same field names the rest of nba_props.py expects
            out[name.upper()] = {
                "Name":        name,
                "playerName":  name,
                "team":        str(row.get("Team", "")),
                "games":       _safe_float(row.get("G", 0)),
                "minutesPg":   _safe_float(row.get("MP", 0)) * _safe_float(row.get("G", 1)),
                "points":      _safe_float(row.get("PTS", 0)) * _safe_float(row.get("G", 1)),
                "threeFg":     _safe_float(row.get("3P", 0))  * _safe_float(row.get("G", 1)),
                "rebounds":    _safe_float(row.get("TRB", 0)) * _safe_float(row.get("G", 1)),
                "assists":     _safe_float(row.get("AST", 0)) * _safe_float(row.get("G", 1)),
                "fieldAttempts": _safe_float(row.get("FGA", 0)) * _safe_float(row.get("G", 1)),
                "ftAttempts":  _safe_float(row.get("FTA", 0))  * _safe_float(row.get("G", 1)),
            }
        _all_players    = out
        _all_players_ts = now
        log.info(f"[NBA Props] bball-ref fallback: {len(out)} players loaded")
        return out
    except Exception as e:
        log.warning(f"[NBA Props] bball-ref fallback failed: {e}")
        return _all_players  # return stale on total failure


def _safe_float(val) -> float:
    try:
        return float(val)
    except:
        return 0.0


def _fetch_pace() -> Dict:
    """
    Derive team pace proxy from player totals.
    Pace proxy = avg (FGA + FTA*0.44) per minute across all players on team.
    Higher = faster pace = more possessions = more counting stats.
    Cached for 4 hours.
    """
    global _pace_cache
    now = time.time()
    if _pace_cache and now - _pace_cache.get("ts", 0) < PACE_TTL:
        return _pace_cache.get("data", {})

    try:
        all_players = _fetch_all_players()
        if not all_players:
            return {}

        team_possession_rate: Dict[str, list] = {}
        for name, p in all_players.items():
            team = p.get("team", "")
            total_mins = float(p.get("Minutes", 0) or 0)  # total mins (mislabeled)
            gp   = int(p.get("GamesPlayed", 0) or 0)
            fga  = float(p.get("fieldAttempts", 0) or 0)
            fta  = float(p.get("ftAttempts", 0) or 0)
            if not team or total_mins < 400 or gp < 20:
                continue
            mins_pg = total_mins / gp
            # Possessions used per minute proxy
            poss_per_min = (fga + fta * 0.44) / total_mins
            if team not in team_possession_rate:
                team_possession_rate[team] = []
            team_possession_rate[team].append(poss_per_min)

        # Average across players, normalize to pace-like number
        team_avg = {}
        league_vals = []
        for team, vals in team_possession_rate.items():
            avg = sum(vals) / len(vals)
            team_avg[team] = avg
            league_vals.append(avg)

        if not league_vals:
            return {}

        league_mean = sum(league_vals) / len(league_vals)
        # Normalize: express as deviation from league average pace (99.0)
        out = {}
        for team, val in team_avg.items():
            normalized = LEAGUE_AVG_PACE + (val - league_mean) / league_mean * LEAGUE_AVG_PACE
            out[team] = round(normalized, 1)

        _pace_cache = {"data": out, "ts": now}
        log.info(f"[NBA Props] Pace proxy built: {len(out)} teams")

        # Log top/bottom pace teams
        sorted_teams = sorted(out.items(), key=lambda x: x[1], reverse=True)
        log.debug(f"[NBA Props] Fastest: {sorted_teams[:3]}")
        log.debug(f"[NBA Props] Slowest: {sorted_teams[-3:]}")
        return out

    except Exception as e:
        log.warning(f"[NBA Props] Pace build failed: {e}")
        return _pace_cache.get("data", {})


def _parse_prop_ticker(ticker: str) -> Tuple[str, str, str, int]:
    """
    Parse Kalshi NBA prop ticker.
    Returns (stat_type, team1, player_fragment, threshold)

    Examples:
      KXNBAPTS-26MAR17PHXMIN-PHXDBOOKER1-25
        -> ("PTS", "PHX", "BOOKER", 25)
      KXNBA3PT-26MAR17MIACHA-CHALBALL1-3
        -> ("3PT", "CHA", "BALL", 3)
    """
    try:
        # Stat type from series prefix
        stat = "PTS" if "NBAPTS" in ticker else "3PT" if "NBA3PT" in ticker else None
        if not stat:
            return None, None, None, None

        parts = ticker.split("-")
        if len(parts) < 4:
            return stat, None, None, None

        # Event part: 26MAR17PHXMIN -> team1=PHX team2=MIN
        event = parts[1]
        date_match = re.match(r'^\d{1,2}[A-Z]{3}\d{2}', event)
        teams_part = event[date_match.end():] if date_match else event
        team1 = teams_part[:3].upper() if len(teams_part) >= 6 else None
        team2 = teams_part[3:6].upper() if len(teams_part) >= 6 else None

        # Market part: PHXDBOOKER1 -> team=PHX, first_initial=D, last=BOOKER, jersey=1
        market = parts[2]
        prop_team = market[:3].upper() if len(market) >= 3 else None
        rest = market[3:]
        # Strip trailing jersey number (1-2 digits)
        rest = re.sub(r'\d+$', '', rest)
        # First char is first initial, rest is last name fragment
        # e.g. DBOOKER -> first=D, last=BOOKER
        #      LBALL   -> first=L, last=BALL
        #      SGILGEOUSALEXANDER -> first=S, last=GILGEOUSALEXANDER
        if len(rest) >= 2:
            first_initial = rest[0]
            last_name_frag = rest[1:]
        else:
            first_initial = ""
            last_name_frag = rest
        player_frag = last_name_frag.upper()
        player_initial = first_initial.upper()

        # Threshold: last part
        try:
            threshold = int(parts[3])
        except:
            threshold = None

        return stat, prop_team, player_frag, player_initial, threshold

    except Exception as e:
        log.debug(f"[NBA Props] Ticker parse error {ticker}: {e}")
        return None, None, None, None, None


def _find_player(player_frag: str, prop_team: str, all_players: Dict,
                  player_initial: str = "") -> Optional[dict]:
    """
    Match a Kalshi player fragment to a player record.
    player_frag:    last name fragment e.g. "BOOKER", "BALL", "TOWNS"
    player_initial: first name initial e.g. "D", "L", "K"
    prop_team:      3-letter Kalshi team code e.g. "PHX"
    """
    if not player_frag:
        return None

    team_abbrev = TEAM_MAP.get(prop_team, "")
    candidates  = []

    # Normalize fragment — remove hyphens for compound names
    # e.g. GILGEOUSALEXANDER -> matches GILGEOUS-ALEXANDER
    frag_clean = player_frag.replace("-", "")

    for name_upper, stats in all_players.items():
        # Normalize name too — remove hyphens
        name_clean = name_upper.replace("-", "").replace("'", "")
        name_parts = name_clean.split()
        if not name_parts:
            continue
        last  = name_parts[-1]
        first = name_parts[0] if len(name_parts) > 1 else ""

        # Last name must start with our fragment
        if not last.startswith(frag_clean):
            continue

        # If we have a first initial, it must match
        if player_initial and first and not first.startswith(player_initial):
            continue

        candidates.append((name_upper, stats))

    if not candidates:
        # Fallback: fragment anywhere in normalized name
        for name_upper, stats in all_players.items():
            name_clean = name_upper.replace("-", "").replace("'", "")
            if frag_clean in name_clean:
                candidates.append((name_upper, stats))

    if not candidates:
        return None

    if len(candidates) == 1:
        return candidates[0][1]

    # Disambiguate by team
    if team_abbrev:
        team_matches = [
            (n, s) for n, s in candidates
            if s.get("TeamAbbreviation", "").upper() == team_abbrev
        ]
        if len(team_matches) == 1:
            return team_matches[0][1]
        if team_matches:
            candidates = team_matches

    # Tiebreak by most games played (most established player)
    candidates.sort(key=lambda x: x[1].get("games", 0), reverse=True)
    return candidates[0][1]


def _hit_rate_from_avg(avg: float, threshold: int, std_factor: float = 0.35) -> float:
    """
    Estimate hit rate using normal distribution approximation.
    avg: season per-game average
    threshold: must exceed this value (strict greater than)
    std_factor: std dev as fraction of mean (empirically ~0.35 for NBA props)

    Uses normal CDF approximation.
    """
    if avg <= 0:
        return 0.0

    std = avg * std_factor
    if std == 0:
        return 1.0 if avg > threshold else 0.0

    # Standardize
    z = (threshold + 0.5 - avg) / std  # +0.5 continuity correction

    # Rational approximation of normal CDF (Abramowitz & Stegun)
    def norm_cdf(x):
        t = 1.0 / (1.0 + 0.2316419 * abs(x))
        d = 0.3989423 * (2.718281828 ** (-x * x / 2))
        p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.7814779 + t * (-1.8212560 + t * 1.3302744))))
        return 1.0 - p if x >= 0 else p

    return 1.0 - norm_cdf(z)


def get_nba_prop_context(ticker: str, yes_bid: float, espn_cache=None) -> Optional[NBAProContext]:
    """
    Main entry point. Returns NBAProContext or None if no edge found.

    Called by strategy_prop_nba() in strategies.py.
    """
    stat, prop_team, player_frag, player_initial, threshold = _parse_prop_ticker(ticker)
    if not stat or not player_frag or threshold is None:
        log.debug(f"[NBA Props] Could not parse {ticker}")
        return None

    # Load player data
    all_players = _fetch_all_players()
    if not all_players:
        return None

    player = _find_player(player_frag, prop_team, all_players, player_initial)
    if not player:
        log.debug(f"[NBA Props] No player match for {player_frag} ({prop_team})")
        return None

    player_name = player.get("Name", player_frag)
    gp          = int(player.get("GamesPlayed", 0) or 0)
    mins_total  = float(player.get("Minutes", 0) or 0) / max(gp, 1)  # API returns total mins

    if gp < 10:
        log.debug(f"[NBA Props] {player_name} only {gp} games — skipping")
        return None

    # Per-game averages
    if stat == "PTS":
        total   = float(player.get("Points", 0) or 0)
        avg_pg  = total / gp
        std_fac = 0.32   # pts has moderate variance
    else:  # 3PT
        total   = float(player.get("FG3M", 0) or 0)
        avg_pg  = total / gp
        std_fac = 0.55   # 3PT has higher variance

    # Calculate hit rate
    hit_rate = _hit_rate_from_avg(avg_pg, threshold, std_fac)

    # Base confidence from hit rate
    conf = hit_rate

    reasons = [f"{player_name} avg {avg_pg:.1f} {stat}/g, threshold={threshold}, hist_rate={hit_rate:.0%}"]

    # ── Pace adjustment ────────────────────────────────────────────────
    pace_data = _fetch_pace()
    team_abbrev = TEAM_MAP.get(prop_team, "")
    if pace_data and team_abbrev:
        team_pace = pace_data.get(team_abbrev, LEAGUE_AVG_PACE)
        pace_diff = team_pace - LEAGUE_AVG_PACE
        if pace_diff > 2.0:
            conf   += 0.02
            reasons.append(f"fast pace +{pace_diff:.1f}")
        elif pace_diff < -2.0:
            conf   -= 0.02
            reasons.append(f"slow pace {pace_diff:.1f}")

    # ── Minutes check — don't enter if player is averaging under 25 min ──
    if mins_total > 0 and mins_total < 20:  # skip players under 20 mpg
        log.debug(f"[NBA Props] {player_name} only {mins_total:.0f} mpg — skipping")
        return None

    # ── ESPN context — injury report + game state ──────────────────────
    if espn_cache:
        try:
            nba_col = espn_cache._all.get("NBA")
            if nba_col:
                for ctx in nba_col:
                    # Check if this game has injured key players (usage bump)
                    # If home team matches prop_team, slight boost
                    if team_abbrev and (
                        ctx.home.abbreviation == team_abbrev or
                        ctx.away.abbreviation == team_abbrev
                    ):
                        # Live game — only enter in Q1/Q2
                        if ctx.is_live:
                            if ctx.nba_quarter > 2:
                                log.debug(f"[NBA Props] {ticker} live Q{ctx.nba_quarter} — too late")
                                return None
                            # Q1/Q2 — small live boost (more game remaining)
                            if ctx.nba_quarter <= 1:
                                conf   += 0.01
                                reasons.append("Q1 entry")
                        # Home team boost
                        if ctx.home.abbreviation == team_abbrev:
                            conf   += 0.01
                            reasons.append("home")
                        break
        except Exception as e:
            log.debug(f"[NBA Props] ESPN context error: {e}")

    # ── Injury report boost ───────────────────────────────────────────
    if _INJURIES and team_abbrev:
        try:
            # Derive opponent from event ticker
            # e.g. KXNBAPTS-26MAR17MIACHA -> teams are MIA + CHA
            opp_abbrev = ""
            try:
                parts = ticker.split("-")
                event = parts[1]
                date_match = __import__("re").match(r"^\d{1,2}[A-Z]{3}\d{2}", event)
                teams_part = event[date_match.end():] if date_match else event
                t1 = teams_part[:3].upper()
                t2 = teams_part[3:6].upper()
                opp_abbrev = t2 if t1 == team_abbrev else t1
            except Exception:
                pass

            inj_report = get_injury_report()
            boost, inj_reason = get_teammate_boost(
                team_abbrev, player_frag, inj_report, opp_abbrev
            )
            if boost > 0:
                conf += boost
                reasons.append(f"inj: {inj_reason}")
        except Exception as e:
            log.debug(f"[NBA Props] Injury boost error: {e}")

    # ── Edge calculation ───────────────────────────────────────────────
    market_price = yes_bid
    edge         = conf - market_price

    # Only enter with meaningful edge after fees
    # Minimum 8c edge for PTS (more predictable), 10c for 3PT (higher variance)
    min_edge = 0.08 if stat == "PTS" else 0.10
    should_enter = edge >= min_edge and conf >= 0.62

    conf = round(min(max(conf, 0.50), 0.82), 3)

    reason = " | ".join(reasons)

    ctx = NBAProContext(
        ticker       = ticker,
        player_name  = player_name,
        stat_type    = stat,
        threshold    = threshold,
        season_avg   = round(avg_pg, 2),
        hit_rate     = round(hit_rate, 3),
        games_sample = gp,
        confidence   = conf,
        edge         = round(edge, 3),
        reason       = reason,
        should_enter = should_enter,
    )

    log.info(f"[NBA Props] {ctx.summary()} | enter={should_enter}")
    return ctx
