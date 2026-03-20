#!/usr/bin/env python3
"""
strategy_closing_line.py

Edge: Late line movement = sharp money. Fade the public side.
When a Kalshi market moves 5c+ in the 30 minutes before game start,
the movement direction indicates where sharp bettors are going.
The public side (the side that lost ground) is now mispriced.

Entry conditions:
- Pre-game market (status=open)
- Price moved >= 5c in last 30 min (tracked by price_watcher)
- Current price 35-65c (movement zone — not a lock being crushed)
- Volume >= 15000 (enough action to create meaningful movement)
- Spread <= 3c

Payoff:
- Buy the side that LOST ground (public was wrong)
- Entry at 35-65c gives roughly 1:1 payoff
- TP: +12c, SL: -6c = 1.25x net after fees
- Need 44% win rate. Sharp money historically right ~55% of the time.

Source: Closing line value is the most documented edge in sports betting.
Sharp books move lines when they take action from known sharp bettors.
Kalshi is less efficient than Pinnacle but same principle applies.
"""

import time
import logging
from typing import Optional

log = logging.getLogger("kalshi_bot.clv")

# Price history: ticker -> list of (timestamp, price) tuples
_price_history: dict = {}
HISTORY_WINDOW = 1800   # 30 minutes
MIN_MOVEMENT   = 5      # cents
MIN_VOLUME     = 15000
MAX_SPREAD     = 3
PRICE_MIN      = 0.35
PRICE_MAX      = 0.65


def record_price(ticker: str, yes_bid: float):
    """Call this every cycle to build price history."""
    now = time.time()
    if ticker not in _price_history:
        _price_history[ticker] = []

    _price_history[ticker].append((now, yes_bid))

    # Prune old entries
    cutoff = now - HISTORY_WINDOW
    _price_history[ticker] = [
        (t, p) for t, p in _price_history[ticker]
        if t >= cutoff
    ]


def get_price_movement(ticker: str) -> Optional[float]:
    """
    Returns price movement in cents over the last 30 minutes.
    Positive = YES bid went up. Negative = YES bid went down.
    None if insufficient history.
    """
    history = _price_history.get(ticker, [])
    if len(history) < 3:   # need at least 3 data points
        return None

    now   = time.time()
    old   = [p for t, p in history if t < now - 900]   # >15 min ago
    recent = [p for t, p in history if t >= now - 900] # last 15 min

    if not old or not recent:
        return None

    old_price    = sum(old) / len(old)
    recent_price = sum(recent) / len(recent)
    movement     = (recent_price - old_price) * 100  # convert to cents

    return round(movement, 1)


def strategy_closing_line(item: dict, espn_cache=None) -> Optional[object]:
    """
    Fade the public side when sharp money has moved the line.
    """
    from models import TradeSignal, Config
    from strategies import _ev

    m     = item["market"]
    sport = item.get("sport", "")

    # NBA and MLB game markets only (most liquid, most sharp action)
    if sport not in ("NBA", "MLB"):
        return None
    if not any(m.ticker.startswith(s) for s in [
        "KXNBAGAME", "KXMLBGAME"
    ]):
        return None

    # Pre-game only — closing line is a pre-game concept
    status = item.get("market_status", "open")
    if status != "open":
        return None

    # Market quality
    if m.volume < MIN_VOLUME:
        return None
    if m.spread > MAX_SPREAD:
        return None

    # Record current price (builds history over time)
    record_price(m.ticker, m.yes_bid)

    # Check for meaningful movement
    movement = get_price_movement(m.ticker)
    if movement is None or abs(movement) < MIN_MOVEMENT:
        return None

    # Determine which side to bet
    # If YES moved UP 5c+: sharp money bought YES, public may now be on NO
    # If YES moved DOWN 5c+: sharp money sold YES / bought NO
    # We follow sharp money: bet the side that GAINED
    if movement > 0:
        # YES moved up — sharp money is on YES
        # Buy YES if it's in our price range
        if m.yes_bid < PRICE_MIN or m.yes_bid > PRICE_MAX:
            return None
        side        = "yes"
        price_cents = int(m.yes_ask * 100)
        entry_price = m.yes_ask
        reason_side = f"YES moved +{movement:.1f}c (sharp buying)"
    else:
        # YES moved down — sharp money is on NO
        no_bid = 1.0 - m.yes_bid
        if no_bid < PRICE_MIN or no_bid > PRICE_MAX:
            return None
        side        = "no"
        price_cents = max(1, int(m.no_bid * 100))
        entry_price = m.no_bid
        reason_side = f"YES moved {movement:.1f}c (sharp selling)"

    if price_cents < 35 or price_cents > 65:
        return None

    # Confidence scales with movement size and volume
    # Larger movement = stronger signal
    move_abs = abs(movement)
    if move_abs >= 10:
        conf = 0.63
    elif move_abs >= 7:
        conf = 0.61
    else:
        conf = 0.58
    # Volume boost — more action = more reliable signal
    if m.volume >= 30000:
        conf += 0.02
    elif m.volume >= 20000:
        conf += 0.01
    conf = round(min(conf, 0.72), 3)

    # Hard cap at 3 contracts until win rate is validated from trade history
    contracts = max(1, min(
        int(Config.MAX_POSITION_USD / max(entry_price, 0.01)),
        3
    ))
    # EV differs by side
    if side == "no":
        ev = _ev(contracts, price_cents, conf, is_maker=True)
    else:
        # YES: win=(100-price)/100 per contract, lose=price/100 per contract
        payout_c = 100 - price_cents
        stake_c  = price_cents
        fee      = 0.0175 * contracts * (stake_c/100) * (payout_c/100) * 100
        ev       = round(conf*(payout_c/100)*contracts
                         - (1-conf)*(stake_c/100)*contracts - fee*2, 4)
    if ev < 2.0:
        return None

    reason = (
        f"CLV: {reason_side} | "
        f"price={price_cents}c vol={int(m.volume)} "
        f"spread={m.spread}c | follow sharp"
    )

    return TradeSignal(
        event_ticker  = item["event_ticker"],
        market_ticker = m.ticker,
        side          = side,
        action        = "buy",
        price         = price_cents,
        contracts     = contracts,
        strategy      = "closing_line",
        reason        = reason,
        confidence    = conf,
    )
