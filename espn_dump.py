#!/usr/bin/env python3
"""
espn_module.py
─────────────────────────────────────────────────────────────────────────────
ESPN + Odds context module for Kalshi Sports Bot.

Provides:

- Live game state (score, period, time remaining)
- Season records for both teams
- Implied win probability from season record
- Pre-game value detection (Kalshi price vs season record implied probability)
- Team name matching between ESPN and Kalshi tickers

USAGE IN STRATEGIES:
from espn_module import ESPNFetcher
espn = ESPNFetcher()
ctx = espn.get_context("KXNBAGAME-26MAR16MEMCHI-MEM")
if ctx:
print(ctx.home_team, ctx.away_team, ctx.value_signal)

INTEGRATION IN BOT LOOP:
# After get_live_sports_snapshot():
espn_fetcher.refresh()  # call once per cycle
# In strategies, call espn_fetcher.get_context(event_ticker)
"""

import re
import time
import logging
import requests
from datetime import datetime, timezone, timedelta
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger("kalshi_bot")

# ── Team name mappings ESPN display name -> Kalshi abbreviation ───────────────

NBA_TEAMS = {
"Atlanta Hawks":          "ATL",
"Boston Celtics":         "BOS",
"Brooklyn Nets":          "BKN",
"Charlotte Hornets":      "CHA",
"Chicago Bulls":          "CHI",
"Cleveland Cavaliers":    "CLE",
"Dallas Mavericks":       "DAL",
"Denver Nuggets":         "DEN",
"Detroit Pistons":        "DET",
"Golden State Warriors":  "GSW",
"Houston Rockets":        "HOU",
"Indiana Pacers":         "IND",
"LA Clippers":            "LAC",
"Los Angeles Clippers":   "LAC",
"Los Angeles Lakers":     "LAL",
"Memphis Grizzlies":      "MEM",
"Miami Heat":             "MIA",
"Milwaukee Bucks":        "MIL",
"Minnesota Timberwolves": "MIN",
"New Orleans Pelicans":   "NOP",
"New York Knicks":        "NYK",
"Oklahoma City Thunder":  "OKC",
"Orlando Magic":          "ORL",
"Philadelphia 76ers":     "PHI",
"Phoenix Suns":           "PHX",
"Portland Trail Blazers": "POR",
"Sacramento Kings":       "SAC",
"San Antonio Spurs":      "SAS",
"Toronto Raptors":        "TOR",
"Utah Jazz":              "UTA",
"Washington Wizards":     "WAS",
}

MLB_TEAMS = {
"Arizona Diamondbacks":   "AZ",
"Atlanta Braves":         "ATL",
"Baltimore Orioles":      "BAL",
"Boston Red Sox":         "BOS",
"Chicago Cubs":           "CHC",
"Chicago White Sox":      "CWS",
"Cincinnati Reds":        "CIN",
"Cleveland Guardians":    "CLE",
"Colorado Rockies":       "COL",
"Detroit Tigers":         "DET",
"Houston Astros":         "HOU",
"Kansas City Royals":     "KC",
"Los Angeles Angels":     "LAA",
"Los Angeles Dodgers":    "LAD",
"Miami Marlins":          "MIA",
"Milwaukee Brewers":      "MIL",
"Minnesota Twins":        "MIN",
"New York Mets":          "NYM",
"New York Yankees":       "NYY",
"Athletics Athletics":    "ATH",
"Oakland Athletics":      "ATH",
"Philadelphia Phillies":  "PHI",
"Pittsburgh Pirates":     "PIT",
"San Diego Padres":       "SD",
"San Francisco Giants":   "SF",
"Seattle Mariners":       "SEA",
"St. Louis Cardinals":    "STL",
"Tampa Bay Rays":         "TB",
"Texas Rangers":          "TEX",
"Toronto Blue Jays":      "TOR",
"Washington Nationals":   "WSH",
}

# ── Data structures ───────────────────────────────────────────────────────────

@dataclass
class TeamInfo:
    name:         str
    abbreviation: str
    score:        int   = 0
    wins:         int   = 0
    losses:       int   = 0
    win_rate:     float = 0.0

    def implied_prob(self) -> float:
        """Season win rate as implied probability (0.0 - 1.0)."""
        return self.win_rate

@dataclass
class ESPNGameContext:
    event_name:    str
    sport:         str
    state:         str        # "pre", "in", "post"
    detail:        str        # "Final", "Q3 4:32", "Scheduled", etc.
    period:        int        # quarter/inning/set
    clock:         str        # "4:32" or "0:00"
    home:          TeamInfo
    away:          TeamInfo
    start_time:    str        # ISO or display string
    espn_game_id:  str

    # Computed fields
    score_diff:    int   = 0  # home - away (positive = home leading)
    is_live:       bool  = False
    is_pre:        bool  = False
    is_final:      bool  = False

    # Value signal for pre-game
    # Positive = home team underpriced on Kalshi vs season record
    # Negative = away team underpriced on Kalshi vs season record
    value_signal:  Optional[float] = None
    value_team:    Optional[str]   = None  # "home" or "away"
    value_note:    Optional[str]   = None

    def __post_init__(self):
        self.score_diff = self.home.score - self.away.score
        self.is_live    = self.state == "in"
        self.is_pre     = self.state == "pre"
        self.is_final   = self.state == "post"

    def minutes_remaining(self) -> Optional[int]:
        """Rough minutes remaining for NBA (4 periods of 12 min each)."""
        if not self.is_live:
            return None
        try:
            parts = self.clock.split(":")
            mins  = int(parts[0])
            secs  = int(parts[1]) if len(parts) > 1 else 0
            remaining_in_period = mins + secs / 60
            periods_left = max(0, 4 - self.period)
            return int(remaining_in_period + periods_left * 12)
        except Exception:
            return None

    def is_blowout(self, threshold: int = 15) -> bool:
        """True if the leading team is up by threshold+ points."""
        return abs(self.score_diff) >= threshold

    def leading_team_abbr(self) -> Optional[str]:
        if self.score_diff > 0:
            return self.home.abbreviation
        elif self.score_diff < 0:
            return self.away.abbreviation
        return None

    def summary(self) -> str:
        if self.is_pre:
            return (f"PRE {self.away.name} @ {self.home.name} | "
                    f"{self.away.wins}-{self.away.losses} vs {self.home.wins}-{self.home.losses}")
        elif self.is_live:
            return (f"LIVE Q{self.period} {self.clock} | "
                    f"{self.away.name} {self.away.score} - {self.home.score} {self.home.name}")
        else:
            return (f"FINAL {self.away.name} {self.away.score} - "
                    f"{self.home.score} {self.home.name}")

# ── Parser helpers ────────────────────────────────────────────────────────────

def _parse_record(summary: str) -> tuple:
    """Parse "53-15" or "7-14-1" into (wins, losses, win_rate)."""
    try:
        parts  = summary.split("-")
        wins   = int(parts[0])
        losses = int(parts[1])
        total  = wins + losses
        rate   = wins / total if total > 0 else 0.5
        return wins, losses, rate
    except Exception:
        return 0, 0, 0.5

def _get_abbr(display_name: str, team_map: dict) -> str:
    """Look up abbreviation from display name, fallback to first 3 chars."""
    return team_map.get(display_name, display_name[:3].upper())

def _parse_competitor(comp_data: dict, team_map: dict) -> TeamInfo:
    name  = comp_data.get("team", {}).get("displayName", "Unknown")
    abbr  = _get_abbr(name, team_map)
    score = int(comp_data.get("score", 0) or 0)
    records = comp_data.get("records", [])
    wins, losses, win_rate = 0, 0, 0.5
    for rec in records:
        if rec.get("type") == "total" or rec.get("name") == "overall":
            wins, losses, win_rate = _parse_record(rec.get("summary", "0-0"))
            break
    if wins == 0 and records:
        wins, losses, win_rate = _parse_record(records[0].get("summary", "0-0"))
    return TeamInfo(name=name, abbreviation=abbr, score=score,
                    wins=wins, losses=losses, win_rate=win_rate)

def _parse_competition(event: dict, sport: str) -> Optional["ESPNGameContext"]:
    try:
        comp      = event["competitions"][0]
        status    = comp["status"]
        state     = status["type"]["state"]
        detail    = status["type"].get("detail", "")
        period    = status.get("period", 0)
        clock     = status.get("displayClock", "0:00")
        game_id   = event.get("id", "")
        name      = event.get("name", "")
        start     = event.get("date", "")

        team_map  = NBA_TEAMS if sport == "NBA" else MLB_TEAMS

        competitors = comp.get("competitors", [])
        home_data   = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0] if competitors else {})
        away_data   = next((c for c in competitors if c.get("homeAway") == "away"), competitors[1] if len(competitors) > 1 else {})

        home = _parse_competitor(home_data, team_map)
        away = _parse_competitor(away_data, team_map)

        return ESPNGameContext(
            event_name   = name,
            sport        = sport,
            state        = state,
            detail       = detail,
            period       = period,
            clock        = clock,
            home         = home,
            away         = away,
            start_time   = start,
            espn_game_id = game_id,
        )
    except Exception as e:
        log.warning(f"[ESPN] Parse error for {event.get('name','?')}: {e}")
        return None

# ── Kalshi ticker parser ──────────────────────────────────────────────────────

def _extract_abbrs_from_ticker(event_ticker: str) -> list:
    """
    Extract team abbreviations from a Kalshi event ticker.
    e.g. KXNBAGAME-26MAR16MEMCHI -> ["MEM", "CHI"]
    KXMLBGAME-26MAR16BOSBAL -> ["BOS", "BAL"]
    Strips the date prefix and splits remaining into 3-char chunks.
    """
    # Remove series prefix (everything up to and including the date)
    # Pattern: KXNBAGAME-26MAR16MEMCHI  -> MEMCHI
    m = re.search(r"\d{2}[A-Z]{3}\d{2}([A-Z]+)$", event_ticker)
    if not m:
        return []
    raw = m.group(1)
    # Split into 3-char chunks
    abbrs = [raw[i:i+3] for i in range(0, len(raw), 3) if len(raw[i:i+3]) == 3]
    return abbrs

def _teams_match(espn_ctx: ESPNGameContext, abbrs: list) -> bool:
    """Check if ESPN game teams match the extracted Kalshi abbreviations."""
    if not abbrs:
        return False
    home_abbr = espn_ctx.home.abbreviation.upper()
    away_abbr = espn_ctx.away.abbreviation.upper()
    abbrs_upper = [a.upper() for a in abbrs]
    # Check if any combination of abbrs matches home+away
    for i, a1 in enumerate(abbrs_upper):
        for a2 in abbrs_upper[i+1:]:
            if (home_abbr.startswith(a1[:2]) or a1.startswith(home_abbr[:2])) and \
               (away_abbr.startswith(a2[:2]) or a2.startswith(away_abbr[:2])):
                return True
            if (home_abbr.startswith(a2[:2]) or a2.startswith(home_abbr[:2])) and \
               (away_abbr.startswith(a1[:2]) or a1.startswith(away_abbr[:2])):
                return True
    # Looser match: any abbr appears in either team name
    matches = sum(1 for a in abbrs_upper
                  if home_abbr.startswith(a[:2]) or away_abbr.startswith(a[:2])
                  or a.startswith(home_abbr[:2]) or a.startswith(away_abbr[:2]))
    return matches >= 2

# ── Value signal calculator ───────────────────────────────────────────────────

def _compute_value_signal(ctx: ESPNGameContext, kalshi_yes_bid: float,
                          kalshi_side: str) -> ESPNGameContext:
    """
    Compare Kalshi implied probability vs season record implied probability.
    kalshi_yes_bid: 0.0-1.0 (e.g. 0.40 for 40c)
    kalshi_side: "home" or "away" (which team the YES bet is on)
    """
    if not ctx.is_pre:
        return ctx

    home_implied = ctx.home.implied_prob()
    away_implied = ctx.away.implied_prob()

    # Normalize so they sum to 1
    total = home_implied + away_implied
    if total > 0:
        home_implied = home_implied / total
        away_implied = away_implied / total
    else:
        home_implied = away_implied = 0.5

    if kalshi_side == "home":
        edge = home_implied - kalshi_yes_bid
        team_name = ctx.home.name
    else:
        edge = away_implied - kalshi_yes_bid
        team_name = ctx.away.name

    ctx.value_signal = round(edge, 3)
    ctx.value_team   = kalshi_side

    if edge > 0.10:
        ctx.value_note = (f"VALUE: {team_name} at {int(kalshi_yes_bid*100)}c but "
                          f"season record implies {int((home_implied if kalshi_side=='home' else away_implied)*100)}c "
                          f"(+{int(edge*100)}% edge)")
    elif edge < -0.10:
        ctx.value_note = (f"OVERPRICED: {team_name} at {int(kalshi_yes_bid*100)}c but "
                          f"season record implies {int((home_implied if kalshi_side=='home' else away_implied)*100)}c "
                          f"({int(edge*100)}% against)")
    else:
        ctx.value_note = f"FAIR: {int(edge*100):+d}% vs season record"

    return ctx

# ── Main fetcher class ────────────────────────────────────────────────────────

class ESPNFetcher:
    """
    Fetches and caches ESPN game data for NBA and MLB.
    Call refresh() once per bot cycle, then get_context() per market.
    """

    ESPN_URLS = {
        "NBA": "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
        "MLB": "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
    }

    def __init__(self):
        self._cache:      list  = []   # list of ESPNGameContext
        self._last_fetch: float = 0.0
        self._cache_ttl:  int   = 55   # seconds (just under 1 cycle)

    def refresh(self, force: bool = False):
        """Fetch fresh data from ESPN. Call once per bot cycle."""
        now = time.time()
        if not force and (now - self._last_fetch) < self._cache_ttl:
            return

        new_cache = []
        today    = datetime.now(timezone.utc).strftime("%Y%m%d")
        tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y%m%d")

        for sport, url in self.ESPN_URLS.items():
            for date in [today, tomorrow]:
                try:
                    r = requests.get(url, params={"dates": date}, timeout=8)
                    r.raise_for_status()
                    for event in r.json().get("events", []):
                        ctx = _parse_competition(event, sport)
                        if ctx:
                            new_cache.append(ctx)
                    time.sleep(0.1)
                except Exception as e:
                    log.warning(f"[ESPN] Fetch {sport} {date} failed: {e}")

        self._cache      = new_cache
        self._last_fetch = now
        live  = sum(1 for c in new_cache if c.is_live)
        pre   = sum(1 for c in new_cache if c.is_pre)
        final = sum(1 for c in new_cache if c.is_final)
        log.info(f"[ESPN] Refreshed: {len(new_cache)} games "
                 f"({pre} pre, {live} live, {final} final)")

    def get_context(self, event_ticker: str,
                    kalshi_yes_bid: float = None,
                    kalshi_side: str = None) -> Optional[ESPNGameContext]:
        """
        Match a Kalshi event ticker to an ESPN game context.
        Optionally compute value signal if kalshi_yes_bid and side provided.
        """
        abbrs = _extract_abbrs_from_ticker(event_ticker)
        for ctx in self._cache:
            if _teams_match(ctx, abbrs):
                if kalshi_yes_bid is not None and kalshi_side and ctx.is_pre:
                    ctx = _compute_value_signal(ctx, kalshi_yes_bid, kalshi_side)
                return ctx
        return None

    def get_all_live(self) -> list:
        return [c for c in self._cache if c.is_live]

    def get_all_pre(self) -> list:
        return [c for c in self._cache if c.is_pre]

    def get_by_sport(self, sport: str) -> list:
        return [c for c in self._cache if c.sport == sport]

# ── Strategy helpers (import these in kalshi_bot.py strategies) ───────────────

def espn_should_skip_entry(ctx: Optional[ESPNGameContext], side: str) -> tuple:
    """
    Returns (should_skip: bool, reason: str).
    Call this at the start of any entry strategy.

    Rules:
    - Live NBA: skip if blowout (15+ points) AND past Q3
    - Live NBA: skip if less than 5 minutes remaining
    - Pre-game: skip if Kalshi price is overpriced vs season record by 10%+
    """
    if ctx is None:
        return False, ""

    if ctx.is_live:
        mins_left = ctx.minutes_remaining()

        # Skip if blowout in late game
        if ctx.is_blowout(15) and ctx.period >= 3:
            leader = ctx.leading_team_abbr()
            return True, f"Blowout skip: {leader} up {abs(ctx.score_diff)} in Q{ctx.period}"

        # Skip if less than 5 minutes remaining
        if mins_left is not None and mins_left < 5:
            return True, f"End-game skip: ~{mins_left}m remaining"

    if ctx.is_pre and ctx.value_signal is not None:
        # Skip if betting on overpriced side
        if ctx.value_signal < -0.10:
            return True, f"Overpriced skip: {ctx.value_note}"

    return False, ""

def espn_get_value_yes_signal(ctx: Optional[ESPNGameContext],
                              min_edge: float = 0.10) -> Optional[str]:
    """
    Returns "home" or "away" if a pre-game value YES opportunity exists,
    or None if no clear edge. min_edge is the minimum probability gap.
    """
    if ctx is None or not ctx.is_pre:
        return None

    home_implied = ctx.home.implied_prob()
    away_implied = ctx.away.implied_prob()
    total = home_implied + away_implied
    if total > 0:
        home_implied /= total
        away_implied /= total

    return None  # caller must provide Kalshi prices to compute edge

# ── Standalone test ───────────────────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    fetcher = ESPNFetcher()
    fetcher.refresh(force=True)

    print(f"\nTotal cached: {len(fetcher._cache)}")
    print(f"Live games:   {len(fetcher.get_all_live())}")
    print(f"Pre games:    {len(fetcher.get_all_pre())}")

    print("\n--- ALL GAMES ---")
    for ctx in fetcher._cache:
        print(f"  [{ctx.state.upper():4}] {ctx.summary()}")

    print("\n--- TICKER MATCHING TESTS ---")
    test_tickers = [
        "KXNBAGAME-26MAR16MEMCHI-MEM",
        "KXNBAGAME-26MAR16GSWWAS-WAS",
        "KXNBAGAME-26MAR16LALHOU-LAL",
        "KXMLBGAME-26MAR16BOSBAL-BOS",
        "KXNBAGAME-26MAR17PHXMIN-PHX",
    ]
    for ticker in test_tickers:
        ctx = fetcher.get_context(ticker)
        if ctx:
            print(f"  MATCH: {ticker}")
            print(f"         -> {ctx.summary()}")
        else:
            print(f"  NO MATCH: {ticker}")
            abbrs = _extract_abbrs_from_ticker(ticker)
            print(f"         -> parsed abbrs: {abbrs}")
