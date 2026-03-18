#!/usr/bin/env python3
"""
mlb_props.py
MLB spring training underdog strategy.

Logic:
  - Buy the cheaper side (underdog) when:
    1. Volume >= 400, spread <= 3c
    2. YES bid 33-48c (underdog zone)
    3. Spring training record favors the underdog (>= .450 win%)
    4. Game is pre-game (open status)

Data source: ESPN MLB scoreboard (free, no auth)
Cached: 1hr for team records

Ticker format:
  KXMLBSTGAME-26MAR181605SFLAD-LAD  -> LAD vs SF, pick LAD side
  KXMLBSTGAME-26MAR181605SFLAD-SF   -> LAD vs SF, pick SF side
"""

import re
import time
import logging
import requests
from dataclasses import dataclass
from typing import Optional, Dict, Tuple

log = logging.getLogger("kalshi_bot.mlb_props")

ESPN_MLB = "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
TIMEOUT  = 8

_records_cache: Dict = {}  # {"data": {abbrev: {wins,losses,pct}}, "ts": float}
RECORDS_TTL = 3600  # 1hr

# Kalshi MLB ticker codes -> ESPN abbreviations
# Some differ slightly
MLB_TEAM_MAP = {
    "ARI": "ARI", "ATH": "OAK", "ATL": "ATL", "BAL": "BAL",
    "BOS": "BOS", "CHC": "CHC", "CIN": "CIN", "CLE": "CLE",
    "COL": "COL", "CWS": "CWS", "DET": "DET", "HOU": "HOU",
    "KC":  "KC",  "LAA": "LAA", "LAD": "LAD", "MIA": "MIA",
    "MIL": "MIL", "MIN": "MIN", "NYM": "NYM", "NYY": "NYY",
    "OAK": "OAK", "PHI": "PHI", "PIT": "PIT", "SD":  "SD",
    "SEA": "SEA", "SF":  "SF",  "STL": "STL", "TB":  "TB",
    "TEX": "TEX", "TOR": "TOR", "WSH": "WSH",
}


@dataclass
class MLBContext:
    ticker:       str
    team:         str       # team this market is for
    opponent:     str       # opposing team
    team_record:  str       # e.g. "11-8"
    opp_record:   str
    team_winpct:  float     # spring training win %
    opp_winpct:   float
    is_home:      bool
    confidence:   float
    edge:         float
    should_enter: bool
    reason:       str

    def summary(self) -> str:
        return (
            f"{self.team}({self.team_record}) vs {self.opponent}({self.opp_record}) "
            f"winpct={self.team_winpct:.3f} conf={self.confidence:.2f} edge={self.edge:+.2f}"
        )


def _fetch_records() -> Dict:
    """
    Fetch current spring training records from ESPN.
    Returns {abbrev: {"wins": int, "losses": int, "ties": int, "pct": float}}
    """
    global _records_cache
    now = time.time()
    if _records_cache and now - _records_cache.get("ts", 0) < RECORDS_TTL:
        return _records_cache.get("data", {})

    try:
        r = requests.get(ESPN_MLB, timeout=TIMEOUT)
        r.raise_for_status()
        events = r.json().get("events", [])

        records: Dict = {}
        for event in events:
            for comp in event.get("competitions", []):
                for team_data in comp.get("competitors", []):
                    abbrev = team_data.get("team", {}).get("abbreviation", "")
                    recs   = team_data.get("records", [])
                    if not abbrev or not recs:
                        continue
                    summary = recs[0].get("summary", "0-0")
                    parts   = summary.split("-")
                    try:
                        wins   = int(parts[0])
                        losses = int(parts[1])
                        ties   = int(parts[2]) if len(parts) > 2 else 0
                        total  = wins + losses + ties * 0.5
                        pct    = wins / total if total > 0 else 0.5
                        records[abbrev] = {
                            "wins": wins, "losses": losses, "ties": ties,
                            "pct": round(pct, 3),
                            "record_str": summary,
                        }
                    except Exception:
                        pass

        if records:
            log.info(f"[MLB] Spring training records: {len(records)} teams loaded")
            _records_cache = {"data": records, "ts": now}
        return records

    except Exception as e:
        log.warning(f"[MLB] Records fetch failed: {e}")
        return _records_cache.get("data", {})


def _parse_mlb_ticker(ticker: str) -> Tuple[str, str, str]:
    """
    Parse KXMLBSTGAME ticker.
    KXMLBSTGAME-26MAR181605SFLAD-LAD
      -> event_teams=("SF","LAD"), market_team="LAD"

    Returns (team1, team2, market_team)
    """
    try:
        parts = ticker.split("-")
        if len(parts) < 3:
            return None, None, None

        # Event part: 26MAR181605SFLAD
        event = parts[1]
        # Strip date+time: digits+month+digits+digits = DDMMMYYHHMMTEAM1TEAM2
        # Try to find where teams start — after all digits/month
        date_time_match = re.match(r'^\d{1,2}[A-Z]{3}\d{2}\d{4}', event)
        if date_time_match:
            teams_part = event[date_time_match.end():]
        else:
            date_match = re.match(r'^\d{1,2}[A-Z]{3}\d{2}', event)
            teams_part = event[date_match.end():] if date_match else event

        # Teams are variable length (2-3 chars each)
        # Market team is parts[2]
        market_team = parts[2].upper()

        # Split teams_part into two teams
        # Market team is one of them — find it and derive the other
        if teams_part.startswith(market_team):
            team1 = market_team
            team2 = teams_part[len(market_team):]
        elif teams_part.endswith(market_team):
            team1 = teams_part[:-len(market_team)]
            team2 = market_team
        else:
            # Try 2+2, 2+3, 3+2, 3+3 splits
            for split in [2, 3]:
                t1 = teams_part[:split]
                t2 = teams_part[split:]
                if t1 == market_team or t2 == market_team:
                    team1, team2 = t1, t2
                    break
            else:
                team1 = teams_part[:3]
                team2 = teams_part[3:]

        return team1.upper(), team2.upper(), market_team.upper()

    except Exception as e:
        log.debug(f"[MLB] Ticker parse error {ticker}: {e}")
        return None, None, None


def get_mlb_context(ticker: str, yes_bid: float) -> Optional[MLBContext]:
    """
    Main entry point called by strategy_mlb_underdog().
    Returns MLBContext or None if no edge.
    """
    team1, team2, market_team = _parse_mlb_ticker(ticker)
    if not market_team:
        log.debug(f"[MLB] Could not parse {ticker}")
        return None

    # Opponent is the other team
    opponent = team2 if market_team == team1 else team1

    # Map to ESPN abbreviations
    espn_team = MLB_TEAM_MAP.get(market_team, market_team)
    espn_opp  = MLB_TEAM_MAP.get(opponent, opponent)

    # Fetch records
    records = _fetch_records()

    team_rec = records.get(espn_team, {})
    opp_rec  = records.get(espn_opp, {})

    team_pct = team_rec.get("pct", 0.50)
    opp_pct  = opp_rec.get("pct", 0.50)
    team_str = team_rec.get("record_str", "?-?")
    opp_str  = opp_rec.get("record_str", "?-?")

    # Need at least 5 spring training games to trust the record
    team_games = team_rec.get("wins", 0) + team_rec.get("losses", 0)
    if team_games < 5:
        log.debug(f"[MLB] {market_team} only {team_games} spring games — skipping")
        return None

    # Base confidence from spring training win%
    # Blend: 60% win% signal + 40% market implied (for spring training noise)
    conf = (team_pct * 0.60) + (yes_bid * 0.40)

    reasons = [f"{market_team}({team_str}) vs {opponent}({opp_str}) winpct={team_pct:.3f}"]

    # Boost if opponent has poor spring record
    if opp_pct < 0.420:
        conf   += 0.03
        reasons.append(f"opp struggling ({opp_str})")

    # Slight home field boost (spring training home matters less but still real)
    # We don't have home/away from ticker easily — skip for now

    # Record differential boost
    rec_diff = team_pct - opp_pct
    if rec_diff > 0.100:
        conf   += 0.02
        reasons.append(f"record edge +{rec_diff:.3f}")
    elif rec_diff < -0.100:
        conf   -= 0.03
        reasons.append(f"record deficit {rec_diff:.3f}")

    # Spring training noise penalty — records are noisier than regular season
    # Reduce confidence slightly for all spring training picks
    conf -= 0.03
    reasons.append("spring training noise -0.03")

    conf  = round(max(0.50, min(0.72, conf)), 3)
    edge  = round(conf - yes_bid, 3)

    # Entry requirements
    min_edge    = 0.08
    should_enter = edge >= min_edge and conf >= 0.60

    reason = " | ".join(reasons)
    log.info(f"[MLB] {market_team} conf={conf:.2f} edge={edge:+.2f} enter={should_enter} | {reason}")

    return MLBContext(
        ticker       = ticker,
        team         = market_team,
        opponent     = opponent,
        team_record  = team_str,
        opp_record   = opp_str,
        team_winpct  = team_pct,
        opp_winpct   = opp_pct,
        is_home      = False,
        confidence   = conf,
        edge         = edge,
        should_enter = should_enter,
        reason       = reason,
    )
