#!/usr/bin/env python3
"""
edge_finder.py

Probability engine for Kalshi NBA prop markets.

Data source: api.server.nbaapi.com (free, no auth, confirmed working)
- Season totals: points, 3PM, rebounds, assists, games played
- Derives per-game average
- Uses normal CDF to estimate hit rate
- Compares against Kalshi price to find edge

Hit rate model:
- Normal distribution with empirically calibrated std dev per stat
- PTS=0.28  3PT=0.55  REB=0.25  AST=0.30
- Only trades when edge >= 7c AND kelly > 0
- Hit rate must be 52-85% (no coinflips, no locks)
"""

import math
import time
import logging
import requests
from typing import Optional
from dataclasses import dataclass

log = logging.getLogger("kalshi_bot.edge")

BASE_URL    = "https://api.server.nbaapi.com/api"
TIMEOUT     = 10
PLAYER_TTL  = 3600   # 1 hour

_all_players:    dict  = {}
_all_players_ts: float = 0.0

STD_DEV_FACTOR = {
    "PTS": 0.28,
    "3PT": 0.55,
    "REB": 0.25,
    "AST": 0.30,
}

MIN_GAMES = 15


@dataclass
class EdgeSignal:
    market_ticker: str
    player_name:   str
    stat:          str
    threshold:     int
    season_avg:    float
    hit_rate:      float
    kalshi_price:  float
    edge:          float
    kelly:         float
    contracts:     int
    side:          str
    reason:        str

    @property
    def is_tradeable(self) -> bool:
        return (
            self.edge       >= 0.07  and
            self.kelly      >  0.0   and
            self.hit_rate   >= 0.52  and
            self.hit_rate   <= 0.85  and
            self.season_avg >  0.0
        )


def _norm_cdf(x: float) -> float:
    t = 1.0 / (1.0 + 0.2316419 * abs(x))
    d = 0.3989423 * math.exp(-x * x / 2.0)
    p = d * t * (0.3193815 + t * (-0.3565638
        + t * (1.7814779 + t * (-1.8212560
        + t * 1.3302744))))
    return 1.0 - p if x >= 0 else p


def hit_rate_from_avg(avg: float, threshold: float,
                      stat: str = "PTS") -> float:
    if avg <= 0:
        return 0.0
    std = avg * STD_DEV_FACTOR.get(stat, 0.28)
    if std == 0:
        return 1.0 if avg > threshold else 0.0
    z = (threshold + 0.5 - avg) / std
    return 1.0 - _norm_cdf(z)


def kelly_fraction(true_prob: float, kalshi_price: float,
                   fee_pct: float = 0.04) -> float:
    if kalshi_price <= 0.01 or kalshi_price >= 0.99:
        return 0.0
    b     = (1.0 - kalshi_price) / kalshi_price
    p     = true_prob
    q     = 1.0 - p
    kelly = (b * p - q) / b
    return round((kelly - fee_pct) / 2.0, 4)


def _load_all_players() -> dict:
    global _all_players, _all_players_ts
    now = time.time()
    if _all_players and now - _all_players_ts < PLAYER_TTL:
        return _all_players
    try:
        r = requests.get(
            f"{BASE_URL}/playertotals",
            params={"season": 2025, "sortBy": "points", "pageSize": 500},
            timeout=TIMEOUT,
        )
        r.raise_for_status()
        players = r.json().get("data", [])
        out = {}
        for p in players:
            name = p.get("playerName", "")
            if name:
                out[name.upper()] = p
        _all_players    = out
        _all_players_ts = now
        log.info(f"[Edge] Loaded {len(out)} players")
        return out
    except Exception as e:
        log.warning(f"[Edge] Player load failed: {e}")
        return _all_players


def _find_player(player_frag: str, prop_team: str,
                 player_initial: str = "") -> Optional[dict]:
    all_players = _load_all_players()
    if not all_players or not player_frag:
        return None

    frag_clean = player_frag.upper().replace("-", "")
    candidates = []

    for name_upper, stats in all_players.items():
        name_clean = name_upper.replace("-", "").replace("'", "")
        parts      = name_clean.split()
        if not parts:
            continue
        last  = parts[-1]
        first = parts[0] if len(parts) > 1 else ""
        if not last.startswith(frag_clean):
            continue
        if player_initial and first and not first.startswith(player_initial.upper()):
            continue
        candidates.append((name_upper, stats))

    if not candidates:
        for name_upper, stats in all_players.items():
            if frag_clean in name_upper.replace("-","").replace("'",""):
                candidates.append((name_upper, stats))

    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0][1]

    team_map = {
        "ATL":"ATL","BOS":"BOS","BKN":"BKN","CHA":"CHA","CHI":"CHI",
        "CLE":"CLE","DAL":"DAL","DEN":"DEN","DET":"DET","GSW":"GSW",
        "HOU":"HOU","IND":"IND","LAC":"LAC","LAL":"LAL","MEM":"MEM",
        "MIA":"MIA","MIL":"MIL","MIN":"MIN","NOP":"NOP","NYK":"NYK",
        "OKC":"OKC","ORL":"ORL","PHI":"PHI","PHX":"PHX","POR":"POR",
        "SAC":"SAC","SAS":"SAS","TOR":"TOR","UTA":"UTA","WAS":"WAS",
    }
    team_abbrev = team_map.get(prop_team.upper(), "")
    if team_abbrev:
        team_matches = [(n,s) for n,s in candidates
                        if s.get("team","").upper() == team_abbrev]
        if len(team_matches) == 1:
            return team_matches[0][1]
        if team_matches:
            candidates = team_matches

    candidates.sort(key=lambda x: x[1].get("games", 0), reverse=True)
    return candidates[0][1]


def _get_per_game(stats: dict, stat: str) -> tuple:
    gp = int(stats.get("games", 0) or 0)
    if gp < MIN_GAMES:
        return 0.0, gp
    col_map = {
        "PTS": "points",
        "3PT": "threeFg",
        "REB": "totalRb",
        "AST": "assists",
    }
    col   = col_map.get(stat, "points")
    total = float(stats.get(col, 0) or 0)
    return round(total / gp, 2), gp


def evaluate_market(ticker: str, yes_bid: float, yes_ask: float,
                    player_frag: str, player_initial: str,
                    stat: str, threshold: int,
                    prop_team: str,
                    max_usd: float = 5.0) -> Optional[EdgeSignal]:
    player = _find_player(player_frag, prop_team, player_initial)
    if player is None:
        log.debug(f"[Edge] No player match: {player_frag} ({prop_team})")
        return None

    player_name  = player.get("playerName", player_frag)
    avg, gp      = _get_per_game(player, stat)

    if avg == 0 or gp < MIN_GAMES:
        log.debug(f"[Edge] {player_name} insufficient: avg={avg} gp={gp}")
        return None

    hit_rate     = hit_rate_from_avg(avg, threshold, stat)
    kalshi_price = yes_ask
    edge         = hit_rate - kalshi_price
    kelly        = kelly_fraction(hit_rate, kalshi_price)

    stake_usd  = max(0.0, kelly) * max_usd
    contracts  = max(1, min(20, int(stake_usd / max(kalshi_price, 0.01))))

    signal = EdgeSignal(
        market_ticker = ticker,
        player_name   = player_name,
        stat          = stat,
        threshold     = threshold,
        season_avg    = avg,
        hit_rate      = round(hit_rate, 4),
        kalshi_price  = round(kalshi_price, 4),
        edge          = round(edge, 4),
        kelly         = kelly,
        contracts     = contracts,
        side          = "yes",
        reason        = (
            f"{player_name} {stat}>{threshold} | "
            f"avg={avg:.1f} gp={gp} "
            f"hit={hit_rate:.1%} kalshi={kalshi_price:.0%} "
            f"edge={edge:+.3f} kelly={kelly:.3f}"
        ),
    )

    if signal.is_tradeable:
        log.info(f"[Edge] TRADEABLE: {signal.reason}")
    else:
        log.debug(f"[Edge] No trade: {player_name} {stat}>{threshold} "
                  f"hit={hit_rate:.1%} edge={edge:+.3f}")

    return signal


# Backward compatibility alias
evaluate_kalshi_market = evaluate_market
