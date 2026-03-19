#!/usr/bin/env python3
"""
strategy_prop_edge.py

Entry: NBA prop markets where season hit rate diverges 7c+ from Kalshi price.
Edge: Kalshi prop markets lag sharp book implied probability pre-game.

Entry conditions:
    - NBA prop (PTS, 3PT, REB, AST)
    - Volume >= 8000, spread <= 4c
    - edge_finder returns edge >= 7c AND kelly > 0
    - Hit rate 52-85% (no coinflips, no locks)
    - Pre-game or Q1/Q2 only

Exit: fixed TP+12c SL-6c TIME=90min via exit_manager.py
Math: break-even 44.4%, EV at 52% = +1.36c per trade
"""

import logging
from typing import Optional

log = logging.getLogger("kalshi_bot.prop_edge")

MIN_VOLUME  = 8000
MAX_SPREAD  = 4
PROP_SERIES = ["KXNBAPTS", "KXNBA3PT", "KXNBAREB", "KXNBAAST"]


def strategy_prop_edge(item: dict, espn_cache=None) -> Optional[object]:
    from kalshi_bot import TradeSignal, Config
    from nba_context import parse_prop_ticker, find_game_for_ticker
    from edge_finder import evaluate_market

    m     = item["market"]
    sport = item.get("sport", "")

    if sport != "NBA":
        return None
    if not any(m.ticker.startswith(s) for s in PROP_SERIES):
        return None
    if m.volume < MIN_VOLUME:
        return None
    if m.spread > MAX_SPREAD:
        return None
    if m.yes_bid <= 0 or m.yes_ask <= 0:
        return None

    # Game timing gate
    status = item.get("market_status", "open")
    if status == "active" and espn_cache:
        ctx = find_game_for_ticker(m.ticker, espn_cache)
        if ctx and ctx.is_live and ctx.nba_quarter > 2:
            return None

    # Parse ticker
    parsed  = parse_prop_ticker(m.ticker)
    player  = parsed.get("player", "")
    initial = parsed.get("player_initial", "")
    stat    = parsed.get("stat", "PTS")
    thresh  = parsed.get("threshold")
    team    = parsed.get("prop_team", "")

    if not player or thresh is None:
        return None

    # Get edge signal
    signal = evaluate_market(
        ticker         = m.ticker,
        yes_bid        = m.yes_bid,
        yes_ask        = m.yes_ask,
        player_frag    = player,
        player_initial = initial,
        stat           = stat,
        threshold      = thresh,
        prop_team      = team,
        max_usd        = Config.MAX_POSITION_USD,
    )

    if signal is None or not signal.is_tradeable:
        return None

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "yes",
        action        = "buy",
        price         = int(m.yes_ask * 100),
        contracts     = signal.contracts,
        strategy      = "prop_edge",
        reason        = signal.reason,
        confidence    = round(signal.hit_rate, 3),
    )
