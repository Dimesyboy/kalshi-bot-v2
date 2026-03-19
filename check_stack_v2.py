#!/usr/bin/env python3
"""
check_stack_v2.py
"""

import os, sys, json, time, math, csv, ast, dis, re, inspect
import threading, traceback, importlib, hashlib, tempfile, shutil, signal
from datetime import datetime, timezone, timedelta
from collections import defaultdict
from pathlib import Path

R="\033[91m"; G="\033[92m"; Y="\033[93m"; C="\033[96m"
B="\033[1m";  D="\033[90m"; RESET="\033[0m"

PASS=0; FAIL=0; WARN=0; INFO_CT=0
_section_fails = []
_current_section = ""

def _record(level, msg, exc=None, detail=None):
    global PASS, FAIL, WARN, INFO_CT, _section_fails
    sym = {"ok": f"{G}✅ PASS{RESET}", "fail": f"{R}❌ FAIL{RESET}",
           "warn": f"{Y}⚠️  WARN{RESET}", "info": f"{C}ℹ️  INFO{RESET}"}[level]
    print(f"  {sym}  {msg}")
    if detail:
        for line in str(detail).strip().split("\n"):
            print(f"         {D}{line}{RESET}")
    if exc:
        tb = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))
        for line in tb.strip().split("\n"):
            print(f"         {D}{line}{RESET}")
    if level == "ok":   PASS += 1
    elif level == "fail":
        FAIL += 1
        _section_fails.append((_current_section, msg))
    elif level == "warn": WARN += 1
    else: INFO_CT += 1

ok   = lambda m, **kw: _record("ok",   m, **kw)
fail = lambda m, **kw: _record("fail", m, **kw)
warn = lambda m, **kw: _record("warn", m, **kw)
info = lambda m, **kw: _record("info", m, **kw)

def section(title):
    global _current_section
    _current_section = title
    print(f"\n{B}{C}{'─'*65}{RESET}")
    print(f"{B}{C}  {title}{RESET}")
    print(f"{B}{C}{'─'*65}{RESET}")

class Timer:
    def __init__(self): self.t = time.perf_counter()
    def ms(self): return (time.perf_counter()-self.t)*1000
    def label(self):
        ms = self.ms()
        if ms > 5000: return f"{R}{ms:.0f}ms{RESET}"
        if ms > 1500: return f"{Y}{ms:.0f}ms{RESET}"
        return f"{G}{ms:.0f}ms{RESET}"

ROOT = Path("/root")
REPO = Path(os.path.dirname(os.path.abspath(__file__)))
if (ROOT / "kalshi_bot.py").exists():
    REPO = ROOT

print(f"\n{B}{'='*65}")
print(f"  Kalshi Bot — Comprehensive Stack Check")
print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} UTC")
print(f"  Repo: {REPO}")
print(f"{'='*65}{RESET}")

# ══════════════════════════════════════════════════════════════════════════════
section("§1  Python Environment")
# ══════════════════════════════════════════════════════════════════════════════

major, minor = sys.version_info[:2]
if major == 3 and minor >= 9:
    ok(f"Python {sys.version.split()[0]} (>=3.9 required)")
else:
    fail(f"Python {sys.version.split()[0]} — need >=3.9")

for pkg, pip_name in [
    ("dotenv",        "python-dotenv"),
    ("requests",      "requests"),
    ("kalshi_python", "kalshi-python"),
    ("cryptography",  "cryptography"),
    ("openai",        "openai (optional LLM)"),
]:
    optional = "optional" in pip_name
    try:
        t = Timer()
        importlib.import_module(pkg)
        ok(f"{pip_name}  ({t.label()})")
    except ImportError as e:
        (warn if optional else fail)(f"{pip_name} not importable: {e}")

try:
    import requests as _req
    v = tuple(int(x) for x in _req.__version__.split(".")[:2])
    if v < (2, 28):
        warn(f"requests {_req.__version__} — upgrade to >=2.28")
    else:
        ok(f"requests version {_req.__version__} OK")
except: pass

# ══════════════════════════════════════════════════════════════════════════════
section("§2  Local Module Imports & Syntax")
# ══════════════════════════════════════════════════════════════════════════════

sys.path.insert(0, str(REPO))

LOCAL_MODULES = [
    "kalshi_bot", "strategies", "price_watcher", "trade_tracker",
    "telegram_controller", "timing", "trade_timing", "nba_context",
    "nba_props", "mlb_props", "tennis_context", "espn_data", "espn_module",
    "morning_report", "sports_snapshot", "nba_injuries",
]

_mods = {}
for mod in LOCAL_MODULES:
    src = REPO / f"{mod}.py"
    if not src.exists():
        warn(f"{mod}.py not found in repo")
        continue
    try:
        source = src.read_text(encoding="utf-8")
        ast.parse(source, filename=str(src))
    except SyntaxError as e:
        fail(f"{mod}.py syntax error at line {e.lineno}: {e.msg}")
        continue
    try:
        t = Timer()
        _mods[mod] = importlib.import_module(mod)
        ok(f"{mod}.py  ({t.label()})")
    except Exception as e:
        fail(f"{mod}.py import failed", exc=e)

bot_py = REPO / "bot.py"
if bot_py.exists():
    size = bot_py.stat().st_size
    if size == 0:
        fail("bot.py is empty (0 bytes) — entrypoint is non-functional")
    else:
        ok(f"bot.py has content ({size} bytes)")
else:
    warn("bot.py not found")

# ══════════════════════════════════════════════════════════════════════════════
section("§3  Environment Variables & Secrets")
# ══════════════════════════════════════════════════════════════════════════════

from dotenv import load_dotenv
load_dotenv(REPO / ".env", override=False)
load_dotenv(ROOT / ".env", override=False)

ENV_VARS = {
    "KALSHI_API_KEY_ID":       ("required", r"^[a-zA-Z0-9_\-]{8,}$"),
    "KALSHI_PRIVATE_KEY_PATH": ("required", None),
    "TELEGRAM_BOT_TOKEN":      ("required", r"^\d+:[A-Za-z0-9_\-]{35,}$"),
    "TELEGRAM_CHAT_ID":        ("required", r"^-?\d+$"),
    "OPENAI_API_KEY":          ("optional", r"^sk-"),
}

for var, (level, pattern) in ENV_VARS.items():
    val = os.getenv(var, "")
    if not val:
        (warn if level == "optional" else fail)(f"{var} not set")
        continue
    masked = val[:6] + "***"
    if pattern and not re.match(pattern, val):
        warn(f"{var} set but format looks wrong ({masked})")
    else:
        ok(f"{var} set ({masked})")

key_path = os.getenv("KALSHI_PRIVATE_KEY_PATH", str(ROOT / "kalshi_private_key.pem"))
kp = Path(key_path)
if not kp.exists():
    fail(f"Private key file not found: {key_path}")
else:
    try:
        from cryptography.hazmat.primitives import serialization
        with open(kp, "rb") as f:
            pem = f.read()
        key = serialization.load_pem_private_key(pem, password=None)
        ok(f"Private key loads cleanly ({type(key).__name__})")
        mode = oct(kp.stat().st_mode)[-3:]
        if mode[-1] != "0":
            warn(f"Private key permissions {mode} — other-readable, consider chmod 600")
        else:
            ok(f"Private key permissions {mode} (not world-readable)")
    except Exception as e:
        fail(f"Private key parse failed: {e}")

env_file = REPO / ".env"
if env_file.exists():
    warn(".env file exists in repo directory — ensure it is in .gitignore")
gitignore = REPO / ".gitignore"
if gitignore.exists():
    gi_content = gitignore.read_text()
    if ".env" not in gi_content:
        warn(".gitignore exists but does not contain .env")
    else:
        ok(".gitignore contains .env")
else:
    warn("No .gitignore found — secrets may be committed")

# ══════════════════════════════════════════════════════════════════════════════
section("§4  Config Object — Completeness & Logic Sanity")
# ══════════════════════════════════════════════════════════════════════════════

if "kalshi_bot" in _mods:
    kb = _mods["kalshi_bot"]
    cfg = kb.Config

    required_attrs = [
        "DRY_RUN","LOOP_INTERVAL","LOG_FILE","PNL_LOG_FILE",
        "ENABLE_NBA","ENABLE_TENNIS","ENABLE_MLB",
        "LLM_ASSIST","LLM_MODEL","LLM_CONFIDENCE_THRESHOLD",
        "MIN_VOLUME","MAX_SPREAD_CENTS","MIN_LIQUIDITY",
        "MAX_POSITION_USD","MAX_OPEN_POSITIONS","POSITION_SIZE_PCT",
        "MAX_POSITION_HARD","MAX_OPEN_HARD","MAX_CONTRACTS","MIN_NO_PRICE",
        "MAX_CONTRACTS_PER_EVENT","TAKE_PROFIT_PCT","STOP_LOSS_PCT",
        "SLIP_CENTS","MAX_DAILY_LOSS_USD","POSITION_MAX_AGE_HOURS",
        "SETTLE_MIN_AGE_MINUTES","SIGNAL_COOLDOWN_SECS",
        "TAKER_FEE_MULTIPLIER","MAKER_FEE_MULTIPLIER",
        "KALSHI_BASE","KALSHI_KEY_ID","KALSHI_KEY_FILE",
        "FETCH_DELAY_SECS","LOG_MAX_BYTES","LOG_BACKUP_COUNT",
        "TELEGRAM_TOKEN","TELEGRAM_CHAT","OPENAI_KEY",
    ]
    missing = [a for a in required_attrs if not hasattr(cfg, a)]
    if missing:
        fail(f"Config missing {len(missing)} attrs: {missing}")
    else:
        ok(f"Config has all {len(required_attrs)} expected attributes")

    logic_checks = [
        (cfg.TAKE_PROFIT_PCT > cfg.STOP_LOSS_PCT,
         f"TAKE_PROFIT_PCT ({cfg.TAKE_PROFIT_PCT}) > STOP_LOSS_PCT ({cfg.STOP_LOSS_PCT}) — stops out before profit"),
        (0 < cfg.POSITION_SIZE_PCT < 0.25,
         f"POSITION_SIZE_PCT={cfg.POSITION_SIZE_PCT} outside reasonable range 0.01-0.25"),
        (cfg.MAX_POSITION_HARD <= 50,
         f"MAX_POSITION_HARD=${cfg.MAX_POSITION_HARD} seems high for small-balance bot"),
        (cfg.LOOP_INTERVAL >= 30,
         f"LOOP_INTERVAL={cfg.LOOP_INTERVAL}s — very fast loops risk 429 rate limiting"),
        (cfg.TAKER_FEE_MULTIPLIER != 0.07,
         f"TAKER_FEE_MULTIPLIER={cfg.TAKER_FEE_MULTIPLIER} (Kalshi=7% — verify current)"),
        (cfg.MAKER_FEE_MULTIPLIER != 0.0175,
         f"MAKER_FEE_MULTIPLIER={cfg.MAKER_FEE_MULTIPLIER} (Kalshi=1.75% — verify current)"),
        (cfg.MAX_DAILY_LOSS_USD >= 999998,
         f"MAX_DAILY_LOSS_USD={cfg.MAX_DAILY_LOSS_USD} — daily loss limit is effectively OFF"),
        (cfg.MIN_NO_PRICE < 3,
         f"MIN_NO_PRICE={cfg.MIN_NO_PRICE}c — near-zero payout after fees"),
        (cfg.SIGNAL_COOLDOWN_SECS < 300,
         f"SIGNAL_COOLDOWN_SECS={cfg.SIGNAL_COOLDOWN_SECS} — in-memory only, lost on restart"),
    ]
    for is_warn, message in logic_checks:
        (warn if is_warn else ok)(message)

    if cfg.DRY_RUN:
        warn("DRY_RUN=True — bot will NOT place real orders")
    else:
        ok("DRY_RUN=False — LIVE mode")

# ══════════════════════════════════════════════════════════════════════════════
section("§5  Kalshi API — Auth, Balance, Connectivity")
# ══════════════════════════════════════════════════════════════════════════════

import requests as _req

client = None
if "kalshi_bot" in _mods:
    try:
        t = Timer()
        client = _mods["kalshi_bot"]._get_kalshi_client()
        if client:
            ok(f"Kalshi SDK client init ({t.label()})")
        else:
            fail("Kalshi client returned None")
    except Exception as e:
        fail("Kalshi client init raised", exc=e)

if client and "kalshi_bot" in _mods:
    try:
        t = Timer()
        bal = _mods["kalshi_bot"].get_kalshi_balance(client)
        if bal > 0:
            ok(f"Balance fetch: ${bal:.2f}  ({t.label()})")
        else:
            warn(f"Balance returned $0.00 in {t.label()} — auth failure or empty account")
        if bal < 10:
            warn(f"Balance ${bal:.2f} is very low — dynamic sizing will hit minimums")
    except Exception as e:
        fail("Balance fetch failed", exc=e)

KALSHI_BASE = "https://api.elections.kalshi.com/trade-api/v2"
try:
    t = Timer()
    r = _req.get(f"{KALSHI_BASE}/exchange/status", timeout=8)
    if r.ok:
        status = r.json().get("exchange_active", "unknown")
        ok(f"Exchange status reachable — active={status}  ({t.label()})")
    else:
        warn(f"Exchange status returned HTTP {r.status_code}")
except Exception as e:
    fail(f"Exchange status unreachable: {e}")

for series, sport in [("KXNBAGAME","NBA"), ("KXATPMATCH","Tennis"), ("KXMLBGAME","MLB")]:
    for mstatus in ["open", "active"]:
        try:
            t = Timer()
            r = _req.get(f"{KALSHI_BASE}/markets",
                         params={"series_ticker": series, "status": mstatus, "limit": 5},
                         timeout=10)
            if r.status_code == 400:
                warn(f"{series}/{mstatus} -> 400 (off-season or unsupported combo)")
            elif r.ok:
                n = len(r.json().get("markets", []))
                ok(f"{sport} {series}/{mstatus} -> {n} markets  ({t.label()})")
            else:
                warn(f"{series}/{mstatus} -> HTTP {r.status_code}")
        except Exception as e:
            fail(f"{series}/{mstatus} fetch raised: {e}")

try:
    r1 = _req.get(f"{KALSHI_BASE}/markets", params={"series_ticker":"KXNBAGAME","limit":1}, timeout=5)
    r2 = _req.get(f"{KALSHI_BASE}/markets", params={"series_ticker":"KXNBAGAME","limit":1}, timeout=5)
    if r2.status_code == 429:
        fail("429 on back-to-back calls — FETCH_DELAY_SECS too low")
    else:
        ok("Back-to-back rapid requests did not 429")
except Exception as e:
    warn(f"Rate limit probe failed: {e}")

# ══════════════════════════════════════════════════════════════════════════════
section("§6  ESPN & External Context Data Sources")
# ══════════════════════════════════════════════════════════════════════════════

ESPN_FEEDS = {
    "NBA":        "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
    "MLB":        "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
    "Tennis_ATP": "http://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard",
    "Tennis_WTA": "http://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard",
}
for sport, url in ESPN_FEEDS.items():
    try:
        t = Timer()
        r = _req.get(url, timeout=8)
        r.raise_for_status()
        events = r.json().get("events", [])
        ok(f"{sport}: {len(events)} events  ({t.label()})")
        if events:
            e0 = events[0]
            for field in ["id", "name", "status", "competitions"]:
                if field not in e0:
                    warn(f"{sport} event missing field '{field}' — parser may break")
    except Exception as e:
        fail(f"{sport} ESPN unreachable: {e}")

if "espn_data" in _mods:
    try:
        t = Timer()
        ec = _mods["espn_data"].ESPNClient()
        all_ctx = ec.get_all()
        for sport, col in all_ctx.items():
            live = col.live() if col else []
            if col and len(col) > 0:
                sample = list(col)[0]
                missing_fields = [f for f in
                    ["sport","event_id","name","status","home","away","is_live"]
                    if not hasattr(sample, f)]
                if missing_fields:
                    warn(f"ESPNClient {sport} GameContext missing: {missing_fields}")
                else:
                    ok(f"ESPNClient {sport}: {len(col)} events, {len(live)} live  ({t.label()})")
            else:
                warn(f"ESPNClient {sport}: 0 events (off-season or fetch issue)")
    except Exception as e:
        fail("ESPNClient.get_all() raised", exc=e)

# ══════════════════════════════════════════════════════════════════════════════
section("§7  Persistence Files — Integrity & Schema")
# ══════════════════════════════════════════════════════════════════════════════

PERSIST_FILES = {
    "positions.json": {
        "type": "dict_of_dicts",
        "required_value_keys": ["side","entry_price","contracts","strategy",
                                "entry_time","event_ticker","entry_fee"],
    },
    "pnl_log.json":   {"type": "dict", "key_pattern": r"^\d{4}-\d{2}-\d{2}$"},
    "bot_orders.json":{"type": "list"},
    "cooldown.json":  {"type": "dict"},
    "trade_log.csv":  {
        "type": "csv",
        "required_cols": ["timestamp","strategy","market_ticker","event_ticker",
                          "side","contracts","entry_price","exit_price","pnl"],
    },
}

for fname, schema in PERSIST_FILES.items():
    path = REPO / fname
    if not path.exists():
        info(f"{fname} does not exist yet (created on first run)")
        continue
    size = path.stat().st_size
    try:
        if schema["type"] in ("dict","dict_of_dicts","list"):
            with open(path) as f:
                data = json.load(f)
            expected_type = list if schema["type"] == "list" else dict
            if not isinstance(data, expected_type):
                fail(f"{fname}: expected {expected_type.__name__}, got {type(data).__name__}")
                continue
            if "key_pattern" in schema and isinstance(data, dict):
                bad_keys = [k for k in data if not re.match(schema["key_pattern"], str(k))]
                if bad_keys:
                    warn(f"{fname}: {len(bad_keys)} keys don't match pattern: {bad_keys[:3]}")
                else:
                    ok(f"{fname}: {len(data)} entries, keys match schema  ({size}B)")
            elif "required_value_keys" in schema and isinstance(data, dict) and data:
                sample_key = next(iter(data))
                sample_val = data[sample_key]
                if isinstance(sample_val, dict):
                    missing = [k for k in schema["required_value_keys"] if k not in sample_val]
                    if missing:
                        warn(f"{fname} entry '{sample_key}' missing fields: {missing}")
                    else:
                        ok(f"{fname}: {len(data)} positions, schema OK  ({size}B)")
                now_utc = datetime.now(timezone.utc)
                stale = []
                for ticker, pos in data.items():
                    et = pos.get("entry_time","")
                    if et:
                        try:
                            dt = datetime.fromisoformat(et)
                            if dt.tzinfo is None: dt = dt.replace(tzinfo=timezone.utc)
                            age_h = (now_utc - dt).total_seconds()/3600
                            if age_h > 8:
                                stale.append((ticker, f"{age_h:.1f}h"))
                        except: pass
                if stale:
                    warn(f"{fname}: {len(stale)} stale positions (>8h): {stale[:3]}")
                else:
                    ok(f"{fname}: no stale positions")
            else:
                ok(f"{fname}: valid JSON  ({size}B)")
        elif schema["type"] == "csv":
            with open(path) as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                cols = reader.fieldnames or []
            missing_cols = [c for c in schema["required_cols"] if c not in cols]
            if missing_cols:
                warn(f"{fname}: missing columns {missing_cols}")
            else:
                ok(f"{fname}: {len(rows)} rows, required columns present  ({size}B)")
            bad_pnl = [r for r in rows if r.get("pnl","") in ("","None","null")]
            if bad_pnl:
                warn(f"{fname}: {len(bad_pnl)} rows with missing pnl value")
    except json.JSONDecodeError as e:
        fail(f"{fname}: JSON parse error — {e}")
    except Exception as e:
        fail(f"{fname}: read/parse error", exc=e)

bot_orders_path = REPO / "bot_orders.json"
if bot_orders_path.exists():
    try:
        orders = json.loads(bot_orders_path.read_text())
        if len(orders) != len(set(orders)):
            warn(f"bot_orders.json has {len(orders)-len(set(orders))} duplicate order IDs")
        else:
            ok(f"bot_orders.json: {len(orders)} unique order IDs")
    except: pass

# ══════════════════════════════════════════════════════════════════════════════
section("§8  Filesystem — Permissions, Disk, Log Rotation")
# ══════════════════════════════════════════════════════════════════════════════

write_targets = [
    REPO / "positions.json", REPO / "pnl_log.json",
    REPO / "bot_orders.json", REPO / "cooldown.json",
    REPO / "trade_log.csv",  REPO / "kalshi_bot.log",
]
for path in write_targets:
    try:
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".chk")
        os.close(fd); os.unlink(tmp)
        ok(f"Write OK: {path.name}")
    except Exception as e:
        fail(f"Cannot write to {path}: {e}")

try:
    usage = shutil.disk_usage(str(REPO))
    free_mb = usage.free / (1024*1024)
    if free_mb < 100:
        fail(f"Disk space critically low: {free_mb:.0f}MB free")
    elif free_mb < 500:
        warn(f"Disk space low: {free_mb:.0f}MB free")
    else:
        ok(f"Disk space: {free_mb:.0f}MB free")
except Exception as e:
    warn(f"Disk space check failed: {e}")

log_path = REPO / "kalshi_bot.log"
if log_path.exists():
    log_mb = log_path.stat().st_size / (1024*1024)
    if log_mb > 50:
        warn(f"Log file {log_mb:.1f}MB — rotation may not be working")
    else:
        ok(f"Log file {log_mb:.2f}MB")
    try:
        lines = log_path.read_text(errors="replace").splitlines()
        recent = lines[-200:] if len(lines) > 200 else lines
        errors = [l for l in recent if "[ERROR]" in l or "Traceback" in l]
        if errors:
            warn(f"Last 200 log lines: {len(errors)} ERROR/Traceback entries")
            for e in errors[-3:]:
                info(f"  {e[:120]}")
        else:
            ok("Last 200 log lines: no ERRORs or Tracebacks")
    except: pass

# ══════════════════════════════════════════════════════════════════════════════
section("§9  Threading — Race Conditions & Lock Coverage")
# ══════════════════════════════════════════════════════════════════════════════

if "price_watcher" in _mods and "kalshi_bot" in _mods:
    pw = _mods["price_watcher"]
    kb = _mods["kalshi_bot"]

    shared_positions = {}

    def _race_writer():
        for i in range(20):
            shared_positions[f"TICKER-{i}"] = {
                "entry_price": i, "contracts": 1, "side": "yes",
                "strategy": "test",
                "entry_time": datetime.now(timezone.utc).isoformat(),
                "event_ticker": "TEST", "entry_fee": 0.0,
                "peak_price": i, "last_bid": i,
            }
            time.sleep(0.005)
            if i % 3 == 0 and f"TICKER-{i}" in shared_positions:
                del shared_positions[f"TICKER-{i}"]

    try:
        watcher = pw.PriceWatcher(
            open_positions=shared_positions, client=None,
            config=kb.Config,
            save_positions_fn=lambda x: None,
            save_pnl_fn=lambda x: None,
            pnl_log={},
            get_date_fn=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            bot_orders=set(),
        )
        watcher.start()
        t = threading.Thread(target=_race_writer)
        t.start(); t.join(timeout=0.5)
        watcher.stop()
        watcher._thread.join(timeout=1.0)
        ok("PriceWatcher starts, handles concurrent writes, stops cleanly")
    except Exception as e:
        fail("PriceWatcher threading test raised", exc=e)

    pw_src = (REPO / "price_watcher.py").read_text()
    if "_exiting" in pw_src:
        ok("_exiting guard present in PriceWatcher")
    else:
        fail("_exiting guard missing — duplicate exit orders possible")

    main_src = (REPO / "kalshi_bot.py").read_text()
    if "_exiting" in main_src:
        warn("kalshi_bot.py references _exiting — verify main loop consults watcher set before sells")
    else:
        warn("kalshi_bot.py does NOT check watcher._exiting — duplicate sell orders between main loop and watcher possible")

# ══════════════════════════════════════════════════════════════════════════════
section("§10  Strategy — Signal Logic, EV & Edge Validation")
# ══════════════════════════════════════════════════════════════════════════════

if "strategies" in _mods and "kalshi_bot" in _mods:
    strat = _mods["strategies"]
    kb    = _mods["kalshi_bot"]

    ev_tests = [
        (10,  5, 0.65, True,  True),   # 65% conf NO@5c — strongly +EV
        (10,  5, 0.04, True,  False),  # 4% conf NO@5c — below break-even
        (10, 50, 0.65, True,  True),   # 65% conf @50c — +EV
        (10, 50, 0.48, True,  False),  # 48% conf @50c — -EV
        (1,   5, 0.65, True,  True),   # single contract +EV
        (10, 50, 0.50, True,  False),  # exactly 50% @50c — slightly -EV after fees
    ]
    ev_ok = 0
    for contracts, price_c, conf, is_maker, expect_pos in ev_tests:
        try:
            ev = strat._ev(contracts, price_c, conf, is_maker=is_maker)
            actual_pos = ev > 0
            status = actual_pos == expect_pos
            (ok if status else warn)(
                f"_ev({contracts}c, {price_c}ct, {conf}, maker={is_maker}) = {ev:.4f} "
                f"({'positive' if actual_pos else 'negative'}, {'expected' if status else 'UNEXPECTED'})")
            if status: ev_ok += 1
        except Exception as e:
            fail(f"_ev raised on ({contracts}, {price_c}, {conf})", exc=e)
    if ev_ok < len(ev_tests):
        warn(f"EV formula: {ev_ok}/{len(ev_tests)} test cases matched expectations")

    try:
        fee = kb.calculate_fee(10, 0.05, is_maker=True)
        expected = math.ceil(0.0175 * 10 * 0.05 * 0.95 * 100) / 100.0
        if abs(fee - expected) < 0.001:
            ok(f"calculate_fee(10, $0.05, maker) = ${fee:.4f} matches formula")
        else:
            fail(f"calculate_fee mismatch: got ${fee:.4f}, formula gives ${expected:.4f}")
    except Exception as e:
        fail("calculate_fee raised", exc=e)

    mock_market_fade = kb.Market(
        ticker="KXATPMATCH-26MAR17NADALDJOK-DJOK",
        title="Djokovic wins", yes_bid=0.97, yes_ask=0.98,
        no_bid=0.05, no_ask=0.06, last_price=0.97,
        volume=12000, liquidity=500, close_time=None,
        series="KXATPMATCH", label="ATP Match", market_status="open",
    )
    mock_item_fade = {
        "sport":"Tennis","event_ticker":"KXATPMATCH-26MAR17NADALDJOK",
        "game_title":"Nadal v Djokovic","market":mock_market_fade,
        "flag":"SIGNAL","reason":"mock","market_status":"open",
    }
    try:
        sig = strat.strategy_value_fade(mock_item_fade, espn_cache=None)
        if sig:
            ok(f"value_fade fires: {sig.side} @ {sig.price}ct x{sig.contracts} conf={sig.confidence}")
            if sig.price < 3:
                warn(f"value_fade signal price {sig.price}ct — near-zero payout after fees")
        else:
            warn("value_fade returned None on 97c mock — threshold may have drifted")
    except Exception as e:
        fail("value_fade raised on mock", exc=e)

    mock_pos_exit = {
        "side":"yes","entry_price":70,"peak_price":70,"contracts":5,
        "strategy":"prop_yes","entry_time":"2024-01-01T00:00:00+00:00",
        "event_ticker":"KXNBAPTS-TEST","entry_fee":0.05,
    }
    mock_market_exit = kb.Market(
        ticker="KXNBAPTS-TEST-LEBRON-25", title="LeBron 25+ pts",
        yes_bid=0.40, yes_ask=0.42, no_bid=0.58, no_ask=0.60,
        last_price=0.40, volume=8000, liquidity=500,
        close_time=None, series="KXNBAPTS", label="Player Points",
        market_status="active",
    )
    mock_item_exit = {
        "sport":"NBA","event_ticker":"KXNBAPTS-TEST",
        "game_title":"Mock Game","market":mock_market_exit,
        "flag":"SIGNAL","reason":"mock","market_status":"active",
    }
    try:
        exit_sig = strat.strategy_exit(mock_item_exit, mock_pos_exit)
        if exit_sig:
            ok(f"strategy_exit fires stop loss: {exit_sig.strategy}")
        else:
            warn("strategy_exit returned None — stop loss not triggering on 70->40c drop")
    except Exception as e:
        fail("strategy_exit raised on mock", exc=e)

    mock_pos_no = dict(mock_pos_exit, side="no")
    try:
        no_exit = strat.strategy_exit(mock_item_exit, mock_pos_no)
        if no_exit is None:
            ok("strategy_exit correctly returns None for NO positions (settle naturally)")
        else:
            warn("strategy_exit attempting to exit NO position — verify intentional")
    except Exception as e:
        fail("strategy_exit raised on NO mock", exc=e)

    try:
        c60 = strat._scale_contracts(10, 0.60)
        c70 = strat._scale_contracts(10, 0.70)
        c80 = strat._scale_contracts(10, 0.80)
        if c60 <= c70 <= c80:
            ok(f"_scale_contracts monotonic: 0.60->{c60}, 0.70->{c70}, 0.80->{c80}")
        else:
            warn(f"_scale_contracts non-monotonic: {c60}, {c70}, {c80}")
    except Exception as e:
        warn(f"_scale_contracts check failed: {e}")

    try:
        blocked = strat._allowed("KXPOLITICS-2024USELEC-DEM")
        if not blocked:
            ok("_allowed() correctly blocks non-sports ticker")
        else:
            fail("_allowed() passed a non-sports ticker — strategy gate broken")
    except Exception as e:
        warn(f"_allowed() check failed: {e}")

    trade_log = REPO / "trade_log.csv"
    if trade_log.exists():
        try:
            with open(trade_log) as f:
                rows = list(csv.DictReader(f))
            if len(rows) >= 10:
                by_strategy = defaultdict(list)
                for row in rows:
                    try:
                        pnl = float(row.get("pnl") or 0)
                        by_strategy[row.get("strategy","unknown")].append(pnl)
                    except: pass
                for sname, pnls in sorted(by_strategy.items()):
                    if len(pnls) < 5: continue
                    wins = sum(1 for p in pnls if p > 0)
                    wr = wins/len(pnls)
                    total = sum(pnls)
                    (ok if wr > 0.52 and total > 0 else warn)(
                        f"Strategy '{sname}': {len(pnls)} trades, "
                        f"win={wr:.0%}, total=${total:.2f}")
            else:
                info(f"trade_log.csv has {len(rows)} rows — need >=10 for strategy analysis")
        except Exception as e:
            warn(f"trade_log strategy analysis failed: {e}")

# ══════════════════════════════════════════════════════════════════════════════
section("§11  Fills Reconciliation — Fetch & Integrity")
# ══════════════════════════════════════════════════════════════════════════════

if client and "strategies" in _mods:
    try:
        t = Timer()
        fills = _mods["strategies"]._fetch_fills_raw_single(client)
        ok(f"fills fetch: {len(fills)} fills  ({t.label()})")
        if fills:
            f0 = fills[0]
            expected_keys = ["ticker","side","action","count_fp","created_time"]
            actual_keys = list(f0.keys())
            missing = [k for k in expected_keys
                       if k not in actual_keys and "market_ticker" not in actual_keys]
            if missing:
                warn(f"Fill record missing keys: {missing}  (got: {actual_keys[:8]})")
            else:
                ok("Fill record has expected fields")
            zero_fills = [f for f in fills if float(f.get("count_fp",1) or 1) == 0]
            if zero_fills:
                warn(f"{len(zero_fills)} fills with count_fp=0 — corrupts position counting")
            else:
                ok("No zero-count fills")
            times = [f.get("created_time","") for f in fills if f.get("created_time")]
            if times == sorted(times):
                ok("Fills are time-ordered ascending")
            elif times == sorted(times, reverse=True):
                warn("Fills are reverse time-ordered — reconcile sort logic needs check")
            else:
                warn("Fills are NOT time-ordered — avg_entry calculation may be wrong")
    except Exception as e:
        fail("fills fetch raised", exc=e)
else:
    warn("Skipping fills test — no client or strategies module")

if "strategies" in _mods:
    src = (REPO / "strategies.py").read_text()
    if "urllib3.PoolManager.urlopen" in src:
        warn("strategies.py monkey-patches urllib3.PoolManager.urlopen — fragile, not thread-safe")
    if "urlopen=orig" in src or "urlopen = orig" in src:
        ok("urllib3 patch is restored in finally block")
    else:
        fail("urllib3 monkey-patch may not be restored on exception — permanent transport corruption possible")

# ══════════════════════════════════════════════════════════════════════════════
section("§12  Circular Imports & Module Coupling")
# ══════════════════════════════════════════════════════════════════════════════

if (REPO / "strategies.py").exists():
    src = (REPO / "strategies.py").read_text()
    inside_def = re.findall(r'(?m)^\s+from kalshi_bot import', src)
    if inside_def:
        warn(f"strategies.py has {len(inside_def)} deferred 'from kalshi_bot import' inside functions — circular import risk on reload")
    else:
        ok("strategies.py has no deferred kalshi_bot imports")

if (REPO / "kalshi_bot.py").exists():
    src = (REPO / "kalshi_bot.py").read_text()
    if re.search(r'^from strategies import', src, re.MULTILINE):
        warn("kalshi_bot.py top-level imports strategies while strategies.py imports kalshi_bot inside functions — circular dependency")
    else:
        ok("No circular top-level import detected")
    dupes = src.count("_bot_orders: set = set()")
    if dupes > 1:
        fail(f"kalshi_bot.py: '_bot_orders: set = set()' declared {dupes}x — duplicate global")
    else:
        ok("No duplicate global declarations found")

if (REPO / "telegram_controller.py").exists():
    src = (REPO / "telegram_controller.py").read_text()
    if "import kalshi_bot" in src and "kalshi_bot.Config" in src:
        warn("telegram_controller.py mutates kalshi_bot.Config at runtime — no lock around concurrent config reads")

patch_file = REPO / "integration_patch.py"
if patch_file.exists():
    content = patch_file.read_text().strip()
    if content:
        warn("integration_patch.py is non-empty — indicates manual copy-paste patching workflow, not clean module design")

# ══════════════════════════════════════════════════════════════════════════════
section("§13  execute_signal — Gate, Order Path, Crash Safety")
# ══════════════════════════════════════════════════════════════════════════════

if "kalshi_bot" in _mods:
    kb = _mods["kalshi_bot"]
    orig_dry = kb.Config.DRY_RUN
    kb.Config.DRY_RUN = True

    try:
        positions = {}; pnl_log = {}
        sig_buy = kb.TradeSignal(
            event_ticker="KXATPMATCH-TEST",
            market_ticker="KXATPMATCH-TEST-NODAL",
            side="no", action="buy", price=5, contracts=3,
            strategy="value_fade", reason="stack_check", confidence=0.67,
        )
        t = Timer()
        placed, pnl = kb.execute_signal(sig_buy, {}, positions, 0.0, pnl_log, "2024-01-01", None)
        if placed:
            ok(f"execute_signal BUY dry-run: placed  ({t.label()})")
            if "KXATPMATCH-TEST-NODAL" in positions:
                pos = positions["KXATPMATCH-TEST-NODAL"]
                missing_fields = [f for f in ["side","entry_price","contracts","entry_time","entry_fee"] if f not in pos]
                if missing_fields:
                    warn(f"Position record missing fields: {missing_fields}")
                else:
                    ok("Position record has all required fields")
            else:
                fail("Position not written to dict after dry-run BUY")
        else:
            warn("execute_signal BUY dry-run: not placed — confidence gate may be blocking")
    except Exception as e:
        fail("execute_signal BUY dry-run raised", exc=e)
        positions = {}

    try:
        sig_sell = kb.TradeSignal(
            event_ticker="KXATPMATCH-TEST",
            market_ticker="KXATPMATCH-TEST-NODAL",
            side="no", action="sell", price=8, contracts=3,
            strategy="exit_trail_value_fade", reason="stack_check_exit", confidence=0.80,
        )
        t = Timer()
        placed2, pnl2 = kb.execute_signal(sig_sell, {}, positions, pnl, pnl_log, "2024-01-01", None)
        if placed2:
            ok(f"execute_signal SELL dry-run: placed, PNL=${pnl2:.4f}  ({t.label()})")
            if "KXATPMATCH-TEST-NODAL" not in positions:
                ok("Position correctly removed after SELL")
            else:
                warn("Position still in dict after SELL — tracking leak")
        else:
            warn("execute_signal SELL dry-run: not placed")
    except Exception as e:
        fail("execute_signal SELL dry-run raised", exc=e)

    try:
        sig_low = kb.TradeSignal(
            event_ticker="KXATPMATCH-TEST", market_ticker="KXATPMATCH-TEST-LOW",
            side="no", action="buy", price=5, contracts=3,
            strategy="value_fade", reason="low_conf_test", confidence=0.30,
        )
        placed_low, _ = kb.execute_signal(sig_low, {}, {}, 0.0, {}, "2024-01-01", None)
        if not placed_low:
            ok("Low-confidence signal (0.30) correctly blocked by gate")
        else:
            fail("Low-confidence signal (0.30) was NOT blocked — confidence gate broken")
    except Exception as e:
        warn(f"Low-confidence gate test raised: {e}")

    kb.Config.DRY_RUN = orig_dry

# ══════════════════════════════════════════════════════════════════════════════
section("§14  PNL Accounting — Fee Inclusion, Rounding, Sign")
# ══════════════════════════════════════════════════════════════════════════════

if "kalshi_bot" in _mods:
    kb = _mods["kalshi_bot"]

    contracts, entry_c, exit_c = 10, 5, 8
    entry_fee = kb.calculate_fee(contracts, entry_c/100, is_maker=True)
    exit_fee  = kb.calculate_fee(contracts, exit_c/100,  is_maker=True)
    pnl_net   = (exit_c - entry_c) * contracts / 100.0 - entry_fee - exit_fee
    if pnl_net > 0:
        ok(f"PNL sanity: 10 NO 5ct->8ct net=${pnl_net:.4f} (fees=${entry_fee:.4f}+${exit_fee:.4f})")
    else:
        fail(f"PNL sanity: 10 NO 5ct->8ct gives net=${pnl_net:.4f} — fees exceed gain")

    taker_fee = kb.calculate_fee(10, 0.50, is_maker=False)
    maker_fee = kb.calculate_fee(10, 0.50, is_maker=True)
    if taker_fee > maker_fee:
        ok(f"Fee asymmetry correct: taker=${taker_fee:.4f} > maker=${maker_fee:.4f}")
    else:
        fail("Fee asymmetry wrong: taker should be ~4x maker")

    running = 0.0
    for _ in range(1000):
        running += round((8-5)*1/100.0 - 0.0009 - 0.0002, 4)
    if abs(running - round(running, 2)) < 0.01:
        ok(f"PNL float accumulation 1000 trades: ${running:.4f} (within tolerance)")
    else:
        warn(f"PNL float drift 1000 trades: ${running:.6f} — consider Decimal")

    if (REPO / "morning_report.py").exists():
        mr_src = (REPO / "morning_report.py").read_text()
        if "> 50" in mr_src:
            warn("morning_report.py determines wins by sell_price > 50c — wrong for NO positions and YES positions bought above 50c")
        if 'strat = "unknown"' in mr_src and "strategy_pnl[strat]" in mr_src:
            fail("morning_report.py: strat never overwritten from 'unknown' — all per-strategy PNL is mis-attributed")

# ══════════════════════════════════════════════════════════════════════════════
section("§15  Telegram Controller — Config Attrs & Hard Close")
# ══════════════════════════════════════════════════════════════════════════════

if "telegram_controller" in _mods and "kalshi_bot" in _mods:
    tc = _mods["telegram_controller"]
    kb = _mods["kalshi_bot"]

    try:
        rt = tc.RuntimeConfig(kb.Config)
        for attr in ["TAKE_PROFIT_CENTS","STOP_LOSS_CENTS","DRY_RUN",
                     "LLM_ASSIST","MAX_POSITION_USD","MIN_VOLUME"]:
            if hasattr(rt, attr):
                ok(f"RuntimeConfig.{attr} present")
            else:
                fail(f"RuntimeConfig.{attr} MISSING — Settings panel will crash")
        try:
            rt.summary()
            ok("RuntimeConfig.summary() executes without error")
        except AttributeError as e:
            fail(f"RuntimeConfig.summary() AttributeError: {e}")
    except Exception as e:
        fail("RuntimeConfig init raised", exc=e)

    tg_src = (REPO / "telegram_controller.py").read_text()
    match = re.search(r'sell_price\s*=.*?-\s*20', tg_src)
    if match:
        warn(f"Hard close uses 'entry_price - 20' as sell price — no market price lookup, near-zero on low-value positions")
    if "os.execv" in tg_src:
        ok("Telegram restart uses os.execv (clean process replace)")
    elif "subprocess" in tg_src:
        warn("Telegram restart uses subprocess — may spawn orphan processes")

# ══════════════════════════════════════════════════════════════════════════════
section("§16  Signal Cooldown — Persistence Across Restarts")
# ══════════════════════════════════════════════════════════════════════════════

main_src = (REPO / "kalshi_bot.py").read_text() if (REPO/"kalshi_bot.py").exists() else ""
if "cooldown.json" in main_src:
    ok("Cooldown state persisted to cooldown.json")
elif "cooldown" in main_src.lower():
    warn("Cooldown appears in-memory only — lost on restart, bot re-enters same positions immediately after crash")
else:
    warn("No cooldown mechanism found — unlimited re-entry on same tickers possible")

# ══════════════════════════════════════════════════════════════════════════════
section("§17  Static Analysis — Anti-Patterns & Risk Code")
# ══════════════════════════════════════════════════════════════════════════════

SOURCE_FILES = list(REPO.glob("*.py"))

for src_path in sorted(SOURCE_FILES):
    try:
        src = src_path.read_text(encoding="utf-8")
    except: continue
    name = src_path.name

    bare_excepts = len(re.findall(r'\bexcept\s*:', src))
    if bare_excepts > 3:
        warn(f"{name}: {bare_excepts} bare 'except:' clauses — silently swallows exceptions")
    elif bare_excepts > 0:
        info(f"{name}: {bare_excepts} bare 'except:' clause(s)")

    if re.search(r'\beval\s*\(', src) or re.search(r'\bexec\s*\(', src):
        warn(f"{name}: contains eval() or exec() — potential security risk")

    if re.search(r'(?i)(api_key|password|secret|token)\s*=\s*["\'][^"\']{8,}', src):
        fail(f"{name}: may contain hardcoded credential — review immediately")

    if ("_lock" in src or "threading.Lock" in src) and "time.sleep" in src:
        lock_blocks = re.findall(r'with self\._lock[^:]*:.*?(?=\n\s{0,8}\S)', src, re.DOTALL)
        for block in lock_blocks:
            if "time.sleep" in block:
                fail(f"{name}: time.sleep() inside a threading lock — deadlock risk")
                break

    if "global " in src and ("threading" in src or "Thread" in src):
        globals_found = re.findall(r'global\s+(\w+)', src)
        if globals_found:
            warn(f"{name}: globals {globals_found} modified in threaded context — race condition possible")

    if name not in ("check_stack.py","check_stack_v2.py","morning_report.py","trade_tracker.py"):
        print_count = len(re.findall(r'\bprint\s*\(', src))
        if print_count > 5:
            info(f"{name}: {print_count} print() calls — use logging in production")

# ══════════════════════════════════════════════════════════════════════════════
section("§18  Network Resilience — Timeouts, Retries, Error Handling")
# ══════════════════════════════════════════════════════════════════════════════

for src_path in sorted(SOURCE_FILES):
    try:
        src = src_path.read_text(encoding="utf-8")
    except: continue
    calls = re.findall(r'requests\.get\([^)]+\)', src)
    no_timeout = [c for c in calls if "timeout" not in c]
    if no_timeout:
        warn(f"{src_path.name}: {len(no_timeout)} requests.get() without timeout — hangs on network failure")

retry_found = any(
    "retry" in p.read_text(encoding="utf-8", errors="replace").lower() or
    "backoff" in p.read_text(encoding="utf-8", errors="replace").lower()
    for p in SOURCE_FILES if p.exists()
)
if not retry_found:
    warn("No retry/backoff logic found — single transient failure drops signals or mis-tracks positions")

if (REPO/"price_watcher.py").exists():
    pw_src = (REPO/"price_watcher.py").read_text()
    timeouts = re.findall(r'timeout\s*=\s*(\d+)', pw_src)
    if timeouts:
        max_to = max(int(t) for t in timeouts)
        if max_to > 4:
            warn(f"price_watcher.py max timeout={max_to}s but polls every 2s — slow response causes poll stacking")
        else:
            ok(f"price_watcher.py max timeout={max_to}s (reasonable for 2s poll)")

# ══════════════════════════════════════════════════════════════════════════════
section("§19  Full Snapshot Fetch — End-to-End Timed")
# ══════════════════════════════════════════════════════════════════════════════

snapshot = {}
if "kalshi_bot" in _mods:
    try:
        t = Timer()
        snapshot = _mods["kalshi_bot"].get_live_sports_snapshot()
        ms = t.ms()
        total_events  = sum(len(g) for g in snapshot.values())
        total_markets = sum(len(m) for g in snapshot.values()
                            for ev in g.values() for m in ev.markets.values())
        ok(f"Snapshot: {total_events} events, {total_markets} markets  ({t.label()})")
        loop_interval = getattr(_mods["kalshi_bot"].Config,"LOOP_INTERVAL",45)
        if ms > loop_interval * 1000:
            fail(f"Snapshot {ms/1000:.1f}s exceeds LOOP_INTERVAL={loop_interval}s")
        elif ms > loop_interval * 1000 * 0.7:
            warn(f"Snapshot {ms/1000:.1f}s is >70% of loop interval")
        for sport, games in snapshot.items():
            mc = sum(len(m) for g in games.values() for m in g.markets.values())
            info(f"  {sport}: {len(games)} events, {mc} markets")
        all_markets = [m for g in snapshot.values()
                       for ev in g.values()
                       for ms_list in ev.markets.values()
                       for m in ms_list]
        zero_bid = [m for m in all_markets if m.yes_bid == 0 and m.yes_ask == 0]
        if zero_bid:
            warn(f"{len(zero_bid)} markets with yes_bid=yes_ask=0 — price parsing may be broken")
        else:
            ok(f"All {len(all_markets)} markets have non-zero bid/ask")
        negative_spread = [m for m in all_markets if m.spread < 0]
        if negative_spread:
            fail(f"{len(negative_spread)} markets with negative spread — yes_bid > yes_ask (data error)")
        else:
            ok("No negative spreads in snapshot")
    except Exception as e:
        fail("get_live_sports_snapshot raised", exc=e)

# ══════════════════════════════════════════════════════════════════════════════
section("§20  Analyze + Strategies Pipeline — Integration")
# ══════════════════════════════════════════════════════════════════════════════

watchlist = []
if "kalshi_bot" in _mods and snapshot:
    kb = _mods["kalshi_bot"]
    try:
        t = Timer()
        watchlist = kb.analyze_snapshot(snapshot)
        signals   = [w for w in watchlist if w["flag"] == "SIGNAL"]
        ok(f"analyze_snapshot: {len(watchlist)} markets, {len(signals)} signals  ({t.label()})")
    except Exception as e:
        fail("analyze_snapshot raised", exc=e)

    if "strategies" in _mods and watchlist:
        try:
            open_pos = kb.load_positions()
            t = Timer()
            trade_signals = kb.run_strategies(
                watchlist, open_pos, 0.0, {}, False, espn_cache=None)
            ok(f"run_strategies: {len(trade_signals)} signals generated  ({t.label()})")
        except Exception as e:
            fail("run_strategies raised", exc=e)

# ══════════════════════════════════════════════════════════════════════════════
section("§21  Reconcile Positions — Live Read-Only")
# ══════════════════════════════════════════════════════════════════════════════

if "strategies" in _mods:
    try:
        t = Timer()
        _mods["strategies"].reconcile_positions(
            open_positions={}, kalshi_base=KALSHI_BASE,
            client=None, save_fn=lambda x: None,
            pnl_log={}, current_date="2024-01-01",
            save_pnl_fn=lambda x: None, bot_orders=set(),
        )
        ok(f"reconcile_positions returns cleanly with client=None  ({t.label()})")
    except Exception as e:
        fail("reconcile_positions raised on None client", exc=e)

    if client:
        try:
            t = Timer()
            test_pos = {}
            _mods["strategies"].reconcile_positions(
                open_positions=test_pos, kalshi_base=KALSHI_BASE,
                client=client, save_fn=lambda x: None,
                pnl_log={},
                current_date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                save_pnl_fn=lambda x: None, bot_orders=set(),
            )
            ok(f"reconcile_positions live: {len(test_pos)} positions found  ({t.label()})")
        except Exception as e:
            fail("reconcile_positions live run raised", exc=e)

# ══════════════════════════════════════════════════════════════════════════════
section("§22  Telegram Connectivity")
# ══════════════════════════════════════════════════════════════════════════════

tg_token = os.getenv("TELEGRAM_BOT_TOKEN","")
tg_chat  = os.getenv("TELEGRAM_CHAT_ID","")

if tg_token:
    try:
        t = Timer()
        r = _req.get(f"https://api.telegram.org/bot{tg_token}/getMe", timeout=6)
        r.raise_for_status()
        bot_name = r.json().get("result",{}).get("username","unknown")
        ok(f"Telegram: connected as @{bot_name}  ({t.label()})")
    except Exception as e:
        fail(f"Telegram getMe failed: {e}")
    if tg_chat:
        try:
            r = _req.get(f"https://api.telegram.org/bot{tg_token}/getChat",
                         params={"chat_id": tg_chat}, timeout=6)
            if r.ok:
                chat_type = r.json().get("result",{}).get("type","unknown")
                ok(f"Telegram: chat_id valid (type={chat_type})")
            else:
                warn(f"Telegram: getChat returned {r.status_code} — chat_id may be wrong")
        except Exception as e:
            warn(f"Telegram getChat failed: {e}")
    else:
        warn("TELEGRAM_CHAT_ID not set")
else:
    warn("TELEGRAM_BOT_TOKEN not set — Telegram notifications disabled")

# ══════════════════════════════════════════════════════════════════════════════
section("§23  Timing Modules Self-Test")
# ══════════════════════════════════════════════════════════════════════════════

for mod_name in ["timing", "trade_timing"]:
    if mod_name not in _mods: continue
    tm = _mods[mod_name]
    try:
        if mod_name == "timing":
            r = tm.get_report()
            r.reset(); r.start_cycle()
            with tm.timed_block("test"):
                time.sleep(0.01)
            r.record("manual", 42.0)
            assert len(r.get_slowest(2)) >= 1
            ok("timing: timed_block + record + get_slowest all work")
        else:
            timer = tm.new_timer("BUY","TEST")
            with timer.step("mock"):
                time.sleep(0.005)
            timer.summary()
            tm.get_stats().record_from_timer(timer)
            ok("trade_timing: new_timer + step + summary + stats all work")
    except Exception as e:
        fail(f"{mod_name} self-test raised", exc=e)

# ══════════════════════════════════════════════════════════════════════════════
section("§24  Module Attribute Completeness")
# ══════════════════════════════════════════════════════════════════════════════

ATTR_CHECKS = {
    "kalshi_bot": [
        "Config","TradeSignal","Market","GameEvent",
        "get_live_sports_snapshot","analyze_snapshot","run_strategies",
        "execute_signal","load_positions","save_positions",
        "load_pnl_log","save_pnl_log","get_kalshi_balance",
        "purge_stale_positions","event_open_contracts",
        "is_daily_loss_limit_hit","get_dynamic_config",
    ],
    "strategies": [
        "STRATEGIES","ALLOWED_SERIES","strategy_value_fade","strategy_exit",
        "ESPNContextCache","reconcile_positions","_ev","_allowed",
        "_is_prop","_scale_contracts",
    ],
    "price_watcher":       ["PriceWatcher"],
    "trade_tracker":       ["log_trade","print_stats"],
    "telegram_controller": ["TelegramController","RuntimeConfig"],
    "timing":              ["get_report","timed_block","timed"],
    "trade_timing":        ["new_timer","get_stats"],
}

for mod_name, attrs in ATTR_CHECKS.items():
    if mod_name not in _mods:
        warn(f"{mod_name} not loaded — skipping attr checks")
        continue
    mod = _mods[mod_name]
    missing = [a for a in attrs if not hasattr(mod, a)]
    if missing:
        fail(f"{mod_name}: missing {missing}")
    else:
        ok(f"{mod_name}: all {len(attrs)} expected attributes present")

# ══════════════════════════════════════════════════════════════════════════════
print(f"\n{B}{'='*65}")
print(f"  Stack Check Complete — {datetime.now().strftime('%H:%M:%S')} UTC")
print(f"{'='*65}{RESET}")
print(f"  {G}PASS: {PASS:<4}{RESET}  {R}FAIL: {FAIL:<4}{RESET}  {Y}WARN: {WARN:<4}{RESET}  {C}INFO: {INFO_CT}{RESET}")

if _section_fails:
    print(f"\n{R}{B}  Failed checks:{RESET}")
    for sect, msg in _section_fails:
        print(f"  {R}x{RESET}  [{sect}]  {msg}")

if FAIL == 0 and WARN == 0:
    print(f"\n  {G}{B}All checks passed. Stack is healthy.{RESET}\n")
elif FAIL == 0:
    print(f"\n  {Y}{B}{WARN} warning(s) — review before running live.{RESET}\n")
else:
    print(f"\n  {R}{B}{FAIL} failure(s) — fix before running live.{RESET}\n")

sys.exit(0 if FAIL == 0 else 1)
