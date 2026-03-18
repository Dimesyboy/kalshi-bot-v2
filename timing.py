#!/usr/bin/env python3
"""
timing.py
Lightweight timing instrumentation for the Kalshi bot.
Usage:
    from timing import timed, TimingReport, get_report

Wrap any function:
    @timed("espn_refresh")
    def refresh(...): ...

Or inline:
    with timed_block("snapshot_fetch"):
        snapshot = get_live_sports_snapshot()

At end of cycle:
    get_report().log_summary()
    get_report().reset()
"""

import time
import logging
import functools
from contextlib import contextmanager
from collections import defaultdict
from typing import Optional

log = logging.getLogger("kalshi_bot.timing")


class TimingReport:
    def __init__(self):
        self._data = defaultdict(lambda: {
            "calls": 0,
            "total_ms": 0.0,
            "min_ms": float("inf"),
            "max_ms": 0.0,
            "last_ms": 0.0,
        })
        self._cycle_start: Optional[float] = None

    def start_cycle(self):
        self._cycle_start = time.perf_counter()

    def record(self, label: str, elapsed_ms: float):
        d = self._data[label]
        d["calls"]    += 1
        d["total_ms"] += elapsed_ms
        d["last_ms"]   = elapsed_ms
        if elapsed_ms < d["min_ms"]: d["min_ms"] = elapsed_ms
        if elapsed_ms > d["max_ms"]: d["max_ms"] = elapsed_ms

    def reset(self):
        self._data.clear()
        self._cycle_start = None

    def log_summary(self, threshold_ms: float = 10.0):
        """Log all timings. Only show entries >= threshold_ms to reduce noise."""
        cycle_ms = 0.0
        if self._cycle_start is not None:
            cycle_ms = (time.perf_counter() - self._cycle_start) * 1000

        log.info("[Timing] ── Cycle timing summary ──────────────────────────")
        if cycle_ms:
            log.info(f"[Timing]   TOTAL CYCLE          {cycle_ms:>8.1f}ms")

        # Sort by total time descending
        rows = sorted(self._data.items(), key=lambda x: -x[1]["total_ms"])
        for label, d in rows:
            if d["total_ms"] < threshold_ms:
                continue
            avg = d["total_ms"] / d["calls"] if d["calls"] else 0
            log.info(
                f"[Timing]   {label:<30} "
                f"total={d['total_ms']:>7.1f}ms  "
                f"avg={avg:>6.1f}ms  "
                f"min={d['min_ms']:>6.1f}ms  "
                f"max={d['max_ms']:>6.1f}ms  "
                f"calls={d['calls']}"
            )
        log.info("[Timing] ───────────────────────────────────────────────────")

    def get_slowest(self, n: int = 3) -> list:
        """Return the n slowest labels by total time."""
        rows = sorted(self._data.items(), key=lambda x: -x[1]["total_ms"])
        return [(label, d["total_ms"]) for label, d in rows[:n]]


# Module-level singleton
_report = TimingReport()

def get_report() -> TimingReport:
    return _report


def timed(label: str):
    """
    Decorator. Use on any function:
        @timed("my_label")
        def my_fn(...): ...
    """
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            t0 = time.perf_counter()
            try:
                return fn(*args, **kwargs)
            finally:
                elapsed = (time.perf_counter() - t0) * 1000
                _report.record(label, elapsed)
        return wrapper
    return decorator


@contextmanager
def timed_block(label: str):
    """
    Context manager for inline timing:
        with timed_block("snapshot_fetch"):
            ...
    """
    t0 = time.perf_counter()
    try:
        yield
    finally:
        elapsed = (time.perf_counter() - t0) * 1000
        _report.record(label, elapsed)
