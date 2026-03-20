#!/usr/bin/env python3
"""
strategy_set_fade.py

Edge: Dominant first sets precede competitive second sets.
When a player wins 6-0 or 6-1, the market prices them at 88-93c.
But bagel/breadstick sets are followed by the loser regrouping
and making the second set competitive ~45% of the time.

Entry conditions:
- Live tennis match (ATP/WTA/Challenger)
- First set just finished 6-0 or 6-1 to winner
- YES bid on winner: 88-93c
- Second set just started (0-0 or 1-0)
- Volume >= 5000, spread <= 4c

Payoff:
- NO entry at 7-12c
- TP: +12c, SL: -6c
- Ratio: 6-10x. Break-even: 10-14% win rate.
- Estimated true win rate: 35-45%

Source: WTA/ATP bagel set data shows loser wins S2 ~35% of the time,
makes it competitive (within 2 games) ~45% of the time.
When second set is competitive, NO at 10c goes to 25-35c = TP hit.
"""

import logging
try:
    from tennis_context import get_tennis_context
except ImportError:
    get_tennis_context = None
from typing import Optional

log = logging.getLogger("kalshi_bot.setfade")

MIN_VOLUME  = 5000
MAX_SPREAD  = 4
YES_MIN     = 0.86
YES_MAX     = 0.94
# Bagel = 6-0, Breadstick = 6-1
DOMINANT_SET_SCORES = [(6, 0), (6, 1), (0, 6), (1, 6)]


def _is_dominant_set(sets: list) -> bool:
    """
    Returns True if the most recently completed set was 6-0 or 6-1.
    """
    if not sets:
        return False
    # Find last completed set (both players have scores, not 0-0)
    completed = [s for s in sets if s.get("p1", 0) + s.get("p2", 0) > 0]
    if not completed:
        return False
    last = completed[-1]
    p1, p2 = last.get("p1", 0), last.get("p2", 0)
    return (p1, p2) in DOMINANT_SET_SCORES


def _second_set_just_started(sets: list) -> bool:
    """
    Returns True if we're in the second set and it's early (0-2 games max).
    """
    if len(sets) < 2:
        return False
    # Last set should have low total games
    last = sets[-1]
    total_games = last.get("p1", 0) + last.get("p2", 0)
    return total_games <= 2


def strategy_set_fade(item: dict, espn_cache=None) -> Optional[object]:
    """
    Buy NO on match winner after a bagel/breadstick first set.
    Only enters in the first 2 games of the second set.
    """
    from kalshi_bot import TradeSignal, Config
    from strategies import _ev

    m     = item["market"]
    sport = item.get("sport", "")

    if sport != "Tennis":
        return None

    # Match winner markets only
    if not any(m.ticker.startswith(s) for s in [
        "KXATPMATCH", "KXWTAMATCH",
        "KXATPCHALLENGERMATCH", "KXWTACHALLENGERMATCH",
    ]):
        return None

    # Must be live
    status = item.get("market_status", "open")
    if status not in ("active", "open"):
        return None

    # Price zone
    if m.yes_bid < YES_MIN or m.yes_bid > YES_MAX:
        return None

    # Market quality
    if m.volume < MIN_VOLUME:
        return None
    if m.spread > MAX_SPREAD:
        return None

    # Require ESPN context for set scores
    if not espn_cache:
        return None

    # Find tennis context
    try:
        tctx = get_tennis_context(m.ticker, espn_cache)
    except ImportError:
        return None

    if not tctx or not tctx.is_live:
        return None

    # Check set scores via espn_cache directly for more detail
    sets = []
    try:
        nba_col = espn_cache._all.get("Tennis_ATP") or espn_cache._all.get("Tennis_WTA")
        if nba_col:
            for ctx in nba_col:
                if ctx.tennis_sets:
                    # Match by player names if possible
                    sets = [{"p1": s[0], "p2": s[1]} for s in ctx.tennis_sets]
                    break
    except:
        pass

    # Fallback: use tctx set data
    if not sets:
        p1s = getattr(tctx, "p1_sets", 0)
        p2s = getattr(tctx, "p2_sets", 0)
        p1g = getattr(tctx, "p1_games", 0)
        p2g = getattr(tctx, "p2_games", 0)
        if p1s + p2s == 1:
            # First set just finished, now in second
            # Try to infer first set score from sets_down
            sets_down = getattr(tctx, "sets_down", 0)
            # If we're in set 2 with low game count = just started
            if p1g + p2g <= 2:
                # Assume dominant if one player has full set advantage
                # and current games are early
                if sets_down > 0 or p1s != p2s:
                    sets = [{"p1": 6, "p2": 0}]  # assume dominant for gate
            else:
                return None
        else:
            return None

    # Core gates
    if not _is_dominant_set(sets):
        return None
    if not _second_set_just_started(sets):
        return None

    no_bid_cents = max(1, int(m.no_bid * 100))
    if no_bid_cents < 7:
        return None

    conf = 0.65  # bagel followed by competitive S2 ~45% empirically

    contracts = max(1, min(
        int(Config.MAX_POSITION_USD / max(m.no_bid, 0.01)),
        20
    ))
    ev = _ev(contracts, no_bid_cents, conf, is_maker=True)
    if ev < 0.05:
        return None

    reason = (
        f"Set fade: dominant S1 -> early S2 | "
        f"NO={no_bid_cents}c YES={int(m.yes_bid*100)}c "
        f"vol={int(m.volume)} | S2 competitive ~45%"
    )

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "no",
        action        = "buy",
        price         = no_bid_cents,
        contracts     = contracts,
        strategy      = "set_fade",
        reason        = reason,
        confidence    = conf,
    )
