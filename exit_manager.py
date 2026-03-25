#!/usr/bin/env python3
"""
exit_manager.py

Replaces the ad-hoc stop logic scattered across price_watcher.py
and strategy_exit() with one unified exit manager.

Rules (same for every position, no exceptions):
    Take profit : current_bid >= entry + TAKE_PROFIT_CENTS
    Stop loss   : current_bid <= entry - STOP_LOSS_CENTS
    Time stop   : age > MAX_HOLD_MINUTES * 60

These are fixed-cent rules, not percentages.
Percentages break at different price levels (30% of 5c = 1.5c, meaningless).
Fixed cents give consistent reward/risk regardless of entry price.

Reward/risk = 8/6 = 1.33x
Break-even win rate = 6/14 = 42.9%
"""

import math
import logging
from datetime import datetime, timezone
from typing import Optional, Tuple

log = logging.getLogger("kalshi_bot.exits")

TAKE_PROFIT_CENTS = 12
STOP_LOSS_CENTS   = 6
MAX_HOLD_SECONDS  = 90 * 60   # 90 minutes


def should_exit(pos: dict, current_bid: int) -> Tuple[bool, str]:
    """
    Single function that decides whether to exit a position.

    pos:         position dict from open_positions
    current_bid: current market bid in cents (integer)

    Returns (should_exit: bool, reason: str)
    """
    entry     = int(pos.get("entry_price", 0))
    side      = pos.get("side", "yes")
    entry_time = pos.get("entry_time", "")

    if entry == 0:
        return False, ""

    # ── P&L calculation ────────────────────────────────────────────
    contracts  = int(pos.get("contracts", 1))
    entry_fee  = float(pos.get("entry_fee", 0.0))
    fee_mult   = 0.07    # taker on SL exits (conservative, confirmed empirically)
    exit_fee   = math.ceil(fee_mult * contracts * (current_bid/100) *
                           (1 - current_bid/100) * 100) / 100
    pnl        = (current_bid - entry) * contracts / 100.0 - entry_fee - exit_fee

    move       = current_bid - entry   # positive = moving in our favor

    # ── Take profit ────────────────────────────────────────────────
    if move >= TAKE_PROFIT_CENTS:
        return True, f"TP: +{move}c >= +{TAKE_PROFIT_CENTS}c | PNL=${pnl:.4f}"

    # ── Trailing stop — never give back profit ─────────────────────────
    peak_price = int(pos.get("peak_price", entry))
    peak_move  = peak_price - entry
    if peak_move >= 8:
        trail_stop = peak_price - 3
        if current_bid <= trail_stop:
            return True, f"TRAIL: {current_bid}c <= {trail_stop}c (peak={peak_price}c) | PNL=${pnl:.4f}"
    elif peak_move >= 5:
        trail_stop = peak_price - 4
        if current_bid <= trail_stop:
            return True, f"TRAIL: {current_bid}c <= {trail_stop}c (peak={peak_price}c) | PNL=${pnl:.4f}"

    # ── Stop loss ──────────────────────────────────────────────────
    if move <= -STOP_LOSS_CENTS:
        return True, f"SL: {move}c <= -{STOP_LOSS_CENTS}c | PNL=${pnl:.4f}"

    # ── Time stop ──────────────────────────────────────────────────
    if entry_time:
        try:
            et = datetime.fromisoformat(entry_time)
            if et.tzinfo is None:
                et = et.replace(tzinfo=timezone.utc)
            age = (datetime.now(timezone.utc) - et).total_seconds()
            if age > MAX_HOLD_SECONDS:
                return True, (f"TIME: {int(age/60)}min > {MAX_HOLD_SECONDS//60}min "
                              f"| PNL=${pnl:.4f}")
        except:
            pass

    return False, ""


def get_exit_price(pos: dict, current_bid: int) -> int:
    """
    Returns the price to place the exit order at.
    Uses current bid — no artificial discounts.
    """
    return max(1, current_bid)
