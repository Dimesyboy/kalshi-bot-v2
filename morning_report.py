import json, sys, time, csv, os
sys.path.insert(0, '/root')
from kalshi_bot import _get_kalshi_client, get_kalshi_balance
from datetime import datetime, timezone
from strategies import _fetch_fills_raw
from collections import defaultdict

client = _get_kalshi_client()
balance = get_kalshi_balance(client)
today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

try:
    pnl_log = json.load(open("/root/pnl_log.json"))
    today_pnl = pnl_log.get(today, 0.0)
    total_pnl = sum(pnl_log.values())
except:
    today_pnl = total_pnl = 0.0

try:
    positions = json.load(open("/root/positions.json"))
except:
    positions = {}

print("=" * 60)
print(f" REPORT {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")
print("=" * 60)
print(f" Balance:        ${balance:.2f}")
print(f" Today PNL:      ${today_pnl:.4f}")
print(f" All-time PNL:   ${total_pnl:.4f}")
print(f" Open positions: {len(positions)}")
for t, p in positions.items():
    print(f"   {t[:55]}")
    print(f"   {p.get('side','?').upper()} @ {p.get('entry_price','?')}c "
          f"x{p.get('contracts','?')} [{p.get('strategy','?')}]")

# ── Strategy PNL attribution ──────────────────────────────────────────────
CSV_FILE = "/root/trade_log.csv"
print()
print("=" * 60)
print(" STRATEGY BREAKDOWN (from trade_log.csv)")
print("=" * 60)

def base_strategy(raw):
    """Strip exit/watcher prefix to get the underlying strategy name."""
    for prefix in ("exit_trail_", "exit_sl_", "exit_stale_", "watcher_"):
        if raw.startswith(prefix):
            return raw[len(prefix):]
    return raw

if not os.path.exists(CSV_FILE):
    print(" No trade_log.csv yet.")
else:
    strategy_stats = defaultdict(lambda: {"trades": 0, "wins": 0, "losses": 0, "pnl": 0.0})
    today_stats    = defaultdict(lambda: {"trades": 0, "wins": 0, "losses": 0, "pnl": 0.0})

    try:
        with open(CSV_FILE, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                raw_strat = row.get("strategy", "") or "unknown"
                strat = base_strategy(raw_strat)

                try:
                    pnl = float(row.get("pnl", 0) or 0)
                except:
                    pnl = 0.0

                ts = row.get("timestamp", "")
                is_today = ts[:10] == today

                strategy_stats[strat]["trades"] += 1
                strategy_stats[strat]["pnl"] += pnl
                if pnl > 0:
                    strategy_stats[strat]["wins"] += 1
                else:
                    strategy_stats[strat]["losses"] += 1

                if is_today:
                    today_stats[strat]["trades"] += 1
                    today_stats[strat]["pnl"] += pnl
                    if pnl > 0:
                        today_stats[strat]["wins"] += 1
                    else:
                        today_stats[strat]["losses"] += 1

        # All-time table
        print(f"\n {'Strategy':<28} {'Trades':>6} {'Win%':>6} {'PNL':>10}")
        print(f" {'-'*28} {'-'*6} {'-'*6} {'-'*10}")
        total_trades = total_wins = 0
        total_csv_pnl = 0.0
        for strat in sorted(strategy_stats, key=lambda s: -strategy_stats[s]["pnl"]):
            v = strategy_stats[strat]
            winp = (v["wins"] / v["trades"] * 100) if v["trades"] > 0 else 0
            sign = "+" if v["pnl"] >= 0 else ""
            print(f" {strat:<28} {v['trades']:>6} {winp:>5.1f}% {sign}${v['pnl']:>8.4f}")
            total_trades += v["trades"]
            total_wins += v["wins"]
            total_csv_pnl += v["pnl"]

        overall_winp = (total_wins / total_trades * 100) if total_trades > 0 else 0
        sign = "+" if total_csv_pnl >= 0 else ""
        print(f" {'-'*28} {'-'*6} {'-'*6} {'-'*10}")
        print(f" {'TOTAL':<28} {total_trades:>6} {overall_winp:>5.1f}% {sign}${total_csv_pnl:>8.4f}")

        # Today table
        if today_stats:
            print(f"\n Today ({today}):")
            print(f" {'Strategy':<28} {'Trades':>6} {'Win%':>6} {'PNL':>10}")
            print(f" {'-'*28} {'-'*6} {'-'*6} {'-'*10}")
            for strat in sorted(today_stats, key=lambda s: -today_stats[s]["pnl"]):
                v = today_stats[strat]
                winp = (v["wins"] / v["trades"] * 100) if v["trades"] > 0 else 0
                sign = "+" if v["pnl"] >= 0 else ""
                print(f" {strat:<28} {v['trades']:>6} {winp:>5.1f}% {sign}${v['pnl']:>8.4f}")
        else:
            print(f"\n No closed trades today yet.")

    except Exception as e:
        print(f" Error reading trade_log.csv: {e}")

# ── Today's fills summary ─────────────────────────────────────────────────
print()
print("=" * 60)
print(" TODAY'S FILLS")
print("=" * 60)
try:
    fills = _fetch_fills_raw(client)
    today_fills = [f for f in fills if f.get("created_time","")[:10] == today]
    buys  = [f for f in today_fills if f.get("action") == "buy"]
    sells = [f for f in today_fills if f.get("action") == "sell"]
    print(f" Total: {len(today_fills)} ({len(buys)} buys, {len(sells)} sells)")
    wins = losses = 0
    for f in sells:
        price = float(f.get("yes_price_dollars", 0) or f.get("no_price_dollars", 0) or 0)
        if price * 100 > 50:
            wins += 1
        else:
            losses += 1
    if sells:
        print(f" Sells: ~{wins} profitable, ~{losses} at loss")
except Exception as e:
    print(f" Could not fetch fills: {e}")

print()
print("=" * 60)
