import json, sys, time
sys.path.insert(0, '/root')
from kalshi_bot import _get_kalshi_client, get_kalshi_balance
from datetime import datetime, timezone
from strategies import _fetch_fills_raw

client  = _get_kalshi_client()
balance = get_kalshi_balance(client)
today   = datetime.now(timezone.utc).strftime("%Y-%m-%d")

try:
    pnl_log   = json.load(open("/root/pnl_log.json"))
    today_pnl = pnl_log.get(today, 0.0)
    total_pnl = sum(pnl_log.values())
except:
    today_pnl = total_pnl = 0.0

try:
    positions = json.load(open("/root/positions.json"))
except:
    positions = {}

print("=" * 55)
print(f"  REPORT  {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
print("=" * 55)
print(f"  Balance:        ${balance:.2f}")
print(f"  Today PNL:      ${today_pnl:.4f}")
print(f"  All-time PNL:   ${total_pnl:.4f}")
print(f"  Open positions: {len(positions)}")

for t, p in positions.items():
    print(f"    {t[:50]}")
    print(f"      {p.get('side','?').upper()} @ {p.get('entry_price','?')}c "
          f"x{p.get('contracts','?')} [{p.get('strategy','?')}]")

# Today's fills
fills      = _fetch_fills_raw(client)
today_fills = [f for f in fills if f.get("created_time","")[:10] == today]
buys       = [f for f in today_fills if f.get("action") == "buy"]
sells      = [f for f in today_fills if f.get("action") == "sell"]

print(f"\n  Today's fills: {len(today_fills)} ({len(buys)} buys, {len(sells)} sells)")

# PNL by strategy from fills
from collections import defaultdict
strategy_pnl = defaultdict(float)
strategy_trades = defaultdict(int)

# Match buys to sells by ticker
ticker_positions = {}
for f in sorted(today_fills, key=lambda x: x.get("created_time","")):
    ticker  = f.get("ticker") or f.get("market_ticker","")
    action  = f.get("action","")
    count   = int(float(f.get("count_fp",0) or 0))
    yes_p   = float(f.get("yes_price_dollars",0) or 0)
    no_p    = float(f.get("no_price_dollars",0) or 0)
    price_c = round((yes_p or no_p) * 100)
    if action == "buy":
        ticker_positions[ticker] = {"entry": price_c, "count": count}
    elif action == "sell" and ticker in ticker_positions:
        entry   = ticker_positions[ticker]["entry"]
        ct      = ticker_positions[ticker]["count"]
        pnl     = (price_c - entry) * ct / 100.0
        strat   = "unknown"
        # Try to match to open positions history
        strategy_pnl[strat]    += pnl
        strategy_trades[strat] += 1

print(f"\n  Wins/losses today:")
wins   = sum(1 for f in sells if
    float(f.get("yes_price_dollars",0) or f.get("no_price_dollars",0) or 0) * 100 > 50)
losses = len(sells) - wins
print(f"    Sells: {len(sells)} total | ~{wins} profitable | ~{losses} at loss")

print("\n" + "=" * 55)
