# Kalshi Sports Trading Bot 🚀

**Automated edge trading for NBA, Tennis & MLB event contracts on Kalshi**
*(CFTC-regulated prediction market — live trading bot)*

---

## What it does (layman's version)

A bot that runs 24/7 on a VPS, checks Kalshi every **45 seconds**, pulls
**live scores and injury data** from ESPN, spots when the market is pricing
a team or player too high or too low, and buys or sells contracts to capture
the difference.

It risks a small fixed amount per trade, locks profits at **+50% gain** on
entry price, cuts losses at **-30 to -35%**, and sends you **Telegram alerts**
for every trade and status update.

Goal: **small, fast, repeatable wins** while you sleep or watch the game.
NOT gambling. NOT long-term holding. Pure edge trading on mispriced markets.

---

## Strategies

| Strategy | What it does | Status |
|---|---|---|
| value_fade | Buys NO on heavy favorites (95c+) that are overpriced | Active |
| tennis_underdog | Buys YES on live tennis underdogs at 20-38c when match is competitive | Active |
| prop_nba | Buys YES on NBA player props using season avg + hit rate model | Active |
| mlb_underdog | Buys cheaper side on MLB spring training using win record edge | Active |
| quarter_winner | Buys contested Q/H winner markets pre-game at 40-60c | Active |
| prop_yes | Generic prop YES — replaced by prop_nba | Disabled |

---

## Architecture

kalshi_bot.py          — Main loop, config, executor, market fetcher
strategies.py          — All entry strategies + exit logic
price_watcher.py       — Background thread (2s poll), fires exits instantly
telegram_controller.py — Full Telegram bot UI for live remote control
espn_data.py           — ESPN API wrapper (NBA/MLB/Tennis live context)
nba_context.py         — Maps Kalshi NBA tickers to ESPN game state
nba_props.py           — NBA player prop hit rate model
nba_injuries.py        — ESPN injury report, boosts confidence on teammate out
mlb_props.py           — MLB spring training record-based edge
tennis_context.py      — api-tennis.com live match data
trade_tracker.py       — CSV trade log at /root/trade_log.csv
morning_report.py      — Daily PNL report with per-strategy breakdown
check_stack.py         — 20-point health check for the full stack
sports_snapshot.py     — Standalone live market viewer
timing.py              — Cycle timing instrumentation
trade_timing.py        — Per-trade step timing

---

## Key config (kalshi_bot.py Config class)

DRY_RUN = False           set True to simulate without real orders
LOOP_INTERVAL = 45s       how often the main loop runs
POSITION_SIZE_PCT = 8%    percent of balance per trade
MAX_POSITION_HARD = $10   hard cap regardless of balance
MAX_OPEN_POSITIONS = 4-8  scales with balance
SIGNAL_COOLDOWN = 1800s   30 min cooldown per ticker after entry
MIN_VOLUME = 5000-8000    minimum market volume to consider
MAX_SPREAD_CENTS = 8c     skip illiquid markets

---

## Exit logic

Price watcher runs every 2 seconds:
- 50% profit lock — exits when bid >= entry * 1.5 (captures brief spikes)
- Trail stop at 82% of peak once $0.50+ profit
- Trail stop at 88% of peak once $2.00+ profit
- Stop loss at 70% of entry price
- Floor exit if bid drops to 5c on entry above 15c

Tennis-specific:
- Dynamic TP/SL tightens as match completion % increases
- Exits immediately on match over
- Locks profit on final set tiebreak

---

## How to run

python3 kalshi_bot.py          — run the bot
python3 kalshi_bot.py -status  — print PNL and open positions
python3 morning_report.py      — daily strategy breakdown report
python3 check_stack.py         — full health check
python3 sports_snapshot.py     — view live markets without trading

---

## Setup

1. Clone repo
   git clone https://github.com/Dimesyboy/kalshi-bot

2. Install dependencies
   pip install kalshi-python python-dotenv requests cryptography

3. Create .env file with:
   KALSHI_API_KEY_ID=your_key_id
   KALSHI_PRIVATE_KEY_PATH=/path/to/private_key.pem
   TELEGRAM_BOT_TOKEN=your_telegram_token
   TELEGRAM_CHAT_ID=your_chat_id

4. Run health check
   python3 check_stack.py

5. Start bot
   python3 kalshi_bot.py

---

## Recent changes (March 2026)

- 50% profit lock added to price_watcher.py — exits at entry * 1.5
- Stale price guard in strategies.py — skips markets pinned at 95c+ for over 2 minutes
- Confidence floor raised from 0.60 to 0.63 across all strategies
- Live NBA fade tightened — lead threshold reduced from 8 to 5 points
- EV gate raised from 0.08 to 0.12 except MLB spring training
- Morning report fixed — per-strategy trade count, win%, and PNL
- trade_log.csv fixed — column mismatch between old and new format resolved

---

## Current performance (March 18 2026)

Strategy           Trades   Win%      PNL
tennis_underdog       39   10.3%   -$6.24
manual                 5    0.0%   -$6.87
reconciled             1    0.0%   -$0.37
TOTAL                 45    8.9%  -$13.48

Balance: $2.11 | All-time PNL: -$15.93

Primary finding: tennis underdog positions spike briefly then reverse.
50% profit lock added to capture these spikes going forward.

---

## Giving Claude access (new chat workflow)

1. Make repo public temporarily
2. Share https://github.com/Dimesyboy/kalshi-bot in new chat
3. Claude reads CONTEXT.md first, then fetches files as needed
4. Make repo private again when done

---

## Roadmap

- Tennis underdog momentum filter (only enter on stable or rising price)
- Split tennis entry tiers: 20-28c longshot vs 29-38c contested
- More value_fade data before tightening further
- Historical backtester on fills data
- Kelly criterion position sizing
- Sportradar API for richer live context
