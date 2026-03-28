#!/usr/bin/env python3
"""
telegram_bot.py
─────────────────────────────────────────────────────────────────────────────
Telegram command listener for kalshi-bot-v2.

Commands:
    /parlay  — Find and explain today's best combo
    /stats   — Show paper trader stats
    /balance — Show current balance

Run in a screen session alongside the main bot.
"""

import logging
import os
import sys
import json
import requests as req

import sys as _sys
_sys.path = [p for p in _sys.path if "kalshi-bot-v2" not in p]
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
_sys.path.insert(0, '/root/kalshi-bot-v2')

sys.path.insert(0, '/root/kalshi-bot-v2')
from core.config import config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("telegram_bot")

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"


# ── LLM reasoning ─────────────────────────────────────────────────────────

STAT_LABELS = {
    'KXNBAPTS': 'points', 'KXNBAREB': 'rebounds',
    'KXNBAAST': 'assists', 'KXNBA3PT': 'threes',
    'KXNBASTL': 'steals',  'KXNBABLK': 'blocks',
}

def explain_leg(leg) -> str:
    """Ask Claude Haiku to explain why this leg is a good pick in one sentence."""
    if not config.ANTHROPIC_API_KEY:
        return f"avg {leg.reasoning.split('avg')[1].split('→')[0].strip() if 'avg' in leg.reasoning else ''}"

    series    = leg.ticker.split('-')[0]
    stat_name = STAT_LABELS.get(series, 'stat')
    threshold = leg.ticker.split('-')[-1]

    prompt = f"""You are a sharp sports analyst. Explain in ONE concise sentence (max 12 words) why this player prop is a good combo leg tonight.

Player stat: {leg.reasoning}
Stat type: {stat_name}
Threshold: {threshold}+

Focus specifically on {stat_name} — why will this player get {threshold}+ {stat_name} tonight?
Be specific and accurate. Just the sentence, no preamble."""

    try:
        headers = {
            "x-api-key":         config.ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type":      "application/json",
        }
        body = {
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 60,
            "messages":   [{"role": "user", "content": prompt}],
        }
        r    = req.post(ANTHROPIC_URL, headers=headers, json=body, timeout=8)
        text = r.json().get("content", [{}])[0].get("text", "").strip()
        return text
    except Exception as e:
        log.debug(f"LLM error: {e}")
        return ""


def format_parlay_message(candidate, legs_with_reasons: list[tuple]) -> str:
    """Format the combo into a clean Telegram message."""
    payout     = candidate.expected_payout
    conf_pct   = candidate.combined_confidence * 100
    stake      = 5.00
    win_amount = round(stake * payout, 2)

    # Group legs by game
    games = {}
    for leg, reason in legs_with_reasons:
        # Extract game from ticker e.g. KXNBAPTS-26MAR29NYKOKC → NYK vs OKC
        import re as _re
        parts = leg.ticker.split('-')
        if len(parts) >= 2:
            # e.g. 26MAR29NYKOKC → extract NYKOKC
            m = _re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', parts[1])
            if m:
                code = m.group(1)
                t1, t2 = code[:3], code[3:6]
                game_key = f"{t1} vs {t2}"
            else:
                game_key = parts[1]
        else:
            game_key = "Other"
        games.setdefault(game_key, []).append((leg, reason))

    lines = [
        f"🎯 Best Combo — {len(legs_with_reasons)} legs",
        f"📊 {conf_pct:.1f}% combined conf | {payout:.1f}x payout",
        f"💰 $5 → ${win_amount:.0f} if all hit",
        ""
    ]

    stat_labels = {
        'KXNBAPTS': 'pts', 'KXNBAREB': 'reb',
        'KXNBAAST': 'ast', 'KXNBA3PT': '3s',
        'KXNBASTL': 'stl', 'KXNBABLK': 'blk',
    }

    for game, game_legs in games.items():
        lines.append(f"🏀 {game}")
        for leg, reason in game_legs:
            series    = leg.ticker.split('-')[0]
            label     = stat_labels.get(series, '')
            threshold = leg.ticker.split('-')[-1]
            player    = leg.reasoning.split(' avg')[0] if ' avg' in leg.reasoning else ''
            avg       = leg.reasoning.split('avg ')[1].split(' vs')[0] if 'avg' in leg.reasoning else ''
            price     = int(leg.implied_prob * 100)

            lines.append(f"• {player} {threshold}+ {label} ({price}¢) avg {avg}")
            if reason:
                lines.append(f"  → {reason}")
        lines.append("")

    lines.append("⚡ Place manually in Kalshi app")
    return "\n".join(lines)


# ── Command handlers ───────────────────────────────────────────────────────

async def cmd_parlay(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /parlay command."""
    await update.message.reply_text("🔍 Scanning props... give me a sec")

    try:
        from combo_scanner import scan_all_props, build_best_combo
        legs      = scan_all_props()
        candidate = build_best_combo(legs)

        if not candidate:
            await update.message.reply_text("❌ No qualifying combo found right now. Try closer to game time.")
            return

        # Get LLM reasoning for each leg
        await update.message.reply_text(f"✅ Found {len(candidate.legs)}-leg combo — generating analysis...")

        legs_with_reasons = []
        for leg in candidate.legs:
            reason = explain_leg(leg)
            legs_with_reasons.append((leg, reason))

        msg = format_parlay_message(candidate, legs_with_reasons)
        await update.message.reply_text(msg)

    except Exception as e:
        log.error(f"Parlay command error: {e}")
        await update.message.reply_text(f"❌ Error: {str(e)[:100]}")


async def cmd_stats(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /stats command — paper trader results."""
    try:
        import csv
        from collections import defaultdict

        paper_file = "/root/kalshi-bot-v2/data/paper_trades.csv"
        if not os.path.exists(paper_file):
            await update.message.reply_text("No paper trades yet.")
            return

        rows     = list(csv.DictReader(open(paper_file)))
        resolved = [r for r in rows if r.get("resolved","") not in ("","no")]
        pending  = len(rows) - len(resolved)

        if not resolved:
            await update.message.reply_text(f"No resolved trades yet. {pending} pending.")
            return

        strats = defaultdict(lambda: {"n":0,"wins":0,"pnl":0.0})
        for r in resolved:
            s   = r.get("strategy","?")
            pnl = float(r.get("hyp_pnl",0) or 0)
            strats[s]["n"]   += 1
            strats[s]["pnl"] += pnl
            if pnl > 0: strats[s]["wins"] += 1

        lines = [f"📊 Paper Trader v2 — {len(resolved)} resolved / {len(rows)} total\n"]
        total_pnl = 0.0
        for s, d in sorted(strats.items()):
            wr  = d["wins"]/d["n"]*100 if d["n"] else 0
            avg = d["pnl"]/d["n"] if d["n"] else 0
            total_pnl += d["pnl"]
            lines.append(f"{s}\n  n={d['n']} WR={wr:.0f}% PNL=${d['pnl']:+.2f} avg=${avg:+.3f}")

        lines.append(f"\nTotal PNL: ${total_pnl:+.2f}")
        await update.message.reply_text("\n".join(lines))

    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)[:100]}")


async def cmd_balance(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /balance command."""
    try:
        from core.kalshi_client import get_balance
        balance = get_balance()
        await update.message.reply_text(f"💵 Balance: ${balance:.2f}")
    except Exception as e:
        await update.message.reply_text(f"❌ Error: {str(e)[:100]}")


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 Kalshi Bot v2\n\n"
        "/parlay — Best combo pick with analysis\n"
        "/stats  — Paper trader results\n"
        "/balance — Current balance"
    )


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    if not config.TELEGRAM_BOT_TOKEN:
        log.error("No TELEGRAM_BOT_TOKEN in .env")
        sys.exit(1)

    app = Application.builder().token(config.TELEGRAM_BOT_TOKEN).build()
    app.add_handler(CommandHandler("start",   cmd_start))
    app.add_handler(CommandHandler("parlay",  cmd_parlay))
    app.add_handler(CommandHandler("stats",   cmd_stats))
    app.add_handler(CommandHandler("balance", cmd_balance))

    log.info("Telegram bot started — polling for commands")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
