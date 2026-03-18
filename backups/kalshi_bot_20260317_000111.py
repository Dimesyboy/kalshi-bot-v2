#!/usr/bin/env python3
"""
kalshi_bot.py
─────────────────────────────────────────────────────────────────────────────
Kalshi Sports Trading Bot
Sports: NBA / Tennis / MLB
Modules: Fetcher / Analyzer / Strategies / Executor / LLM / Telegram / Logger
─────────────────────────────────────────────────────────────────────────────

## USAGE

python3 kalshi_bot.py            # run the bot
python3 kalshi_bot.py -status   # print PNL + open positions and exit

FIXES vs previous version
──────────────────────────

1. total_pnl float pass-by-value bug
1. Duplicate signal entries mid-loop
1. LLM confidence blending could kill valid approvals
1. Kalshi client re-init per live order
1. No exit path for strategy_custom
1. No signal cooldown/dedup
1. None client crash in alert_startup
1. Local vs UTC date for PNL keys
1. Telegram startup REST fallback for balance
1. Hot-reload / graceful stop
1. Balance reported 100x too high
1. Tennis showing 0 games - now queries open + active status
1. 429 Too Many Requests - sequential fetch with delay
1. 400 Bad Request on status=active - per-status error handling
1. Stale positions - age-based purge at startup and each cycle
1. Settlement checker age gate replaces cycle throttle
1. Momentum strategy thresholds tightened
1. LLM prompt skeptical framing
1. Stop-loss added
1. Position sizing MAX_POSITION_USD raised
1. -status CLI flag
1. RotatingFileHandler - 5MB cap with 3 backups
1. Slippage simulation in dry-run
1. Event overexposure guard - MAX_CONTRACTS_PER_EVENT
1. Atomic JSON writes via os.replace()
1. Daily loss limit - blocks entries when breached
1. Session PNL resume from today's log on restart
1. [FIX] Live order uses PortfolioApi.create_order(create_order_request=...)
   instead of client.create_order() which does not exist on KalshiClient.
   Live positions are now tracked locally so exits/stop-loss work correctly.
   """

import os
import sys
import json
import time
import logging
import logging.handlers
import requests
import traceback
import math
import tempfile
from datetime import datetime, timezone, timedelta
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional
from dotenv import load_dotenv
from telegram_controller import TelegramController
from trade_tracker import log_trade
from price_watcher import PriceWatcher
from strategies import (
    strategy_value_fade, strategy_momentum, strategy_custom,
    strategy_exit, STRATEGIES, ESPNContextCache, reconcile_positions,
)

load_dotenv()

# ==============================================================================

# CONFIG

# ==============================================================================

class Config:
    # - Bot control ------------------------------------------
    DRY_RUN         = False
    LOOP_INTERVAL   = 30
    LOG_FILE        = "kalshi_bot.log"
    PNL_LOG_FILE    = "pnl_log.json"

    # -- Hot-reload ------------------------------------------------------------
    WATCH_SOURCE_FILE = True

    # -- Sports toggles --------------------------------------------------------
    ENABLE_NBA    = True
    ENABLE_TENNIS = True
    ENABLE_MLB    = True

    # -- LLM -------------------------------------------------------------------
    LLM_ASSIST               = False
    LLM_MODEL                = "gpt-4o"
    LLM_CONFIDENCE_THRESHOLD = 0.60

    # -- Trade thresholds ------------------------------------------------------
    MIN_VOLUME       = 5000
    MAX_SPREAD_CENTS = 8
    MIN_LIQUIDITY    = 0.0
    MAX_POSITION_USD = 1.30
    MAX_OPEN_POSITIONS  = 15
    MAX_CONTRACTS    = 20
    MIN_NO_PRICE     = 5

    # -- Overexposure guard ----------------------------------------------------
    MAX_CONTRACTS_PER_EVENT = 20

    # -- Exit thresholds (cents) -----------------------------------------------
    TAKE_PROFIT_PCT = 0.30  # 30% gain — faster scalp target
    STOP_LOSS_PCT   = 0.35  # 35% loss — tighter stop

    # -- Slippage simulation (dry-run only) ------------------------------------
    SLIP_CENTS = 1

    # -- Daily loss limit ------------------------------------------------------
    MAX_DAILY_LOSS_USD = 25.00

    # -- Stale position pruning ------------------------------------------------
    POSITION_MAX_AGE_HOURS = 12

    # -- Settlement check age gate ---------------------------------------------
    SETTLE_MIN_AGE_MINUTES = 30

    # -- Signal cooldown -------------------------------------------------------
    SIGNAL_COOLDOWN_SECS = 600

    # -- Fees ------------------------------------------------------------------
    TAKER_FEE_MULTIPLIER = 0.07
    MAKER_FEE_MULTIPLIER = 0.0175

    # -- Kalshi API ------------------------------------------------------------
    KALSHI_BASE     = "https://api.elections.kalshi.com/trade-api/v2"
    KALSHI_KEY_ID   = os.getenv("KALSHI_API_KEY_ID", "")
    KALSHI_KEY_FILE = os.getenv("KALSHI_PRIVATE_KEY_PATH", "/root/kalshi_private_key.pem")

    # -- Fetcher rate-limit guard ----------------------------------------------
    FETCH_DELAY_SECS = 0.25

    # -- Logging rotation ------------------------------------------------------
    LOG_MAX_BYTES    = 5 * 1024 * 1024
    LOG_BACKUP_COUNT = 3

    # -- Telegram --------------------------------------------------------------
    TELEGRAM_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
    TELEGRAM_CHAT  = os.getenv("TELEGRAM_CHAT_ID", "")

    # -- OpenAI ----------------------------------------------------------------
    OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")

# ==============================================================================

# LOGGING

# ==============================================================================

_file_handler = logging.handlers.RotatingFileHandler(
Config.LOG_FILE,
maxBytes    = Config.LOG_MAX_BYTES,
backupCount = Config.LOG_BACKUP_COUNT,
)
_file_handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
_stream_handler = logging.StreamHandler()
_stream_handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
logging.basicConfig(level=logging.INFO, handlers=[_file_handler, _stream_handler])
log = logging.getLogger("kalshi_bot")

# ==============================================================================

# DATA STRUCTURES

# ==============================================================================

@dataclass
class Market:
    ticker:     str
    title:      str
    yes_bid:    float
    yes_ask:    float
    no_bid:     float
    no_ask:     float
    last_price: float
    volume:     float
    liquidity:  float
    close_time: Optional[str]
    series:     str
    label:      str
    market_status: str = "active"

    @property
    def spread(self):
        return round((self.yes_ask - self.yes_bid) * 100, 1)

    @property
    def mid(self):
        return round((self.yes_bid + self.yes_ask) / 2 * 100, 1)

@dataclass
class GameEvent:
    event_ticker: str
    title:        str
    sport:        str
    close_time:   Optional[str]
    markets:      dict = field(default_factory=dict)

@dataclass
class TradeSignal:
    event_ticker:  str
    market_ticker: str
    side:          str
    action:        str
    price:         int
    contracts:     int
    strategy:      str
    reason:        str
    confidence:    float
    llm_approved:  Optional[bool] = None
    llm_note:      Optional[str]  = None
    market_status: str             = "active"

# ==============================================================================

# ATOMIC JSON I/O

# ==============================================================================

def _atomic_write_json(path: str, data):
    dir_name = os.path.dirname(os.path.abspath(path)) or "."
    try:
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
        try:
            with os.fdopen(fd, 'w') as f:
                json.dump(data, f, indent=2)
            os.replace(tmp_path, path)
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
    except Exception as e:
        log.warning(f"[IO] Atomic write failed for {path}: {e}")

# ==============================================================================

# POSITION / PNL PERSISTENCE

# ==============================================================================

POSITIONS_FILE = "positions.json"

def load_positions() -> dict:
    try:
        with open(POSITIONS_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except Exception as e:
        log.warning(f"Failed to load positions: {e}")
        return {}

def save_positions(positions: dict):
    _atomic_write_json(POSITIONS_FILE, positions)

def load_pnl_log() -> dict:
    try:
        with open(Config.PNL_LOG_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except Exception as e:
        log.warning(f"Failed to load PNL log: {e}")
        return {}

def save_pnl_log(pnl_log: dict):
    _atomic_write_json(Config.PNL_LOG_FILE, pnl_log)


BOT_ORDERS_FILE = "bot_orders.json"

def load_bot_orders() -> set:
    try:
        with open(BOT_ORDERS_FILE) as f:
            return set(json.load(f))
    except FileNotFoundError:
        return set()
    except Exception as e:
        log.warning(f"Failed to load bot orders: {e}")
        return set()

def save_bot_orders(bot_orders: set):
    _atomic_write_json(BOT_ORDERS_FILE, list(bot_orders))

def _parse_entry_time(entry_time_str: str) -> Optional[datetime]:
    if not entry_time_str:
        return None
    try:
        dt = datetime.fromisoformat(entry_time_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None

def purge_stale_positions(open_positions: dict) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=Config.POSITION_MAX_AGE_HOURS)
    stale  = []
    for ticker, pos in open_positions.items():
        dt = _parse_entry_time(pos.get("entry_time", ""))
        if dt is None:
            stale.append(ticker)
            log.warning(f"[Positions] {ticker} missing entry_time - purging")
        elif dt < cutoff:
            age_h = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
            stale.append(ticker)
            log.warning(f"[Positions] {ticker} stale ({age_h:.1f}h) - purging")
    for ticker in stale:
        del open_positions[ticker]
    if stale:
        save_positions(open_positions)
        log.info(f"[Positions] Purged {len(stale)} stale: {stale}")
    return len(stale)

def event_open_contracts(open_positions: dict, event_ticker: str) -> int:
    return sum(
        p.get("contracts", 0)
        for p in open_positions.values()
        if p.get("event_ticker") == event_ticker
    )

# ==============================================================================

# STATUS COMMAND

# ==============================================================================

def print_status():
    now_utc  = datetime.now(timezone.utc)
    today    = now_utc.strftime("%Y-%m-%d")
    divider  = "-" * 68

    print()
    print("=" * 68)
    print(f"  KALSHI BOT STATUS  --  {now_utc.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print("=" * 68)

    pnl_log   = load_pnl_log()
    total_all = sum(pnl_log.values())
    today_pnl = pnl_log.get(today, 0.0)

    print()
    print("  REALIZED PNL")
    print(divider)
    if not pnl_log:
        print("  (no PNL recorded yet)")
    else:
        for date in sorted(pnl_log.keys()):
            marker = " <-- today" if date == today else ""
            val    = pnl_log[date]
            sign   = "+" if val >= 0 else ""
            print(f"  {date}   {sign}${val:.4f}{marker}")
        print(divider)
        sign_all   = "+" if total_all >= 0 else ""
        sign_today = "+" if today_pnl >= 0 else ""
        print(f"  All-time total:  {sign_all}${total_all:.4f}")
        print(f"  Today so far:    {sign_today}${today_pnl:.4f}")
        limit_remaining = Config.MAX_DAILY_LOSS_USD + today_pnl
        if today_pnl < 0:
            print(f"  Daily loss headroom: ${limit_remaining:.4f} "
                  f"(limit: -${Config.MAX_DAILY_LOSS_USD:.2f})")

    open_positions = load_positions()
    print()
    print("  OPEN POSITIONS")
    print(divider)
    if not open_positions:
        print("  (no open positions)")
    else:
        cutoff = now_utc - timedelta(hours=Config.POSITION_MAX_AGE_HOURS)
        for ticker, pos in sorted(open_positions.items()):
            dt      = _parse_entry_time(pos.get("entry_time", ""))
            age_str = "unknown age"
            stale   = ""
            if dt:
                age_m = int((now_utc - dt).total_seconds() / 60)
                age_str = f"{age_m // 60}h {age_m % 60:02d}m" if age_m >= 60 else f"{age_m}m"
                if dt < cutoff:
                    stale = "  [STALE]"
            print(f"  {ticker}")
            print(f"    {pos.get('side','?').upper()} @ {pos.get('entry_price','?')}c  "
                  f"x{pos.get('contracts','?')}  [{pos.get('strategy','?')}]  "
                  f"entered {age_str} ago  fee=${pos.get('entry_fee',0.0):.4f}{stale}")
        print(divider)
        bot_pos    = {t:p for t,p in open_positions.items() if p.get('is_bot') is not False}
    manual_pos = {t:p for t,p in open_positions.items() if p.get('is_bot') is False}
    print(divider)
    print(f"  Total open: {len(open_positions)}  "
          f"(bot: {len(bot_pos)}  manual: {len(manual_pos)})")

    print()
    print("=" * 68)
    print()

# ==============================================================================

# KALSHI CLIENT

# ==============================================================================

def _get_kalshi_client():
    try:
        import kalshi_python
        config = kalshi_python.Configuration(host=Config.KALSHI_BASE)
        with open(Config.KALSHI_KEY_FILE, "r") as f:
            config.private_key_pem = f.read()
        config.api_key_id = Config.KALSHI_KEY_ID
        return kalshi_python.KalshiClient(config)
    except Exception as e:
        log.error(f"[Client] Kalshi client init failed: {e}")
        return None

# ==============================================================================

# BALANCE

# ==============================================================================

def _kalshi_rest_get(path: str) -> dict:
    """Signed GET request to Kalshi REST API. Reused by balance + reconcile."""
    import base64
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    with open(Config.KALSHI_KEY_FILE, "rb") as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + "GET" + path).encode()
    sig   = private_key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
    sig_b64 = base64.b64encode(sig).decode()
    headers = {
        "KALSHI-ACCESS-KEY":       Config.KALSHI_KEY_ID,
        "KALSHI-ACCESS-SIGNATURE": sig_b64,
        "KALSHI-ACCESS-TIMESTAMP": ts_ms,
    }
    r = requests.get(
        "https://api.elections.kalshi.com" + path,
        headers=headers, timeout=10,
    )
    r.raise_for_status()
    return r.json()


def get_kalshi_balance(client) -> float:
    if client is not None:
        try:
            import kalshi_python
            portfolio_api = kalshi_python.PortfolioApi(api_client=client)
            response = portfolio_api.get_balance()
            if response is not None and hasattr(response, "balance"):
                return float(response.balance) / 100.0
        except Exception as e:
            log.warning(f"[Balance] SDK path failed: {e}; trying REST fallback")

    if not Config.KALSHI_KEY_ID or not Config.KALSHI_KEY_FILE:
        log.warning("[Balance] No key credentials configured")
        return 0.0

    try:
        import base64
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        with open(Config.KALSHI_KEY_FILE, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)

        ts_ms   = str(int(time.time() * 1000))
        path    = "/trade-api/v2/portfolio/balance"
        msg     = (ts_ms + "GET" + path).encode()
        sig     = private_key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.b64encode(sig).decode()

        headers = {
            "KALSHI-ACCESS-KEY":       Config.KALSHI_KEY_ID,
            "KALSHI-ACCESS-SIGNATURE": sig_b64,
            "KALSHI-ACCESS-TIMESTAMP": ts_ms,
        }
        r = requests.get(
            "https://api.elections.kalshi.com/trade-api/v2/portfolio/balance",
            headers=headers, timeout=8,
        )
        r.raise_for_status()
        return float(r.json().get("balance", 0.0)) / 100.0
    except Exception as e:
        log.warning(f"[Balance] REST fallback failed: {e}")
        return 0.0

# ==============================================================================

# FEE CALCULATION

# ==============================================================================

def calculate_fee(contracts: int, price_dollars: float, is_maker: bool = True) -> float:
    multiplier = Config.MAKER_FEE_MULTIPLIER if is_maker else Config.TAKER_FEE_MULTIPLIER
    return math.ceil(multiplier * contracts * price_dollars * (1 - price_dollars) * 100) / 100.0

# ==============================================================================

# DAILY LOSS LIMIT

# ==============================================================================

def is_daily_loss_limit_hit(total_pnl: float, pnl_log: dict) -> bool:
    return total_pnl <= -Config.MAX_DAILY_LOSS_USD

# ==============================================================================

# SPORTS FETCHER

# ==============================================================================

SERIES_MAP = {}
if Config.ENABLE_NBA:
    SERIES_MAP["NBA"] = [
        ("KXNBAGAME",      "Moneyline"),
        ("KXNBASPREAD",    "Spread"),
        ("KXNBATOTAL",     "Total"),
        ("KXNBATEAMTOTAL", "Team Total"),
        ("KXNBA1HWINNER",  "1H Winner"),
        ("KXNBA1HTOTAL",   "1H Total"),
        ("KXNBA2HWINNER",  "2H Winner"),
        ("KXNBA1QWINNER",  "Q1 Winner"),
        ("KXNBA2QWINNER",  "Q2 Winner"),
        ("KXNBA3QWINNER",  "Q3 Winner"),
        ("KXNBA4QWINNER",  "Q4 Winner"),
        ("KXNBAPTS",       "Player Points"),
        ("KXNBAREB",       "Player Rebounds"),
        ("KXNBAAST",       "Player Assists"),
        ("KXNBA3PT",       "Player 3PT"),
        ("KXNBAPRA",       "Pts+Reb+Ast"),
        ("KXNBASTL",       "Player Steals"),
        ("KXNBABLK",       "Player Blocks"),
    ]
if Config.ENABLE_TENNIS:
    SERIES_MAP["Tennis"] = [
        ("KXATPGAME",          "ATP Winner"),
        ("KXWTAGAME",          "WTA Winner"),
        ("KXATPMATCH",         "ATP Match"),
        ("KXWTAMATCH",         "WTA Match"),
        ("KXATPDOUBLES",       "ATP Doubles"),
        ("KXWTADOUBLES",       "WTA Doubles"),
        ("KXTENNISEXHIBITION", "Exhibition"),
        ("KXEXHIBITIONMEN",    "Exhibition Men"),
        ("KXEXHIBITIONWOMEN",  "Exhibition Women"),
    ]
if Config.ENABLE_MLB:
    SERIES_MAP["MLB"] = [
        ("KXMLBGAME",   "Moneyline"),
        ("KXMLBSPREAD", "Run Line"),
        ("KXMLBTOTAL",  "Total Runs"),
        ("KXMLBRFI",    "Run 1st Inning"),
        ("KXMLBHIT",    "Player Hits"),
        ("KXMLBSTGAME", "Spring Training"),
    ]

def _fetch_series(series_ticker: str, label: str) -> tuple:
    all_events         = []
    seen_event_tickers = set()
    for status in ("active", "open"):
        try:
            r = requests.get(
                f"{Config.KALSHI_BASE}/events",
                params={
                    "series_ticker":       series_ticker,
                    "status":              status,
                    "limit":               50,
                    "with_nested_markets": "true",
                },
                timeout=10,
            )
            if r.status_code == 400:
                continue
            r.raise_for_status()
            for event in r.json().get("events", []):
                key = event.get("event_ticker", "")
                if key and key not in seen_event_tickers:
                    seen_event_tickers.add(key)
                    for m in event.get("markets", []):
                        m["market_status"] = status
                    all_events.append(event)
        except requests.exceptions.HTTPError:
            log.warning(f"[Fetcher] {series_ticker} status={status}: HTTP error")
        except Exception as e:
            log.warning(f"[Fetcher] {series_ticker} status={status}: {e}")
    return label, series_ticker, all_events

def _parse_market(raw: dict, label: str, series: str) -> Market:
    def f(key):
        value = raw.get(key)
        try:
            return float(value) if value is not None else 0.0
        except Exception:
            return 0.0
    return Market(
        ticker     = raw.get("ticker") or raw.get("market_ticker", ""),
        title      = raw.get("title", ""),
        yes_bid    = f("yes_bid_dollars"),
        yes_ask    = f("yes_ask_dollars"),
        no_bid     = f("no_bid_dollars"),
        no_ask     = f("no_ask_dollars"),
        last_price = f("last_price_dollars"),
        volume     = f("volume_fp"),
        liquidity  = f("liquidity_dollars"),
        close_time = raw.get("close_time"),
        series     = series,
        label      = label,
        market_status = raw.get("market_status", "active"),
    )

def get_live_sports_snapshot() -> dict:
    snapshot: dict = {}
    for sport, series_list in SERIES_MAP.items():
        games: dict = {}
        for idx, (series_ticker, label) in enumerate(series_list):
            if idx > 0:
                time.sleep(Config.FETCH_DELAY_SECS)
            _, _, events = _fetch_series(series_ticker, label)
            for e in events:
                key = e.get("event_ticker", "")
                if not key:
                    continue
                if key not in games:
                    games[key] = GameEvent(
                        event_ticker = key,
                        title        = e.get("title", key),
                        sport        = sport,
                        close_time   = e.get("close_time"),
                        markets      = defaultdict(list),
                    )
                for raw_m in e.get("markets", []):
                    m = _parse_market(raw_m, label, series_ticker)
                    if m.ticker:
                        games[key].markets[label].append(m)
        snapshot[sport] = games
        log.info(f"[Fetcher] {sport}: {len(games)} live events")
    return snapshot

# ==============================================================================

# MARKET ANALYZER

# ==============================================================================

def analyze_snapshot(snapshot: dict) -> list:
    watchlist = []
    for sport, games in snapshot.items():
        for event_ticker, game in games.items():
            for label, markets in game.markets.items():
                for m in markets:
                    if m.volume < Config.MIN_VOLUME:
                        continue
                    if m.spread > Config.MAX_SPREAD_CENTS:
                        continue
                    if m.yes_bid <= 0 or m.yes_ask <= 0:
                        continue

                    flag   = "WATCHLIST"
                    reason = ""
                    drift  = round((m.last_price - m.yes_bid) * 100, 1)

                    if abs(drift) >= 5:
                        flag   = "SIGNAL"
                        reason = f"Price drift {drift:+.1f}c from last trade"
                    if m.yes_bid >= 0.85:
                        flag   = "SIGNAL"
                        reason = f"Heavy favorite at {m.mid}c mid - fade candidate"
                    if m.spread <= 3 and m.volume >= 2000:
                        flag   = "SIGNAL"
                        reason = f"Tight spread {m.spread}c + vol {int(m.volume)} - liquid"

                    watchlist.append({
                        "sport":        sport,
                        "event_ticker": event_ticker,
                        "game_title":   game.title,
                        "market":       m,
                        "flag":         flag,
                        "reason":       reason,
                        "market_status": m.market_status,
                    })

    signals = [w for w in watchlist if w["flag"] == "SIGNAL"]
    log.info(f"[Analyzer] {len(watchlist)} markets watched | {len(signals)} signals")
    return watchlist

# ==============================================================================

# STRATEGY ENGINE

# ==============================================================================


def run_strategies(watchlist, open_positions, total_pnl, pnl_log, daily_limit_hit, espn_cache=None):
    signals = []
    pending_tickers = set()
    for item in watchlist:
        ticker = item["market"].ticker
        if ticker in open_positions:
            exit_signal = strategy_exit(item, open_positions[ticker], espn_cache=espn_cache)
            if exit_signal:
                log.info(f"[Strategy:exit] {exit_signal.market_ticker} - {exit_signal.reason}")
                signals.append(exit_signal)
            continue
        if ticker in pending_tickers or daily_limit_hit:
            continue
        event_ticker = item["event_ticker"]
        current_exposure = event_open_contracts(open_positions, event_ticker)
        if current_exposure >= Config.MAX_CONTRACTS_PER_EVENT:
            continue
        for strategy_fn in STRATEGIES:
            try:
                signal = strategy_fn(item, espn_cache=espn_cache)
                if signal:
                    if current_exposure + signal.contracts > Config.MAX_CONTRACTS_PER_EVENT:
                        allowed = Config.MAX_CONTRACTS_PER_EVENT - current_exposure
                        if allowed <= 0:
                            continue
                        signal.contracts = allowed
                    log.info(f"[Strategy:{signal.strategy}] {signal.market_ticker} - {signal.reason}")
                    signals.append(signal)
                    pending_tickers.add(ticker)
                    break
            except Exception as e:
                log.warning(f"[Strategy] {strategy_fn.__name__}: {e}")
    return signals


# ==============================================================================

# LLM ADVISOR

# ==============================================================================

def llm_evaluate_signal(signal: TradeSignal, game: GameEvent) -> TradeSignal:
    if not Config.LLM_ASSIST or not Config.OPENAI_KEY:
        signal.llm_approved = None
        signal.llm_note = "LLM disabled"
        return signal

    try:
        import openai
        openai.api_key = Config.OPENAI_KEY

        market_summary = []
        for label, mkts in game.markets.items():
            for m in mkts[:3]:
                market_summary.append(
                    f"  [{label}] {m.title} | "
                    f"Yes: {int(m.yes_bid*100)}c/{int(m.yes_ask*100)}c | "
                    f"Vol: {int(m.volume)}"
                )

        prompt = f"""You are a skeptical prediction market trading assistant reviewing a proposed Kalshi sports trade.

Your job is to REJECT trades that lack a strong edge. Only approve if you see a genuine reason to expect profit.
Default to rejection when uncertain. A confidence above 0.70 should be rare.

GAME: {game.title} ({game.sport})
EVENT: {game.event_ticker}
CLOSES: {game.close_time or 'Live/Unknown'}

MARKET CONTEXT:
{chr(10).join(market_summary)}

PROPOSED TRADE:
Market: {signal.market_ticker}
Action: {signal.action.upper()} {signal.side.upper()}
Price:  {signal.price}c
Size:   {signal.contracts} contracts
Strategy: {signal.strategy}
Reason: {signal.reason}

EVALUATE:

- Does the proposed edge make sense given the market context?
- Is the price reasonable vs the market data shown?
- Are there reasons this trade could fail?

Respond ONLY in JSON, no extra text:
{{
"approved": true or false,
"confidence": 0.0 to 1.0,
"note": "one sentence - state the main risk or reason for your decision"
}}"""

        response = openai.chat.completions.create(
            model       = Config.LLM_MODEL,
            messages    = [{"role": "user", "content": prompt}],
            max_tokens  = 150,
            temperature = 0.2,
        )

        raw    = response.choices[0].message.content.strip()
        raw    = raw.replace("```json", "").replace("```", "").strip()
        result = json.loads(raw)

        signal.llm_approved = result.get("approved", False)
        signal.llm_note     = result.get("note", "")
        llm_conf            = float(result.get("confidence", 0))
        signal.confidence   = round((signal.confidence + llm_conf) / 2, 2)

        log.info(f"[LLM] {signal.market_ticker} -> approved={signal.llm_approved} "
                 f"conf={signal.confidence} | {signal.llm_note}")

    except Exception as e:
        log.warning(f"[LLM] Error: {e}")
        signal.llm_approved = None
        signal.llm_note = f"LLM error: {str(e)[:80]}"

    return signal

# ==============================================================================

# TRADE EXECUTOR

# ==============================================================================

def execute_signal(
    signal:         TradeSignal,
    snapshot:       dict,
    open_positions: dict,
    total_pnl:      float,
    pnl_log:        dict,
    current_date:   str,
    client,
) -> tuple:
    """
    Gate -> LLM check -> confidence check -> place order or sim.
    Returns (placed: bool, updated_total_pnl: float).
    Exit signals bypass all gates.

    LIVE ORDER PATH uses PortfolioApi.create_order(create_order_request=...)
    which is the correct method on the kalshi_python SDK. KalshiClient itself
    has no create_order method - it is a low-level HTTP client only.
    """
    is_exit = signal.action == "sell"

    if not is_exit:
        if getattr(signal, "market_status", "active") == "open" and signal.llm_approved is None:
            log.info(f"[Executor] SKIP {signal.market_ticker} - pre-game requires LLM approval")
            return False, total_pnl
        if Config.LLM_ASSIST and signal.llm_approved is False:
            log.info(f"[Executor] SKIP {signal.market_ticker} - LLM rejected: {signal.llm_note}")
            return False, total_pnl
        if signal.llm_approved is not True:
            if signal.confidence < Config.LLM_CONFIDENCE_THRESHOLD:
                log.info(f"[Executor] SKIP {signal.market_ticker} - "
                         f"conf {signal.confidence} < {Config.LLM_CONFIDENCE_THRESHOLD}")
                return False, total_pnl

    is_maker = True

    # -- DRY RUN --------------------------------------------------------------
    if Config.DRY_RUN:
        if signal.action == "buy":
            fill_price    = signal.price + Config.SLIP_CENTS
            price_dollars = fill_price / 100.0
            entry_fee     = calculate_fee(signal.contracts, price_dollars, is_maker)
            log.info(
                f"[SIM BUY] {signal.contracts}x {signal.side.upper()} "
                f"@ {fill_price}c (quoted {signal.price}c + {Config.SLIP_CENTS}c slip) "
                f"on {signal.market_ticker} [{signal.strategy} | conf={signal.confidence}] "
                f"| Entry fee: ${entry_fee:.4f}"
            )
            open_positions[signal.market_ticker] = {
                "side":         signal.side,
                "entry_price":  fill_price,
                "quoted_price": signal.price,
                "contracts":    signal.contracts,
                "strategy":     signal.strategy,
                "entry_time":   datetime.now(timezone.utc).isoformat(),
                "event_ticker": signal.event_ticker,
                "reason":       signal.reason,
                "entry_fee":    entry_fee,
            }
            save_positions(open_positions)
            return True, total_pnl

        elif signal.action == "sell":
            if signal.market_ticker in open_positions:
                pos           = open_positions[signal.market_ticker]
                if pos["side"] == signal.side:
                    fill_price    = max(0, signal.price - Config.SLIP_CENTS)
                    price_dollars = fill_price / 100.0
                    exit_fee      = calculate_fee(pos["contracts"], price_dollars, is_maker)
                    entry         = pos["entry_price"]
                    pnl_cents     = (fill_price - entry) * pos["contracts"]
                    entry_fee     = pos.get("entry_fee", 0.0)
                    pnl_dollars   = pnl_cents / 100.0 - entry_fee - exit_fee
                    total_pnl    += pnl_dollars
                    pnl_log[current_date] = pnl_log.get(current_date, 0.0) + pnl_dollars
                    log.info(
                        f"[SIM SELL] {pos['contracts']}x {signal.side.upper()} "
                        f"@ {fill_price}c (quoted {signal.price}c - {Config.SLIP_CENTS}c slip) "
                        f"on {signal.market_ticker}: PNL ${pnl_dollars:.4f} "
                        f"(session ${total_pnl:.4f}) | Exit fee: ${exit_fee:.4f}"
                    )
                    try:
                        import math
                        exit_fee_sim = math.ceil(0.0175*pos["contracts"]*(fill_price/100)*(1-fill_price/100)*100)/100
                        log_trade(
                            market_ticker = signal.market_ticker,
                            event_ticker  = pos.get("event_ticker",""),
                            sport         = "",
                            side          = pos["side"],
                            strategy      = signal.strategy,
                            entry_price   = pos["entry_price"],
                            exit_price    = fill_price,
                            peak_price    = pos.get("peak_price", pos["entry_price"]),
                            contracts     = pos["contracts"],
                            entry_fee     = pos.get("entry_fee",0.0),
                            exit_fee      = exit_fee_sim,
                            exit_reason   = signal.reason,
                            entry_time    = pos.get("entry_time",""),
                            is_bot        = True,
                        )
                    except Exception as _te:
                        log.debug(f"[Tracker] log_trade failed: {_te}")
                    del open_positions[signal.market_ticker]
                    save_positions(open_positions)
                    save_pnl_log(pnl_log)
                    return True, total_pnl
            log.warning(f"[SIM] Sell without matching position: {signal.market_ticker}")
            return False, total_pnl

    # -- LIVE TRADING ---------------------------------------------------------
    else:
        try:
            import uuid
            import kalshi_python
            from kalshi_python.models import CreateOrderRequest

            if not client:
                log.error("[Executor] No Kalshi client available for live order")
                return False, total_pnl

            # Balance + position count gate
            if len(open_positions) >= Config.MAX_OPEN_POSITIONS:
                log.info(f"[Executor] SKIP {signal.market_ticker} - max open positions ({Config.MAX_OPEN_POSITIONS}) reached")
                return False, total_pnl
            balance = get_kalshi_balance(client)
            cost    = signal.price / 100.0 * signal.contracts
            if balance < cost + 0.50:
                log.warning(f"[Executor] SKIP {signal.market_ticker} - insufficient balance ${balance:.2f} < cost ${cost:.2f}")
                return False, total_pnl

            # PortfolioApi is the correct class - KalshiClient has no create_order
            portfolio_api = kalshi_python.PortfolioApi(api_client=client)

            order_req = CreateOrderRequest(
                ticker          = signal.market_ticker,
                action          = signal.action,
                side            = signal.side,
                type            = "limit",
                yes_price       = signal.price if signal.side == "yes" else None,
                no_price        = signal.price if signal.side == "no"  else None,
                count           = int(signal.contracts),
                client_order_id = str(uuid.uuid4()),
            )

            # For sell orders on NO positions, yes_price = 100 - no_bid
            if signal.action == "sell" and signal.side == "no":
                _yes_p = max(1, 100 - signal.price)
                _no_p  = None
            elif signal.side == "yes":
                _yes_p = max(1, signal.price)
                _no_p  = None
            else:
                _yes_p = None
                _no_p  = max(1, signal.price)

            order    = portfolio_api.create_order(
                ticker          = signal.market_ticker,
                action          = signal.action,
                side            = signal.side,
                type            = "limit",
                yes_price       = _yes_p,
                no_price        = _no_p,
                count           = int(signal.contracts),
                client_order_id = str(uuid.uuid4()),
            )
            order_id = order.order.order_id

            log.info(
                f"[LIVE ORDER PLACED] {order_id} | "
                f"{signal.market_ticker} {signal.side.upper()} @ {signal.price}c"
            )

            price_dollars = signal.price / 100.0

            if signal.action == "buy":
                entry_fee = calculate_fee(signal.contracts, price_dollars, is_maker)
                open_positions[signal.market_ticker] = {
                    "side":         signal.side,
                    "entry_price":  signal.price,
                    "contracts":    signal.contracts,
                    "strategy":     signal.strategy,
                    "entry_time":   datetime.now(timezone.utc).isoformat(),
                    "event_ticker": signal.event_ticker,
                    "reason":       signal.reason,
                    "entry_fee":    entry_fee,
                    "order_id":     order_id,
                }
                save_positions(open_positions)
                log.info(f"[LIVE] Position recorded: {signal.market_ticker} "
                         f"{signal.side.upper()} @ {signal.price}c x{signal.contracts}")

            elif signal.action == "sell":
                if signal.market_ticker in open_positions:
                    pos         = open_positions[signal.market_ticker]
                    exit_fee    = calculate_fee(pos["contracts"], price_dollars, is_maker)
                    entry       = pos["entry_price"]
                    pnl_cents   = (signal.price - entry) * pos["contracts"]
                    pnl_dollars = pnl_cents / 100.0 - pos.get("entry_fee", 0.0) - exit_fee
                    total_pnl  += pnl_dollars
                    pnl_log[current_date] = pnl_log.get(current_date, 0.0) + pnl_dollars
                    log.info(f"[LIVE] Position closed: {signal.market_ticker} "
                             f"PNL ${pnl_dollars:.4f} (session ${total_pnl:.4f})")
                    # Log to trade tracker
                    try:
                        import math
                        exit_fee_amt = math.ceil(0.0175*pos["contracts"]*(signal.price/100)*(1-signal.price/100)*100)/100
                        log_trade(
                            market_ticker = signal.market_ticker,
                            event_ticker  = pos.get("event_ticker",""),
                            sport         = pos.get("event_ticker","").split("-")[0].replace("KXNBA","NBA").replace("KXWTA","Tennis").replace("KXATP","Tennis").replace("KXMLB","MLB"),
                            side          = pos["side"],
                            strategy      = signal.strategy,
                            entry_price   = pos["entry_price"],
                            exit_price    = signal.price,
                            peak_price    = pos.get("peak_price", pos["entry_price"]),
                            contracts     = pos["contracts"],
                            entry_fee     = pos.get("entry_fee",0.0),
                            exit_fee      = exit_fee_amt,
                            exit_reason   = signal.reason,
                            entry_time    = pos.get("entry_time",""),
                            is_bot        = pos.get("is_bot", True),
                        )
                    except Exception as _te:
                        log.debug(f"[Tracker] log_trade failed: {_te}")
                    del open_positions[signal.market_ticker]
                    save_positions(open_positions)
                    save_pnl_log(pnl_log)
                else:
                    log.warning(f"[LIVE] Sell placed for {signal.market_ticker} "
                                f"but no local position record found")

            return True, total_pnl

        except Exception as e:
            log.error(f"[Executor] Order failed: {e}")
            return False, total_pnl

    return False, total_pnl

# ==============================================================================

# SETTLEMENT CHECKER

# ==============================================================================

def check_settled_positions(
    open_positions: dict,
    total_pnl:      float,
    pnl_log:        dict,
    current_date:   str,
) -> float:
    """
    DRY_RUN: calculates simulated PNL from market result.
    Live:    removes local position record only (Kalshi credits account directly).
    Skips positions younger than SETTLE_MIN_AGE_MINUTES.
    """
    now    = datetime.now(timezone.utc)
    cutoff = now - timedelta(minutes=Config.SETTLE_MIN_AGE_MINUTES)

    to_remove = []
    skipped   = 0

    for ticker, pos in list(open_positions.items()):
        dt = _parse_entry_time(pos.get("entry_time", ""))
        if dt is not None and dt > cutoff:
            skipped += 1
            continue
        try:
            r = requests.get(f"{Config.KALSHI_BASE}/markets/{ticker}", timeout=8)
            r.raise_for_status()
            data = r.json().get("market", {})
            if data.get("status") in ("settled", "finalized"):
                result = data.get("result", "").lower()
                side   = pos["side"].lower()
                if Config.DRY_RUN:
                    entry_price = pos["entry_price"]
                    contracts   = pos["contracts"]
                    pnl_cents   = (100 - entry_price) * contracts if result == side else -entry_price * contracts
                    pnl_dollars = pnl_cents / 100.0 - pos.get("entry_fee", 0.0)
                    total_pnl  += pnl_dollars
                    pnl_log[current_date] = pnl_log.get(current_date, 0.0) + pnl_dollars
                    log.info(f"[SIM SETTLED] {ticker} result={result.upper()} "
                             f"PNL ${pnl_dollars:.4f} (session ${total_pnl:.4f})")
                else:
                    log.info(f"[LIVE SETTLED] {ticker} result={result.upper()} "
                             f"- removing local record")
                to_remove.append(ticker)
        except Exception as e:
            log.warning(f"[Settle] {ticker} failed: {e}")

    for t in to_remove:
        del open_positions[t]
    if to_remove:
        save_positions(open_positions)
        if Config.DRY_RUN:
            save_pnl_log(pnl_log)
    if skipped:
        log.debug(f"[Settle] Skipped {skipped} position(s) younger than {Config.SETTLE_MIN_AGE_MINUTES}m")

    return total_pnl

# ==============================================================================

# TELEGRAM ALERTER

# ==============================================================================

def _tg_validate() -> bool:
    if not Config.TELEGRAM_TOKEN or not Config.TELEGRAM_CHAT:
        log.warning("[Telegram] Token or chat ID not set - alerts disabled")
        return False
    try:
        r = requests.get(f"https://api.telegram.org/bot{Config.TELEGRAM_TOKEN}/getMe", timeout=5)
        if not r.ok:
            log.warning(f"[Telegram] getMe failed: {r.status_code}")
            return False
        bot_name = r.json().get("result", {}).get("username", "unknown")
        log.info(f"[Telegram] Connected as @{bot_name}")
        return True
    except Exception as e:
        log.warning(f"[Telegram] Validation failed: {e}")
        return False

_tg_state = {"ok": False}

def _tg_send(text: str):
    if not _tg_state["ok"]:
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{Config.TELEGRAM_TOKEN}/sendMessage",
            json={"chat_id": Config.TELEGRAM_CHAT, "text": text, "parse_mode": "HTML"},
            timeout=5,
        ).raise_for_status()
    except Exception as e:
        log.warning(f"[Telegram] Send failed: {e}")

def alert_startup(client, pnl_log: dict, open_positions: dict, total_pnl: float):
    mode      = "LIVE TRADING" if not Config.DRY_RUN else "DRY RUN"
    sports    = " / ".join([s for s, e in [("NBA", Config.ENABLE_NBA), ("Tennis", Config.ENABLE_TENNIS), ("MLB", Config.ENABLE_MLB)] if e])
    balance   = get_kalshi_balance(client)
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
    today     = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    prev_str  = f"\nPrev Day PNL: ${pnl_log.get(yesterday, 0.0):.2f}" if pnl_log.get(yesterday) else ""
    today_str = f"\nToday PNL: ${pnl_log.get(today, 0.0):.2f}" if pnl_log.get(today) else ""
    pos_str   = f"\nOpen Positions: {len(open_positions)}" if open_positions else ""
    _tg_send(
        f"Kalshi Bot Started\nMode: {mode}\nSports: {sports}\n"
        f"LLM: {'ON' if Config.LLM_ASSIST else 'OFF'}\nInterval: {Config.LOOP_INTERVAL}s\n"
        f"Balance: ${balance:.2f}{prev_str}{today_str}{pos_str}\n"
        f"Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC"
    )

def alert_trade_placed(signal: TradeSignal):
    mode = "DRY RUN" if Config.DRY_RUN else "LIVE"
    verb = "SELL (exit)" if signal.action == "sell" else "BUY (entry)"
    _tg_send(
        f"{verb} - {mode}\nMarket: {signal.market_ticker}\n"
        f"Side: {signal.side.upper()}  @  {signal.price}c  x  {signal.contracts} contracts\n"
        f"Strategy: {signal.strategy}\nReason: {signal.reason}\n"
        f"Confidence: {int(signal.confidence*100)}%"
    )

def alert_daily_limit(total_pnl: float):
    _tg_send(
        f"DAILY LOSS LIMIT HIT\nSession PNL: ${total_pnl:.2f}\n"
        f"Limit: -${Config.MAX_DAILY_LOSS_USD:.2f}\n"
        f"New entries BLOCKED for rest of today (UTC).\n"
        f"Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC"
    )

def alert_error(context: str, error: Exception):
    _tg_send(f"Bot Error\nContext: {context}\nError: {str(error)[:200]}")

def alert_cycle_report(snapshot, signals, trades_placed, open_positions, total_pnl, daily_limit_hit):
    lines = [f"Cycle Report - {datetime.now(timezone.utc).strftime('%H:%M:%S')} UTC"]
    for sport, games in snapshot.items():
        count = sum(len(m) for g in games.values() for m in g.markets.values())
        lines.append(f"  {sport}: {len(games)} games / {count} markets")
    lines.append(f"Signals: {len(signals)}  |  Trades: {trades_placed}  |  Positions: {len(open_positions)}  |  PNL: ${total_pnl:.2f}")
    if daily_limit_hit:
        lines.append("[!] Daily loss limit active - entries blocked")
    _tg_send("\n".join(lines))

def alert_hourly_pnl(client, total_pnl: float, open_positions: dict):
    balance = get_kalshi_balance(client)
    _tg_send(
        f"Hourly PNL Report\nSession PNL: ${total_pnl:.2f}\n"
        f"Balance: ${balance:.2f}\nOpen Positions: {len(open_positions)}\n"
        f"Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC"
    )

# ==============================================================================

# TERMINAL UI

# ==============================================================================

class C:
    RESET   = "\033[0m";  BOLD    = "\033[1m";  DIM     = "\033[2m"
    BLACK   = "\033[30m"; WHITE   = "\033[97m"; GREY    = "\033[90m"
    CYAN    = "\033[96m"; YELLOW  = "\033[93m"; RED     = "\033[91m"
    GREEN   = "\033[92m"; MAGENTA = "\033[95m"; BLUE    = "\033[94m"
    BG_DARK  = "\033[48;5;234m"
    BG_SPORT = "\033[48;5;236m"

SPORT_COLOR = {"NBA": C.CYAN, "Tennis": C.YELLOW, "MLB": C.RED}
SPORT_TAG   = {"NBA": "[NBA]", "Tennis": "[TEN]", "MLB": "[MLB]"}
W = 76

def _c(text, *codes) -> str:
    return "".join(codes) + str(text) + C.RESET

def _rule(char="-", color=C.GREY, width=W) -> str:
    return _c(char * width, color)

GAME_LABELS = [
    "Moneyline", "Run Line", "Spread", "Total", "Total Runs",
    "Team Total", "Run 1st Inning", "Spring Training",
    "1H Winner", "1H Total", "2H Winner",
    "Q1 Winner", "Q2 Winner", "Q3 Winner", "Q4 Winner",
    "ATP Winner", "WTA Winner", "ATP Match", "WTA Match",
    "ATP Doubles", "WTA Doubles",
    "Exhibition", "Exhibition Men", "Exhibition Women",
]
PROP_LABELS = [
    "Player Points", "Player Rebounds", "Player Assists",
    "Player 3PT", "Pts+Reb+Ast", "Player Steals",
    "Player Blocks", "Player Hits",
]

def _fmt_close(ts) -> str:
    if not ts:
        return _c("* LIVE", C.GREEN, C.BOLD)
    try:
        dt   = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        now  = datetime.now(timezone.utc)
        mins = int((dt - now).total_seconds() / 60)
        if mins < 0:   return _c("closing soon", C.RED, C.BOLD)
        if mins < 10:  return _c(f"~{mins}m", C.RED, C.BOLD)
        if mins < 60:  return _c(f"~{mins}m", C.YELLOW)
        return _c(f"~{mins//60}h {mins%60:02d}m", C.GREY)
    except Exception:
        return ts[:16]

def _fmt_vol(v) -> str:
    try:
        v = float(v)
        if v >= 1_000_000: s = f"{v/1_000_000:.1f}M"
        elif v >= 1_000:   s = f"{v/1_000:.1f}k"
        else:              s = str(int(v))
        return _c(s, C.GREY)
    except Exception:
        return _c("0", C.GREY)

def _fmt_price_bar(bid: int, ask: int) -> str:
    mid = (bid + ask) / 2
    bid_color = C.GREEN if mid >= 70 else (C.YELLOW if mid >= 40 else C.RED)
    return f"YES {_c(f'{bid:>3}c', bid_color, C.BOLD)}{_c('/', C.GREY)}{_c(f'{ask:<3}c', C.GREY)}"

def _fmt_spread(spread: float) -> str:
    color = C.GREEN if spread <= 2 else (C.YELLOW if spread <= 5 else C.RED)
    return _c(f"spd {spread:.0f}c", color)

def _fmt_conf(pct: int) -> str:
    color = C.GREEN if pct >= 80 else (C.YELLOW if pct >= 65 else C.RED)
    bar   = "#" * (pct // 10) + "." * (10 - pct // 10)
    return _c(f"{bar} {pct:>3}%", color)

def _sport_header(sport: str, n_games: int) -> str:
    tag      = SPORT_TAG.get(sport, "[???]")
    color    = SPORT_COLOR.get(sport, C.WHITE)
    plural   = "s" if n_games != 1 else ""
    label    = _c(f" {tag}  {sport} ", color, C.BOLD, C.BG_SPORT)
    games    = _c(f" {n_games} event{plural} ", C.GREY, C.BG_SPORT)
    return f"\n{label}{games}"

def print_snapshot(snapshot, open_positions=None, total_pnl=0.0, daily_limit_hit=False):
    open_positions = open_positions or {}
    now_str  = datetime.now(timezone.utc).strftime("%Y-%m-%d  %H:%M:%S UTC")
    mode_str = _c(" DRY RUN ", C.YELLOW, C.BOLD, C.BG_DARK) if Config.DRY_RUN else _c(" * LIVE  ", C.WHITE, C.BOLD, "\033[41m")
    pnl_col  = C.GREEN if total_pnl >= 0 else C.RED
    pnl_str  = _c(f"${total_pnl:+.2f}", pnl_col, C.BOLD)

    print()
    print(_rule("=", C.GREY))
    print(f"{_c('  KALSHI SPORTS BOT', C.WHITE, C.BOLD)}   {_c(now_str, C.GREY)}   {mode_str}")
    if open_positions:
        n_pos  = len(open_positions)
        plural = "s" if n_pos != 1 else ""
        print(f"  {_c(f'{n_pos} open position{plural}', C.CYAN)}   PNL {pnl_str}")
    if daily_limit_hit:
        print(f"  {_c('  [!] DAILY LOSS LIMIT HIT - entries blocked', C.RED, C.BOLD)}")
    print(_rule("=", C.GREY))

    total_events  = sum(len(g) for g in snapshot.values())
    total_markets = sum(len(m) for g in snapshot.values() for ev in g.values() for m in ev.markets.values())
    print(
        _c(f"  {total_events}", C.WHITE, C.BOLD) + _c(" events  ", C.GREY) +
        _c(f"{total_markets}", C.WHITE, C.BOLD) + _c(" markets across ", C.GREY) +
        _c(f"{len(snapshot)}", C.WHITE, C.BOLD) + _c(" sports\n", C.GREY)
    )

    for sport, games in snapshot.items():
        color = SPORT_COLOR.get(sport, C.WHITE)
        print(_sport_header(sport, len(games)))
        print(_rule("-", C.GREY))

        if not games:
            print(_c("  No live markets.", C.GREY))
            continue

        for event_ticker, game in games.items():
            exposure = event_open_contracts(open_positions, event_ticker)
            exp_str  = ""
            if exposure > 0:
                exp_col = C.RED if exposure >= Config.MAX_CONTRACTS_PER_EVENT else C.YELLOW
                exp_str = _c(f"  [{exposure}/{Config.MAX_CONTRACTS_PER_EVENT} contracts]", exp_col)

            print(f"\n{_c(f'  {game.title}', color, C.BOLD)}{exp_str}")
            print(f"  {_c(event_ticker, C.GREY)}   closes {_fmt_close(game.close_time)}")

            for t, p in {t: p for t, p in open_positions.items() if p.get("event_ticker") == event_ticker}.items():
                ep   = p["entry_price"]
                ep_c = C.GREEN if p["side"] == "yes" else C.RED
                dt   = _parse_entry_time(p.get("entry_time", ""))
                age  = _c(f"  ({int((datetime.now(timezone.utc)-dt).total_seconds()//60)}m ago)", C.GREY) if dt else ""
                print(f"  {_c('  POSITION', C.MAGENTA, C.BOLD)}  {_c(t, C.GREY)}  "
                      f"{_c(p['side'].upper(), ep_c, C.BOLD)} @ {_c(str(ep)+'c', C.WHITE, C.BOLD)}  "
                      f"{_c('x'+str(p['contracts']), C.GREY)}  {_c('['+p['strategy']+']', C.GREY)}{age}")

            for label in GAME_LABELS:
                mkts = game.markets.get(label, [])
                if not mkts:
                    continue
                print(f"\n{_c('  +- ' + label, C.BLUE)}")
                for m in mkts:
                    print(f"  |  {_c(m.title, C.WHITE):<45}  {_fmt_price_bar(int(m.yes_bid*100), int(m.yes_ask*100))}  {_fmt_spread(m.spread)}  vol {_fmt_vol(m.volume)}")

            prop_mkts = [m for lbl in PROP_LABELS for m in game.markets.get(lbl, [])]
            if prop_mkts:
                print(f"\n{_c('  +- Player Props', C.BLUE)}{_c(f'  ({len(prop_mkts)} markets)', C.GREY)}")
                for m in prop_mkts:
                    print(f"  |  {_c(m.title, C.WHITE):<45}  {_fmt_price_bar(int(m.yes_bid*100), int(m.yes_ask*100))}  vol {_fmt_vol(m.volume)}")

        print()
        print(_rule("-", C.GREY))

    print(_rule("=", C.GREY))
    print()

def print_signals(signals: list):
    if not signals:
        print("\n" + _c("  (no signals this cycle)", C.GREY) + "\n")
        return

    entry_signals = [s for s in signals if s.action == "buy"]
    exit_signals  = [s for s in signals if s.action == "sell"]

    print()
    print(_rule("-", C.MAGENTA))
    sub = ""
    if entry_signals: sub += _c(f"  {len(entry_signals)} entry", C.CYAN)
    if exit_signals:  sub += _c(f"  {len(exit_signals)} exit", C.YELLOW)
    n_sig   = len(signals)
    plural  = "S" if n_sig != 1 else ""
    print(f"{_c(f'  >> {n_sig} SIGNAL{plural} THIS CYCLE', C.MAGENTA, C.BOLD)}{sub}")
    print(_rule("-", C.MAGENTA))

    for s in signals:
        is_exit    = s.action == "sell"
        side_color = C.GREEN if s.side == "yes" else C.RED
        tag_bg     = "\033[43m" if is_exit else "\033[46m"
        action_tag = _c(f" {s.action.upper()} {s.side.upper()} ", C.BLACK, C.BOLD, tag_bg)
        strat_str  = _c(f"[{s.strategy}]", C.GREY)

        if s.llm_approved is True:
            llm_badge = _c(" [LLM:OK] ", C.BLACK, C.BOLD, "\033[42m")
        elif s.llm_approved is False:
            llm_badge = _c(" [LLM:NO] ", C.WHITE, C.BOLD, "\033[41m")
        elif s.llm_note:
            llm_badge = _c(" [LLM:?]  ", C.BLACK, "\033[43m")
        else:
            llm_badge = ""

        print(f"\n  {action_tag}  {_c(s.market_ticker, C.WHITE, C.BOLD)}  {strat_str}  {llm_badge}")
        print(f"      {_c('Price', C.GREY)} {_c(str(s.price)+'c', side_color, C.BOLD)}"
              f"   {_c('x', C.GREY)}{_c(str(s.contracts), C.WHITE)}"
              f"   {_c('conf', C.GREY)} {_fmt_conf(int(s.confidence*100))}")
        print(f"      {_c(s.reason, C.GREY)}")
        if s.llm_note and s.llm_note not in ("LLM disabled",):
            print(f"      {_c('# ' + s.llm_note, C.GREY, C.DIM)}")

    print()
    print(_rule("-", C.MAGENTA))
    print()

# ==============================================================================

# HOT-RELOAD

# ==============================================================================

def _get_source_mtime() -> float:
    try:
        return os.path.getmtime(os.path.abspath(__file__))
    except Exception:
        return 0.0

# ==============================================================================

# MAIN BOT LOOP

# ==============================================================================

def run_bot():
    log.info("=" * 68)
    log.info("  Kalshi Sports Bot - Starting")
    log.info(f"  Mode: {'DRY RUN' if Config.DRY_RUN else 'LIVE TRADING'}")
    log.info(f"  LLM assist: {Config.LLM_ASSIST}")
    log.info(f"  Interval: {Config.LOOP_INTERVAL}s")
    log.info(f"  Fetch delay: {Config.FETCH_DELAY_SECS}s")
    log.info(f"  Position max age: {Config.POSITION_MAX_AGE_HOURS}h")
    log.info(f"  Settle min age: {Config.SETTLE_MIN_AGE_MINUTES}m")
    log.info(f"  Take profit: {int(Config.TAKE_PROFIT_PCT*100)}%  |  Stop loss: {int(Config.STOP_LOSS_PCT*100)}%")
    log.info(f"  Slippage sim: {Config.SLIP_CENTS}c per fill")
    log.info(f"  Daily loss limit: -${Config.MAX_DAILY_LOSS_USD:.2f}")
    log.info(f"  Max contracts per event: {Config.MAX_CONTRACTS_PER_EVENT}")
    log.info("=" * 68)

    client = _get_kalshi_client()
    espn_cache = ESPNContextCache()
    _bot_orders = load_bot_orders()
    log.info(f'[Startup] Loaded {len(_bot_orders)} known bot order IDs')
    _tg_state["ok"] = _tg_validate()

    pnl_log        = load_pnl_log()
    open_positions = load_positions()

    # Start price watcher thread
    _watcher = PriceWatcher(
        open_positions    = open_positions,
        client            = client,
        config            = Config,
        save_positions_fn = save_positions,
        save_pnl_fn       = save_pnl_log,
        pnl_log           = pnl_log,
        get_date_fn       = lambda: datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        bot_orders        = _bot_orders,
    )
    _watcher.start()

    n_purged = purge_stale_positions(open_positions)
    if n_purged:
        log.info(f"[Startup] Purged {n_purged} stale position(s)")

    today     = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    total_pnl = pnl_log.get(today, 0.0)
    if total_pnl != 0.0:
        log.info(f"[Startup] Resuming session PNL: ${total_pnl:.4f}")

    last_hour           = datetime.now(timezone.utc).hour
    signal_cooldown     = {}
    # Load persisted cooldowns
    try:
        import json as _j
        if os.path.exists("cooldown.json"):
            _cd = _j.load(open("cooldown.json"))
            now_ts = time.time()
            signal_cooldown = {k:v for k,v in _cd.items() if v > now_ts}
            log.info(f"[Startup] Loaded {len(signal_cooldown)} active cooldowns")
    except: pass
    source_mtime        = _get_source_mtime() if Config.WATCH_SOURCE_FILE else 0.0
    daily_limit_alerted = False

    alert_startup(client, pnl_log, open_positions, total_pnl)
    tg_ctrl = TelegramController(Config, open_positions, pnl_log, client)

    cycle = 0

    while True:
        cycle += 1
        log.info(f"-- Cycle {cycle} " + "-" * 50)

        new_today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        if new_today != today:
            today               = new_today
            daily_limit_alerted = False
            log.info(f"[DailyReset] New UTC day: {today}")

        if Config.WATCH_SOURCE_FILE:
            new_mtime = _get_source_mtime()
            if new_mtime and new_mtime != source_mtime:
                log.info("Source file changed - exiting for hot-reload.")
                _tg_send(f"Bot restarting - source file updated (cycle {cycle})")
                sys.exit(0)

        try:
            purge_stale_positions(open_positions)
            current_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            recon_pnl = reconcile_positions(
                open_positions=open_positions, kalshi_base=Config.KALSHI_BASE,
                client=client, save_fn=save_positions, pnl_log=pnl_log,
                current_date=current_date, save_pnl_fn=save_pnl_log,
                bot_orders=_bot_orders,
            )
            total_pnl += recon_pnl
            espn_cache.refresh()
            espn_cache.summary_log()

            daily_limit_hit = is_daily_loss_limit_hit(total_pnl, pnl_log)
            bot_paused, stop_requested = tg_ctrl.poll(open_positions, total_pnl, pnl_log, daily_limit_hit)
            if stop_requested:
                log.info("Clean stop requested via Telegram.")
                break
            if daily_limit_hit and not daily_limit_alerted:
                log.warning(f"[DailyLimit] PNL ${total_pnl:.2f} breached -${Config.MAX_DAILY_LOSS_USD:.2f}")
                alert_daily_limit(total_pnl)
                daily_limit_alerted = True

            snapshot = get_live_sports_snapshot()
            print_snapshot(snapshot, open_positions, total_pnl, daily_limit_hit)
            watchlist = analyze_snapshot(snapshot)

            now_ts = time.time()
            signal_cooldown = {k: v for k, v in signal_cooldown.items() if v > now_ts}
            watchlist_filtered = [
                item for item in watchlist
                if item["market"].ticker not in signal_cooldown
            ]

            signals = run_strategies(watchlist_filtered, open_positions, total_pnl, pnl_log, daily_limit_hit or bot_paused, espn_cache=espn_cache)

            if Config.LLM_ASSIST:
                evaluated = []
                for signal in signals:
                    if signal.action == "sell":
                        evaluated.append(signal)
                        continue
                    game = None
                    for games in snapshot.values():
                        if signal.event_ticker in games:
                            game = games[signal.event_ticker]
                            break
                    if game:
                        signal = llm_evaluate_signal(signal, game)
                    evaluated.append(signal)
                signals = evaluated

            print_signals(signals)

            trades_placed = 0
            current_date  = datetime.now(timezone.utc).strftime("%Y-%m-%d")

            for signal in signals:
                placed, total_pnl = execute_signal(
                    signal, snapshot, open_positions,
                    total_pnl, pnl_log, current_date, client,
                )
                if placed:
                    trades_placed += 1
                    alert_trade_placed(signal)
                if signal.action == "buy":
                    signal_cooldown[signal.market_ticker] = now_ts + Config.SIGNAL_COOLDOWN_SECS
                    try:
                        import json as _j
                        _atomic_write_json("cooldown.json", signal_cooldown)
                    except: pass

            total_pnl = check_settled_positions(open_positions, total_pnl, pnl_log, current_date)

            alert_cycle_report(snapshot, signals, trades_placed, open_positions, total_pnl, daily_limit_hit)

            current_hour = datetime.now(timezone.utc).hour
            if current_hour != last_hour:
                alert_hourly_pnl(client, total_pnl, open_positions)
                last_hour = current_hour

        except KeyboardInterrupt:
            log.info("Bot stopped by user (Ctrl-C).")
            _watcher.stop()
            _tg_send("Kalshi Bot stopped manually.")
            break

        except Exception as e:
            log.error(f"Cycle error: {e}\n{traceback.format_exc()}")
            alert_error(f"Cycle {cycle}", e)

        log.info(f"Sleeping {Config.LOOP_INTERVAL}s...")
        time.sleep(Config.LOOP_INTERVAL)

# ==============================================================================

# ENTRY POINT

# ==============================================================================

if __name__ == "__main__":
    if "-status" in sys.argv:
        print_status()
    else:
        run_bot()
