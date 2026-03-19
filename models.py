#!/usr/bin/env python3
"""
models.py
─────────────────────────────────────────────────────────────────
Shared data structures and config for kalshi_bot.
Extracted here to break the circular import between
kalshi_bot.py and strategies.py.
─────────────────────────────────────────────────────────────────
"""
import os
from dataclasses import dataclass, field
from typing import Optional
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"), override=False)
load_dotenv("/root/.env", override=False)


class Config:
    # -- Bot control -----------------------------------------------------------
    DRY_RUN         = False
    LOOP_INTERVAL   = 45
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
    LLM_CONFIDENCE_THRESHOLD = 0.58

    # -- Trade thresholds ------------------------------------------------------
    MIN_VOLUME          = 5000
    MAX_SPREAD_CENTS    = 8
    MIN_LIQUIDITY       = 0.0
    MAX_POSITION_USD    = 1.00
    MAX_OPEN_POSITIONS  = 4
    POSITION_SIZE_PCT   = 0.08
    MAX_POSITION_HARD   = 10.00
    MAX_OPEN_HARD       = 8
    MAX_CONTRACTS       = 20
    MIN_NO_PRICE        = 5

    # -- Overexposure guard ----------------------------------------------------
    MAX_CONTRACTS_PER_EVENT = 20

    # -- Exit thresholds -------------------------------------------------------
    TAKE_PROFIT_PCT = 0.30
    STOP_LOSS_PCT   = 0.35

    # -- Slippage simulation (dry-run only) ------------------------------------
    SLIP_CENTS = 1

    # -- Daily loss limit ------------------------------------------------------
    MAX_DAILY_LOSS_USD = 999999.00  # OFF for testing

    # -- Stale position pruning ------------------------------------------------
    POSITION_MAX_AGE_HOURS  = 8
    SETTLE_MIN_AGE_MINUTES  = 30

    # -- Signal cooldown -------------------------------------------------------
    SIGNAL_COOLDOWN_SECS = 1800

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


@dataclass
class Market:
    ticker:        str
    title:         str
    yes_bid:       float
    yes_ask:       float
    no_bid:        float
    no_ask:        float
    last_price:    float
    volume:        float
    liquidity:     float
    close_time:    Optional[str]
    series:        str
    label:         str
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
    second_entry:  bool            = False
