#!/usr/bin/env python3
"""
price_watcher.py
Lightweight price monitor running in a background thread.
Polls open positions every 2 seconds and fires exits when thresholds are crossed.

Tennis-aware exit logic:
  - Trail stop tightens as match progresses (pct_complete)
  - Profit target lowers as underdog gets closer to winning
  - Final set tiebreak = aggressive exit to lock profit
  - Match over = immediate exit if position still open
  - Stop loss widens slightly in early match, tightens in final set
"""

import threading
import time
import math
import logging
import requests

log = logging.getLogger("kalshi_bot.watcher")


def _is_tennis_ticker(ticker: str) -> bool:
    return any(ticker.startswith(x) for x in [
        "KXATPMATCH", "KXWTAMATCH", "KXATPGAME", "KXWTAGAME",
        "KXATPCHALLENGERMATCH", "KXWTACHALLENGERMATCH",
    ])


def _is_nba_ticker(ticker: str) -> bool:
    return ticker.startswith("KXNBA")


def _is_mlb_ticker(ticker: str) -> bool:
    return ticker.startswith("KXMLB")


class PriceWatcher:
    POLL_INTERVAL  = 2
    KALSHI_BASE    = "https://api.elections.kalshi.com/trade-api/v2"
    TENNIS_CTX_TTL = 20   # refresh tennis context every 20s, not every 2s

    def __init__(self, open_positions, client, config,
                 save_positions_fn, save_pnl_fn, pnl_log,
                 get_date_fn, bot_orders):
        self._positions  = open_positions
        self._client     = client
        self._config     = config
        self._save_pos   = save_positions_fn
        self._save_pnl   = save_pnl_fn
        self._pnl_log    = pnl_log
        self._get_date   = get_date_fn
        self._bot_orders = bot_orders
        self._stop_event = threading.Event()
        self._lock       = threading.Lock()
        self._thread     = threading.Thread(
            target=self._run, daemon=True, name="PriceWatcher"
        )
        self._exiting         = set()
        self._tennis_ctx_cache = {}   # ticker -> (tctx, timestamp)

    def start(self):
        log.info("[Watcher] Starting price watcher thread (2s poll, tennis-aware exits)")
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

    def _get_price(self, ticker, side):
        try:
            r = requests.get(f"{self.KALSHI_BASE}/markets/{ticker}", timeout=4)
            r.raise_for_status()
            m = r.json().get("market", {})
            if side == "no":
                bid = float(m.get("no_bid_dollars", 0) or 0)
            else:
                bid = float(m.get("yes_bid_dollars", 0) or 0)
            return max(1, int(bid * 100))
        except Exception as e:
            err = str(e)
            if "404" not in err and "not_found" not in err:
                log.debug(f"[Watcher] Price fetch failed {ticker}: {e}")
            return 0

    def _get_tennis_context_cached(self, ticker):
        """Fetch tennis context with 20s TTL so we don't hit the API every 2s."""
        now = time.time()
        cached = self._tennis_ctx_cache.get(ticker)
        if cached and now - cached[1] < self.TENNIS_CTX_TTL:
            return cached[0]
        try:
            import sys
            sys.path.insert(0, '/root')
            from tennis_context import get_tennis_context
            tctx = get_tennis_context(ticker)
            self._tennis_ctx_cache[ticker] = (tctx, now)
            return tctx
        except Exception as e:
            log.debug(f"[Watcher] Tennis ctx error {ticker}: {e}")
            return None

    def _place_exit(self, ticker, pos, bid, reason):
        if ticker in self._exiting:
            return
        self._exiting.add(ticker)
        try:
            import uuid
            import kalshi_python
            from trade_timing import new_timer, get_stats
            _tt = new_timer("SELL(watcher)", ticker)

            side      = pos["side"]
            contracts = pos["contracts"]
            entry     = pos["entry_price"]

            portfolio_api = kalshi_python.PortfolioApi(api_client=self._client)

            if side == "no":
                yes_p = max(1, 100 - bid)
                no_p  = None
            else:
                yes_p = max(1, bid)
                no_p  = None

            with _tt.step("order_placement"):
                order    = portfolio_api.create_order(
                    ticker          = ticker,
                    action          = "sell",
                    side            = side,
                    type            = "limit",
                    yes_price       = yes_p,
                    no_price        = no_p,
                    count           = int(contracts),
                    client_order_id = str(uuid.uuid4()),
                )
                order_id = order.order.order_id

            with _tt.step("pnl_calc"):
                fee_mult  = 0.0175
                entry_fee = pos.get("entry_fee", 0.0)
                exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
                pnl       = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee

            current_date = self._get_date()
            self._pnl_log[current_date] = self._pnl_log.get(current_date, 0.0) + pnl

            log.info(
                f"[Watcher] EXIT {ticker} {side.upper()} @ {bid}c x{contracts} "
                f"| {reason} | PNL ${pnl:.4f} | order={order_id}"
            )

            try:
                from trade_tracker import log_trade
                with _tt.step("trade_log"):
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

            with _tt.step("position_remove"):
                with self._lock:
                    if ticker in self._positions:
                        del self._positions[ticker]
                        self._save_pos(self._positions)
                        self._save_pnl(self._pnl_log)
            _tt.summary()
            get_stats().record_from_timer(_tt)

        except Exception as e:
            err_str = str(e)
            if any(x in err_str for x in ["MARKET_NOT_ACTIVE","409","market_not_found","404","Not Found"]):
                log.info(f"[Watcher] {ticker} market gone — removing")
                with self._lock:
                    if ticker in self._positions:
                        del self._positions[ticker]
                        self._save_pos(self._positions)
            elif "insufficient_balance" in err_str and self._positions.get(ticker,{}).get("side") == "no":
                log.info(f"[Watcher] {ticker} NO position — removing, let settle")
                with self._lock:
                    if ticker in self._positions:
                        del self._positions[ticker]
                        self._save_pos(self._positions)
            else:
                log.error(f"[Watcher] Exit order failed {ticker}: {e}")
        finally:
            self._exiting.discard(ticker)

    def _check_tennis_position(self, ticker, pos, bid):
        """
        Tennis-aware exit logic.
        Returns True if an exit was triggered.

        Stop loss and take profit both adjust dynamically based on
        match completion percentage from api-tennis.com live data.

        pct 0-33%  early:  stop=65% entry  TP=80c
        pct 33-66% mid:    stop=68% entry  TP=72c
        pct 66-85% late:   stop=72% entry  TP=67c
        pct 85%+   final:  stop=78% entry  TP=62c
        tiebreak:          exit at any profit
        match over:        exit immediately
        """
        entry     = pos["entry_price"]
        contracts = pos["contracts"]
        fee_mult  = 0.0175
        entry_fee = pos.get("entry_fee", 0.0)
        exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
        pnl       = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee
        peak      = pos.get("peak_price", entry)

        tctx = self._get_tennis_context_cached(ticker)

        if tctx:
            pct        = tctx.pct_complete
            sets_down  = tctx.sets_down
            p1_sets    = tctx.p1_sets
            p2_sets    = tctx.p2_sets
            is_live    = tctx.is_live
            p1_games   = tctx.p1_games
            p2_games   = tctx.p2_games
            total_sets = p1_sets + p2_sets
            max_sets   = 3
            in_final_set = (total_sets == max_sets - 1)
            in_tiebreak  = in_final_set and p1_games >= 6 and p2_games >= 6

            log.debug(
                f"[Watcher:Tennis] {ticker} bid={bid}c pct={pct:.0%} "
                f"sets={p1_sets}-{p2_sets} games={p1_games}-{p2_games} "
                f"live={is_live} tb={in_tiebreak} pnl=${pnl:.2f}"
            )

            # ── Match finished ─────────────────────────────────────────
            if not is_live and total_sets > 0:
                self._place_exit(ticker, pos, bid,
                    f"Match over {p1_sets}-{p2_sets} PNL=${pnl:.2f}")
                return True

            # ── Final set tiebreak — don't gamble it ──────────────────
            if in_tiebreak and pnl > 0:
                self._place_exit(ticker, pos, bid,
                    f"Tiebreak {p1_games}-{p2_games} lock PNL=${pnl:.2f}")
                return True

            # ── Dynamic stop loss ──────────────────────────────────────
            if pct < 0.33:
                stop_pct = 0.65
                tp       = 80
            elif pct < 0.66:
                stop_pct = 0.68
                tp       = 72
            elif pct < 0.85:
                stop_pct = 0.72
                tp       = 67
            else:
                stop_pct = 0.78
                tp       = 62

            # Adjust for match state
            if sets_down >= 2:
                stop_pct = max(stop_pct, 0.82)
                tp       = min(tp, 60)
            if in_final_set and p1_sets > p2_sets:
                stop_pct = max(stop_pct, 0.85)   # winning — protect it

            # ── Capital-aware tightening ───────────────────────────────
            # Large positions (>$5 deployed) get tighter stops
            # to protect capital regardless of match state
            deployed = entry * contracts / 100.0
            if deployed > 10.0:
                # Big position — max loss $3 regardless of stop_pct
                max_loss_cents = int(300 / contracts)  # $3 loss limit
                floor_stop     = max(1, entry - max_loss_cents)
                stop_pct_tight = floor_stop / entry
                if stop_pct_tight > stop_pct:
                    stop_pct = stop_pct_tight
                    log.debug(f"[Watcher] {ticker} capital guard: stop tightened to {floor_stop}c (${deployed:.2f} deployed)")
            elif deployed > 5.0:
                # Medium position — max loss $2
                max_loss_cents = int(200 / contracts)
                floor_stop     = max(1, entry - max_loss_cents)
                stop_pct_tight = floor_stop / entry
                if stop_pct_tight > stop_pct:
                    stop_pct = stop_pct_tight

            stop = int(entry * stop_pct)
            if bid <= stop:
                self._place_exit(ticker, pos, bid,
                    f"Tennis SL pct={pct:.0%} {bid}c<={stop}c PNL=${pnl:.2f}")
                return True

            # ── Dynamic take profit ────────────────────────────────────
            if bid >= tp and pnl > 0:
                self._place_exit(ticker, pos, bid,
                    f"Tennis TP pct={pct:.0%} {bid}c>={tp}c PNL=${pnl:.2f}")
                return True

            # ── Trail stop once profitable ─────────────────────────────
            if pnl >= 0.50:
                trail = int(peak * 0.82)
                if bid <= trail:
                    self._place_exit(ticker, pos, bid,
                        f"Tennis trail PNL=${pnl:.2f} peak={peak}c stop={trail}c")
                    return True

            # ── Spike exit ─────────────────────────────────────────────
            last_bid = pos.get("last_bid", entry)
            if bid - last_bid >= 20 and pnl >= 0.30:
                self._place_exit(ticker, pos, bid,
                    f"Tennis spike +{bid-last_bid}c PNL=${pnl:.2f}")
                return True

        else:
            # No context available — standard stops
            if bid <= int(entry * 0.70):
                self._place_exit(ticker, pos, bid,
                    f"Tennis SL(no-ctx) {bid}c PNL=${pnl:.2f}")
                return True
            if pnl >= 0.50 and bid <= int(peak * 0.82):
                self._place_exit(ticker, pos, bid,
                    f"Tennis trail(no-ctx) PNL=${pnl:.2f}")
                return True

        return False

    def _check_positions(self):
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

            peak = max(bid, pos.get("peak_price", entry))
            pos["peak_price"] = peak

            contracts = pos["contracts"]
            fee_mult  = 0.0175
            entry_fee = pos.get("entry_fee", 0.0)
            exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
            pnl       = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee

            # ── Tennis: use match-state aware logic ────────────────────
            if _is_tennis_ticker(ticker):
                if self._check_tennis_position(ticker, pos, bid):
                    continue
                pos["last_bid"] = bid
                continue

            # ── NBA / MLB: generic price-based logic ───────────────────
            if pnl >= 2.00:
                stop = int(peak * 0.88)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid,
                        f"Trail exit: ${pnl:.2f} profit, peak={peak}c")
                    continue
                if bid >= entry * 2.5:
                    self._place_exit(ticker, pos, bid,
                        f"2.5x exit: {bid}c vs entry {entry}c profit=${pnl:.2f}")
                    continue

            elif pnl >= 0.50:
                stop = int(peak * 0.82)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid,
                        f"Trail exit: ${pnl:.2f} profit, peak={peak}c stop={stop}c")
                    continue

            if bid <= int(entry * 0.70):
                self._place_exit(ticker, pos, bid,
                    f"Stop loss: {bid}c <= {int(entry*0.70)}c (entry={entry}c)")
                continue

            if bid <= 5 and entry > 15:
                self._place_exit(ticker, pos, bid, f"Floor exit: {bid}c")
                continue

            last_bid = pos.get("last_bid", entry)
            jump     = bid - last_bid
            if jump >= 25 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid,
                    f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
                continue

            if entry <= 15 and bid >= 30 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid,
                    f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
                continue

            pos["last_bid"] = bid

    def notify_new_position(self, ticker):
        log.debug(f"[Watcher] Tracking new position: {ticker}")

    def update_scan_tickers(self, tickers, cooldown):
        pass
