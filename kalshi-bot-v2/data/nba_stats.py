#!/usr/bin/env python3
"""
data/nba_stats.py
─────────────────────────────────────────────────────────────────────────────
NBA player season average stats for combo leg scoring.
Sources: ESPN roster + statistics endpoints.
"""

import logging
import re
import requests
from data.cache import TTLCache

log = logging.getLogger("kalshi_bot.data.nba_stats")

stats_cache = TTLCache(default_ttl=3600)   # 1 hour — stats don't change mid-game

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"
ESPN_CORE = "https://sports.core.api.espn.com/v2/sports/basketball/leagues/nba"

# Kalshi team code → ESPN team abbreviation
TEAM_CODE_MAP = {
    "ATL": "ATL", "BOS": "BOS", "BKN": "BKN", "CHA": "CHA",
    "CHI": "CHI", "CLE": "CLE", "DAL": "DAL", "DEN": "DEN",
    "DET": "DET", "GSW": "GS",  "HOU": "HOU", "IND": "IND",
    "LAC": "LAC", "LAL": "LAL", "MEM": "MEM", "MIA": "MIA",
    "MIL": "MIL", "MIN": "MIN", "NOP": "NO",  "NYK": "NY",
    "OKC": "OKC", "ORL": "ORL", "PHI": "PHI", "PHX": "PHX",
    "POR": "POR", "SAC": "SAC", "SAS": "SA",  "TOR": "TOR",
    "UTA": "UTAH", "WAS": "WSH",
}


def get_player_averages(kalshi_ticker: str) -> dict:
    """
    Given a Kalshi prop ticker like KXNBAPTS-26MAR27LACIND-LACKLEONARD2-25,
    return player season averages dict.

    Returns dict with keys:
        avg_points, avg_rebounds, avg_assists, avg_blocks,
        avg_steals, avg_threes, player_name, espn_id
    """
    cached = stats_cache.get(kalshi_ticker)
    if cached is not None:
        return cached

    parsed = _parse_ticker(kalshi_ticker)
    if not parsed:
        return {}

    team_code, last_name = parsed
    espn_team = TEAM_CODE_MAP.get(team_code, team_code)

    # Find ESPN athlete ID from roster
    espn_id, full_name = _find_player(espn_team, last_name)
    if not espn_id:
        log.debug(f"[NBAStats] Player not found: {last_name} on {espn_team}")
        return {}

    # Fetch season averages
    avgs = _fetch_averages(espn_id, full_name)
    stats_cache.set(kalshi_ticker, avgs)
    return avgs


def _parse_ticker(ticker: str) -> tuple:
    """
    Parse Kalshi prop ticker to extract team code and player last name.
    KXNBAPTS-26MAR27LACIND-LACKLEONARD2-25 → ('LAC', 'leonard')
    KXNBAREB-26MAR27LACIND-INDPSIAKAM43-10 → ('IND', 'siakam')
    """
    # Match the player section: TEAMPLAYERNAME#-THRESHOLD
    m = re.search(r'-([A-Z]{3})([A-Z]+)(\d+)-(\d+)$', ticker)
    if not m:
        return None
    team_code   = m.group(1)        # e.g. LAC
    player_code = m.group(2).lower() # e.g. kleonard
    return (team_code, player_code)


def _find_player(espn_team: str, player_code: str) -> tuple:
    """
    Find ESPN athlete ID by matching player_code against team roster.
    Returns (espn_id, full_name) or (None, None).
    """
    cache_key = f"roster_{espn_team}"
    roster = stats_cache.get(cache_key)

    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=3600)
        except Exception as e:
            log.warning(f"[NBAStats] Roster fetch failed {espn_team}: {e}")
            return (None, None)

    # Match player_code against last names
    for athlete in roster:
        last = athlete.get('lastName', '').lower().replace('-','').replace("'",'')
        full = athlete.get('fullName', '')
        code = player_code.replace('-','').replace("'",'')

        # Direct last name match
        if code.endswith(last) or last in code:
            return (athlete['id'], full)

        # Partial match — player_code contains significant part of last name
        if len(last) >= 4 and last[:4] in code:
            return (athlete['id'], full)

        # Reverse partial — last name contains player code fragment
        if len(code) >= 4 and code[:4] in last:
            return (athlete['id'], full)

    # Not found on primary team — search all NBA teams (handles trades)
    all_teams = list(TEAM_CODE_MAP.values())
    for team in all_teams:
        if team == espn_team:
            continue
        try:
            r2 = requests.get(f"{ESPN_BASE}/teams/{team}/roster", timeout=4)
            r2.raise_for_status()
            for athlete in r2.json().get('athletes', []):
                last = athlete.get('lastName', '').lower().replace('-','').replace("'",'')
                full = athlete.get('fullName', '')
                code = player_code.replace('-','').replace("'",'')
                if code.endswith(last) or last in code:
                    log.debug(f"[NBAStats] Found {full} on {team} (traded from {espn_team})")
                    return (athlete['id'], full)
                if len(last) >= 4 and last[:4] in code:
                    log.debug(f"[NBAStats] Found {full} on {team} (traded from {espn_team})")
                    return (athlete['id'], full)
        except Exception:
            continue

    return (None, None)


def get_injury_status(espn_id: str, espn_team: str) -> str:
    """
    Return injury status for a player: 'active', 'out', 'doubtful', 'questionable'.
    Uses ESPN roster endpoint which includes injury status.
    """
    cache_key = f"injury_{espn_team}"
    roster = stats_cache.get(cache_key)
    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=300)  # 5 min — injuries change
        except Exception as e:
            log.warning(f"[NBAStats] Roster fetch failed {espn_team}: {e}")
            return 'active'

    for athlete in roster:
        if athlete.get('id') == espn_id:
            # Check injuries array first — most accurate
            injuries = athlete.get('injuries', [])
            if injuries:
                s = str(injuries[0].get('status', 'Active')).lower()
            else:
                status = athlete.get('status', {})
                if isinstance(status, dict):
                    type_val = status.get('type', 'active')
                    s = str(type_val).lower() if not isinstance(type_val, dict) else 'active'
                else:
                    s = str(status).lower()
            if 'out' in s:
                return 'out'
            if 'doubtful' in s:
                return 'doubtful'
            if 'questionable' in s:
                return 'questionable'
            return 'active'
    return 'active'


def _fetch_averages(espn_id: str, full_name: str) -> dict:
    """Fetch current season per-game averages from ESPN."""
    try:
        r = requests.get(
            f"{ESPN_CORE}/seasons/2026/types/2/athletes/{espn_id}/statistics",
            timeout=6
        )
        r.raise_for_status()
        splits = r.json().get('splits', {})
        cats   = splits.get('categories', [])

        avgs = {
            'player_name':    full_name,
            'espn_id':        espn_id,
            'avg_points':     0.0,
            'avg_rebounds':   0.0,
            'avg_assists':    0.0,
            'avg_blocks':     0.0,
            'avg_steals':     0.0,
            'avg_threes':     0.0,
            'avg_minutes':    0.0,
        }

        for cat in cats:
            for stat in cat.get('stats', []):
                name = stat.get('name', '')
                val  = float(stat.get('value', 0) or 0)
                if name == 'avgPoints':      avgs['avg_points']   = val
                if name == 'avgRebounds':    avgs['avg_rebounds'] = val
                if name == 'avgAssists':     avgs['avg_assists']  = val
                if name == 'avgBlocks':      avgs['avg_blocks']   = val
                if name == 'avgSteals':      avgs['avg_steals']   = val
                if name == 'avgThreePointFieldGoalsMade':
                    avgs['avg_threes'] = val
                if name == 'avgMinutes':     avgs['avg_minutes']  = val

        log.debug(f"[NBAStats] {full_name}: "
                 f"pts={avgs['avg_points']} reb={avgs['avg_rebounds']} "
                 f"ast={avgs['avg_assists']}")
        return avgs

    except Exception as e:
        log.warning(f"[NBAStats] Stats fetch failed {espn_id}: {e}")
        return {}


def get_prop_stat(avgs: dict, stat_type: str) -> float:
    """
    Map Kalshi prop series to the relevant average stat.
    stat_type: PTS, REB, AST, BLK, STL, 3PT
    """
    mapping = {
        'KXNBAPTS':  'avg_points',
        'KXNBAREB':  'avg_rebounds',
        'KXNBAAST':  'avg_assists',
        'KXNBABLK':  'avg_blocks',
        'KXNBASTL':  'avg_steals',
        'KXNBA3PT':  'avg_threes',
    }
    key = mapping.get(stat_type, '')
    return avgs.get(key, 0.0)


def get_threshold(ticker: str) -> float:
    """Extract the numeric threshold from a Kalshi prop ticker."""
    m = re.search(r'-(\d+)$', ticker)
    return float(m.group(1)) if m else 0.0


def get_stat_series(ticker: str) -> str:
    """Extract the stat series prefix from a Kalshi prop ticker."""
    m = re.match(r'(KXNBA[A-Z0-9]+)-', ticker)
    return m.group(1) if m else ''


def score_prop_leg(ticker: str) -> dict:
    """
    Score a prop leg for combo selection.
    Returns dict with confidence, reasoning, and stats.

    Logic:
    - Get player season average for this stat
    - Compute ratio: avg / threshold
    - Higher ratio = more confident the player clears the threshold
    - Filter: skip if avg/threshold < 1.3 (too close to threshold)
    - Filter: skip if market yes_bid > 0.92 (barely adds to payout)
    - Filter: skip if player is injured
    """
    avgs      = get_player_averages(ticker)
    if not avgs:
        return {'confidence': 0.0, 'reason': 'No stats available'}

    # Check injury status — skip injured players
    espn_id   = avgs.get('espn_id', '')
    parsed    = _parse_ticker(ticker)
    if parsed and espn_id:
        team_code = parsed[0]
        espn_team = TEAM_CODE_MAP.get(team_code, team_code)
        status    = get_injury_status(espn_id, espn_team)
        if status in ('out', 'doubtful'):
            log.debug(f"[NBAStats] {avgs.get('player_name')} is {status} — skipping")
            return {'confidence': 0.0, 'reason': f"{avgs.get('player_name')} is {status} tonight", 'injured': True}
        if status == 'questionable':
            log.debug(f"[NBAStats] {avgs.get('player_name')} is questionable — reducing confidence")
            # Will apply 0.1 penalty to confidence below

    series    = get_stat_series(ticker)
    threshold = get_threshold(ticker)
    avg_stat  = get_prop_stat(avgs, series)

    if threshold <= 0 or avg_stat <= 0:
        return {'confidence': 0.0, 'reason': 'Invalid threshold or no stat'}

    ratio = avg_stat / threshold

    # Confidence based on ratio
    if ratio >= 2.0:
        confidence = 0.88
    elif ratio >= 1.7:
        confidence = 0.82
    elif ratio >= 1.5:
        confidence = 0.76
    elif ratio >= 1.3:
        confidence = 0.70
    else:
        confidence = 0.0  # Too close — skip

    # Apply questionable penalty
    injury_note = ""
    if confidence > 0:
        parsed2 = _parse_ticker(ticker)
        espn_id2 = avgs.get("espn_id", "")
        if parsed2 and espn_id2:
            team_code2 = parsed2[0]
            espn_team2 = TEAM_CODE_MAP.get(team_code2, team_code2)
            status2    = get_injury_status(espn_id2, espn_team2)
            if status2 == "questionable":
                confidence = round(max(0, confidence - 0.10), 2)
                injury_note = " [questionable]"

    reason = (f"{avgs['player_name']} avg {avg_stat:.1f} vs threshold {threshold} "
              f"(ratio={ratio:.2f}) → conf={confidence:.2f}{injury_note}")

    return {
        'confidence':   confidence,
        'avg_stat':     avg_stat,
        'threshold':    threshold,
        'ratio':        ratio,
        'player_name':  avgs['player_name'],
        'reason':       reason,
    }
