#!/usr/bin/env python3
"""
telegram_bot.py — kalshi-bot-v2
Telegram control panel with inline keyboards and formatted parlay suggestions.
"""

import logging
import os
import sys
import csv
import json
import requests as req
from datetime import datetime, timezone
from collections import defaultdict

import sys as _sys
_sys.path = [p for p in _sys.path if 'kalshi-bot-v2' not in p]
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes, MessageHandler, filters
_sys.path.insert(0, '/root/kalshi-bot-v2')

from core.config import config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("telegram_bot")

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"

STAT_LABELS = {
    'KXNBAPTS': 'pts', 'KXNBAREB': 'reb',
    'KXNBAAST': 'ast', 'KXNBA3PT': '3s',
    'KXNBASTL': 'stl', 'KXNBABLK': 'blk',
}

# ── Game schedule cache ────────────────────────────────────────────────────

_game_times = {}

def get_game_times() -> dict:
    """Return {game_code: tip_time_str} e.g. {'NYKOKC': '7:30 PM ET'}"""
    global _game_times
    if _game_times:
        return _game_times
    try:
        from datetime import date
        today = date.today().strftime("%Y%m%d")
        r = req.get(
            f"https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates={today}",
            timeout=6
        )
        for event in r.json().get("events", []):
            dt_str = event.get("date", "")
            teams  = event.get("competitions", [{}])[0].get("competitors", [])
            if len(teams) == 2 and dt_str:
                t1 = teams[0].get("team", {}).get("abbreviation", "")
                t2 = teams[1].get("team", {}).get("abbreviation", "")
                dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                et = dt.astimezone()
                tip = et.strftime("%-I:%M %p ET")
                _game_times[f"{t1}{t2}"] = tip
                _game_times[f"{t2}{t1}"] = tip
    except Exception as e:
        log.debug(f"Game times fetch failed: {e}")
    return _game_times


# ── LLM reasoning ──────────────────────────────────────────────────────────

def explain_leg(leg) -> str:
    if not config.ANTHROPIC_API_KEY:
        return ""
    series    = leg.ticker.split('-')[0]
    stat_name = {'KXNBAPTS':'points','KXNBAREB':'rebounds','KXNBAAST':'assists',
                 'KXNBA3PT':'threes','KXNBASTL':'steals','KXNBABLK':'blocks'}.get(series,'stat')
    threshold = leg.ticker.split('-')[-1]
    prompt = (f"One sentence (max 10 words): why will {leg.reasoning.split(' avg')[0]} "
              f"get {threshold}+ {stat_name} tonight? Be specific, no fluff.")
    try:
        r = req.post(ANTHROPIC_URL, headers={
            "x-api-key": config.ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }, json={
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 50,
            "messages": [{"role": "user", "content": prompt}],
        }, timeout=8)
        return r.json().get("content", [{}])[0].get("text", "").strip()
    except Exception:
        return ""


# ── Message formatter ──────────────────────────────────────────────────────

def format_parlay(candidate, legs_with_reasons: list) -> str:
    import re
    payout   = candidate.expected_payout
    conf_pct = candidate.combined_confidence * 100
    win_amt  = round(5.0 * payout, 0)
    game_times = get_game_times()

    lines = [
        f"🎯 *{len(legs_with_reasons)}-leg combo* • *{payout:.1f}x* • {conf_pct:.1f}% conf",
        f"💰 $5 → *${win_amt:.0f}* if all hit",
        ""
    ]

    # Group by game
    games = {}
    for leg, reason in legs_with_reasons:
        m = re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', leg.ticker.split('-')[1])
        code     = m.group(1) if m else "????"
        t1, t2   = code[:3], code[3:6]
        tip      = game_times.get(code, "")
        game_key = f"{t1} vs {t2}"
        label    = f"{game_key}{' • ' + tip if tip else ''}"
        games.setdefault(label, []).append((leg, reason))

    for game_label, game_legs in games.items():
        lines.append(f"🏀 *{game_label}*")
        for leg, reason in game_legs:
            series    = leg.ticker.split('-')[0]
            stat      = STAT_LABELS.get(series, '')
            threshold = leg.ticker.split('-')[-1]
            player    = leg.reasoning.split(' avg')[0] if ' avg' in leg.reasoning else ''
            avg       = leg.reasoning.split('avg ')[1].split(' vs')[0] if 'avg' in leg.reasoning else ''
            price     = int(leg.implied_prob * 100)
            lines.append(f"• {player} {threshold}+ {stat} _{price}¢_ — avg {avg}")
            if reason:
                lines.append(f"  _{reason}_")
        lines.append("")

    return "\n".join(lines)


# ── Keyboards ──────────────────────────────────────────────────────────────

def main_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🎯 Best Parlay", callback_data="parlay"),
         InlineKeyboardButton("📊 Stats",       callback_data="stats")],
        [InlineKeyboardButton("💵 Balance",     callback_data="balance"),
         InlineKeyboardButton("📋 Positions",   callback_data="positions")],
        [InlineKeyboardButton("⚙️ Settings",    callback_data="settings"),
         InlineKeyboardButton("🔄 Refresh",     callback_data="menu")],
    ])

def settings_keyboard():
    max_bet = os.popen("grep MAX_POSITION_USD /root/.env | tail -1").read().strip().split('=')[-1]
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(f"💰 Max Bet: ${max_bet}", callback_data="set_maxbet")],
        [InlineKeyboardButton("🔙 Back", callback_data="menu")],
    ])


# ── Command handlers ───────────────────────────────────────────────────────

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 *Kalshi Bot v2*\nWhat would you like to do?",
        parse_mode="Markdown",
        reply_markup=main_menu_keyboard()
    )

async def cmd_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 *Kalshi Bot v2*",
        parse_mode="Markdown",
        reply_markup=main_menu_keyboard()
    )


# ── Callback handlers ──────────────────────────────────────────────────────

async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data  = query.data

    if data == "menu":
        await query.edit_message_text(
            "🤖 *Kalshi Bot v2*",
            parse_mode="Markdown",
            reply_markup=main_menu_keyboard()
        )

    elif data == "parlay":
        await query.edit_message_text("🔍 Scanning props...")
        try:
            from combo_scanner import scan_all_props, build_best_combo
            legs      = scan_all_props()
            candidate = build_best_combo(legs)
            if not candidate:
                await query.edit_message_text(
                    "❌ No qualifying combo right now.\nTry closer to game time.",
                    reply_markup=InlineKeyboardMarkup([[
                        InlineKeyboardButton("🔙 Menu", callback_data="menu")
                    ]])
                )
                return
            await query.edit_message_text(f"✅ Found {len(candidate.legs)}-leg combo — analysing...")
            legs_with_reasons = [(leg, explain_leg(leg)) for leg in candidate.legs]
            msg = format_parlay(candidate, legs_with_reasons)
            await query.edit_message_text(
                msg,
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("🔄 Rescan", callback_data="parlay"),
                    InlineKeyboardButton("🔙 Menu",   callback_data="menu")
                ]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ Error: {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "stats":
        try:
            paper_file = "/root/kalshi-bot-v2/data/paper_trades.csv"
            v1_file    = "/root/trade_log.csv"
            lines      = ["📊 *Trading Stats*\n"]

            # V1 live stats
            if os.path.exists(v1_file):
                rows = list(csv.DictReader(open(v1_file)))
                total_pnl = sum(float(r.get('pnl',0) or 0) for r in rows)
                lines.append(f"*V1 Bot (live)*")
                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\n")

            # V2 paper stats
            if os.path.exists(paper_file):
                rows     = list(csv.DictReader(open(paper_file)))
                resolved = [r for r in rows if r.get('resolved','') not in ('','no')]
                if resolved:
                    wins    = sum(1 for r in resolved if float(r.get('hyp_pnl',0) or 0) > 0)
                    pnl     = sum(float(r.get('hyp_pnl',0) or 0) for r in resolved)
                    wr      = wins/len(resolved)*100
                    lines.append(f"*V2 Paper*")
                    lines.append(f"Resolved: {len(resolved)} | WR: {wr:.0f}% | PNL: ${pnl:+.2f}")
                else:
                    lines.append("*V2 Paper*\nNo resolved trades yet")

            await query.edit_message_text(
                "\n".join(lines),
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "balance":
        try:
            from core.kalshi_client import get_balance
            balance = get_balance()
            max_bet = os.popen("grep MAX_POSITION_USD /root/.env | tail -1").read().strip().split('=')[-1]
            await query.edit_message_text(
                f"💵 *Balance*\n\nCash: ${balance:.2f}\nMax bet: ${max_bet}",
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "positions":
        try:
            pos_file = "/root/kalshi-bot-v2/data/positions.json"
            if os.path.exists(pos_file):
                positions = json.load(open(pos_file))
                if positions:
                    lines = [f"📋 *Open Positions* ({len(positions)})\n"]
                    for ticker, pos in list(positions.items())[:8]:
                        entry = pos.get('entry_price', 0)
                        lines.append(f"• {ticker[-20:]} @ {entry}¢")
                    await query.edit_message_text(
                        "\n".join(lines),
                        parse_mode="Markdown",
                        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
                    )
                else:
                    await query.edit_message_text(
                        "📋 No open positions",
                        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
                    )
            else:
                await query.edit_message_text(
                    "📋 No positions file found",
                    reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
                )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "settings":
        await query.edit_message_text(
            "⚙️ *Settings*\n\nTap to change:",
            parse_mode="Markdown",
            reply_markup=settings_keyboard()
        )

    elif data == "set_maxbet":
        context.user_data['awaiting'] = 'maxbet'
        await query.edit_message_text(
            "💰 Enter new max bet amount (e.g. 1.00):",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Cancel", callback_data="settings")]])
        )


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle text input for settings."""
    awaiting = context.user_data.get('awaiting')

    if awaiting == 'maxbet':
        try:
            val = float(update.message.text.strip())
            if val <= 0 or val > 100:
                await update.message.reply_text("❌ Enter a value between 0.01 and 100")
                return
            # Update .env
            env_path = '/root/.env'
            lines    = open(env_path).readlines()
            lines    = [l for l in lines if not l.startswith('MAX_POSITION_USD=')]
            lines.append(f'MAX_POSITION_USD={val:.2f}\n')
            open(env_path, 'w').writelines(lines)
            context.user_data['awaiting'] = None
            await update.message.reply_text(
                f"✅ Max bet updated to ${val:.2f}",
                reply_markup=main_menu_keyboard()
            )
        except ValueError:
            await update.message.reply_text("❌ Invalid amount — enter a number like 1.00")


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    if not config.TELEGRAM_BOT_TOKEN:
        log.error("No TELEGRAM_BOT_TOKEN")
        sys.exit(1)

    app = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("menu",  cmd_menu))
    app.add_handler(CallbackQueryHandler(handle_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    log.info("Telegram bot started")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
