#!/usr/bin/env python3
"""
paper_trader.py
Runs strategy logic without placing orders.
Every signal is logged with entry price.
45 minutes later, fetches current price and logs the hypothetical outcome.
Run continuously during live sports to build a real sample fast.

Usage: python3 paper_trader.py
"""

import os, sys, json, time, csv, requests, logging
from datetime import datetime, timezone
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("paper_trader")

KALSHI_BASE  = "https://api.elections.kalshi.com/trade-api/v2"
PAPER_FILE   = "/root/paper_trades.csv"
FIELDS       = ["signal_time","market_ticker","strategy","side",
                "entry_price","contracts","confidence","reason",
                "resolve_time","resolve_price","hyp_pnl","resolved"]
RESOLVE_SECS = 45 * 60   # check outcome after 45 min
LOOP_SECS    = 45

# ── Lazy imports from bot ────────────────────────────────────────────
sys.path.insert(0, '/root')
from kalshi_bot import (
    get_live_sports_snapshot, analyze_snapshot,
    Config, calculate_fee
)
from strategies import STRATEGIES, ESPNContextCache

def get_current_price(ticker, side):
    try:
        r = requests.get(f"{KALSHI_BASE}/markets/{ticker}", timeout=6)
        r.raise_for_status()
        m = r.json().get("market", {})
        key = "no_bid_dollars" if side == "no" else "yes_bid_dollars"
        return max(1, int(float(m.get(key, 0) or 0) * 100))
    except:
        return None

def load_pending():
    pending = []
    if not os.path.exists(PAPER_FILE):
        return pending
    with open(PAPER_FILE) as f:
        for row in csv.DictReader(f):
            if row.get("resolved","") != "yes":
                pending.append(row)
    return pending

def update_row(ticker, resolved_price, entry_price, side, contracts, signal_time):
    ep    = float(entry_price)
    xp    = resolved_price
    ct    = int(contracts)
    fee_e = calculate_fee(ct, ep/100, is_maker=True)
    fee_x = calculate_fee(ct, xp/100, is_maker=True)
    pnl   = (xp - ep) * ct / 100.0 - fee_e - fee_x
    return {
        "resolve_time":  datetime.now(timezone.utc).isoformat(),
        "resolve_price": xp,
        "hyp_pnl":       round(pnl, 4),
        "resolved":      "yes",
    }

def rewrite_csv(all_rows):
    with open(PAPER_FILE, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(all_rows)

def log_signal(sig):
    exists = os.path.exists(PAPER_FILE)
    with open(PAPER_FILE, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        if not exists:
            w.writeheader()
        w.writerow({
            "signal_time":   datetime.now(timezone.utc).isoformat(),
            "market_ticker": sig.market_ticker,
            "strategy":      sig.strategy,
            "side":          sig.side,
            "entry_price":   sig.price,
            "contracts":     sig.contracts,
            "confidence":    sig.confidence,
            "reason":        sig.reason,
            "resolve_time":  "",
            "resolve_price": "",
            "hyp_pnl":       "",
            "resolved":      "no",
        })
    log.info(f"[Paper] SIGNAL logged: {sig.market_ticker} {sig.side} @ {sig.price}c "
             f"strat={sig.strategy} conf={sig.confidence:.2f}")

def print_paper_stats():
    if not os.path.exists(PAPER_FILE):
        print("No paper trades yet.")
        return
    from collections import defaultdict
    import math
    rows = list(csv.DictReader(open(PAPER_FILE)))
    resolved = [r for r in rows if r.get("resolved") == "yes"]
    if not resolved:
        print(f"No resolved paper trades yet. {len(rows)} pending.")
        return
    strats = defaultdict(lambda: {"n":0,"wins":0,"pnl":0.0})
    for r in resolved:
        s = r.get("strategy","?")
        try:    pnl = float(r.get("hyp_pnl",0))
        except: pnl = 0.0
        strats[s]["n"]    += 1
        strats[s]["pnl"]  += pnl
        if pnl > 0: strats[s]["wins"] += 1
    print(f"\n{'='*65}")
    print(f"  PAPER TRADE RESULTS — {len(resolved)} resolved / {len(rows)} total")
    print(f"{'='*65}")
    print(f"  {'Strategy':<30} {'N':>4}  {'Win%':>6}  {'Total':>9}  {'Avg':>8}")
    print("  " + "-"*55)
    for s, v in sorted(strats.items(), key=lambda x: -x[1]["pnl"]):
        n   = v["n"]
        wp  = v["wins"]/n
        avg = v["pnl"]/n
        wins_needed = max(0, 20-n)
        sig = f"  (need {wins_needed} more)" if n < 20 else ""
        print(f"  {s:<30} {n:>4}  {wp:>5.1%}  {v['pnl']:>+9.4f}  {avg:>+8.4f}{sig}")
    total = sum(v["pnl"] for v in strats.values())
    print(f"\n  Net hypothetical PNL: ${total:+.4f}")
    print()

# ── Main loop ────────────────────────────────────────────────────────
if len(sys.argv) > 1 and sys.argv[1] == "--stats":
    print_paper_stats()
    sys.exit(0)

log.info("Paper trader starting. Signals logged to paper_trades.csv")
log.info("Run with --stats to see results at any time.")

espn_cache   = ESPNContextCache()
seen_tickers = set()   # cooldown within session
cycle        = 0

while True:
    cycle += 1
    now = time.time()

    # ── Resolve pending trades ─────────────────────────────────────
    if os.path.exists(PAPER_FILE):
        all_rows = list(csv.DictReader(open(PAPER_FILE)))
        updated  = False
        for row in all_rows:
            if row.get("resolved") == "yes":
                continue
            try:
                st = datetime.fromisoformat(row["signal_time"])
                if st.tzinfo is None:
                    st = st.replace(tzinfo=timezone.utc)
                age = (datetime.now(timezone.utc) - st).total_seconds()
            except:
                continue
            if age < RESOLVE_SECS:
                continue
            rp = get_current_price(row["market_ticker"], row["side"])
            if rp is None:
                continue
            update = update_row(
                row["market_ticker"], rp,
                row["entry_price"], row["side"],
                row["contracts"],   row["signal_time"]
            )
            row.update(update)
            updated = True
            log.info(f"[Paper] RESOLVED {row['market_ticker']} "
                     f"entry={row['entry_price']}c exit={rp}c "
                     f"pnl=${update['hyp_pnl']:+.4f}")
        if updated:
            rewrite_csv(all_rows)

    # ── Generate new signals ──────────────────────────────────────
    try:
        espn_cache.refresh(max_age=50)
        snapshot  = get_live_sports_snapshot()
        watchlist = analyze_snapshot(snapshot)
        open_pos  = {}   # no real positions in paper mode

        for item in watchlist:
            ticker = item["market"].ticker
            if ticker in seen_tickers:
                continue
            for strategy_fn in STRATEGIES:
                try:
                    sig = strategy_fn(item, espn_cache=espn_cache)
                    if sig and sig.action == "buy":
                        log_signal(sig)
                        seen_tickers.add(ticker)
                        break
                except Exception as e:
                    log.debug(f"Strategy error: {e}")

    except Exception as e:
        log.warning(f"Cycle {cycle} error: {e}")

    # Print stats every 10 cycles
    if cycle % 10 == 0:
        print_paper_stats()

    time.sleep(LOOP_SECS)
