# kalshi_bot.py integration patch

# Apply these 4 changes to kalshi_bot.py

# ─────────────────────────────────────────────────────────────────────────────

# ── CHANGE 1 ──────────────────────────────────────────────────────────────────

# At the top of the file, after `load_dotenv()`, add:

from telegram_controller import TelegramController

# ── CHANGE 2 ──────────────────────────────────────────────────────────────────

# In run_bot(), after:

# alert_startup(client, pnl_log, open_positions, total_pnl)

# Add:

tg_ctrl = TelegramController(Config, open_positions, pnl_log, client)

# ── CHANGE 3 ──────────────────────────────────────────────────────────────────

# In the while True loop, replace:

# cycle += 1

# log.info(f”– Cycle {cycle} “ + “-” * 50)

# With:

cycle += 1
log.info(f”– Cycle {cycle} “ + “-” * 50)
bot_paused, stop_requested = tg_ctrl.poll(
open_positions, total_pnl, pnl_log, daily_limit_hit,
)
if stop_requested:
log.info(“Clean stop requested via Telegram.”)
_tg_send(“🔴 Bot stopped cleanly.”)
break

# ── CHANGE 4 ──────────────────────────────────────────────────────────────────

# In run_strategies() call, change daily_limit_hit to:

# daily_limit_hit or bot_paused

# So the line becomes:

signals = run_strategies(
watchlist_filtered, open_positions, total_pnl,
pnl_log, daily_limit_hit or bot_paused,
)

# ── OPTIONAL: read runtime config settings each cycle ─────────────────────────

# If you want take profit / stop loss changes to take effect immediately,

# Config is already patched in-place by the controller’s _handle_setting().

# No extra code needed — strategy_exit reads Config.TAKE_PROFIT_CENTS directly.
