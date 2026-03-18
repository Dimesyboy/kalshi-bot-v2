#!/usr/bin/env python3
"""
trade_tracker.py
Logs every closed trade with full context for strategy performance analysis.
Written to trade_log.csv — one row per closed position.
"""

import csv
import os
from datetime import datetime, timezone

TRADE_LOG = "/root/trade_log.csv"

FIELDS = [
    "timestamp",
    "market_ticker",
    "event_ticker", 
    "sport",
    "side",
    "strategy",
    "entry_price",
    "exit_price",
    "peak_price",
    "contracts",
    "entry_fee",
    "exit_fee",
    "pnl_gross",
    "pnl_net",
    "win",
    "exit_reason",
    "age_seconds",
    "price_range",   # entry price bucket: 5-15, 15-25, 25-35, 35-45, 45-55, 55-65, 65-75, 75-85, 85-95
    "is_bot",
]

def _price_range(price_cents: int) -> str:
    for lo in range(5, 100, 10):
        if lo <= price_cents < lo + 10:
            return f"{lo}-{lo+9}"
    return "other"

def log_trade(
    market_ticker: str,
    event_ticker:  str,
    sport:         str,
    side:          str,
    strategy:      str,
    entry_price:   int,
    exit_price:    int,
    peak_price:    int,
    contracts:     int,
    entry_fee:     float,
    exit_fee:      float,
    exit_reason:   str,
    entry_time:    str,
    is_bot:        bool = True,
):
    now        = datetime.now(timezone.utc).isoformat()
    pnl_gross  = (exit_price - entry_price) * contracts / 100.0
    pnl_net    = pnl_gross - entry_fee - exit_fee
    win        = 1 if pnl_net > 0 else 0

    age_secs = 0
    try:
        et = datetime.fromisoformat(entry_time)
        if et.tzinfo is None:
            et = et.replace(tzinfo=timezone.utc)
        age_secs = int((datetime.now(timezone.utc) - et).total_seconds())
    except Exception:
        pass

    row = {
        "timestamp":    now,
        "market_ticker": market_ticker,
        "event_ticker": event_ticker,
        "sport":        sport,
        "side":         side,
        "strategy":     strategy,
        "entry_price":  entry_price,
        "exit_price":   exit_price,
        "peak_price":   peak_price,
        "contracts":    contracts,
        "entry_fee":    round(entry_fee, 4),
        "exit_fee":     round(exit_fee, 4),
        "pnl_gross":    round(pnl_gross, 4),
        "pnl_net":      round(pnl_net, 4),
        "win":          win,
        "exit_reason":  exit_reason,
        "age_seconds":  age_secs,
        "price_range":  _price_range(entry_price),
        "is_bot":       1 if is_bot else 0,
    }

    write_header = not os.path.exists(TRADE_LOG)
    with open(TRADE_LOG, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def print_stats():
    """Print strategy performance summary from trade log."""
    if not os.path.exists(TRADE_LOG):
        print("No trade log yet.")
        return

    from collections import defaultdict
    stats = defaultdict(lambda: {"trades":0,"wins":0,"pnl":0.0,"fees":0.0})

    with open(TRADE_LOG) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("is_bot","1") == "0":
                continue  # skip manual trades
            s = row.get("strategy","unknown")
            # Normalize exit strategies back to entry strategy
            for prefix in ["exit_tp_","exit_sl_","exit_stale_","exit_trail_","exit_floor_","exit_espn_"]:
                if s.startswith(prefix):
                    s = s[len(prefix):]
                    break
            stats[s]["trades"]  += 1
            stats[s]["wins"]    += int(row.get("win",0))
            stats[s]["pnl"]     += float(row.get("pnl_net",0))
            stats[s]["fees"]    += float(row.get("entry_fee",0)) + float(row.get("exit_fee",0))

    # Also stats by price range
    price_stats = defaultdict(lambda: {"trades":0,"wins":0,"pnl":0.0})
    with open(TRADE_LOG) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("is_bot","1") == "0": continue
            pr = row.get("price_range","?")
            price_stats[pr]["trades"] += 1
            price_stats[pr]["wins"]   += int(row.get("win",0))
            price_stats[pr]["pnl"]    += float(row.get("pnl_net",0))

    print()
    print("=" * 65)
    print("  STRATEGY PERFORMANCE")
    print("=" * 65)
    print(f"  {'Strategy':<25} {'Trades':>6} {'Win%':>6} {'PNL':>9} {'Fees':>8}")
    print("  " + "-" * 60)
    total_pnl = 0.0
    for s, v in sorted(stats.items(), key=lambda x: -x[1]["pnl"]):
        win_pct = v["wins"]/v["trades"]*100 if v["trades"] else 0
        sign    = "+" if v["pnl"] >= 0 else ""
        print(f"  {s:<25} {v['trades']:>6} {win_pct:>5.1f}% {sign}${v['pnl']:>7.4f} ${v['fees']:>6.4f}")
        total_pnl += v["pnl"]
    print("  " + "-" * 60)
    print(f"  {'TOTAL':<25} {'':>6} {'':>6} ${total_pnl:>+8.4f}")

    print()
    print("=" * 65)
    print("  PERFORMANCE BY ENTRY PRICE RANGE")
    print("=" * 65)
    print(f"  {'Range':<12} {'Trades':>6} {'Win%':>6} {'PNL':>9}")
    print("  " + "-" * 40)
    for pr in sorted(price_stats.keys()):
        v = price_stats[pr]
        win_pct = v["wins"]/v["trades"]*100 if v["trades"] else 0
        sign    = "+" if v["pnl"] >= 0 else ""
        print(f"  {pr+'c':<12} {v['trades']:>6} {win_pct:>5.1f}% {sign}${v['pnl']:>7.4f}")
    print()


if __name__ == "__main__":
    print_stats()
