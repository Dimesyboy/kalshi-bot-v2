"""Simple backtester - load your real pnl_log.json and compute stats
Run: python backtests/backtest.py
Extend with historical Kalshi snapshots later for full strategy validation."""
import json
from datetime import datetime
import math

def analyze_pnl():
    try:
        with open("pnl_log.json") as f:
            data = json.load(f)
    except FileNotFoundError:
        print("No pnl_log.json yet - run the bot first!")
        return

    if not data:
        print("Empty log")
        return

    profits = [entry.get("pnl_usd", 0) for entry in data if "pnl_usd" in entry]
    wins = sum(1 for p in profits if p > 0)
    total_trades = len(profits)

    print("=== BACKTEST SUMMARY ===")
    print(f"Total trades: {total_trades}")
    print(f"Total PNL: ${sum(profits):.2f}")
    print(f"Win rate: {wins/total_trades*100:.1f}%")
    print(f"Sharpe (rough): {sum(profits)/max(1, math.sqrt(total_trades)):.2f}")
    print(f"Max daily loss seen: ${min(profits):.2f}")
    print("\nReady to add historical Kalshi+ESPN replay here for true edge testing.")

if __name__ == "__main__":
    analyze_pnl()
