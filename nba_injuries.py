#!/usr/bin/env python3
"""
nba_injuries.py
Fetches tonight's NBA injury report from ESPN.
Used by nba_props.py to boost confidence on teammates of injured stars.

Data source: ESPN scoreboard API (already used by espn_data.py)
No additional API key needed.

Usage:
    from nba_injuries import get_injury_report, get_teammate_boost
    
    # Returns {team_abbrev: [{"name": str, "status": str, "position": str}]}
    injuries = get_injury_report()
    
    # Returns confidence boost for a player given their team
    boost, reason = get_teammate_boost("PHX", "Booker", injuries)
"""

import time
import logging
import requests
from typing import Dict, List, Tuple, Optional

log = logging.getLogger("kalshi_bot.injuries")

ESPN_BASE     = "http://site.api.espn.com/apis/site/v2/sports/basketball/nba"
TIMEOUT       = 8
CACHE_TTL     = 1800  # 30 min — injuries don't change that fast

_injury_cache: Dict = {}  # {"data": {...}, "ts": float}

# Stars whose absence significantly boosts teammates
# Maps last name fragment -> typical usage boost to teammates
STAR_BOOST = {
    # Superstars — big usage shifts when out
    "JAMES":        0.05,
    "CURRY":        0.06,   # Steph is GSW offense — huge boost to rest
    "DURANT":       0.05,
    "GIANNIS":      0.06,   # Giannis IS the Bucks offense
    "EMBIID":       0.05,
    "JOKIC":        0.05,
    "DONCIC":       0.06,
    "TATUM":        0.05,
    "BUTLER":       0.04,   # Jimmy Butler out -> Heat guards boost
    "EDWARDS":      0.05,   # ANT out -> Towns carries more
    "BRUNSON":      0.05,   # Brunson out -> Towns/Hart boost
    "HALIBURTON":   0.05,   # Hali out -> Siakam/Nembhard carry
    "WILLIAMS":     0.04,   # Jalen Williams out -> SGA even more dominant
    "WAGNER":       0.04,   # Franz out -> Banchero/Suggs boost
    "MORANT":       0.05,   # Ja out -> Bane/Aldama carry
    # Stars
    "BOOKER":       0.03,
    "MITCHELL":     0.03,
    "GILGEOUS":     0.04,
    "TOWNS":        0.03,
    "LILLARD":      0.04,   # Lillard out -> Dame carries everything
    "IRVING":       0.04,   # Kyrie out -> Luka must carry (but Luka also out)
    "ADEBAYO":      0.03,   # Bam out -> LaMelo gets easy buckets inside
    "SIAKAM":       0.03,
    "SABONIS":      0.03,
    "LAVINE":       0.03,
    "MARKKANEN":    0.03,
    "GEORGE":       0.03,
    "MAXEY":        0.04,   # Maxey out -> Philly wide open for opponents
}

# Status strings that mean definitely out
OUT_STATUSES = {"out", "doubtful", "o", "d"}


def get_injury_report() -> Dict[str, List[dict]]:
    """
    Returns injury report grouped by team abbreviation.
    {
        "PHX": [{"name": "Kevin Durant", "status": "Out", "position": "SF"}],
        "BOS": [{"name": "Jaylen Brown", "status": "Questionable", "position": "SG"}],
        ...
    }
    Cached for 30 minutes.
    """
    global _injury_cache
    now = time.time()
    if _injury_cache and now - _injury_cache.get("ts", 0) < CACHE_TTL:
        return _injury_cache["data"]

    injuries: Dict[str, List[dict]] = {}

    try:
        r = requests.get(
            f"{ESPN_BASE}/injuries",
            timeout=TIMEOUT
        )
        r.raise_for_status()
        entries = r.json().get("injuries", [])

        for entry in entries:
            for inj in entry.get("injuries", []):
                athlete     = inj.get("athlete", {})
                name        = athlete.get("displayName", "")
                status      = inj.get("status", "")
                pos         = athlete.get("position", {}).get("abbreviation", "")
                team_abbrev = athlete.get("team", {}).get("abbreviation", "")

                if not name or not status or not team_abbrev:
                    continue

                if team_abbrev not in injuries:
                    injuries[team_abbrev] = []

                injuries[team_abbrev].append({
                    "name":     name,
                    "status":   status,
                    "position": pos,
                })
                log.debug(f"[Injuries] {team_abbrev}: {name} - {status}")

        total = sum(len(v) for v in injuries.values())
        log.info(f"[Injuries] Loaded {total} injuries across {len(injuries)} teams")
        _injury_cache = {"data": injuries, "ts": now}
        return injuries

    except Exception as e:
        log.warning(f"[Injuries] Fetch failed: {e}")
        return _injury_cache.get("data", {})


def _fetch_injuries_alternate() -> Dict[str, List[dict]]:
    """
    Fallback: fetch injuries from ESPN injuries endpoint directly.
    """
    injuries: Dict[str, List[dict]] = {}
    try:
        r = requests.get(
            "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/injuries",
            timeout=TIMEOUT
        )
        if not r.ok:
            return {}

        data = r.json()
        for team_entry in data.get("injuries", []):
            team_abbrev = team_entry.get("team", {}).get("abbreviation", "")
            if not team_abbrev:
                continue
            for inj in team_entry.get("injuries", []):
                athlete = inj.get("athlete", {})
                name    = athlete.get("displayName", "")
                status  = inj.get("status", "")
                pos     = athlete.get("position", {}).get("abbreviation", "")
                if name and status:
                    if team_abbrev not in injuries:
                        injuries[team_abbrev] = []
                    injuries[team_abbrev].append({
                        "name": name, "status": status, "position": pos
                    })

        total = sum(len(v) for v in injuries.values())
        log.info(f"[Injuries] Alternate: {total} injuries across {len(injuries)} teams")
        return injuries

    except Exception as e:
        log.debug(f"[Injuries] Alternate fetch failed: {e}")
        return {}


def get_teammate_boost(
    team_abbrev: str,
    player_last: str,
    injuries: Optional[Dict] = None,
    opponent_abbrev: str = ""
) -> Tuple[float, str]:
    """
    Check injuries for confidence boost.
    Two sources:
      1. Teammate stars out -> player carries more load (usage boost)
      2. Opponent stars out -> easier matchup (scoring boost for pts/3pt)

    Args:
        team_abbrev:     player's team e.g. "CHA"
        player_last:     last name fragment e.g. "BALL"
        injuries:        pre-fetched injury dict
        opponent_abbrev: opposing team e.g. "MIA"
    """
    if injuries is None:
        injuries = get_injury_report()

    total_boost = 0.0
    reasons     = []

    # 1. Own team: star teammate out -> usage boost
    for inj in injuries.get(team_abbrev, []):
        name   = inj.get("name", "").upper()
        status = inj.get("status", "").lower()
        if player_last.upper() in name:
            continue
        if not any(s in status for s in OUT_STATUSES):
            continue
        for star_frag, boost in STAR_BOOST.items():
            if star_frag in name:
                total_boost += boost
                short_name = inj["name"].split()[-1]
                reasons.append(f"{short_name} OUT(tm)")
                log.info(f"[Injuries] {team_abbrev}: {inj['name']} OUT → +{boost:.2f} usage boost for {player_last}")
                break

    # 2. Opponent team: star out -> easier scoring matchup
    # Scoring props (PTS/3PT) benefit when opponent is depleted
    if opponent_abbrev:
        opp_star_count = 0
        for inj in injuries.get(opponent_abbrev, []):
            name   = inj.get("name", "").upper()
            status = inj.get("status", "").lower()
            if not any(s in status for s in OUT_STATUSES):
                continue
            for star_frag, boost in STAR_BOOST.items():
                if star_frag in name:
                    # Opponent star out = smaller boost (easier defense)
                    opp_boost = boost * 0.6
                    total_boost += opp_boost
                    opp_star_count += 1
                    short_name = inj["name"].split()[-1]
                    reasons.append(f"{short_name} OUT(opp)")
                    log.info(f"[Injuries] Opp {opponent_abbrev}: {inj['name']} OUT → +{opp_boost:.2f} scoring boost for {player_last}")
                    break

    return round(min(total_boost, 0.10), 3), " + ".join(reasons)


def print_injury_report():
    """Print tonight's injury report to console."""
    injuries = get_injury_report()
    if not injuries:
        print("No injuries found (or ESPN not returning data)")
        return

    print(f"\nNBA Injury Report ({sum(len(v) for v in injuries.values())} total)\n")
    for team in sorted(injuries.keys()):
        team_inj = injuries[team]
        print(f"  {team}:")
        for inj in team_inj:
            print(f"    {inj['name']:<25} {inj['status']:<15} {inj['position']}")


if __name__ == "__main__":
    print_injury_report()
