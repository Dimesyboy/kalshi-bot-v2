import os
import sys
import json
import time
import logging
import math
import requests
import subprocess
from datetime import datetime, timezone, timedelta
from typing import Optional

log = logging.getLogger("kalshi_bot")

class RuntimeConfig:
    def __init__(self, base_config):
        self.DRY_RUN           = base_config.DRY_RUN
        self.LLM_ASSIST        = base_config.LLM_ASSIST
        self.TAKE_PROFIT_PCT   = getattr(base_config, "TAKE_PROFIT_PCT", 0.30)
        self.STOP_LOSS_PCT     = getattr(base_config, "STOP_LOSS_PCT",   0.35)
        # FIX: CENTS versions derived from PCT — these are what the UI buttons use
        self.TAKE_PROFIT_CENTS = int(self.TAKE_PROFIT_PCT * 100)
        self.STOP_LOSS_CENTS   = int(self.STOP_LOSS_PCT   * 100)
        self.MAX_POSITION_USD  = base_config.MAX_POSITION_USD
        self.MIN_VOLUME        = base_config.MIN_VOLUME

    def summary(self):
        mode = "DRY RUN" if self.DRY_RUN else "LIVE"
        llm  = "ON" if self.LLM_ASSIST else "OFF"
        return (
            "<b>Current Settings</b>\n"
            f"Mode:          <code>{mode}</code>\n"
            f"LLM:           <code>{llm}</code>\n"
            f"Take Profit:   <code>{self.TAKE_PROFIT_CENTS}c</code>\n"
            f"Stop Loss:     <code>{self.STOP_LOSS_CENTS}c</code>\n"
            f"Max Pos USD:   <code>${self.MAX_POSITION_USD:.2f}</code>\n"
            f"Min Volume:    <code>{int(self.MIN_VOLUME)}</code>"
        )


def _main_keyboard(paused):
    pause_btn = "Resume" if paused else "Pause"
    return {
        "inline_keyboard": [
            [
                {"text": "Status",         "callback_data": "cmd_status"},
                {"text": "PNL Report",     "callback_data": "cmd_pnl"},
            ],
            [
                {"text": pause_btn,        "callback_data": "cmd_pause_toggle"},
                {"text": "Settings",       "callback_data": "cmd_settings"},
            ],
            [
                {"text": "Soft Close All", "callback_data": "cmd_soft_close"},
                {"text": "Hard Close All", "callback_data": "cmd_hard_close"},
            ],
            [
                {"text": "Restart",        "callback_data": "cmd_restart"},
                {"text": "Stop Bot",       "callback_data": "cmd_stop"},
            ],
        ]
    }

def _settings_keyboard(rt):
    dry_label = "Switch to LIVE" if rt.DRY_RUN else "Switch to DRY RUN"
    llm_label = "LLM: OFF" if rt.LLM_ASSIST else "LLM: ON"
    return {
        "inline_keyboard": [
            [{"text": dry_label,                              "callback_data": "set_dry_toggle"}],
            [{"text": llm_label,                              "callback_data": "set_llm_toggle"}],
            [{"text": f"TP +1c (now {rt.TAKE_PROFIT_CENTS}c)", "callback_data": "set_tp_up"},
             {"text": "TP -1c",                               "callback_data": "set_tp_down"}],
            [{"text": f"SL +1c (now {rt.STOP_LOSS_CENTS}c)",  "callback_data": "set_sl_up"},
             {"text": "SL -1c",                               "callback_data": "set_sl_down"}],
            [{"text": f"MaxPos +1 (now ${rt.MAX_POSITION_USD:.0f})", "callback_data": "set_pos_up"},
             {"text": "MaxPos -1",                            "callback_data": "set_pos_down"}],
            [{"text": f"MinVol +250 (now {int(rt.MIN_VOLUME)})", "callback_data": "set_vol_up"},
             {"text": "MinVol -250",                          "callback_data": "set_vol_down"}],
            [{"text": "Back",                                 "callback_data": "cmd_back"}],
        ]
    }

def _confirm_keyboard(action):
    return {
        "inline_keyboard": [[
            {"text": "Confirm", "callback_data": f"confirm_{action}"},
            {"text": "Cancel",  "callback_data": "cmd_back"},
        ]]
    }

def _calc_fee(contracts, price_dollars, maker=True):
    mult = 0.0175 if maker else 0.07
    return math.ceil(mult * contracts * price_dollars * (1 - price_dollars) * 100) / 100.0


class TelegramController:
    # FIX: only send cycle reports every N minutes, not every 30s
    CYCLE_REPORT_INTERVAL_SECS = 1800  # 30 minutes

    def __init__(self, base_config, open_positions, pnl_log, kalshi_client=None):
        self.token       = base_config.TELEGRAM_TOKEN
        self.chat_id     = str(base_config.TELEGRAM_CHAT)
        self.client      = kalshi_client
        self.rt          = RuntimeConfig(base_config)
        self.base_config = base_config
        self._paused         = False
        self._stop_requested = False
        self._last_update_id = None
        self._total_pnl      = 0.0
        self._positions      = open_positions
        self._pnl_log        = pnl_log
        self._last_cycle_report = 0.0  # timestamp of last cycle report
        self._send("Control Panel Ready - Bot is running.", reply_markup=_main_keyboard(self._paused))

    def poll(self, open_positions, total_pnl, pnl_log, daily_limit_hit, snapshot=None):
        self._positions = open_positions
        self._pnl_log   = pnl_log
        self._total_pnl = total_pnl
        try:
            updates = self._get_updates()
            for upd in updates:
                self._handle_update(upd, daily_limit_hit, snapshot)
        except Exception as e:
            log.warning(f"[TGCtrl] Poll error: {e}")
        return self._paused, self._stop_requested

    @property
    def runtime_config(self):
        return self.rt

    def _api(self, method, **kwargs):
        try:
            r = requests.post(
                f"https://api.telegram.org/bot{self.token}/{method}",
                json=kwargs, timeout=6,
            )
            r.raise_for_status()
            return r.json()
        except Exception as e:
            log.warning(f"[TGCtrl] {method} failed: {e}")
            return {}

    def _send(self, text, reply_markup=None, parse_mode="HTML"):
        payload = {"chat_id": int(self.chat_id), "text": text, "parse_mode": parse_mode}
        if reply_markup:
            payload["reply_markup"] = reply_markup
        result = self._api("sendMessage", **payload)
        return result.get("result", {}).get("message_id")

    def _edit(self, message_id, text, reply_markup=None):
        payload = {
            "chat_id":    int(self.chat_id),
            "message_id": message_id,
            "text":       text,
            "parse_mode": "HTML",
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup
        self._api("editMessageText", **payload)

    def _answer_callback(self, callback_id, text=""):
        try:
            self._api("answerCallbackQuery", callback_query_id=callback_id, text=text)
        except Exception:
            pass  # stale callback IDs are normal after restart — ignore silently

    def _get_updates(self):
        params = {"timeout": 0, "allowed_updates": ["callback_query"]}
        if self._last_update_id is not None:
            params["offset"] = self._last_update_id + 1
        result = self._api("getUpdates", **params)
        updates = result.get("result", [])
        if updates:
            self._last_update_id = updates[-1]["update_id"]
        return updates

    def _handle_update(self, upd, daily_limit_hit, snapshot):
        cb = upd.get("callback_query")
        if not cb:
            return
        cid  = cb["id"]
        data = cb.get("data", "")
        msg  = cb.get("message", {})
        mid  = msg.get("message_id")
        if str(msg.get("chat", {}).get("id", "")) != self.chat_id:
            return
        self._answer_callback(cid)
        log.info(f"[TGCtrl] Command: {data}")

        if data.startswith("confirm_"):
            action = data[len("confirm_"):]
            if action == "hard_close":
                self._do_hard_close(mid)
            elif action == "soft_close":
                self._do_soft_close(mid)
            elif action == "restart":
                self._do_restart(mid)
            elif action == "stop":
                self._do_stop(mid)
            return

        if data == "cmd_status":
            self._cmd_status(mid)
        elif data == "cmd_pnl":
            self._cmd_pnl(mid)
        elif data == "cmd_pause_toggle":
            self._paused = not self._paused
            state = "PAUSED - no new entries." if self._paused else "RESUMED - entries enabled."
            self._edit(mid, state, reply_markup=_main_keyboard(self._paused))
        elif data == "cmd_settings":
            self._edit(mid, self.rt.summary(), reply_markup=_settings_keyboard(self.rt))
        elif data == "cmd_back":
            self._edit(mid, "Control Panel", reply_markup=_main_keyboard(self._paused))
        elif data == "cmd_soft_close":
            self._edit(mid, "Soft Close All: removes positions locally, Kalshi settles naturally. Confirm?",
                       reply_markup=_confirm_keyboard("soft_close"))
        elif data == "cmd_hard_close":
            n = len(self._positions)
            if n == 0:
                self._edit(mid, "No open positions.", reply_markup=_main_keyboard(self._paused))
            else:
                self._edit(mid, f"Hard Close All: place SELL orders for {n} position(s). Confirm?",
                           reply_markup=_confirm_keyboard("hard_close"))
        elif data == "cmd_restart":
            self._edit(mid, "Restart bot? Confirm?", reply_markup=_confirm_keyboard("restart"))
        elif data == "cmd_stop":
            self._edit(mid, "Stop bot after current cycle? Confirm?", reply_markup=_confirm_keyboard("stop"))
        elif data.startswith("set_"):
            self._handle_setting(data, mid)

    def _cmd_status(self, mid):
        now   = datetime.now(timezone.utc)
        today = now.strftime("%Y-%m-%d")
        pnl   = self._total_pnl
        sign  = "+" if pnl >= 0 else ""
        mode  = "DRY RUN" if self.rt.DRY_RUN else "LIVE"
        paused = " | PAUSED" if self._paused else ""
        lines = [
            f"<b>Status</b>  <code>{now.strftime('%H:%M:%S')} UTC</code>",
            f"Mode: <code>{mode}</code>{paused}",
            f"Session PNL: <code>{sign}${pnl:.4f}</code>",
            f"Today: <code>${self._pnl_log.get(today, 0.0):.4f}</code>",
            f"Open Positions: <b>{len(self._positions)}</b>",
            "",
        ]
        if self._positions:
            for ticker, pos in self._positions.items():
                side  = pos.get("side", "?").upper()
                ep    = pos.get("entry_price", "?")
                ct    = pos.get("contracts", "?")
                strat = pos.get("strategy", "?")
                lines.append(f"- <code>{ticker}</code>")
                lines.append(f"  {side} @ {ep}c x{ct}  [{strat}]")
        else:
            lines.append("No open positions.")
        self._send("\n".join(lines), reply_markup=_main_keyboard(self._paused))

    def _cmd_pnl(self, mid):
        if not self._pnl_log:
            self._send("No PNL recorded yet.", reply_markup=_main_keyboard(self._paused))
            return
        today  = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        total  = sum(self._pnl_log.values())
        sign_t = "+" if total >= 0 else ""
        lines  = ["<b>PNL Report</b>", ""]
        for date in sorted(self._pnl_log.keys()):
            val  = self._pnl_log[date]
            sign = "+" if val >= 0 else ""
            tag  = " &lt;- today" if date == today else ""
            lines.append(f"<code>{date}  {sign}${val:.4f}{tag}</code>")
        lines.append("")
        lines.append(f"<b>All-time: {sign_t}${total:.4f}</b>")
        self._send("\n".join(lines), reply_markup=_main_keyboard(self._paused))

    def _do_soft_close(self, mid):
        n = len(self._positions)
        if n == 0:
            self._edit(mid, "No open positions.", reply_markup=_main_keyboard(self._paused))
            return
        tickers = list(self._positions.keys())
        self._positions.clear()
        self._save_positions()
        log.info(f"[TGCtrl] Soft close: removed {n} positions")
        msg = f"Soft Close Complete. Removed {n} position(s).\n" + "\n".join(f"- {t}" for t in tickers)
        self._edit(mid, msg, reply_markup=_main_keyboard(self._paused))

    def _do_hard_close(self, mid):
        if not self._positions:
            self._edit(mid, "No open positions.", reply_markup=_main_keyboard(self._paused))
            return
        if self.rt.DRY_RUN:
            self._edit(mid, "Hard close skipped - DRY RUN mode. Use Soft Close instead.",
                       reply_markup=_main_keyboard(self._paused))
            return
        try:
            import uuid
            import kalshi_python
            if not self.client:
                self._edit(mid, "No Kalshi client available.", reply_markup=_main_keyboard(self._paused))
                return
            portfolio_api = kalshi_python.PortfolioApi(api_client=self.client)
            results = []
            today   = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            for ticker, pos in list(self._positions.items()):
                try:
                    side       = pos["side"]
                    contracts  = int(pos["contracts"])
                    sell_price = max(1, pos.get("entry_price", 1) - 20)
                    portfolio_api.create_order(
                        ticker          = ticker,
                        action          = "sell",
                        side            = side,
                        type            = "limit",
                        yes_price       = max(1, sell_price) if side == "yes" else None,
                        no_price        = max(1, sell_price) if side == "no"  else None,
                        count           = contracts,
                        client_order_id = str(uuid.uuid4()),
                    )
                    exit_fee    = _calc_fee(contracts, sell_price / 100.0)
                    pnl_cents   = (sell_price - pos["entry_price"]) * contracts
                    pnl_dollars = pnl_cents / 100.0 - pos.get("entry_fee", 0.0) - exit_fee
                    self._total_pnl += pnl_dollars
                    self._pnl_log[today] = self._pnl_log.get(today, 0.0) + pnl_dollars
                    results.append(f"OK {ticker} PNL ${pnl_dollars:.4f}")
                    del self._positions[ticker]
                except Exception as e:
                    results.append(f"FAIL {ticker}: {str(e)[:60]}")
            self._save_positions()
            self._save_pnl()
            msg = "Hard Close Complete:\n" + "\n".join(results)
            self._edit(mid, msg, reply_markup=_main_keyboard(self._paused))
        except Exception as e:
            self._edit(mid, f"Hard close failed: {str(e)[:120]}", reply_markup=_main_keyboard(self._paused))

    def _do_stop(self, mid):
        self._stop_requested = True
        self._edit(mid, "Stop signal sent. Bot will exit after current cycle.")
        log.info("[TGCtrl] Stop requested via Telegram.")

    def _do_restart(self, mid):
        self._edit(mid, "Restarting bot...")
        log.info("[TGCtrl] Restart requested via Telegram.")
        try:
            # FIX: use os.execv for reliable restart instead of screen injection
            import os
            self._edit(mid, "Restarting now...")
            os.execv(sys.executable, [sys.executable] + sys.argv)
        except Exception as e:
            log.error(f"[TGCtrl] Restart failed: {e}")
            self._edit(mid, f"Restart failed: {e}")

    def _handle_setting(self, data, mid):
        rt = self.rt
        if data == "set_dry_toggle":
            rt.DRY_RUN = not rt.DRY_RUN
        elif data == "set_llm_toggle":
            rt.LLM_ASSIST = not rt.LLM_ASSIST
        elif data == "set_tp_up":
            rt.TAKE_PROFIT_CENTS = min(50, rt.TAKE_PROFIT_CENTS + 1)
        elif data == "set_tp_down":
            rt.TAKE_PROFIT_CENTS = max(1, rt.TAKE_PROFIT_CENTS - 1)
        elif data == "set_sl_up":
            rt.STOP_LOSS_CENTS = min(50, rt.STOP_LOSS_CENTS + 1)
        elif data == "set_sl_down":
            rt.STOP_LOSS_CENTS = max(1, rt.STOP_LOSS_CENTS - 1)
        elif data == "set_pos_up":
            rt.MAX_POSITION_USD = min(50.0, round(rt.MAX_POSITION_USD + 1.0, 2))
        elif data == "set_pos_down":
            rt.MAX_POSITION_USD = max(1.0, round(rt.MAX_POSITION_USD - 1.0, 2))
        elif data == "set_vol_up":
            rt.MIN_VOLUME = min(10000, rt.MIN_VOLUME + 250)
        elif data == "set_vol_down":
            rt.MIN_VOLUME = max(0, rt.MIN_VOLUME - 250)
        try:
            import kalshi_bot
            kalshi_bot.Config.DRY_RUN           = rt.DRY_RUN
            kalshi_bot.Config.LLM_ASSIST        = rt.LLM_ASSIST
            kalshi_bot.Config.TAKE_PROFIT_CENTS = rt.TAKE_PROFIT_CENTS
            kalshi_bot.Config.STOP_LOSS_CENTS   = rt.STOP_LOSS_CENTS
            kalshi_bot.Config.MAX_POSITION_USD  = rt.MAX_POSITION_USD
            kalshi_bot.Config.MIN_VOLUME        = rt.MIN_VOLUME
        except Exception:
            pass
        log.info(f"[TGCtrl] Setting changed: {data}")
        self._edit(mid, rt.summary(), reply_markup=_settings_keyboard(rt))

    def send_cycle_report(self, snapshot, signals, trades_placed,
                          open_positions, total_pnl, daily_limit_hit):
        """
        FIX: Only send cycle report every 30 minutes OR when trades were placed.
        Prevents Telegram rate limiting from 2880 messages/day.
        """
        now = time.time()
        has_trades = trades_placed > 0
        due        = (now - self._last_cycle_report) >= self.CYCLE_REPORT_INTERVAL_SECS

        if not has_trades and not due:
            return

        self._last_cycle_report = now
        lines = [f"Cycle Report - {datetime.now(timezone.utc).strftime('%H:%M:%S')} UTC"]
        if snapshot:
            for sport, games in snapshot.items():
                count = sum(len(m) for g in games.values() for m in g.markets.values())
                lines.append(f"  {sport}: {len(games)} games / {count} markets")
        lines.append(
            f"Signals: {len(signals)}  |  Trades: {trades_placed}  "
            f"|  Positions: {len(open_positions)}  |  PNL: ${total_pnl:.2f}"
        )
        if daily_limit_hit:
            lines.append("[!] Daily loss limit active - entries blocked")
        self._send("\n".join(lines), reply_markup=_main_keyboard(self._paused))

    def _save_positions(self):
        try:
            import tempfile
            fd, tmp = tempfile.mkstemp(dir=".", suffix=".tmp")
            with os.fdopen(fd, "w") as f:
                json.dump(self._positions, f, indent=2)
            os.replace(tmp, "positions.json")
        except Exception as e:
            log.warning(f"[TGCtrl] Save positions failed: {e}")

    def _save_pnl(self):
        try:
            import tempfile
            fd, tmp = tempfile.mkstemp(dir=".", suffix=".tmp")
            with os.fdopen(fd, "w") as f:
                json.dump(self._pnl_log, f, indent=2)
            os.replace(tmp, "pnl_log.json")
        except Exception as e:
            log.warning(f"[TGCtrl] Save PNL failed: {e}")
