#!/usr/bin/env python3
"""
strategy_momentum_reversal.py

Edge: NBA scoring runs end.
When a team goes on an 8+ point run, the market overreacts and
prices the leading team at 90c+. But scoring runs end with ~75%
probability within the next 4 minutes of game time.

Entry conditions:
- Live NBA game, Q1 or Q2 only
- YES bid 88-93c (run-inflated price)
- ESPN confirms: current lead is 10-18pts (run just happened)
- Market volume >= 10000 (liquid enough to exit)
- Spread <= 3c

Payoff:
- NO entry at 7-12c
- TP: +12c (NO goes to 19-24c when run ends)
- SL: -6c
- Ratio: 7-12x. Break-even: 8-12% win rate.
- Estimated true win rate: 30-35% (run continuation ~25%)

Source: NBA scoring run regression is well documented.
Teams on 8-0 runs allow response runs within 4min ~75% of games.
"""

import logging
from typing import Optional

log = logging.getLogger("kalshi_bot.momentum")

MIN_VOLUME    = 10000
MAX_SPREAD    = 3
YES_MIN       = 0.88
YES_MAX       = 0.93
MIN_LEAD      = 10     # pts — confirms a run just happened
MAX_LEAD      = 18     # pts — beyond this it may be a real blowout
MAX_QUARTER   = 2      # Q1/Q2 only — enough game left to regress


def strategy_momentum_reversal(item: dict, espn_cache=None) -> Optional[object]:
    """
    Buy NO when a scoring run has inflated the favorite's price.
    Requires ESPN live context to confirm the run and game state.
    """
    from kalshi_bot import TradeSignal, Config
    from nba_context import find_game_for_ticker

    m     = item["market"]
    sport = item.get("sport", "")

    # NBA moneyline and spread only
    if sport != "NBA":
        return None
    if not any(m.ticker.startswith(s) for s in ["KXNBAGAME", "KXNBASPREAD"]):
        return None

    # Market quality
    if m.volume < MIN_VOLUME:
        return None
    if m.spread > MAX_SPREAD:
        return None
    if m.yes_bid < YES_MIN or m.yes_bid > YES_MAX:
        return None

    # Must be live — pre-game 88-93c favorites have different dynamics
    status = item.get("market_status", "open")
    if status != "active":
        return None

    # Require ESPN context — never enter blind on live game
    if not espn_cache:
        return None

    ctx = find_game_for_ticker(m.ticker, espn_cache)
    if not ctx or not ctx.is_live:
        return None

    # Quarter gate — Q1/Q2 only
    if ctx.nba_quarter > MAX_QUARTER:
        return None

    # Lead gate — confirms run just happened, not a real blowout
    lead = abs(ctx.lead)
    if lead < MIN_LEAD or lead > MAX_LEAD:
        return None

    # Clock gate — need at least 4 min left in quarter for regression
    try:
        if ctx.clock_secs < 240:   # less than 4 min left in quarter
            return None
    except:
        pass

    no_bid_cents = max(1, int(m.no_bid * 100))
    if no_bid_cents < 7:
        return None

    # Confidence based on lead size
    # 10pt lead: market might be right, lower conf
    # 14pt lead: classic run overshoot, higher conf
    # 18pt lead: might be real, lower conf again
    if lead <= 12:
        conf = 0.62
    elif lead <= 16:
        conf = 0.68   # sweet spot
    else:
        conf = 0.60

    # EV check with real payoff math
    # Win: NO goes from ~10c to ~22c = +12c
    # Lose: NO goes from ~10c to ~4c = -6c
    from strategies import _ev
    contracts = max(1, min(
        int(Config.MAX_POSITION_USD / max(m.no_bid, 0.01)),
        20
    ))
    ev = _ev(contracts, no_bid_cents, conf, is_maker=True)
    if ev < 0.05:
        return None

    leading_team = "home" if ctx.lead > 0 else "away"
    reason = (
        f"Run reversal: {leading_team} +{lead}pts Q{ctx.nba_quarter} "
        f"clock={ctx.clock} | NO={no_bid_cents}c YES={int(m.yes_bid*100)}c "
        f"vol={int(m.volume)} | run regression ~75%"
    )

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = "no",
        action        = "buy",
        price         = no_bid_cents,
        contracts     = contracts,
        strategy      = "momentum_reversal",
        reason        = reason,
        confidence    = conf,
    )
