import json
import math
from datetime import datetime

def analyze_pnl():
    try:
        with open("pnl_log.json") as f:
            data = json.load(f)
    except:
        print("No pnl_log.json yet — run the bot live first!")
        return

    profits = [float(entry.get("pnl_usd", 0)) for entry in data if "pnl_usd" in entry]
    if not profits:
        print("=== REAL TRADE BACKTEST SUMMARY ===")
        print("No trades logged yet.")
        print("Run the live bot (python kalshi_bot.py) to start collecting data!")
        print("\nOnce you have trades, re-run this for win rate + PNL stats.")
        return

    wins = sum(1 for p in profits if p > 0)
    total_trades = len(profits)
    total_pnl = sum(profits)

    print("=== REAL TRADE BACKTEST SUMMARY ===")
    print(f"Total trades: {total_trades}")
    print(f"Total PNL: ${total_pnl:.2f}")
    print(f"Win rate: {wins/total_trades*100:.1f}%")
    print(f"Avg profit per trade: ${total_pnl/total_trades:.2f}")
    print(f"Rough Sharpe: {total_pnl / max(1, math.sqrt(total_trades)):.2f}")
    print(f"Biggest loser: ${min(profits):.2f}")
    print("\nUse fetch_historical_candles.py to test strategies on PAST games!")

if __name__ == "__main__":
    analyze_pnl()
