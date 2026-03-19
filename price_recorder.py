#!/usr/bin/env python3
"""
Records Kalshi market prices every 5 minutes for open positions.
Builds historical price data for backtesting exit strategies.
Run in background: screen -dmS recorder python3 /root/price_recorder.py
"""
import json, time, requests, csv, os
from datetime import datetime, timezone

KALSHI_BASE = "https://api.elections.kalshi.com/trade-api/v2"
OUTPUT_FILE = "/root/price_history.csv"
INTERVAL    = 300  # 5 minutes

def get_price(ticker, side):
    try:
        r = requests.get(f"{KALSHI_BASE}/markets/{ticker}", timeout=6)
        if r.ok:
            m = r.json().get("market", {})
            return {
                "yes_bid": float(m.get("yes_bid_dollars", 0) or 0) * 100,
                "no_bid":  float(m.get("no_bid_dollars",  0) or 0) * 100,
                "volume":  float(m.get("volume_fp", 0) or 0),
            }
    except: pass
    return None

fieldnames = ["timestamp","ticker","side","entry_price","yes_bid","no_bid","volume","pnl_if_exit_now"]

if not os.path.exists(OUTPUT_FILE):
    with open(OUTPUT_FILE, 'w', newline='') as f:
        csv.DictWriter(f, fieldnames=fieldnames).writeheader()

print(f"Price recorder started. Writing to {OUTPUT_FILE}")

while True:
    try:
        positions = json.load(open("/root/positions.json"))
        now = datetime.now(timezone.utc).isoformat()
        rows = []
        for ticker, pos in positions.items():
            if not pos.get("is_bot"): continue
            prices = get_price(ticker, pos["side"])
            if not prices: continue
            entry = pos.get("entry_price", 0)
            side  = pos.get("side", "yes")
            contracts = pos.get("contracts", 0)
            bid = prices["no_bid"] if side == "no" else prices["yes_bid"]
            pnl = (bid - entry) * contracts / 100 if entry else 0
            rows.append({
                "timestamp":    now,
                "ticker":       ticker,
                "side":         side,
                "entry_price":  entry,
                "yes_bid":      prices["yes_bid"],
                "no_bid":       prices["no_bid"],
                "volume":       prices["volume"],
                "pnl_if_exit_now": round(pnl, 4),
            })
        if rows:
            with open(OUTPUT_FILE, 'a', newline='') as f:
                w = csv.DictWriter(f, fieldnames=fieldnames)
                for row in rows:
                    w.writerow(row)
            print(f"{now[:19]} — recorded {len(rows)} positions")
    except Exception as e:
        print(f"Error: {e}")
    time.sleep(INTERVAL)
