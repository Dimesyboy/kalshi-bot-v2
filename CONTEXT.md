# Kalshi Bot — Context File for Claude

## What this is
A live Kalshi sports trading bot running on this server (Ubuntu, /root/).
Trades NBA, MLB, and Tennis prediction markets on Kalshi using automated strategies.

## Architecture
- kalshi_bot.py — main loop, config, executor, fetcher (1790 lines)
- strategies.py — 6 entry strategies + exit logic
- price_watcher.py — background thread, 2s poll, fires exits
- telegram_controller.py — Telegram bot UI for live control
- espn_data.py — ESPN API wrapper for live game context
- nba_context.py / nba_props.py / nba_injuries.py — NBA logic
- mlb_props.py — MLB spring training logic
- tennis_context.py — api-tennis.com live match data
- trade_tracker.py — CSV trade log (/root/trade_log.csv)
- timing.py / trade_timing.py — performance instrumentation
- morning_report.py — daily PNL summary with per-strategy breakdown
- check_stack.py — full stack health check (20 checks)
- sports_snapshot.py — standalone market viewer
- strategies_new.py — experimental simplified strategy (not imported anywhere)
- espn_dump.py / espn_module.py — older ESPN modules (legacy, unused)
- integration_patch.py — notes on Telegram integration
- kalshi_test.py — minimal API connectivity test

## Key config (kalshi_bot.py Config class)
- DRY_RUN = False (live trading)
- POSITION_SIZE_PCT = 8% of balance per trade
- MAX_POSITION_HARD = $10
- TAKE_PROFIT_PCT = 30%
- STOP_LOSS_PCT = 35%
- SIGNAL_COOLDOWN_SECS = 1800
- LOOP_INTERVAL = 45s

## Recent changes (March 2026)
- strategies.py: added stale price guard (_is_stale_high) — skips markets
  pinned at 95c+ for >2 minutes (correctly priced, not a fade opportunity)
- strategies.py: raised confidence floor from 0.60 to 0.63 across all strategies
- strategies.py: tightened live NBA fade lead threshold from 8 to 5 points
- strategies.py: raised EV gate from 0.08 to 0.12 (except MLB spring training)
- price_watcher.py: added 50% profit lock (QUICK_PROFIT_MULT=1.5) — exits
  immediately when bid >= entry * 1.5, capturing brief spikes before reversal
- morning_report.py: fixed strategy PNL attribution — now reads trade_log.csv
  correctly, strips exit/watcher prefixes to show base strategy performance
- trade_log.csv: fixed column mismatch (old 9-col header vs new 16-col rows)

## Current performance (as of March 18 2026)
- Balance: $2.11
- All-time PNL: -$15.93
- tennis_underdog: 39 trades, 10.3% win rate, -$6.24
- manual: 5 trades, 0% win rate, -$6.87
- Primary issue: tennis underdog positions spike briefly then reverse —
  50% profit lock added to capture these spikes

## How to run
python3 kalshi_bot.py         # run bot
python3 kalshi_bot.py -status # print PNL + positions
python3 check_stack.py        # health check
python3 morning_report.py     # daily report with strategy breakdown

## Claude preferences (from user)
- Use cat EOF autowriting style for all file updates
- Add echo confirmations after each file write
- Provide one-liner tests after each change to verify it landed
- Do not commit changes until user confirms tests pass
- When making changes, plan them explicitly before writing

## GitHub repo
https://github.com/Dimesyboy/kalshi-bot (keep private)
To give Claude access: temporarily make public, share URL, Claude fetches
CONTEXT.md first then fetches specific files needed for the task.

## Last updated
March 18 2026
