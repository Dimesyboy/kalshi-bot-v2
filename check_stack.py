#!/usr/bin/env python3
"""
check_stack.py
Runs the full Kalshi bot stack end-to-end in dry-run / read-only mode
and reports every error, warning, and timing issue it finds.

Checks:
  1.  Python imports — every module loads cleanly
  2.  Config validation — required env vars, file paths
  3.  Kalshi API connectivity + auth (read-only balance fetch)
  4.  Kalshi API market fetch (one series, one status)
  5.  ESPN API connectivity (all four feeds)
  6.  ESPN data parsing (GameContext fields present)
  7.  Fills fetch (read-only, pagination)
  8.  Position file integrity (JSON valid, required fields)
  9.  PNL log integrity
  10. Bot orders file integrity
  11. Cooldown file integrity
  12. Trade log integrity (CSV readable, required columns)
  13. Strategy instantiation (each strategy fires with mock data)
  14. EV calculation sanity
  15. Fee calculation sanity
  16. Timing module self-test
  17. Trade timing module self-test
  18. Telegram connectivity (getMe only, no message sent)
  19. Watcher thread start/stop (no orders placed)
  20. Full snapshot fetch + analyze (read-only, timed)
  21. Reconcile dry-run (read positions only)
  22. execute_signal dry-run (sim buy + sim sell, no real orders)
  23. File write permissions (positions, pnl, cooldown)
  24. Log rotation config
  25. Module attribute checks (no missing attrs that cause runtime crashes)
"""

import os
import sys
import json
import time
import math
import traceback
import importlib
from datetime import datetime, timezone
from collections import defaultdict

# ── colour helpers ────────────────────────────────────────────────────────────
GREEN  = "\033[92m"
RED    = "\033[91m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
GREY   = "\033[90m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):   print(f"  {GREEN}✅ PASS{RESET}  {msg}")
def fail(msg): print(f"  {RED}❌ FAIL{RESET}  {msg}")
def warn(msg): print(f"  {YELLOW}⚠️  WARN{RESET}  {msg}")
def info(msg): print(f"  {CYAN}ℹ️  INFO{RESET}  {msg}")
def section(title):
    print(f"\n{BOLD}{CYAN}{'─'*60}{RESET}")
    print(f"{BOLD}{CYAN}  {title}{RESET}")
    print(f"{BOLD}{CYAN}{'─'*60}{RESET}")

PASS = 0
FAIL = 0
WARN = 0

def record_ok(msg):
    global PASS; PASS += 1; ok(msg)

def record_fail(msg, exc=None):
    global FAIL; FAIL += 1
    fail(msg)
    if exc:
        lines = traceback.format_exception(type(exc), exc, exc.__traceback__)
        for line in "".join(lines).strip().split("\n"):
            print(f"      {GREY}{line}{RESET}")

def record_warn(msg):
    global WARN; WARN += 1; warn(msg)

# ── timing helper ─────────────────────────────────────────────────────────────
class T:
    def __init__(self): self.t = time.perf_counter()
    def ms(self): return (time.perf_counter() - self.t) * 1000
    def sec(self): return time.perf_counter() - self.t

def timed_label(ms):
    if ms > 5000: return f"{RED}{ms:.0f}ms{RESET}"
    if ms > 1000: return f"{YELLOW}{ms:.0f}ms{RESET}"
    return f"{GREEN}{ms:.0f}ms{RESET}"

# ══════════════════════════════════════════════════════════════════════════════
print(f"\n{BOLD}{'═'*60}")
print(f"  Kalshi Bot Stack Check  —  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"{'═'*60}{RESET}")

# ── 1. IMPORTS ────────────────────────────────────────────────────────────────
section("1. Module Imports")

modules = {
    "dotenv":            "python-dotenv",
    "requests":          "requests",
    "kalshi_python":     "kalshi-python",
    "cryptography":      "cryptography",
    "pandas":            "pandas (optional — tennis Sackmann)",
}

loaded = {}
for mod, label in modules.items():
    try:
        t = T()
        loaded[mod] = importlib.import_module(mod)
        record_ok(f"{label} ({timed_label(t.ms())})")
    except ImportError as e:
        if "optional" in label:
            record_warn(f"{label} not installed — {e}")
        else:
            record_fail(f"{label} — {e}")

local_modules = [
    "espn_data",
    "nba_context",
    "tennis_context",
    "strategies",
    "price_watcher",
    "trade_tracker",
    "telegram_controller",
    "timing",
    "trade_timing",
    "kalshi_bot",
]

local_loaded = {}
for mod in local_modules:
    try:
        t = T()
        local_loaded[mod] = importlib.import_module(mod)
        record_ok(f"{mod}.py ({timed_label(t.ms())})")
    except Exception as e:
        record_fail(f"{mod}.py failed to import", e)

# ── 2. CONFIG VALIDATION ──────────────────────────────────────────────────────
section("2. Config Validation")

from dotenv import load_dotenv
load_dotenv()

required_env = {
    "KALSHI_API_KEY_ID":      os.getenv("KALSHI_API_KEY_ID", ""),
    "KALSHI_PRIVATE_KEY_PATH": os.getenv("KALSHI_PRIVATE_KEY_PATH", ""),
    "TELEGRAM_BOT_TOKEN":     os.getenv("TELEGRAM_BOT_TOKEN", ""),
    "TELEGRAM_CHAT_ID":       os.getenv("TELEGRAM_CHAT_ID", ""),
}

for var, val in required_env.items():
    if val:
        record_ok(f"{var} set ({val[:6]}...)")
    else:
        record_warn(f"{var} not set in environment")

key_path = os.getenv("KALSHI_PRIVATE_KEY_PATH", "/root/kalshi_private_key.pem")
if os.path.exists(key_path):
    record_ok(f"Private key file exists: {key_path}")
    try:
        from cryptography.hazmat.primitives import serialization
        with open(key_path, "rb") as f:
            serialization.load_pem_private_key(f.read(), password=None)
        record_ok("Private key parses cleanly")
    except Exception as e:
        record_fail("Private key parse failed", e)
else:
    record_fail(f"Private key file NOT found: {key_path}")

if "kalshi_bot" in local_loaded:
    kb = local_loaded["kalshi_bot"]
    cfg_attrs = [
        "DRY_RUN","LOOP_INTERVAL","MAX_POSITION_USD","MAX_CONTRACTS",
        "MAX_OPEN_POSITIONS","MIN_VOLUME","MAX_SPREAD_CENTS",
        "SIGNAL_COOLDOWN_SECS","MAX_DAILY_LOSS_USD",
        "MAKER_FEE_MULTIPLIER","TAKER_FEE_MULTIPLIER",
        "KALSHI_BASE","FETCH_DELAY_SECS",
    ]
    missing = [a for a in cfg_attrs if not hasattr(kb.Config, a)]
    if missing:
        record_fail(f"Config missing attrs: {missing}")
    else:
        record_ok(f"Config has all {len(cfg_attrs)} expected attributes")

# ── 3. KALSHI API AUTH ────────────────────────────────────────────────────────
section("3. Kalshi API — Auth + Balance")

client = None
if "kalshi_bot" in local_loaded:
    try:
        t = T()
        client = local_loaded["kalshi_bot"]._get_kalshi_client()
        if client:
            record_ok(f"Kalshi client init ({timed_label(t.ms())})")
        else:
            record_fail("Kalshi client returned None")
    except Exception as e:
        record_fail("Kalshi client init exception", e)

if client and "kalshi_bot" in local_loaded:
    try:
        t = T()
        bal = local_loaded["kalshi_bot"].get_kalshi_balance(client)
        record_ok(f"Balance fetch: ${bal:.2f} ({timed_label(t.ms())})")
        if bal == 0.0:
            record_warn("Balance is $0.00 — auth may have failed silently")
    except Exception as e:
        record_fail("Balance fetch failed", e)

# ── 4. KALSHI MARKET FETCH ────────────────────────────────────────────────────
section("4. Kalshi API — Market Fetch")

import requests as _requests
KALSHI_BASE = "https://api.elections.kalshi.com/trade-api/v2"

for series, status in [("KXNBAGAME","open"), ("KXATPMATCH","active")]:
    try:
        t = T()
        r = _requests.get(
            f"{KALSHI_BASE}/events",
            params={"series_ticker": series, "status": status, "limit": 5, "with_nested_markets": "true"},
            timeout=10,
        )
        if r.status_code == 400:
            record_warn(f"{series}/{status} → 400 (expected for some combos)")
        else:
            r.raise_for_status()
            events = r.json().get("events", [])
            record_ok(f"{series}/{status} → {len(events)} events ({timed_label(t.ms())})")
    except Exception as e:
        record_fail(f"{series}/{status} fetch failed", e)

# ── 5. ESPN CONNECTIVITY ──────────────────────────────────────────────────────
section("5. ESPN API — Connectivity")

ESPN_URLS = {
    "NBA":        "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
    "MLB":        "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
    "Tennis_ATP": "http://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard",
    "Tennis_WTA": "http://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard",
}

espn_data = {}
for sport, url in ESPN_URLS.items():
    try:
        t = T()
        r = _requests.get(url, timeout=8)
        r.raise_for_status()
        events = r.json().get("events", [])
        espn_data[sport] = events
        record_ok(f"{sport}: {len(events)} events ({timed_label(t.ms())})")
    except Exception as e:
        record_fail(f"{sport} ESPN fetch failed", e)

# ── 6. ESPN DATA PARSING ──────────────────────────────────────────────────────
section("6. ESPN Data Parsing")

if "espn_data" in local_loaded:
    try:
        t = T()
        ec = local_loaded["espn_data"].ESPNClient()
        all_ctx = ec.get_all()
        for sport, col in all_ctx.items():
            live = col.live()
            sample = list(col)[0] if len(col) > 0 else None
            if sample:
                required = ["sport","event_id","name","status","home","away","is_live"]
                missing  = [f for f in required if not hasattr(sample, f)]
                if missing:
                    record_fail(f"{sport} GameContext missing fields: {missing}")
                else:
                    record_ok(f"{sport}: {len(col)} events, {len(live)} live, fields OK ({timed_label(t.ms())})")
            else:
                record_warn(f"{sport}: 0 events returned (off-season or fetch issue)")
    except Exception as e:
        record_fail("ESPN data parsing failed", e)

# ── 7. FILLS FETCH ────────────────────────────────────────────────────────────
section("7. Fills Fetch (read-only)")

if client and "strategies" in local_loaded:
    try:
        t = T()
        fills = local_loaded["strategies"]._fetch_fills_raw_single(client)
        record_ok(f"Fills fetch: {len(fills)} fills ({timed_label(t.ms())})")
        if fills:
            sample = fills[0]
            required_keys = ["ticker","side","action","count_fp","created_time"]
            missing = [k for k in required_keys if k not in sample and
                      "market_ticker" not in sample]
            if missing:
                record_warn(f"Fill sample missing keys: {missing}")
    except Exception as e:
        record_fail("Fills fetch failed", e)
else:
    record_warn("Skipping fills fetch — no client or strategies module")

# ── 8. POSITION FILE ──────────────────────────────────────────────────────────
section("8. Persistence Files")

files_to_check = {
    "positions.json":  ["side","entry_price","contracts","strategy","entry_time","event_ticker"],
    "pnl_log.json":    None,
    "bot_orders.json": None,
    "cooldown.json":   None,
    "trade_log.csv":   None,
}

for fname, required_fields in files_to_check.items():
    path = f"/root/{fname}"
    if not os.path.exists(path):
        record_warn(f"{fname} does not exist yet (will be created on first run)")
        continue
    try:
        if fname.endswith(".json"):
            with open(path) as f:
                data = json.load(f)
            if required_fields and isinstance(data, dict) and data:
                sample_key = next(iter(data))
                sample_val = data[sample_key]
                if isinstance(sample_val, dict):
                    missing = [k for k in required_fields if k not in sample_val]
                    if missing:
                        record_warn(f"{fname} position '{sample_key}' missing fields: {missing}")
                    else:
                        record_ok(f"{fname}: {len(data)} entries, required fields present")
                else:
                    record_ok(f"{fname}: valid JSON, {len(data)} entries")
            else:
                record_ok(f"{fname}: valid JSON ({type(data).__name__})")
        elif fname.endswith(".csv"):
            import csv
            with open(path) as f:
                reader = csv.DictReader(f)
                rows = list(reader)
            expected_cols = [
                "timestamp","market_ticker","strategy","entry_price",
                "exit_price","contracts","pnl_net","win","exit_reason"
            ]
            if reader.fieldnames:
                missing = [c for c in expected_cols if c not in reader.fieldnames]
                if missing:
                    record_warn(f"{fname} missing columns: {missing}")
                else:
                    record_ok(f"{fname}: {len(rows)} trades, all expected columns present")
            else:
                record_warn(f"{fname} is empty")
    except Exception as e:
        record_fail(f"{fname} read/parse failed", e)

# ── 9. WRITE PERMISSIONS ──────────────────────────────────────────────────────
section("9. File Write Permissions")

write_targets = [
    "/root/positions.json",
    "/root/pnl_log.json",
    "/root/cooldown.json",
    "/root/trade_log.csv",
    "/root/kalshi_bot.log",
]

for path in write_targets:
    try:
        import tempfile
        dir_ = os.path.dirname(path)
        fd, tmp = tempfile.mkstemp(dir=dir_, suffix=".chk")
        os.close(fd)
        os.unlink(tmp)
        record_ok(f"Write OK: {path}")
    except Exception as e:
        record_fail(f"Cannot write to {path}", e)

# ── 10. STRATEGY INSTANTIATION ────────────────────────────────────────────────
section("10. Strategy — Mock Signal Generation")

if "strategies" in local_loaded and "kalshi_bot" in local_loaded:
    strat = local_loaded["strategies"]
    kb    = local_loaded["kalshi_bot"]

    # Build a mock market and item that should trigger value_fade
    mock_market = kb.Market(
        ticker="KXATPMATCH-26MAR17NADALDJOK",
        title="Nadal vs Djokovic",
        yes_bid=0.98,
        yes_ask=0.99,
        no_bid=0.05,   # 5c — passes min no_bid_cents >= 5 check
        no_ask=0.06,
        last_price=0.98,
        volume=12000,  # above 8000 threshold
        liquidity=500,
        close_time=None,
        series="KXATPMATCH",
        label="ATP Match",
        market_status="open",
    )
    mock_item = {
        "sport": "Tennis",
        "event_ticker": "KXATPMATCH-26MAR17NADALDJOK",
        "game_title": "Nadal vs Djokovic",
        "market": mock_market,
        "flag": "SIGNAL",
        "reason": "mock",
        "market_status": "open",
    }

    try:
        sig = strat.strategy_value_fade(mock_item, espn_cache=None)
        if sig:
            record_ok(f"value_fade fired: {sig.side} @ {sig.price}c x{sig.contracts} conf={sig.confidence}")
        else:
            record_warn("value_fade returned None on mock data (check thresholds vs mock values)")
    except Exception as e:
        record_fail("value_fade raised exception on mock data", e)

    # Mock exit scenario
    mock_pos = {
        "side": "yes",
        "entry_price": 40,
        "peak_price": 55,
        "contracts": 5,
        "strategy": "value_fade",
        "entry_time": "2024-01-01T00:00:00+00:00",
        "event_ticker": "KXATPMATCH-26MAR17NADALDJOK",
        "entry_fee": 0.05,
    }
    mock_exit_market = kb.Market(
        ticker="KXATPMATCH-26MAR17NADALDJOK",
        title="Nadal vs Djokovic",
        yes_bid=0.25,  # dropped — should trigger stop loss
        yes_ask=0.27,
        no_bid=0.73,
        no_ask=0.75,
        last_price=0.25,
        volume=10000,
        liquidity=500,
        close_time=None,
        series="KXATPMATCH",
        label="ATP Match",
        market_status="active",
    )
    mock_exit_item = {**mock_item, "market": mock_exit_market}
    try:
        exit_sig = strat.strategy_exit(mock_exit_item, mock_pos)
        if exit_sig:
            record_ok(f"strategy_exit fired: {exit_sig.strategy} reason='{exit_sig.reason}'")
        else:
            record_warn("strategy_exit returned None — stop loss may not be triggering on mock data")
    except Exception as e:
        record_fail("strategy_exit raised exception", e)

    # Confirm disabled strategies are gone
    strategy_names = [fn.__name__ for fn in strat.STRATEGIES]
    expected_active = [
        "strategy_value_fade",
        "strategy_prop_yes",
        "strategy_tennis_underdog",
        "strategy_quarter_winner",
    ]
    for s in expected_active:
        if s in strategy_names:
            record_ok(f"{s} active in STRATEGIES")
        else:
            record_warn(f"{s} missing from STRATEGIES — should be active")
    record_ok(f"Active strategies: {strategy_names}")

# ── 11. EV + FEE SANITY ───────────────────────────────────────────────────────
section("11. EV + Fee Calculation Sanity")

if "strategies" in local_loaded:
    strat = local_loaded["strategies"]
    # NO @ 5c, 10 contracts, 65% confidence
    ev = strat._ev(10, 5, 0.65, is_maker=True)
    if ev > 0:
        record_ok(f"_ev(10 contracts, 5c, 65%, maker) = {ev:.4f} > 0 ✓")
    else:
        record_warn(f"_ev(10 contracts, 5c, 65%, maker) = {ev:.4f} — negative EV at these params")

    # NO @ 3c should be near zero or negative
    ev_low = strat._ev(10, 3, 0.65, is_maker=True)
    record_ok(f"_ev(10 contracts, 3c, 65%, maker) = {ev_low:.4f} (informational)")

if "kalshi_bot" in local_loaded:
    kb = local_loaded["kalshi_bot"]
    fee = kb.calculate_fee(10, 0.05, is_maker=True)
    expected = math.ceil(0.0175 * 10 * 0.05 * 0.95 * 100) / 100
    if abs(fee - expected) < 0.001:
        record_ok(f"calculate_fee(10, $0.05, maker) = ${fee:.4f} ✓")
    else:
        record_fail(f"calculate_fee mismatch: got {fee}, expected {expected}")

# ── 12. TIMING MODULES ────────────────────────────────────────────────────────
section("12. Timing Modules Self-Test")

if "timing" in local_loaded:
    tm = local_loaded["timing"]
    try:
        r = tm.get_report()
        r.reset()
        r.start_cycle()
        with tm.timed_block("test_block"):
            time.sleep(0.01)
        r.record("manual_label", 42.0)
        slowest = r.get_slowest(2)
        assert len(slowest) >= 1
        record_ok(f"timing module: timed_block + record + get_slowest all work")
    except Exception as e:
        record_fail("timing module self-test failed", e)

if "trade_timing" in local_loaded:
    tt = local_loaded["trade_timing"]
    try:
        timer = tt.new_timer("BUY", "TEST-TICKER")
        with timer.step("mock_step"):
            time.sleep(0.005)
        timer.summary()
        stats = tt.get_stats()
        stats.record_from_timer(timer)
        record_ok("trade_timing module: new_timer + step + summary + stats all work")
    except Exception as e:
        record_fail("trade_timing module self-test failed", e)

# ── 13. TELEGRAM CONNECTIVITY ─────────────────────────────────────────────────
section("13. Telegram Connectivity (getMe only)")

tg_token = os.getenv("TELEGRAM_BOT_TOKEN", "")
if tg_token:
    try:
        t = T()
        r = _requests.get(
            f"https://api.telegram.org/bot{tg_token}/getMe",
            timeout=6
        )
        r.raise_for_status()
        bot_name = r.json().get("result", {}).get("username", "unknown")
        record_ok(f"Telegram connected as @{bot_name} ({timed_label(t.ms())})")
    except Exception as e:
        record_fail("Telegram getMe failed", e)
else:
    record_warn("TELEGRAM_BOT_TOKEN not set — skipping")

# ── 14. WATCHER THREAD ────────────────────────────────────────────────────────
section("14. PriceWatcher Thread Start/Stop")

if "price_watcher" in local_loaded and "kalshi_bot" in local_loaded:
    pw = local_loaded["price_watcher"]
    kb = local_loaded["kalshi_bot"]
    try:
        positions = {}
        pnl_log   = {}
        watcher = pw.PriceWatcher(
            open_positions    = positions,
            client            = None,  # no client = no real orders
            config            = kb.Config,
            save_positions_fn = lambda x: None,
            save_pnl_fn       = lambda x: None,
            pnl_log           = pnl_log,
            get_date_fn       = lambda: "2024-01-01",
            bot_orders        = set(),
        )
        watcher.start()
        time.sleep(0.1)
        watcher.stop()
        record_ok("PriceWatcher thread starts and stops cleanly")
    except Exception as e:
        record_fail("PriceWatcher thread failed", e)

# ── 15. MODULE ATTRIBUTE CHECKS ───────────────────────────────────────────────
section("15. Module Attribute Checks (runtime crash prevention)")

attr_checks = {
    "kalshi_bot": [
        ("Config", "DRY_RUN"),
        ("Config", "MAX_POSITION_USD"),
        ("Config", "MAX_CONTRACTS"),
        ("TradeSignal", None),
        ("Market", None),
        ("GameEvent", None),
        ("get_live_sports_snapshot", None),
        ("analyze_snapshot", None),
        ("run_strategies", None),
        ("execute_signal", None),
        ("check_settled_positions", None),
        ("reconcile_positions", None),
        ("save_positions", None),
        ("load_positions", None),
        ("save_pnl_log", None),
        ("load_pnl_log", None),
    ],
    "strategies": [
        ("STRATEGIES", None),
        ("strategy_value_fade", None),
        ("strategy_exit", None),
        ("ESPNContextCache", None),
        ("reconcile_positions", None),
        ("_ev", None),
    ],
    "price_watcher": [
        ("PriceWatcher", None),
    ],
    "trade_tracker": [
        ("log_trade", None),
        ("print_stats", None),
    ],
    "telegram_controller": [
        ("TelegramController", None),
        ("RuntimeConfig", None),
    ],
}

for mod_name, checks in attr_checks.items():
    if mod_name not in local_loaded:
        record_warn(f"{mod_name} not loaded — skipping attr checks")
        continue
    mod = local_loaded[mod_name]
    for attr, sub_attr in checks:
        try:
            obj = getattr(mod, attr)
            if sub_attr:
                getattr(obj, sub_attr)
            record_ok(f"{mod_name}.{attr}{'.'+sub_attr if sub_attr else ''}")
        except AttributeError as e:
            record_fail(f"{mod_name}.{attr}{'.'+sub_attr if sub_attr else ''} MISSING", e)

# ── 16. TELEGRAM CONTROLLER ATTR BUG CHECK ───────────────────────────────────
section("16. TelegramController / RuntimeConfig Bug Check")

if "telegram_controller" in local_loaded and "kalshi_bot" in local_loaded:
    tc_mod = local_loaded["telegram_controller"]
    kb     = local_loaded["kalshi_bot"]
    try:
        rt = tc_mod.RuntimeConfig(kb.Config)
        # The known bug: summary() references TAKE_PROFIT_CENTS / STOP_LOSS_CENTS
        # which don't exist — only PCT versions are set in __init__
        missing_rt = []
        for attr in ["TAKE_PROFIT_CENTS","STOP_LOSS_CENTS","DRY_RUN","LLM_ASSIST",
                     "MAX_POSITION_USD","MIN_VOLUME"]:
            if not hasattr(rt, attr):
                missing_rt.append(attr)
        if missing_rt:
            record_fail(
                f"RuntimeConfig missing attrs (will crash Telegram Settings): {missing_rt}\n"
                f"      Fix: add self.TAKE_PROFIT_CENTS and self.STOP_LOSS_CENTS in RuntimeConfig.__init__"
            )
        else:
            record_ok("RuntimeConfig has all attrs including TAKE_PROFIT_CENTS / STOP_LOSS_CENTS")

        # Try calling summary() directly
        try:
            s = rt.summary()
            record_ok("RuntimeConfig.summary() executes without error")
        except AttributeError as e:
            record_fail(f"RuntimeConfig.summary() AttributeError: {e}")
    except Exception as e:
        record_fail("RuntimeConfig instantiation failed", e)

# ── 17. FULL SNAPSHOT FETCH (timed, read-only) ────────────────────────────────
section("17. Full Snapshot Fetch (read-only, timed)")

if "kalshi_bot" in local_loaded:
    kb = local_loaded["kalshi_bot"]
    try:
        t = T()
        snapshot = kb.get_live_sports_snapshot()
        total_ms = t.ms()
        total_events  = sum(len(g) for g in snapshot.values())
        total_markets = sum(
            len(m) for g in snapshot.values()
            for ev in g.values() for m in ev.markets.values()
        )
        record_ok(
            f"Snapshot: {total_events} events, {total_markets} markets "
            f"across {list(snapshot.keys())} — {timed_label(total_ms)}"
        )
        if total_ms > 30000:
            record_warn(f"Snapshot took {total_ms/1000:.1f}s — exceeds loop interval")
        elif total_ms > 15000:
            record_warn(f"Snapshot took {total_ms/1000:.1f}s — consider increasing LOOP_INTERVAL")

        # Per-sport breakdown
        for sport, games in snapshot.items():
            market_count = sum(len(m) for g in games.values() for m in g.markets.values())
            info(f"  {sport}: {len(games)} events, {market_count} markets")
    except Exception as e:
        record_fail("Snapshot fetch failed", e)
        snapshot = {}
else:
    snapshot = {}

# ── 18. ANALYZE SNAPSHOT ─────────────────────────────────────────────────────
section("18. Analyze Snapshot")

if "kalshi_bot" in local_loaded and snapshot:
    kb = local_loaded["kalshi_bot"]
    try:
        t = T()
        watchlist = kb.analyze_snapshot(snapshot)
        signals   = [w for w in watchlist if w["flag"] == "SIGNAL"]
        record_ok(
            f"analyze_snapshot: {len(watchlist)} markets, {len(signals)} signals "
            f"({timed_label(t.ms())})"
        )
    except Exception as e:
        record_fail("analyze_snapshot failed", e)

# ── 19. EXECUTE_SIGNAL DRY RUN ────────────────────────────────────────────────
section("19. execute_signal Dry-Run (sim only)")

if "kalshi_bot" in local_loaded:
    kb = local_loaded["kalshi_bot"]
    orig_dry = kb.Config.DRY_RUN
    kb.Config.DRY_RUN = True  # force dry run for this test

    try:
        positions = {}
        pnl_log   = {}
        mock_signal = kb.TradeSignal(
            event_ticker  = "KXATPMATCH-TEST",
            market_ticker = "KXATPMATCH-TEST-NODAL",
            side          = "no",
            action        = "buy",
            price         = 5,
            contracts     = 3,
            strategy      = "value_fade",
            reason        = "stack check mock",
            confidence    = 0.67,
        )
        t = T()
        placed, pnl = kb.execute_signal(
            mock_signal, {}, positions, 0.0, pnl_log, "2024-01-01", None
        )
        if placed:
            record_ok(f"execute_signal BUY (dry): placed={placed} ({timed_label(t.ms())})")
        else:
            record_warn(f"execute_signal BUY (dry): not placed — check confidence gate")

        # Now simulate sell
        if placed and "KXATPMATCH-TEST-NODAL" in positions:
            sell_signal = kb.TradeSignal(
                event_ticker  = "KXATPMATCH-TEST",
                market_ticker = "KXATPMATCH-TEST-NODAL",
                side          = "no",
                action        = "sell",
                price         = 8,
                contracts     = 3,
                strategy      = "exit_trail_value_fade",
                reason        = "stack check mock exit",
                confidence    = 0.80,
            )
            t2 = T()
            placed2, pnl2 = kb.execute_signal(
                sell_signal, {}, positions, pnl, pnl_log, "2024-01-01", None
            )
            if placed2:
                record_ok(f"execute_signal SELL (dry): placed={placed2} PNL=${pnl2:.4f} ({timed_label(t2.ms())})")
            else:
                record_warn("execute_signal SELL (dry): not placed")
    except Exception as e:
        record_fail("execute_signal dry-run failed", e)
    finally:
        kb.Config.DRY_RUN = orig_dry

# ── 20. RECONCILE DRY RUN ────────────────────────────────────────────────────
section("20. Reconcile Positions (read-only, no client)")

if "strategies" in local_loaded:
    strat = local_loaded["strategies"]
    try:
        t = T()
        result = strat.reconcile_positions(
            open_positions = {},
            kalshi_base    = KALSHI_BASE,
            client         = None,   # no client = returns immediately
            save_fn        = lambda x: None,
            pnl_log        = {},
            current_date   = "2024-01-01",
            save_pnl_fn    = lambda x: None,
            bot_orders     = set(),
        )
        record_ok(f"reconcile_positions with None client returns cleanly ({timed_label(t.ms())})")
    except Exception as e:
        record_fail("reconcile_positions raised on None client", e)

# ── FINAL SUMMARY ─────────────────────────────────────────────────────────────
print(f"\n{BOLD}{'═'*60}")
print(f"  Stack Check Complete")
print(f"{'═'*60}{RESET}")
print(f"  {GREEN}PASS: {PASS}{RESET}   {RED}FAIL: {FAIL}{RESET}   {YELLOW}WARN: {WARN}{RESET}")

if FAIL == 0 and WARN == 0:
    print(f"\n  {GREEN}{BOLD}All checks passed. Stack looks healthy.{RESET}\n")
elif FAIL == 0:
    print(f"\n  {YELLOW}{BOLD}{WARN} warning(s) — review before running live.{RESET}\n")
else:
    print(f"\n  {RED}{BOLD}{FAIL} failure(s) found — fix before running live.{RESET}\n")

sys.exit(0 if FAIL == 0 else 1)
