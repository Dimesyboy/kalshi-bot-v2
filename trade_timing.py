#!/usr/bin/env python3
"""
trade_timing.py
Detailed step-by-step timing for buy and sell execution paths.
Logs each gate/step with elapsed time so you can see exactly where
latency lives inside execute_signal() and _place_exit().

Steps tracked for BUY:
  1. gate_checks        - daily limit, position count, balance fetch
  2. balance_fetch      - just the get_kalshi_balance() call
  3. order_placement    - the actual API call to create_order
  4. position_record    - saving to open_positions + disk write
  5. total_buy          - full buy path end to end

Steps tracked for SELL (main loop):
  1. order_placement    - the actual API call
  2. pnl_calc           - fee + pnl math
  3. trade_log          - writing to trade_tracker csv
  4. position_remove    - del + disk write
  5. total_sell         - full sell path end to end

Steps tracked for SELL (watcher):
  Same as above but prefixed with watcher_
"""

import time
import logging
from contextlib import contextmanager
from collections import defaultdict

log = logging.getLogger("kalshi_bot.trade_timing")


class TradeTimer:
    """
    Used once per trade execution. Tracks each named step.
    Call .start(step) before, .end(step) after, .summary() at the end.
    """
    def __init__(self, trade_type: str, ticker: str):
        self.trade_type = trade_type  # "BUY" or "SELL"
        self.ticker     = ticker
        self._steps     = {}          # label -> (t_start, elapsed_ms)
        self._order     = []          # insertion order
        self._t0        = time.perf_counter()

    def start(self, step: str):
        self._steps[step] = [time.perf_counter(), None]
        if step not in self._order:
            self._order.append(step)

    def end(self, step: str):
        if step in self._steps:
            self._steps[step][1] = (time.perf_counter() - self._steps[step][0]) * 1000

    @contextmanager
    def step(self, label: str):
        self.start(label)
        try:
            yield
        finally:
            self.end(label)

    def total_ms(self) -> float:
        return (time.perf_counter() - self._t0) * 1000

    def summary(self):
        total = self.total_ms()
        log.info(
            f"[TradeTiming] ── {self.trade_type} {self.ticker} "
            f"{'─' * max(0, 45 - len(self.ticker))} total={total:.1f}ms"
        )
        for label in self._order:
            entry = self._steps.get(label)
            if entry and entry[1] is not None:
                ms = entry[1]
                bar = _bar(ms, total)
                log.info(f"[TradeTiming]   {label:<25} {ms:>8.1f}ms  {bar}")
        log.info(f"[TradeTiming] {'─' * 55}")


# Session-level aggregate stats across all trades this run
class TradeTimingStats:
    def __init__(self):
        self._data = defaultdict(lambda: {
            "count": 0, "total_ms": 0.0, "max_ms": 0.0
        })

    def record(self, trade_type: str, step: str, ms: float):
        key = f"{trade_type}:{step}"
        d = self._data[key]
        d["count"]    += 1
        d["total_ms"] += ms
        if ms > d["max_ms"]:
            d["max_ms"] = ms

    def record_from_timer(self, timer: TradeTimer):
        for label, entry in timer._steps.items():
            if entry[1] is not None:
                self.record(timer.trade_type, label, entry[1])
        self.record(timer.trade_type, "TOTAL", timer.total_ms())

    def log_summary(self):
        if not self._data:
            return
        log.info("[TradeTiming] ── Session aggregate ────────────────────────")
        rows = sorted(self._data.items(), key=lambda x: -x[1]["total_ms"])
        for key, d in rows:
            avg = d["total_ms"] / d["count"] if d["count"] else 0
            log.info(
                f"[TradeTiming]   {key:<30} "
                f"avg={avg:>7.1f}ms  "
                f"max={d['max_ms']:>7.1f}ms  "
                f"n={d['count']}"
            )
        log.info("[TradeTiming] ───────────────────────────────────────────────")


def _bar(ms: float, total_ms: float, width: int = 20) -> str:
    if total_ms <= 0:
        return ""
    pct = min(ms / total_ms, 1.0)
    filled = int(pct * width)
    return f"[{'█' * filled}{'░' * (width - filled)}] {pct*100:>4.0f}%"


# Module singletons
_stats = TradeTimingStats()

def get_stats() -> TradeTimingStats:
    return _stats

def new_timer(trade_type: str, ticker: str) -> TradeTimer:
    return TradeTimer(trade_type.upper(), ticker)
