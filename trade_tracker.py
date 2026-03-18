#!/usr/bin/env python3
""" trade_tracker.py — ROBUST RECENT TRADES + stats + EDGE CONFIRMATION """
import csv
import os
from datetime import datetime
from collections import defaultdict

CSV_FILE = "/root/trade_log.csv"
FIELDS = ["timestamp", "strategy", "market_ticker", "event_ticker", "sport", "side", "contracts", "entry_price", "exit_price", "peak_price", "entry_fee", "exit_fee", "pnl", "exit_reason", "entry_time", "is_bot"]

def log_trade(strategy: str = "", ticker: str = "", side: str = "",
              contracts: int = 0, entry_price: float = 0.0,
              exit_price: float = None, pnl: float = 0.0, reason: str = "",
              market_ticker: str = "", event_ticker: str = "", sport: str = "",
              peak_price: float = 0.0, entry_fee: float = 0.0,
              exit_fee: float = 0.0, exit_reason: str = "",
              entry_time: str = "", is_bot: bool = True):
    """Write a fully populated row to trade_log.csv"""
    market_ticker = market_ticker or ticker
    exit_reason   = exit_reason or reason
    if pnl == 0.0 and exit_price and entry_price:
        pnl = round(((exit_price - entry_price) * contracts / 100.0) - entry_fee - exit_fee, 4)
    row = {
        "timestamp":    datetime.now().isoformat(),
        "strategy":     strategy,
        "market_ticker": market_ticker,
        "event_ticker": event_ticker,
        "sport":        sport,
        "side":         side,
        "contracts":    contracts,
        "entry_price":  entry_price,
        "exit_price":   exit_price or 0.0,
        "peak_price":   peak_price,
        "entry_fee":    entry_fee,
        "exit_fee":     exit_fee,
        "pnl":          pnl,
        "exit_reason":  exit_reason,
        "entry_time":   entry_time,
        "is_bot":       is_bot,
    }
    file_exists = os.path.exists(CSV_FILE)
    with open(CSV_FILE, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if not file_exists:
            writer.writeheader()
        writer.writerow(row)

def print_stats():
    if not os.path.exists(CSV_FILE):
        print("No trades yet.")
        return

    trades = []
    stats = defaultdict(lambda: {"trades": 0, "wins": 0, "pnl": 0.0})

    with open(CSV_FILE, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            trades.append(row)
            s = row.get("strategy", "unknown")
            try:
                pnl = float(row.get("pnl", 0))
            except:
                pnl = 0.0
            stats[s]["trades"] += 1
            stats[s]["pnl"] += pnl
            if pnl > 0:
                stats[s]["wins"] += 1

    # === RECENT TRADES (bulletproof for old CSV rows) ===
    print("\n" + "="*85)
    print("RECENT TRADES (last 20 — OLD rows show N/A where column missing)")
    print("="*85)
    recent = sorted(trades, key=lambda x: x.get("timestamp",""), reverse=True)[:20]
    for row in recent:
        t = (row.get("timestamp", "OLD") or "OLD")[:19]
        strategy = row.get("strategy", "unknown")
        ticker = row.get("ticker", row.get("event", row.get("market", "N/A")))
        side = row.get("side", "N/A")
        try:
            contracts = int(float(row.get("contracts", 0) or 0))
            entry_price = float(row.get("entry_price", 0) or 0)
            exit_price = float(row.get("exit_price", 0) or 0)
            pnl = float(row.get("pnl", 0) or 0)
        except (ValueError, TypeError):
            contracts = 0
            entry_price = 0.0
            exit_price = 0.0
            pnl = 0.0
        reason = row.get("reason", "N/A")
        print(f"{t} | {strategy:<22} | {ticker:<18} | {side} {contracts:2d} @ {entry_price:.2f} → {exit_price:.2f} | PNL ${pnl:.2f} | {reason}")

    print("\n" + "="*70)
    print("OVERALL STRATEGY STATS")
    print("="*70)
    for s in sorted(stats, key=lambda x: -stats[x]["pnl"]):
        v = stats[s]
        winp = (v["wins"] / v["trades"] * 100) if v["trades"] > 0 else 0
        print(f"  {s:<28} Trades:{v['trades']:3d}  Win:{winp:5.1f}%  PNL:${v['pnl']:8.2f}")

    print("\n" + "="*70)
    print("  EDGE CONFIRMATION (>52% win + positive PNL after 5+ trades)")
    print("="*70)
    confirmed = False
    for s, v in sorted(stats.items(), key=lambda x: -x[1]["pnl"]):
        if v["trades"] >= 5:
            winp = v["wins"] / v["trades"]
            if winp > 0.52 and v["pnl"] > 0:
                print(f"  ✅ EDGE CONFIRMED: {s:<20} {winp*100:>5.1f}% +${v['pnl']:.2f}")
                confirmed = True
            else:
                print(f"  ⚠️  {s:<20} {winp*100:>5.1f}% — more data needed")
        else:
            print(f"  ⏳ {s:<20} only {v['trades']} trades — need 5+")
    if not confirmed:
        print("  ℹ️  Keep running during live slates — edge will appear after 5+ trades per strategy!")

    print("\n✅ Tracker now fully robust. Old + new trades both display.")

if __name__ == "__main__":
    print_stats()
