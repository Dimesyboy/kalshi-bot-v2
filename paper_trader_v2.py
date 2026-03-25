#!/usr/bin/env python3
"""
paper_trader_v2.py

Tests the new edge_finder strategy specifically.
Logs every signal with:
- true_prob source (sharp book vs empirical)
- edge at entry
- what the market did 90 minutes later (our hold window)
- would TP (+12c) or SL (-6c) have been hit first

This tells us the ACTUAL win rate before we go live.
"""

import os, sys, csv, time, requests, logging
from datetime import datetime, timezone, timedelta
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(
    level   = logging.INFO,
    format  = "%(asctime)s %(message)s",
    handlers= [
        logging.FileHandler("/root/paper_v2.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger("paper_v2")

sys.path.insert(0, '/root')

KALSHI_BASE  = "https://api.elections.kalshi.com/trade-api/v2"
PAPER_FILE   = "/root/paper_trades_v2.csv"
FIELDS = [
    "signal_time", "market_ticker", "strategy", "side",
    "entry_price", "contracts", "true_prob", "kalshi_prob",
    "edge", "kelly", "source", "reason",
    "resolved", "resolve_time", "resolve_price",
    "tp_hit", "sl_hit", "time_hit",
    "outcome", "gross_pnl", "net_pnl",
]

TP_CENTS = 12
SL_CENTS = 6
FEE_CENTS = 4.0   # empirically measured round trip

LOOP_SECS    = 45
RESOLVE_SECS = 90 * 60   # 90 min hold window


def fetch_price_history(ticker: str, side: str,
                         since: datetime) -> list:
    """
    Fetch price snapshots for a ticker since entry.
    Used to determine if TP or SL was hit first.
    """
    prices = []
    try:
        r = requests.get(
            f"{KALSHI_BASE}/markets/{ticker}",
            timeout=6,
        )
        r.raise_for_status()
        m   = r.json().get("market", {})
        key = "no_bid_dollars" if side == "no" else "yes_bid_dollars"
        p   = float(m.get(key, 0) or 0)
        if p > 0:
            prices.append(int(p * 100))
    except:
        pass
    return prices


def simulate_outcome(entry: int, current: int,
                     side: str) -> dict:
    """
    Given entry price and current price, determine outcome.
    For YES positions: profit when price goes up.
    For NO positions:  profit when price goes up (NO bid rises as YES falls).
    Both sides use same logic since we always track the bid of our side.
    """
    move      = current - entry
    tp_hit    = move >= TP_CENTS
    sl_hit    = move <= -SL_CENTS

    if tp_hit:
        gross = TP_CENTS
        outcome = "TP"
    elif sl_hit:
        gross = -SL_CENTS
        outcome = "SL"
    else:
        gross = move
        outcome = "TIME"   # held to 90min without hitting either

    net = gross - FEE_CENTS
    return {
        "tp_hit":    tp_hit,
        "sl_hit":    sl_hit,
        "time_hit":  not (tp_hit or sl_hit),
        "outcome":   outcome,
        "gross_pnl": gross,
        "net_pnl":   net,
    }


def load_rows() -> list:
    if not os.path.exists(PAPER_FILE):
        return []
    with open(PAPER_FILE) as f:
        return list(csv.DictReader(f))


def save_rows(rows: list):
    with open(PAPER_FILE, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


def log_signal(sig, edge_signal):
    rows   = load_rows()
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
            "true_prob":     edge_signal.true_prob,
            "kalshi_prob":   edge_signal.kalshi_prob,
            "edge":          edge_signal.edge,
            "kelly":         edge_signal.kelly,
            "source":        edge_signal.source,
            "reason":        sig.reason,
            "resolved":      "no",
            "resolve_time":  "",
            "resolve_price": "",
            "tp_hit":        "",
            "sl_hit":        "",
            "time_hit":      "",
            "outcome":       "",
            "gross_pnl":     "",
            "net_pnl":       "",
        })
    log.info(f"[Paper] SIGNAL  {sig.market_ticker} {sig.side}@{sig.price}c "
             f"true={edge_signal.true_prob:.3f} edge={edge_signal.edge:+.3f} "
             f"src={edge_signal.source}")


def resolve_pending():
    rows    = load_rows()
    updated = False

    for row in rows:
        if row.get("resolved") == "yes":
            continue
        try:
            st  = datetime.fromisoformat(row["signal_time"])
            if st.tzinfo is None:
                st = st.replace(tzinfo=timezone.utc)
            age = (datetime.now(timezone.utc) - st).total_seconds()
        except:
            continue

        if age < RESOLVE_SECS:
            continue

        # Fetch current price
        try:
            r = requests.get(
                f"{KALSHI_BASE}/markets/{row['market_ticker']}",
                timeout=6,
            )
            r.raise_for_status()
            m   = r.json().get("market", {})
            key = ("no_bid_dollars" if row["side"] == "no"
                   else "yes_bid_dollars")
            rp  = int(float(m.get(key, 0) or 0) * 100)
        except:
            continue

        if rp == 0:
            continue

        result = simulate_outcome(
            int(float(row["entry_price"])), rp, row["side"]
        )
        row.update({
            "resolved":      "yes",
            "resolve_time":  datetime.now(timezone.utc).isoformat(),
            "resolve_price": rp,
            **{k: str(v) for k, v in result.items()},
        })
        updated = True
        log.info(f"[Paper] RESOLVED {row['market_ticker']} "
                 f"entry={row['entry_price']}c exit={rp}c "
                 f"outcome={result['outcome']} net={result['net_pnl']:+.1f}c")

    if updated:
        save_rows(rows)


def print_stats():
    rows     = load_rows()
    resolved = [r for r in rows if r.get("resolved") == "yes"]
    pending  = [r for r in rows if r.get("resolved") != "yes"]

    if not resolved:
        log.info(f"No resolved trades yet. {len(pending)} pending.")
        return

    from collections import defaultdict
    by_source  = defaultdict(lambda: {
        "n":0,"tp":0,"sl":0,"time":0,"net_pnl":0.0,"edges":[]
    })

    for r in resolved:
        src = r.get("source", "unknown")
        d   = by_source[src]
        d["n"] += 1
        try:
            net = float(r.get("net_pnl", 0))
            d["net_pnl"] += net
        except:
            pass
        outcome = r.get("outcome","")
        if outcome == "TP":   d["tp"]   += 1
        if outcome == "SL":   d["sl"]   += 1
        if outcome == "TIME": d["time"] += 1
        try:
            d["edges"].append(float(r.get("edge", 0)))
        except:
            pass

    print(f"\n{'='*65}")
    print(f"  PAPER V2 RESULTS  —  {len(resolved)} resolved / "
          f"{len(pending)} pending")
    print(f"{'='*65}")
    print(f"  {'Source':<25} {'N':>4}  {'TP':>4}  {'SL':>4} "
          f"{'TIME':>5}  {'Win%':>6}  {'Net PNL':>9}  {'Avg edge':>9}")
    print("  " + "-"*60)

    total_n = total_tp = total_net = 0
    for src, d in sorted(by_source.items(),
                          key=lambda x: -x[1]["net_pnl"]):
        n      = d["n"]
        tp     = d["tp"]
        win_pct = tp / n if n else 0
        avg_edge = sum(d["edges"]) / len(d["edges"]) if d["edges"] else 0
        total_n   += n
        total_tp  += tp
        total_net += d["net_pnl"]
        be = 44.4   # our break-even
        flag = "✅" if win_pct*100 > be and d["net_pnl"] > 0 else "❌"
        print(f"  {src:<25} {n:>4}  {tp:>4}  {d['sl']:>4} "
              f"{d['time']:>5}  {win_pct:>5.1%}  "
              f"{d['net_pnl']:>+8.2f}c  {avg_edge:>+8.3f}  {flag}")

    print("  " + "-"*60)
    overall_wp = total_tp/total_n if total_n else 0
    print(f"  {'TOTAL':<25} {total_n:>4}  {total_tp:>4}  "
          f"{'':>4} {'':>5}  {overall_wp:>5.1%}  {total_net:>+8.2f}c")
    print(f"\n  Break-even win rate: 44.4%")
    print(f"  Current win rate:    {overall_wp:.1%}  "
          f"{'✅ ABOVE' if overall_wp > 0.444 else '❌ BELOW'} break-even")
    if total_n >= 20:
        import math
        z = (overall_wp - 0.444) / math.sqrt(0.444 * 0.556 / total_n)
        print(f"  Z-score vs break-even: {z:+.2f}  "
              f"({'significant' if abs(z)>1.645 else 'not yet significant'})")
    print()


# ── Main loop ─────────────────────────────────────────────────────────
if len(sys.argv) > 1 and sys.argv[1] == "--stats":
    print_stats()
    sys.exit(0)

log.info("Paper trader v2 starting — testing edge_finder strategy")
log.info(f"Parameters: TP=+{TP_CENTS}c SL=-{SL_CENTS}c HOLD=90min")
log.info("Logging to paper_trades_v2.csv")

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import ESPNContextCache
from strategy_edge import strategy_prop_edge
from edge_finder import evaluate_kalshi_market

espn_cache   = ESPNContextCache()
seen_tickers = set()
cycle        = 0

while True:
    cycle += 1

    resolve_pending()

    try:
        espn_cache.refresh(max_age=50)
        snapshot  = get_live_sports_snapshot()
        watchlist = analyze_snapshot(snapshot)

        for item in watchlist:
            ticker = item["market"].ticker
            if ticker in seen_tickers:
                continue

            m = item["market"]

            # Run the new strategy
            try:
                sig = strategy_prop_edge(item, espn_cache=espn_cache)
            except Exception as e:
                log.debug(f"strategy error {ticker}: {e}")
                continue

            if sig is None:
                continue

            # Also grab the edge_signal for logging
            from nba_context import parse_prop_ticker
            parsed = parse_prop_ticker(ticker)
            edge_sig = evaluate_kalshi_market(
                ticker      = ticker,
                yes_bid     = m.yes_bid,
                yes_ask     = m.yes_ask,
                player_name = parsed.get("player",""),
                stat        = parsed.get("stat","PTS"),
                threshold   = parsed.get("threshold",0),
                sport       = item.get("sport","NBA"),
            )

            if edge_sig and edge_sig.is_tradeable:
                log_signal(sig, edge_sig)
                seen_tickers.add(ticker)

    except Exception as e:
        log.warning(f"Cycle {cycle} error: {e}")

    if cycle % 20 == 0:
        print_stats()

    time.sleep(LOOP_SECS)
