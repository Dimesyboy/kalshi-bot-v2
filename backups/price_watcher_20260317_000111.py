#!/usr/bin/env python3
"""
price_watcher.py
─────────────────────────────────────────────────────────────────────────────
Lightweight price monitor that runs in a background thread.
Polls open positions every 5 seconds and fires exits immediately
when price crosses take profit, trail stop, or floor thresholds.
Completely independent of the main 30-second bot cycle.
─────────────────────────────────────────────────────────────────────────────
"""

import threading
import time
import math
import logging
import requests

log = logging.getLogger("kalshi_bot.watcher")


class PriceWatcher:
    """
    Background thread that monitors open positions every POLL_INTERVAL seconds.
    Fires exit orders directly via Kalshi API when thresholds are crossed.
    Does NOT place new entries — exits only.
    """

    POLL_INTERVAL = 5      # seconds between price checks
    KALSHI_BASE   = "https://api.elections.kalshi.com/trade-api/v2"

    def __init__(self, open_positions: dict, client, config,
                 save_positions_fn, save_pnl_fn, pnl_log: dict,
                 get_date_fn, bot_orders: set):
        self._positions     = open_positions   # shared reference — bot updates this
        self._client        = client
        self._config        = config
        self._save_pos      = save_positions_fn
        self._save_pnl      = save_pnl_fn
        self._pnl_log       = pnl_log
        self._get_date      = get_date_fn
        self._bot_orders    = bot_orders
        self._stop_event    = threading.Event()
        self._lock          = threading.Lock()
        self._thread        = threading.Thread(
            target=self._run, daemon=True, name="PriceWatcher"
        )
        self._exiting       = set()   # tickers currently being exited (debounce)

    def start(self):
        log.info("[Watcher] Starting price watcher thread (5s poll)")
        self._thread.start()

    def stop(self):
        log.info("[Watcher] Stopping...")
        self._stop_event.set()

    def _run(self):
        while not self._stop_event.is_set():
            try:
                self._check_positions()
            except Exception as e:
                log.warning(f"[Watcher] Cycle error: {e}")
            self._stop_event.wait(self.POLL_INTERVAL)

    def _get_price(self, ticker: str, side: str) -> int:
        """Fetch current bid price in cents for the given side."""
        try:
            r = requests.get(
                f"{self.KALSHI_BASE}/markets/{ticker}",
                timeout=4,
            )
            r.raise_for_status()
            m = r.json().get("market", {})
            if side == "no":
                bid = float(m.get("no_bid_dollars", 0) or 0)
            else:
                bid = float(m.get("yes_bid_dollars", 0) or 0)
            return max(1, int(bid * 100))
        except Exception as e:
            log.debug(f"[Watcher] Price fetch failed {ticker}: {e}")
            return 0

    def _place_exit(self, ticker: str, pos: dict, bid: int, reason: str):
        """Place a sell order directly via PortfolioApi."""
        if ticker in self._exiting:
            return
        self._exiting.add(ticker)
        try:
            import uuid
            import kalshi_python
            from kalshi_python.models import CreateOrderRequest

            side      = pos["side"]
            contracts = pos["contracts"]
            entry     = pos["entry_price"]

            portfolio_api = kalshi_python.PortfolioApi(api_client=self._client)
            order_id_str  = str(uuid.uuid4())

            # Selling NO requires yes_price = 100 - no_bid
            # Selling YES uses yes_price directly
            if side == "no":
                yes_p = max(1, 100 - bid)
                no_p  = None
            else:
                yes_p = max(1, bid)
                no_p  = None

            order = portfolio_api.create_order(
                ticker          = ticker,
                action          = "sell",
                side            = side,
                type            = "limit",
                yes_price       = yes_p,
                no_price        = no_p,
                count           = int(contracts),
                client_order_id = order_id_str,
            )
            order_id = order.order.order_id

            # Calculate PNL
            fee_mult  = 0.0175
            entry_fee = pos.get("entry_fee", 0.0)
            exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
            pnl_cents = (bid - entry) * contracts
            pnl       = pnl_cents / 100.0 - entry_fee - exit_fee

            current_date = self._get_date()
            self._pnl_log[current_date] = self._pnl_log.get(current_date, 0.0) + pnl

            log.info(
                f"[Watcher] EXIT {ticker} {side.upper()} @ {bid}c x{contracts} "
                f"| {reason} | PNL ${pnl:.4f} | order={order_id}"
            )

            # Log to trade tracker
            try:
                from trade_tracker import log_trade
                log_trade(
                    market_ticker = ticker,
                    event_ticker  = pos.get("event_ticker", ""),
                    sport         = "",
                    side          = side,
                    strategy      = f"watcher_{pos.get('strategy','')}",
                    entry_price   = entry,
                    exit_price    = bid,
                    peak_price    = pos.get("peak_price", entry),
                    contracts     = contracts,
                    entry_fee     = entry_fee,
                    exit_fee      = exit_fee,
                    exit_reason   = reason,
                    entry_time    = pos.get("entry_time", ""),
                    is_bot        = pos.get("is_bot", True),
                )
            except Exception as te:
                log.debug(f"[Watcher] trade_tracker error: {te}")

            # Remove from positions
            with self._lock:
                if ticker in self._positions:
                    del self._positions[ticker]
                    self._save_pos(self._positions)
                    self._save_pnl(self._pnl_log)

        except Exception as e:
            log.error(f"[Watcher] Exit order failed {ticker}: {e}")
        finally:
            self._exiting.discard(ticker)

    def _check_positions(self):
        # Snapshot current positions to avoid mutation during iteration
        with self._lock:
            snapshot = dict(self._positions)

        for ticker, pos in snapshot.items():
            if ticker in self._exiting:
                continue
            entry = pos.get("entry_price", 0)
            if entry == 0:
                continue

            side = pos["side"]
            bid  = self._get_price(ticker, side)
            if bid == 0:
                continue

            # Update peak price
            peak = max(bid, pos.get("peak_price", entry))
            pos["peak_price"] = peak

            contracts = pos["contracts"]
            fee_mult  = 0.0175
            entry_fee = pos.get("entry_fee", 0.0)
            exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
            pnl       = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee

            # --- Exit conditions ---

            # 1. Take profit tiers
            if pnl >= 2.00:
                # Big winner — tighten trail aggressively
                stop = int(peak * 0.88)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid, f"Trail exit: ${pnl:.2f} profit, peak={peak}c")
                    continue
                # Also take full profit at 3x entry
                if bid >= entry * 2.5:
                    self._place_exit(ticker, pos, bid, f"3x exit: {bid}c vs entry {entry}c profit=${pnl:.2f}")
                    continue

            elif pnl >= 0.50:
                # Minimum profit hit — trail at 20% below peak
                stop = int(peak * 0.82)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid, f"Trail exit: ${pnl:.2f} profit, peak={peak}c stop={stop}c")
                    continue

            # 2. Stop loss — 30% below entry
            if bid <= int(entry * 0.70):
                self._place_exit(ticker, pos, bid, f"Stop loss: {bid}c <= {int(entry*0.70)}c (entry={entry}c)")
                continue

            # 3. Floor exit — below 5c on entry > 15c
            if bid <= 5 and entry > 15:
                self._place_exit(ticker, pos, bid, f"Floor exit: {bid}c")
                continue

            # 4. Rocket exit — price jumped 25c+ in one check (fast move)
            last_bid = pos.get("last_bid", entry)
            jump     = bid - last_bid
            if jump >= 25 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid, f"Rocket exit: jumped +{jump}c this cycle, profit=${pnl:.2f}")
                continue

            # 5. Longshot hit — entered below 15c and now above 30c
            if entry <= 15 and bid >= 30 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid, f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
                continue

            pos["last_bid"] = bid

    def notify_new_position(self, ticker: str):
        """Called by main bot when a new position is recorded."""
        log.debug(f"[Watcher] Tracking new position: {ticker}")
