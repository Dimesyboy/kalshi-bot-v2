#!/usr/bin/env python3
"""
tennis_context.py
Full implementation using api-tennis.com live data.

Data flow each strategy call:
  1. get_tennis_context(ticker, espn_cache=None)
     -> _fetch_livescore()    live matches from api-tennis.com (cached 45s)
     -> fuzzy match ticker to live match
     -> _fetch_rankings()     ATP/WTA standings (cached 1hr)
     -> _fetch_h2h()          H2H by player key (cached 24hr)
     -> build TennisContext
"""

import re
import time
import logging
import requests
from dataclasses import dataclass, field
from typing import Optional, List, Tuple, Dict

log = logging.getLogger("kalshi_bot.tennis")

TENNIS_API_KEY = "d5a36c825abb6150aa2b7b90bcf353b5e94da8400f477f02c02727ff068b2b87"
TENNIS_API_URL = "https://api.api-tennis.com/tennis/"
TIMEOUT        = 8

_livescore_cache: Dict = {}
_rankings_cache:  Dict = {}
_h2h_cache:       Dict = {}

LIVESCORE_TTL = 45
RANKINGS_TTL  = 3600
H2H_TTL       = 86400


@dataclass
class TennisContext:
    ticker:         str
    p1_name:        str
    p2_name:        str
    p1_sets:        int
    p2_sets:        int
    sets:           List[Tuple[int, int]] = field(default_factory=list)
    p1_games:       int   = 0
    p2_games:       int   = 0
    server:         str   = ""
    p1_rank:        int   = 999
    p2_rank:        int   = 999
    is_live:        bool  = False
    pct_complete:   float = 0.0
    sets_down:      int   = 0
    underdog_conf:  float = 0.62
    comeback_conf:  float = 0.58
    h2h:            str   = "?"
    surface_edge:   float = 0.50
    event_key:      str   = ""
    p1_key:         str   = ""
    p2_key:         str   = ""

    def summary(self) -> str:
        set_str = " ".join(f"{a}-{b}" for a, b in self.sets) if self.sets else "?"
        return (
            f"{self.p1_name} vs {self.p2_name} [{set_str}] "
            f"R{self.p1_rank}/{self.p2_rank} H2H:{self.h2h}"
        )


def _api(params: dict) -> Optional[dict]:
    try:
        params["APIkey"] = TENNIS_API_KEY
        r = requests.get(TENNIS_API_URL, params=params, timeout=TIMEOUT)
        r.raise_for_status()
        data = r.json()
        if data.get("success") != 1:
            log.debug(f"[Tennis API] Non-success: {data}")
            return None
        return data
    except Exception as e:
        log.warning(f"[Tennis API] {params.get('method')} failed: {e}")
        return None


def _fetch_livescore() -> List[dict]:
    global _livescore_cache
    now = time.time()
    if _livescore_cache and now - _livescore_cache.get("ts", 0) < LIVESCORE_TTL:
        return _livescore_cache["data"]
    data = _api({"method": "get_livescore"})
    if data and isinstance(data.get("result"), list):
        _livescore_cache = {"data": data["result"], "ts": now}
        log.info(f"[Tennis] Livescore: {len(data['result'])} live matches")
        return data["result"]
    return _livescore_cache.get("data", [])


def _fetch_rankings() -> Dict:
    global _rankings_cache
    now = time.time()
    if _rankings_cache and now - _rankings_cache.get("ts", 0) < RANKINGS_TTL:
        return _rankings_cache
    out: Dict = {"ATP": {}, "WTA": {}, "ts": now}
    for league in ("ATP", "WTA"):
        data = _api({"method": "get_standings", "event_type": league})
        if data and isinstance(data.get("result"), list):
            for entry in data["result"]:
                try:
                    name = entry.get("player", "")
                    rank = int(entry.get("place", 999))
                    if name:
                        out[league][name.upper()] = rank
                except Exception:
                    pass
            log.info(f"[Tennis] Rankings: {league} {len(out[league])} players")
    _rankings_cache = out
    return out


def _get_rank(player_name: str, league: str) -> int:
    rankings = _fetch_rankings()
    table = rankings.get(league.upper(), {})
    if not player_name or not table:
        return 999
    name_upper = player_name.upper()
    if name_upper in table:
        return table[name_upper]
    last = name_upper.split()[-1]
    for key, rank in table.items():
        key_last = key.split()[-1] if key.split() else ""
        if last and key_last == last:
            return rank
    return 999


def _fetch_h2h(p1_key: str, p2_key: str, p1_name: str, p2_name: str) -> str:
    if not p1_key or not p2_key:
        return "?"
    cache_key = (min(p1_key, p2_key), max(p1_key, p2_key))
    now = time.time()
    cached = _h2h_cache.get(cache_key)
    if cached and now - cached.get("ts", 0) < H2H_TTL:
        return cached["str"]
    data = _api({"method": "get_H2H", "first_player_key": p1_key, "second_player_key": p2_key})
    if not data or not isinstance(data.get("result"), dict):
        return "?"
    h2h_matches = data["result"].get("H2H", [])
    p1_wins = sum(1 for m in h2h_matches if m.get("event_winner") == "First Player")
    p2_wins = sum(1 for m in h2h_matches if m.get("event_winner") == "Second Player")
    p1_short = p1_name.split()[-1] if p1_name else "P1"
    p2_short = p2_name.split()[-1] if p2_name else "P2"
    result_str = f"{p1_short} {p1_wins}-{p2_wins} {p2_short}"
    _h2h_cache[cache_key] = {"str": result_str, "ts": now}
    log.debug(f"[Tennis] H2H: {result_str}")
    return result_str


def _parse_ticker_players(ticker: str) -> Tuple[str, str]:
    """
    Kalshi tennis ticker format:
    KXATPMATCH-26MAR17GUICAD-GUI
    The middle segment after date = P1code+P2code concatenated
    The last segment = P1code (3 chars)
    So P1code = parts[2], P2code = middle[-(len(parts[2])):]
    Example: GUICAD-GUI -> P1=GUI, P2=CAD
    """
    try:
        parts = ticker.split("-")
        if len(parts) < 3:
            return "", ""
        event_segment = parts[1]  # e.g. 26MAR17GUICAD
        p1_code = parts[2]        # e.g. GUI (always the last segment)
        import re as _re
        date_match = _re.match(r"^\d{2}[A-Z]{3}\d{2}", event_segment)
        if not date_match:
            return "", ""
        combined = event_segment[date_match.end():]  # e.g. GUICAD
        # P2 code is whatever is left after removing P1 code from combined
        if combined.startswith(p1_code):
            p2_code = combined[len(p1_code):]
        else:
            # fallback: split combined in half
            mid = len(combined) // 2
            p2_code = combined[mid:]
        if not p1_code or not p2_code:
            return "", ""
        log.debug(f"[Tennis] Parsed {ticker} -> P1={p1_code} P2={p2_code}")
        return p1_code.upper(), p2_code.upper()
    except Exception as e:
        log.debug(f"[Tennis] Ticker parse error {ticker}: {e}")
        return "", ""

def _name_matches_fragment(fragment: str, full_name: str) -> bool:
    if not fragment or not full_name:
        return False
    # Require minimum fragment length to avoid false positives
    if len(fragment) < 4:
        return False
    frag = fragment.upper()
    name = full_name.upper()
    # Direct substring match
    if frag in name:
        return True
    # Word-level match - fragment must match start of a word with 4+ chars
    for word in re.split(r'[\s.\-]', name):
        if len(word) >= 4 and word.startswith(frag[:4]):
            return True
    return False

def _build_context(match: dict, ticker: str) -> Optional[TennisContext]:
    try:
        p1_name   = match.get("event_first_player", "")
        p2_name   = match.get("event_second_player", "")
        p1_key    = str(match.get("first_player_key", ""))
        p2_key    = str(match.get("second_player_key", ""))
        event_key = str(match.get("event_key", ""))
        is_live   = str(match.get("event_live", "0")) == "1"

        raw_scores = match.get("scores", [])
        sets: List[Tuple[int, int]] = []
        for s in raw_scores:
            try:
                # API returns tiebreak scores as floats e.g. 7.7 or 6.11 — round to int
                sets.append((round(float(s["score_first"])), round(float(s["score_second"]))))
            except Exception:
                pass

        p1_sets = sum(1 for a, b in sets if a > b)
        p2_sets = sum(1 for a, b in sets if b > a)

        p1_games, p2_games = 0, 0
        if sets:
            a, b = sets[-1]
            set_complete = (max(a, b) >= 6 and abs(a - b) >= 2) or max(a, b) >= 7
            if not set_complete:
                p1_games, p2_games = a, b

        serve_raw = match.get("event_serve", "") or ""
        if serve_raw == "First Player":
            server = p1_name
        elif serve_raw == "Second Player":
            server = p2_name
        else:
            server = serve_raw

        sets_down  = abs(p1_sets - p2_sets)
        event_type = (match.get("event_type_type") or "").upper()
        max_sets   = 5 if any(x in event_type for x in ("GRAND SLAM", "GS")) else 3
        total_sets = p1_sets + p2_sets
        pct        = min(total_sets / max_sets, 0.99)
        if total_sets == max_sets - 1 and (p1_games + p2_games) > 0:
            pct = min(pct + min((p1_games + p2_games) / 12.0, 0.99) * (1.0 / max_sets), 0.99)

        league  = "WTA" if ("WTA" in event_type or "WOMEN" in event_type) else "ATP"
        p1_rank = _get_rank(p1_name, league)
        p2_rank = _get_rank(p2_name, league)
        h2h_str = _fetch_h2h(p1_key, p2_key, p1_name, p2_name)

        underdog_conf = 0.62
        rank_diff = abs(p1_rank - p2_rank)
        if rank_diff > 50:
            underdog_conf -= 0.03
        elif rank_diff <= 10:
            underdog_conf += 0.02
        if total_sets == 0:
            underdog_conf += 0.02
        if pct > 0.65:
            underdog_conf -= 0.04
        if sets_down >= 2:
            underdog_conf -= 0.06
        game_diff = abs(p1_games - p2_games)
        if game_diff >= 4:
            underdog_conf -= 0.03
        elif game_diff <= 1:
            underdog_conf += 0.02
        try:
            h_parts = h2h_str.split()
            if len(h_parts) == 3 and "-" in h_parts[1]:
                w1, w2 = h_parts[1].split("-")
                total_h2h = int(w1) + int(w2)
                if total_h2h >= 3 and int(w2) / total_h2h > 0.55:
                    underdog_conf += 0.02
        except Exception:
            pass

        underdog_conf = round(max(0.55, min(0.74, underdog_conf)), 3)
        comeback_conf = round(underdog_conf - 0.04, 3)

        surface_edge = 0.52
        t_name = (match.get("tournament_name") or "").upper()
        if "CLAY" in t_name:
            surface_edge = 0.53
        elif "GRASS" in t_name or "WIMBLEDON" in t_name:
            surface_edge = 0.53

        return TennisContext(
            ticker=ticker, p1_name=p1_name, p2_name=p2_name,
            p1_sets=p1_sets, p2_sets=p2_sets, sets=sets,
            p1_games=p1_games, p2_games=p2_games, server=server,
            p1_rank=p1_rank, p2_rank=p2_rank, is_live=is_live,
            pct_complete=pct, sets_down=sets_down,
            underdog_conf=underdog_conf, comeback_conf=comeback_conf,
            h2h=h2h_str, surface_edge=surface_edge,
            event_key=event_key, p1_key=p1_key, p2_key=p2_key,
        )

    except Exception as e:
        log.warning(f"[Tennis] _build_context failed for {ticker}: {e}")
        return None


def get_tennis_context(ticker: str, espn_cache=None) -> Optional[TennisContext]:
    """
    Main entry point called by strategies.py.
    espn_cache accepted for compatibility but unused — data comes from api-tennis.com.
    """
    p1_frag, p2_frag = _parse_ticker_players(ticker)
    if not p1_frag and not p2_frag:
        log.debug(f"[Tennis] Could not parse fragments from {ticker}")
        return None

    live_matches = _fetch_livescore()
    if not live_matches:
        log.debug("[Tennis] No live matches available")
        return None

    best_match = None
    best_score = 0
    for match in live_matches:
        p1n = (match.get("event_first_player") or "").upper()
        p2n = (match.get("event_second_player") or "").upper()
        # Both fragments must match something — prevents dead matches cross-firing
        p1_hits = _name_matches_fragment(p1_frag, p1n) or _name_matches_fragment(p1_frag, p2n)
        p2_hits = _name_matches_fragment(p2_frag, p2n) or _name_matches_fragment(p2_frag, p1n)
        if not p1_hits or not p2_hits:
            continue
        score = 0
        if _name_matches_fragment(p1_frag, p1n): score += 2
        if _name_matches_fragment(p2_frag, p2n): score += 2
        if _name_matches_fragment(p1_frag, p2n): score += 1
        if _name_matches_fragment(p2_frag, p1n): score += 1
        if score > best_score:
            best_score = score
            best_match = match
    if not best_match or best_score < 3:
        log.debug(f"[Tennis] No match for {ticker} (frags={p1_frag}/{p2_frag} score={best_score})")
        return None

    tctx = _build_context(best_match, ticker)
    if tctx:
        log.info(
            f"[Tennis] {ticker} -> {tctx.summary()} "
            f"| live={tctx.is_live} pct={tctx.pct_complete:.0%} "
            f"sets_down={tctx.sets_down} conf={tctx.underdog_conf}"
        )
    return tctx
