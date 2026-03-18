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
- trade_tracker.py — CSV trade log
- timing.py / trade_timing.py — performance instrumentation
- morning_report.py — daily PNL summary
- check_stack.py — full stack health check
- sports_snapshot.py — standalone market viewer
- strategies_new.py — experimental simplified strategy file
- espn_dump.py / espn_module.py — older ESPN modules (legacy)
- integration_patch.py — notes on Telegram integration
- kalshi_test.py — minimal API connectivity test

## Key config (kalshi_bot.py Config class)
- DRY_RUN = False (live trading)
- POSITION_SIZE_PCT = 8% of balance per trade
- MAX_POSITION_HARD = $10
- TAKE_PROFIT_PCT = 30%
- STOP_LOSS_PCT = 35%
- SIGNAL_COOLDOWN_SECS = 1800

## How to run
python3 kalshi_bot.py         # run bot
python3 kalshi_bot.py -status # print PNL + positions
python3 check_stack.py        # health check
python3 morning_report.py     # daily report

## GitHub repo
https://github.com/Dimesyboy/kalshi-bot (private)
To give Claude access: temporarily make public, share URL, Claude fetches files

## Last updated
$(date)
