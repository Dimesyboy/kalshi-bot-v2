open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && echo "=== BALANCE ===" && python3 -c "from core.kalshi_client import get_balance; print(f'\${get_balance():.2f}')" && echo "" && echo "=== V2 BOT CYCLES ===" && tail -5 kalshi_bot.log | grep -E "Cycle|signal|trade" && echo "" && echo "=== PROP SIGNALS ===" && grep "PropNBA" kalshi_bot.log | tail -10 && echo "" && echo "=== TRADES PLACED ===" && grep -E "place_order|Order placed|BUY\|SELL|DRY RUN" kalshi_bot.log | tail -10 && echo "" && echo "=== SCREENS ===" && screen -ls && echo "" && echo "=== COMBO SCHEDULER ===" && screen -r combo 2>&1 | head -5
grep -n "reset_cycle\|scanned_tickers\|cooldown" /root/kalshi-bot-v2/bot.py | head -20
# Fix 1: signal module name conflict
grep -n "^import signal" /root/kalshi-bot-v2/bot.py
# Fix signal import conflict and the broken variable name
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

# Rename import to avoid conflict
c = c.replace('import signal\n', 'import signal as _signal\n')

# Fix all uses of signal module
c = c.replace('signal.SIGTERM', '_signal.SIGTERM')
c = c.replace('signal.SIGINT', '_signal.SIGINT')
c = c.replace('signal.signal(', '_signal.signal(')

# Fix the broken variable name in dry run log
c = c.replace(
    'log.info(f"[DRY RUN] Would place: {trade_trade_signal.market_ticker} "\n                                    f"{trade_trade_signal.side.value.upper()} @ {trade_trade_signal.price}c")',
    'log.info(f"[DRY RUN] Would place: {trade_signal.market_ticker} {trade_signal.side.value.upper()} @ {trade_signal.price}c")'
)

open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile bot.py && echo "Syntax OK"
systemctl restart kalshi-bot-v2
sleep 5
tail -20 kalshi_bot.log | grep -E "PropNBA|Cycle|signal|trade|error|Error"
grep -n "signal      = signal" /root/kalshi-bot-v2/bot.py
sed -n '405,425p' /root/kalshi-bot-v2/bot.py
sed -i 's/                                signal      = signal,/                                signal      = trade_signal,/' /root/kalshi-bot-v2/bot.py
grep -n "signal      = " /root/kalshi-bot-v2/bot.py
sed -n '422,428p' /root/kalshi-bot-v2/bot.py
sed -i 's/                            alert_trade(signal)/                            alert_trade(trade_signal)/' /root/kalshi-bot-v2/bot.py
python3 -m py_compile bot.py && echo "Syntax OK"
systemctl restart kalshi-bot-v2
sleep 5
tail -10 kalshi_bot.log | grep -E "PropNBA|Cycle|Error|trade"
grep -n "side.value.upper\|side.upper" /root/kalshi-bot-v2/bot.py
sed -i 's/trade_signal.side.value.upper()/str(trade_signal.side).upper()/' /root/kalshi-bot-v2/bot.py
python3 -m py_compile bot.py && echo "Syntax OK"
systemctl restart kalshi-bot-v2
sleep 5
tail -10 kalshi_bot.log | grep -E "PropNBA|Cycle|Error|trade|placed"
sleep 10 && tail -5 kalshi_bot.log | grep -E "Cycle|trade|placed|Error|order"
grep -n "side.upper\|side.value.upper\|Side.*upper\|JSON serial" /root/kalshi-bot-v2/order_manager.py | head -10
sed -i 's/signal.side.upper()/str(signal.side).split(".")[-1].upper()/' /root/kalshi-bot-v2/order_manager.py
# Fix JSON serialization of Side enum
grep -n "json.dump\|_atomic_write\|to_dict\|asdict" /root/kalshi-bot-v2/order_manager.py | head -10
sed -n '345,365p' /root/kalshi-bot-v2/order_manager.py
sed -n '100,130p' /root/kalshi-bot-v2/order_manager.py
sed -i 's/"side":         signal.side,/"side":         str(signal.side).split(".")[-1].lower(),/' /root/kalshi-bot-v2/order_manager.py
# Also fix OrderState enum
grep -n "OrderState\." /root/kalshi-bot-v2/order_manager.py | grep "state.*=" | head -5
grep -n "\"state\".*OrderState\|state.*=.*OrderState" /root/kalshi-bot-v2/order_manager.py | head -10
sed -i 's/"state":        OrderState.PENDING,/"state":        "pending",/' /root/kalshi-bot-v2/order_manager.py
sed -i 's/self._pending\[order_id\]\["state"\]  = OrderState.PARTIAL/self._pending[order_id]["state"]  = "partial"/' /root/kalshi-bot-v2/order_manager.py
# Check for any other OrderState references in pending dict
grep -n "OrderState\." /root/kalshi-bot-v2/order_manager.py | head -10
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 -m py_compile order_manager.py && echo "OM OK" && python3 -m py_compile bot.py && echo "BOT OK" && systemctl restart kalshi-bot-v2 && sleep 10 && tail -10 kalshi_bot.log | grep -E "Cycle|PropNBA|trade|placed|Error"
sleep 15 && tail -15 kalshi_bot.log | grep -E "Cycle done|placed|order|Error|PENDING|PropNBA"
sleep 30 && tail -20 kalshi_bot.log | grep -E "Cycle done|PENDING|PropNBA|Error|placed|balance"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
orders = pa.get_orders(status='resting')
print(f'Resting orders: {len(orders.orders or [])}')
for o in (orders.orders or [])[:5]:
    print(f'  {o.ticker[-30:]} {o.side} @ {o.yes_price}c')
" 2>&1 | grep -v DEBUG | grep -v WARNING
screen -r
systemctl stop kalshi-bot-v2
echo "Bot stopped"
# Cancel all resting orders
python3 -c "
import kalshi_python, time
from core.kalshi_client import get_client
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
orders = pa.get_orders(status='resting')
all_orders = orders.orders or []
print(f'Cancelling {len(all_orders)} orders...')
cancelled = 0
for o in all_orders:
    try:
        pa.cancel_order(o.order_id)
        cancelled += 1
        time.sleep(0.1)
    except Exception as e:
        print(f'Failed: {e}')
print(f'Cancelled {cancelled}/{len(all_orders)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
sed -n '355,365p' /root/kalshi-bot-v2/bot.py
sed -n '415,430p' /root/kalshi-bot-v2/bot.py
sed -n '388,420p' /root/kalshi-bot-v2/bot.py
sed -n '133,155p' /root/kalshi-bot-v2/bot.py
grep -n "MAX_OPEN_POSITIONS" /root/kalshi-bot-v2/core/config.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

old = '''            # Count open positions
            open_count   = len(open_positions)
            pending_count= order_mgr.get_pending_count()
            signals_found= 0
            trades_placed= 0

            # Skip trading if at position limit
            if open_count + pending_count >= config.MAX_OPEN_POSITIONS:'''

new = '''            # Count open positions
            open_count   = len(open_positions)
            pending_count= order_mgr.get_pending_count()
            signals_found= 0
            trades_placed= 0

            # Also count resting orders from Kalshi directly
            try:
                resting = pa.get_orders(status='resting')
                resting_count = len(resting.orders or [])
            except Exception:
                resting_count = 0

            # Skip trading if at position limit
            if open_count + pending_count + resting_count >= config.MAX_OPEN_POSITIONS:'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

# Make sure pa is defined in scope - check imports
grep -n "^pa\|PortfolioApi\|pa = " /root/kalshi-bot-v2/bot.py | head -5
grep -n "pa = \|PortfolioApi" /root/kalshi-bot-v2/bot.py | head -10
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

old = '''            # Also count resting orders from Kalshi directly
            try:
                resting = pa.get_orders(status='resting')
                resting_count = len(resting.orders or [])
            except Exception:
                resting_count = 0'''

new = '''            # Also count resting orders from Kalshi directly
            try:
                import kalshi_python
                from core.kalshi_client import get_client as _gc
                _pa = kalshi_python.PortfolioApi(api_client=_gc())
                resting = _pa.get_orders(status='resting')
                resting_count = len(resting.orders or [])
            except Exception:
                resting_count = 0'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile bot.py && echo "Syntax OK"
systemctl start kalshi-bot-v2
sleep 15
tail -15 kalshi_bot.log | grep -E "Cycle|PropNBA|PENDING|position limit|Error|resting"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)

# Check resting orders
resting = pa.get_orders(status='resting')
print(f'Resting orders: {len(resting.orders or [])}')

# Check positions
positions = pa.get_positions()
all_pos = positions.positions or []
print(f'Open positions: {len(all_pos)}')
for p in all_pos[:5]:
    print(f'  {str(p.ticker)[-30:]} qty={getattr(p, \"position\", 0)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
# Clear stale internal state files
rm -f /root/kalshi-bot-v2/data/pending_orders.json
rm -f /root/kalshi-bot-v2/data/open_positions.json  
rm -f /root/kalshi-bot-v2/data/cooldowns.json
rm -f /root/kalshi-bot-v2/data/bot_orders.json
echo "State cleared"
systemctl restart kalshi-bot-v2
sleep 15
tail -10 kalshi_bot.log | grep -E "Cycle|PropNBA|PENDING|position|Error"
sleep 10 && python3 -c "
import kalshi_python
from core.kalshi_client import get_client
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resting = pa.get_orders(status='resting')
positions = pa.get_positions()
print(f'Resting: {len(resting.orders or [])}')
print(f'Positions: {len(positions.positions or [])}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
systemctl stop kalshi-bot-v2
# Cancel all resting
python3 -c "
import kalshi_python, time
from core.kalshi_client import get_client
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
orders = pa.get_orders(status='resting')
all_orders = orders.orders or []
print(f'Cancelling {len(all_orders)}...')
for o in all_orders:
    try:
        pa.cancel_order(o.order_id)
        time.sleep(0.05)
    except: pass
print('Done')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cd /root/kalshi-bot-v2 && python3 << 'PYEOF'
f = open('strategies/prop_nba.py', 'r')
c = f.read()
f.close()

old = '''class NBAPropStrategy(BaseStrategy):
    """
    Trades individual NBA prop markets with positive edge.
    Buys YES on props where our model confidence > market price.
    """

    name  = "prop_nba"
    sport = Sport.NBA

    def __init__(self):
        super().__init__()
        self._scanned_tickers = set()  # avoid re-evaluating same market

    def evaluate('''

new = '''class NBAPropStrategy(BaseStrategy):
    """
    Trades individual NBA prop markets with positive edge.
    Buys YES on props where our model confidence > market price.
    """

    name  = "prop_nba"
    sport = Sport.NBA
    MAX_TRADES_PER_SESSION = 4  # Hard cap per bot session

    def __init__(self):
        super().__init__()
        self._scanned_tickers  = set()
        self._session_trades   = 0
        self._traded_players   = set()  # one trade per player per session

    def evaluate('''

c = c.replace(old, new)

old2 = '''        # Skip already evaluated
        if ticker in self._scanned_tickers:
            return None
        self._scanned_tickers.add(ticker)'''

new2 = '''        # Hard cap — stop after MAX_TRADES_PER_SESSION
        if self._session_trades >= self.MAX_TRADES_PER_SESSION:
            return None

        # Skip already evaluated
        if ticker in self._scanned_tickers:
            return None
        self._scanned_tickers.add(ticker)'''

c = c.replace(old2, new2)

old3 = '''        log.info(
            f"[PropNBA] {player} {thr}+ {stat} YES @ {yes_price}c "
            f"conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%}"
        )

        return make_signal('''

new3 = '''        # One trade per player per session
        player_key = f"{player}_{stat}"
        if player_key in self._traded_players:
            return None
        self._traded_players.add(player_key)
        self._session_trades += 1

        log.info(
            f"[PropNBA] {player} {thr}+ {stat} YES @ {yes_price}c "
            f"conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%} "
            f"[{self._session_trades}/{self.MAX_TRADES_PER_SESSION}]"
        )

        return make_signal('''

c = c.replace(old3, new3)

old4 = '''    def reset_cycle(self):
        """Call at start of each bot cycle to allow re-evaluation."""
        self._scanned_tickers.clear()'''

new4 = '''    def reset_session(self):
        """Call to reset session counters (e.g. new trading day)."""
        self._scanned_tickers.clear()
        self._session_trades  = 0
        self._traded_players  = set()
        log.info("[PropNBA] Session reset")

    def reset_cycle(self):
        """Call at start of each bot cycle — only clears market cache."""
        self._scanned_tickers.clear()'''

c = c.replace(old4, new4)
open('strategies/prop_nba.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile strategies/prop_nba.py && echo "Syntax OK"
systemctl start kalshi-bot-v2
sleep 15
tail -10 kalshi_bot.log | grep -E "PropNBA|PENDING|FILLED|position|Cycle done"
systemctl stop kalshi-bot-v2
rm -f data/pending_orders.json data/open_positions.json data/cooldowns.json data/bot_orders.json
echo "Cleared"
# Verify Kalshi is clean
python3 -c "
import kalshi_python
from core.kalshi_client import get_client
pa = kalshi_python.PortfolioApi(api_client=get_client())
r = pa.get_orders(status='resting')
p = pa.get_positions()
print(f'Resting: {len(r.orders or [])} | Positions: {len(p.positions or [])}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
systemctl start kalshi-bot-v2
sleep 15
tail -10 kalshi_bot.log | grep -E "PropNBA|PENDING|FILLED|position limit|Cycle done"
systemctl stop kalshi-bot-v2
grep -n "side.*=.*Side\|Side.YES\|Side.NO" /root/kalshi-bot-v2/strategies/prop_nba.py
cat > /root/kalshi-bot-v2/core/reconciler.py << 'PYEOF'
#!/usr/bin/env python3
"""
core/reconciler.py
─────────────────────────────────────────────────────────────────────────────
Account reconciler — single source of truth for all positions and PNL.

Polls Kalshi every 30s and maintains accurate state of:
- All open positions (bot vs manual)
- All fills with attribution
- Separate PNL for bot trades vs manual trades
- Resting order count (for position limit enforcement)

Bot trades are identified by client_order_id saved in bot_orders.json.
Everything else is attributed to manual trading.
"""

import logging
import json
import os
import time
import threading
from datetime import datetime, timezone
from typing import Optional

log = logging.getLogger("kalshi_bot.reconciler")

BOT_ORDERS_FILE = "/root/kalshi-bot-v2/data/bot_orders.json"
RECON_FILE      = "/root/kalshi-bot-v2/data/reconciler_state.json"
POLL_INTERVAL   = 30  # seconds


class Position:
    def __init__(self, ticker, side, qty, cost_basis, market_value,
                 source, entry_time):
        self.ticker       = ticker
        self.side         = side
        self.qty          = qty
        self.cost_basis   = cost_basis    # dollars
        self.market_value = market_value  # dollars
        self.unrealized   = round(market_value - cost_basis, 4)
        self.source       = source        # 'bot' or 'manual'
        self.entry_time   = entry_time

    def to_dict(self):
        return {
            'ticker':       self.ticker,
            'side':         self.side,
            'qty':          self.qty,
            'cost_basis':   self.cost_basis,
            'market_value': self.market_value,
            'unrealized':   self.unrealized,
            'source':       self.source,
            'entry_time':   self.entry_time,
        }


class Reconciler:
    """
    Background thread that keeps account state in sync with Kalshi.
    Single source of truth for all position and PNL data.
    """

    def __init__(self):
        self._lock          = threading.Lock()
        self._positions     = {}   # ticker -> Position
        self._resting_count = 0
        self._bot_pnl       = 0.0
        self._manual_pnl    = 0.0
        self._bot_orders    = self._load_bot_orders()
        self._last_sync     = None
        self._running       = False
        self._thread        = None

    # ── Bot order tracking ─────────────────────────────────────────────

    def _load_bot_orders(self) -> set:
        try:
            if os.path.exists(BOT_ORDERS_FILE):
                data = json.load(open(BOT_ORDERS_FILE))
                if isinstance(data, list):
                    return set(data)
                return set(data.get('orders', []))
        except Exception:
            pass
        return set()

    def register_bot_order(self, order_id: str, client_order_id: str):
        """Register a bot-placed order for attribution."""
        with self._lock:
            self._bot_orders.add(order_id)
            self._bot_orders.add(client_order_id)
        self._save_bot_orders()

    def _save_bot_orders(self):
        try:
            with self._lock:
                orders = list(self._bot_orders)
            json.dump({'orders': orders}, open(BOT_ORDERS_FILE, 'w'))
        except Exception as e:
            log.warning(f"Failed to save bot orders: {e}")

    def is_bot_trade(self, order_id: str, client_order_id: str = '') -> bool:
        return (order_id in self._bot_orders or
                client_order_id in self._bot_orders)

    # ── Sync ───────────────────────────────────────────────────────────

    def sync(self):
        """Pull current state from Kalshi and update internal state."""
        try:
            import kalshi_python
            from core.kalshi_client import get_client
            client = get_client()
            pa     = kalshi_python.PortfolioApi(api_client=client)

            # ── Positions ─────────────────────────────────────────────
            resp     = pa.get_positions()
            all_pos  = resp.positions or []
            new_pos  = {}

            for p in all_pos:
                ticker = str(p.ticker or '')
                qty    = getattr(p, 'position', 0) or 0
                cost   = (getattr(p, 'total_cost', 0) or 0) / 100.0
                value  = (getattr(p, 'market_value', 0) or 0) / 100.0

                if qty == 0:
                    continue

                # Determine side from position sign
                side = 'yes' if qty > 0 else 'no'

                # Attribution — check fills for this ticker
                source = self._get_position_source(pa, ticker)

                new_pos[ticker] = Position(
                    ticker       = ticker,
                    side         = side,
                    qty          = abs(qty),
                    cost_basis   = abs(cost),
                    market_value = abs(value),
                    source       = source,
                    entry_time   = datetime.now(timezone.utc).isoformat()[:16],
                )

            # ── Resting orders ────────────────────────────────────────
            try:
                resting = pa.get_orders(status='resting')
                resting_count = len(resting.orders or [])
            except Exception:
                resting_count = 0

            # ── Settled PNL ───────────────────────────────────────────
            bot_pnl, manual_pnl = self._calc_settled_pnl(pa)

            # ── Update state ──────────────────────────────────────────
            with self._lock:
                self._positions     = new_pos
                self._resting_count = resting_count
                self._bot_pnl       = bot_pnl
                self._manual_pnl    = manual_pnl
                self._last_sync     = datetime.now(timezone.utc).isoformat()

            self._save_state()
            log.debug(f"[Recon] Synced: {len(new_pos)} positions, "
                     f"{resting_count} resting, "
                     f"bot_pnl=${bot_pnl:.2f} manual_pnl=${manual_pnl:.2f}")

        except Exception as e:
            log.warning(f"[Recon] Sync failed: {e}")

    def _get_position_source(self, pa, ticker: str) -> str:
        """Check recent fills to attribute position to bot or manual."""
        try:
            fills = pa.get_fills(ticker=ticker, limit=5)
            for fill in (fills.fills or []):
                order_id  = str(getattr(fill, 'order_id', '') or '')
                client_id = str(getattr(fill, 'client_order_id', '') or '')
                if self.is_bot_trade(order_id, client_id):
                    return 'bot'
            return 'manual'
        except Exception:
            return 'unknown'

    def _calc_settled_pnl(self, pa) -> tuple[float, float]:
        """Calculate settled PNL split by bot vs manual."""
        bot_pnl    = 0.0
        manual_pnl = 0.0
        try:
            settlements = pa.get_settlements(limit=100)
            for s in (settlements.settlements or []):
                revenue = (s.revenue or 0) / 100.0
                if revenue == 0:
                    continue
                ticker = str(s.ticker or '')
                source = self._get_settlement_source(pa, ticker)
                if source == 'bot':
                    bot_pnl += revenue
                else:
                    manual_pnl += revenue
        except Exception as e:
            log.debug(f"[Recon] PNL calc error: {e}")
        return round(bot_pnl, 2), round(manual_pnl, 2)

    def _get_settlement_source(self, pa, ticker: str) -> str:
        """Attribute a settlement to bot or manual."""
        try:
            fills = pa.get_fills(ticker=ticker, limit=3)
            for fill in (fills.fills or []):
                order_id  = str(getattr(fill, 'order_id', '') or '')
                client_id = str(getattr(fill, 'client_order_id', '') or '')
                if self.is_bot_trade(order_id, client_id):
                    return 'bot'
        except Exception:
            pass
        return 'manual'

    def _save_state(self):
        """Persist reconciler state to disk."""
        try:
            with self._lock:
                state = {
                    'last_sync':     self._last_sync,
                    'resting_count': self._resting_count,
                    'bot_pnl':       self._bot_pnl,
                    'manual_pnl':    self._manual_pnl,
                    'positions':     {k: v.to_dict()
                                     for k, v in self._positions.items()},
                }
            json.dump(state, open(RECON_FILE, 'w'), indent=2)
        except Exception as e:
            log.debug(f"[Recon] Save failed: {e}")

    # ── Public API ─────────────────────────────────────────────────────

    def get_positions(self) -> list[dict]:
        with self._lock:
            return [p.to_dict() for p in self._positions.values()]

    def get_bot_positions(self) -> list[dict]:
        with self._lock:
            return [p.to_dict() for p in self._positions.values()
                    if p.source == 'bot']

    def get_manual_positions(self) -> list[dict]:
        with self._lock:
            return [p.to_dict() for p in self._positions.values()
                    if p.source == 'manual']

    def get_open_count(self) -> int:
        """Total open positions — use for position limit checks."""
        with self._lock:
            return len(self._positions)

    def get_resting_count(self) -> int:
        with self._lock:
            return self._resting_count

    def get_total_exposure(self) -> int:
        """Open positions + resting orders."""
        with self._lock:
            return len(self._positions) + self._resting_count

    def get_pnl(self) -> dict:
        with self._lock:
            return {
                'bot_pnl':    self._bot_pnl,
                'manual_pnl': self._manual_pnl,
                'total_pnl':  round(self._bot_pnl + self._manual_pnl, 2),
                'last_sync':  self._last_sync,
            }

    def get_last_sync(self) -> Optional[str]:
        with self._lock:
            return self._last_sync

    # ── Background thread ──────────────────────────────────────────────

    def start(self):
        """Start background sync thread."""
        self._running = True
        self._thread  = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        log.info("[Recon] Started background sync")

    def stop(self):
        self._running = False

    def _run(self):
        while self._running:
            self.sync()
            time.sleep(POLL_INTERVAL)


# ── Singleton ──────────────────────────────────────────────────────────────
reconciler = Reconciler()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/core/reconciler.py) lines"
python3 -m py_compile core/reconciler.py && echo "Syntax OK"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

# Add import at top
old = 'from strategies.nba import NBAFade, NBAMomentumReversal'
new = 'from strategies.nba import NBAFade, NBAMomentumReversal\nfrom core.reconciler import reconciler'
c = c.replace(old, new)

# Start reconciler in main loop
old = '''    log.info("[Bot] Starting main loop")
    price_history  = PriceHistoryCache()'''
new = '''    log.info("[Bot] Starting main loop")
    reconciler.start()
    price_history  = PriceHistoryCache()'''
c = c.replace(old, new)

# Replace position limit check with reconciler
old = '''            # Count open positions
            open_count   = len(open_positions)
            pending_count= order_mgr.get_pending_count()
            signals_found= 0
            trades_placed= 0

            # Also count resting orders from Kalshi directly
            try:
                import kalshi_python
                from core.kalshi_client import get_client as _gc
                _pa = kalshi_python.PortfolioApi(api_client=_gc())
                resting = _pa.get_orders(status='resting')
                resting_count = len(resting.orders or [])
            except Exception:
                resting_count = 0

            # Skip trading if at position limit
            if open_count + pending_count + resting_count >= config.MAX_OPEN_POSITIONS:'''
new = '''            # Use reconciler as source of truth for position counts
            signals_found= 0
            trades_placed= 0
            total_exposure = reconciler.get_total_exposure()

            # Skip trading if at position limit
            if total_exposure >= config.MAX_OPEN_POSITIONS:'''
c = c.replace(old, new)

# Update log message
old = '                log.info(f"[Bot] At position limit ({open_count} open, {pending_count} pending)")'
new = '                log.info(f"[Bot] At position limit ({total_exposure} exposure)")'
c = c.replace(old, new)

# Register bot orders with reconciler after placement
old = '''                        if order_id:
                            from strategies.base import calculate_fee
                            entry_fee = calculate_fee(
                                trade_signal.contracts,
                                trade_signal.price / 100.0,
                                is_maker=True
                            )
                            bot_orders.add(order_id)
                            save_bot_orders(bot_orders)'''
new = '''                        if order_id:
                            from strategies.base import calculate_fee
                            entry_fee = calculate_fee(
                                trade_signal.contracts,
                                trade_signal.price / 100.0,
                                is_maker=True
                            )
                            bot_orders.add(order_id)
                            save_bot_orders(bot_orders)
                            reconciler.register_bot_order(order_id, client_order_id)'''
c = c.replace(old, new)

open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile bot.py && echo "Syntax OK"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''    elif data == "positions":
        try:
            import kalshi_python
            from core.kalshi_client import get_client
            client = get_client()
            pa     = kalshi_python.PortfolioApi(api_client=client)
            resp   = pa.get_positions()
            all_pos = resp.positions or []

            # Separate combos from single legs
            combos  = [p for p in all_pos if 'MULTIGAME' in str(p.ticker) or 'CROSSCATEGORY' in str(p.ticker)]
            singles = [p for p in all_pos if p not in combos]

            lines = [f"📋 *Open Positions* ({len(all_pos)} total)\n"]

            if combos:
                lines.append(f"*🎯 Combos ({len(combos)})*")
                for p in combos[:5]:
                    cost  = getattr(p, 'total_cost', 0) or 0
                    val   = getattr(p, 'market_value', 0) or 0
                    lines.append(f"• {str(p.ticker)[-28:]} cost=${cost/100:.2f} val=${val/100:.2f}")
                lines.append("")

            if singles:
                lines.append(f"*🏀 Single Props ({len(singles)})*")
                for p in singles[:5]:
                    cost = getattr(p, 'total_cost', 0) or 0
                    lines.append(f"• {str(p.ticker)[-28:]} cost=${cost/100:.2f}")
                lines.append("")

            if not all_pos:
                lines = ["📋 No open positions"]

            await query.edit_message_text(
                "\n".join(lines),
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:150]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))'''

new = '''    elif data == "positions":
        try:
            from core.reconciler import reconciler
            all_pos    = reconciler.get_positions()
            bot_pos    = reconciler.get_bot_positions()
            manual_pos = reconciler.get_manual_positions()
            pnl        = reconciler.get_pnl()
            last_sync  = reconciler.get_last_sync() or "never"

            lines = [
                f"📋 *Positions* ({len(all_pos)} total)",
                f"_Synced: {last_sync[-5:] if last_sync else '?'} UTC_",
                f"",
                f"🤖 Bot PNL: ${pnl['bot_pnl']:+.2f} | 👤 Manual: ${pnl['manual_pnl']:+.2f}",
                f"",
            ]

            if bot_pos:
                lines.append(f"*🤖 Bot Positions ({len(bot_pos)})*")
                for p in bot_pos[:5]:
                    unr = p['unrealized']
                    flag = "📈" if unr >= 0 else "📉"
                    lines.append(f"{flag} {p['ticker'][-22:]} {p['side'].upper()} "
                               f"cost=${p['cost_basis']:.2f} unr=${unr:+.2f}")
                lines.append("")

            if manual_pos:
                lines.append(f"*👤 Your Positions ({len(manual_pos)})*")
                for p in manual_pos[:5]:
                    comboflag = "🎯" if "MULTI" in p['ticker'] else "🏀"
                    lines.append(f"{comboflag} {p['ticker'][-22:]} "
                               f"cost=${p['cost_basis']:.2f}")
                lines.append("")

            if not all_pos:
                lines = ["📋 No open positions"]

            await query.edit_message_text(
                "\n".join(lines),
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("🔄 Refresh", callback_data="positions"),
                    InlineKeyboardButton("🔙 Menu",    callback_data="menu")
                ]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:150]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/api_server.py', 'r')
c = f.read()
f.close()

old = '''@app.get("/api/balance")
def get_balance(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from core.kalshi_client import get_balance
        bal = get_balance()
        return {"balance": round(bal, 2)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))'''

new = '''@app.get("/api/balance")
def get_balance(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from core.kalshi_client import get_balance
        from core.reconciler import reconciler
        bal = get_balance()
        pnl = reconciler.get_pnl()
        return {
            "balance":     round(bal, 2),
            "bot_pnl":     pnl["bot_pnl"],
            "manual_pnl":  pnl["manual_pnl"],
            "total_pnl":   pnl["total_pnl"],
            "last_sync":   pnl["last_sync"],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/positions")
def get_positions(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from core.reconciler import reconciler
        return {
            "all":         reconciler.get_positions(),
            "bot":         reconciler.get_bot_positions(),
            "manual":      reconciler.get_manual_positions(),
            "pnl":         reconciler.get_pnl(),
            "exposure":    reconciler.get_total_exposure(),
            "resting":     reconciler.get_resting_count(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/api_server.py', 'w').write(c)
print("Done")
PYEOF

# Syntax check everything
python3 -m py_compile core/reconciler.py && echo "reconciler OK"
python3 -m py_compile bot.py && echo "bot OK"
python3 -m py_compile telegram_bot.py && echo "telegram OK"
python3 -m py_compile api_server.py && echo "api OK"
# Restart all screens
screen -S tgbot -X quit
screen -S api -X quit
# Clear stale state
rm -f data/pending_orders.json data/open_positions.json data/cooldowns.json data/bot_orders.json data/reconciler_state.json
# Start api
screen -S api bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && BOT_API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d"=" -f2) python3 api_server.py; exec bash'
# Start tgbot
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
# Restart v2 bot
systemctl restart kalshi-bot-v2
sleep 15
tail -10 kalshi_bot.log | grep -E "Recon|PropNBA|PENDING|FILLED|Cycle|Error|position"
sleep 10 && python3 -c "
import kalshi_python
from core.kalshi_client import get_client
pa = kalshi_python.PortfolioApi(api_client=get_client())
r = pa.get_orders(status='resting')
p = pa.get_positions()
print(f'Resting: {len(r.orders or [])}')
print(f'Positions: {len(p.positions or [])}')
for pos in (p.positions or []):
    print(f'  {str(pos.ticker)[-30:]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
sleep 30 && python3 -c "
import kalshi_python
from core.kalshi_client import get_client
pa = kalshi_python.PortfolioApi(api_client=get_client())
r = pa.get_orders(status='resting')
p = pa.get_positions()
print(f'Resting: {len(r.orders or [])}')
print(f'Positions: {len(p.positions or [])}')
for pos in (p.positions or []):
    qty  = getattr(pos, 'position', 0)
    cost = (getattr(pos, 'total_cost', 0) or 0) / 100
    print(f'  {str(pos.ticker)[-32:]} qty={qty} cost=\${cost:.2f}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cat > /root/kalshi-bot-v2/data/positions_db.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/positions_db.py
─────────────────────────────────────────────────────────────────────────────
SQLite journal for all positions — bot and manual.
Never wiped. Single source of historical truth.

Schema:
    positions   — every position opened (fill received)
    settlements — every position closed (settlement received)
"""

import sqlite3
import logging
import os
from datetime import datetime, timezone

log = logging.getLogger("kalshi_bot.positions_db")
DB_PATH = "/root/kalshi-bot-v2/data/positions.db"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS positions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker          TEXT NOT NULL,
        order_id        TEXT,
        client_order_id TEXT,
        side            TEXT,
        qty             INTEGER,
        entry_price     REAL,
        cost_basis      REAL,
        source          TEXT DEFAULT 'unknown',
        strategy        TEXT,
        entry_time      TEXT,
        status          TEXT DEFAULT 'open',
        created_at      TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS settlements (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker          TEXT NOT NULL,
        revenue         REAL,
        pnl             REAL,
        source          TEXT DEFAULT 'unknown',
        strategy        TEXT,
        entry_price     REAL,
        exit_price      REAL,
        settled_at      TEXT,
        created_at      TEXT DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_positions_ticker  ON positions(ticker);
    CREATE INDEX IF NOT EXISTS idx_positions_source  ON positions(source);
    CREATE INDEX IF NOT EXISTS idx_settlements_source ON settlements(source);
    """)
    conn.commit()
    conn.close()
    log.info(f"[PositionsDB] Initialized at {DB_PATH}")


def record_fill(ticker: str, order_id: str, client_order_id: str,
                side: str, qty: int, entry_price: float,
                source: str = 'unknown', strategy: str = ''):
    """Record a fill when a position is opened."""
    cost_basis = qty * entry_price / 100.0
    conn = get_db()
    try:
        conn.execute("""
            INSERT OR IGNORE INTO positions
            (ticker, order_id, client_order_id, side, qty,
             entry_price, cost_basis, source, strategy, entry_time, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open')
        """, (ticker, order_id, client_order_id, side, qty,
              entry_price, cost_basis, source, strategy,
              datetime.now(timezone.utc).isoformat()[:16]))
        conn.commit()
        log.info(f"[PositionsDB] Recorded fill: {ticker} {side} @ {entry_price}¢ source={source}")
    except Exception as e:
        log.warning(f"[PositionsDB] Fill record failed: {e}")
    finally:
        conn.close()


def record_settlement(ticker: str, revenue: float,
                      source: str = 'unknown', strategy: str = ''):
    """Record a settlement when a position closes."""
    conn = get_db()
    try:
        # Find matching open position
        pos = conn.execute(
            "SELECT * FROM positions WHERE ticker=? AND status='open' LIMIT 1",
            (ticker,)
        ).fetchone()

        entry_price = pos['entry_price'] if pos else 0
        cost_basis  = pos['cost_basis']  if pos else 0
        pnl         = revenue - cost_basis
        src         = pos['source']      if pos else source
        strat       = pos['strategy']    if pos else strategy

        conn.execute("""
            INSERT INTO settlements
            (ticker, revenue, pnl, source, strategy, entry_price,
             exit_price, settled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (ticker, revenue, pnl, src, strat, entry_price,
              revenue, datetime.now(timezone.utc).isoformat()[:16]))

        # Mark position as closed
        if pos:
            conn.execute(
                "UPDATE positions SET status='closed' WHERE id=?",
                (pos['id'],)
            )

        conn.commit()
        log.info(f"[PositionsDB] Settlement: {ticker} revenue=${revenue:.2f} pnl=${pnl:.2f}")
    except Exception as e:
        log.warning(f"[PositionsDB] Settlement record failed: {e}")
    finally:
        conn.close()


def get_pnl_summary() -> dict:
    """Get PNL summary split by source."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT source,
                   COUNT(*)        as n,
                   SUM(CASE WHEN pnl > 0 THEN 1 ELSE 0 END) as wins,
                   SUM(revenue)    as revenue,
                   SUM(pnl)        as pnl
            FROM settlements
            GROUP BY source
        """).fetchall()

        result = {}
        for r in rows:
            result[r['source']] = {
                'n':       r['n'],
                'wins':    r['wins'],
                'revenue': round(r['revenue'] or 0, 2),
                'pnl':     round(r['pnl'] or 0, 2),
                'win_rate': round(r['wins'] / r['n'] * 100, 1) if r['n'] else 0,
            }
        return result
    finally:
        conn.close()


def get_open_positions(source: str = None) -> list:
    """Get all open positions, optionally filtered by source."""
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM positions WHERE status='open' AND source=? ORDER BY entry_time DESC",
                (source,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM positions WHERE status='open' ORDER BY entry_time DESC"
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_recent_settlements(limit: int = 20, source: str = None) -> list:
    """Get recent settlements."""
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM settlements WHERE source=? ORDER BY settled_at DESC LIMIT ?",
                (source, limit)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM settlements ORDER BY settled_at DESC LIMIT ?",
                (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_strategy_performance() -> list:
    """Get performance broken down by strategy."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT strategy,
                   COUNT(*)   as n,
                   SUM(CASE WHEN pnl > 0 THEN 1 ELSE 0 END) as wins,
                   SUM(pnl)   as total_pnl,
                   AVG(pnl)   as avg_pnl
            FROM settlements
            WHERE strategy != ''
            GROUP BY strategy
            ORDER BY total_pnl DESC
        """).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


# Initialize on import
init_db()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/positions_db.py) lines"
python3 -m py_compile data/positions_db.py && echo "Syntax OK"
python3 -c "from data.positions_db import init_db, get_pnl_summary; print('DB initialized')"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/order_manager.py', 'r')
c = f.read()
f.close()

# Record fill when position opens
old = '''        log.info(f"[OrderManager] FILLED {ticker} {side.upper()} @ {fill_price}c x{filled} → positions.json")'''
new = '''        log.info(f"[OrderManager] FILLED {ticker} {side.upper()} @ {fill_price}c x{filled} → positions.json")
        try:
            from data.positions_db import record_fill
            from core.reconciler import reconciler
            source   = 'bot' if reconciler.is_bot_trade(order_id, '') else 'manual'
            strategy = self._pending.get(order_id, {}).get('strategy', '')
            record_fill(ticker, order_id, '', side, filled,
                       fill_price, source=source, strategy=strategy)
        except Exception as _e:
            log.debug(f"[OrderManager] DB fill record failed: {_e}")'''

c = c.replace(old, new)

# Record settlement when position closes
old2 = '''        log.info(f"[OrderManager] EXIT {ticker}'''
new2 = '''        try:
            from data.positions_db import record_settlement
            from core.reconciler import reconciler
            _source = 'bot' if reconciler.is_bot_trade(order_id, '') else 'manual'
            record_settlement(ticker, pnl, source=_source)
        except Exception as _e:
            log.debug(f"[OrderManager] DB settlement record failed: {_e}")
        log.info(f"[OrderManager] EXIT {ticker}'''

c = c.replace(old2, new2, 1)

open('/root/kalshi-bot-v2/order_manager.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile order_manager.py && echo "Syntax OK"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/core/reconciler.py', 'r')
c = f.read()
f.close()

old = '''    def _calc_settled_pnl(self, pa) -> tuple[float, float]:
        """Calculate settled PNL split by bot vs manual."""
        bot_pnl    = 0.0
        manual_pnl = 0.0
        try:
            settlements = pa.get_settlements(limit=100)
            for s in (settlements.settlements or []):
                revenue = (s.revenue or 0) / 100.0
                if revenue == 0:
                    continue
                ticker = str(s.ticker or '')
                source = self._get_settlement_source(pa, ticker)
                if source == 'bot':
                    bot_pnl += revenue
                else:
                    manual_pnl += revenue
        except Exception as e:
            log.debug(f"[Recon] PNL calc error: {e}")
        return round(bot_pnl, 2), round(manual_pnl, 2)'''

new = '''    def _calc_settled_pnl(self, pa) -> tuple[float, float]:
        """Calculate settled PNL from positions DB."""
        try:
            from data.positions_db import get_pnl_summary
            summary    = get_pnl_summary()
            bot_pnl    = summary.get('bot', {}).get('pnl', 0.0)
            manual_pnl = summary.get('manual', {}).get('pnl', 0.0)
            return round(bot_pnl, 2), round(manual_pnl, 2)
        except Exception as e:
            log.debug(f"[Recon] PNL calc error: {e}")
            return 0.0, 0.0'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/core/reconciler.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile core/reconciler.py && echo "OK"
# Restart everything
systemctl restart kalshi-bot-v2
screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
git add -A && git commit -m "feat: SQLite positions journal, reconciler, bot/manual attribution" && git push origin master
sleep 10
tail -10 kalshi_bot.log | grep -E "PropNBA|FILLED|PENDING|Cycle done|Error|PositionsDB"
python3 -c "
from data.positions_db import get_open_positions, get_pnl_summary
positions = get_open_positions()
print(f'Open positions in DB: {len(positions)}')
for p in positions:
    print(f'  {p[\"ticker\"][-30:]} {p[\"side\"]} @ {p[\"entry_price\"]}c source={p[\"source\"]} strategy={p[\"strategy\"]}')
print()
summary = get_pnl_summary()
print(f'PNL summary: {summary}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cat > /root/kalshi-bot-v2/data/positions_db.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/positions_db.py
─────────────────────────────────────────────────────────────────────────────
Full trade lifecycle journal. Captures every event from signal to settlement.

Tables:
    signals     — every signal generated (whether traded or not)
    orders      — every order placed with full metadata
    fills       — every fill event
    positions   — current open positions
    exits       — every exit event (TP/SL/time/manual)
    settlements — every Kalshi settlement
    events      — generic event log for anything else
"""

import sqlite3
import logging
import os
from datetime import datetime, timezone

log = logging.getLogger("kalshi_bot.positions_db")
DB_PATH = "/root/kalshi-bot-v2/data/positions.db"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""

    -- Every signal generated by any strategy
    CREATE TABLE IF NOT EXISTS signals (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        signal_time     TEXT NOT NULL,
        ticker          TEXT NOT NULL,
        series          TEXT,           -- KXNBAPTS, KXNBAGAME, KXMVESPORTS etc
        category        TEXT,           -- prop, game, combo, tennis, mlb
        strategy        TEXT,           -- prop_nba, nba_fade, combo_moonshot etc
        side            TEXT,           -- yes/no
        price_cents     INTEGER,
        confidence      REAL,
        edge            REAL,
        hit_rate        REAL,
        reason          TEXT,           -- full reasoning string
        source          TEXT,           -- bot/manual
        acted_on        INTEGER DEFAULT 0,  -- 1 if order placed
        skip_reason     TEXT,           -- why skipped if not acted on
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Every order placed
    CREATE TABLE IF NOT EXISTS orders (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id        TEXT UNIQUE,
        client_order_id TEXT,
        signal_id       INTEGER REFERENCES signals(id),
        ticker          TEXT NOT NULL,
        category        TEXT,
        strategy        TEXT,
        side            TEXT,
        price_cents     INTEGER,
        contracts       INTEGER,
        source          TEXT,           -- bot/manual
        order_time      TEXT,
        status          TEXT DEFAULT 'pending',  -- pending/resting/filled/cancelled/expired
        fill_time       TEXT,
        fill_price      INTEGER,
        time_to_fill_secs INTEGER,      -- seconds from order to fill
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Every fill event
    CREATE TABLE IF NOT EXISTS fills (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        fill_time       TEXT NOT NULL,
        ticker          TEXT NOT NULL,
        order_id        TEXT,
        side            TEXT,
        qty             INTEGER,
        fill_price      INTEGER,
        cost_basis      REAL,
        source          TEXT,
        strategy        TEXT,
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Current open positions (upserted on fill, deleted on settlement)
    CREATE TABLE IF NOT EXISTS positions (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker          TEXT UNIQUE,
        order_id        TEXT,
        side            TEXT,
        qty             INTEGER,
        entry_price     INTEGER,
        cost_basis      REAL,
        source          TEXT,
        strategy        TEXT,
        category        TEXT,
        confidence      REAL,
        edge            REAL,
        hit_rate        REAL,
        reason          TEXT,
        entry_time      TEXT,
        peak_price      INTEGER,        -- highest yes_bid seen
        current_price   INTEGER,        -- last known price
        unrealized_pnl  REAL,
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Exit events (TP/SL/time/manual)
    CREATE TABLE IF NOT EXISTS exits (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        exit_time       TEXT NOT NULL,
        ticker          TEXT NOT NULL,
        order_id        TEXT,
        exit_reason     TEXT,           -- tp/sl/time/manual/settlement
        entry_price     INTEGER,
        exit_price      INTEGER,
        contracts       INTEGER,
        pnl             REAL,
        hold_time_mins  INTEGER,        -- minutes from entry to exit
        source          TEXT,
        strategy        TEXT,
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Kalshi settlements
    CREATE TABLE IF NOT EXISTS settlements (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        settled_time    TEXT NOT NULL,
        ticker          TEXT NOT NULL,
        category        TEXT,
        revenue         REAL,
        cost_basis      REAL,
        pnl             REAL,
        source          TEXT,
        strategy        TEXT,
        entry_price     INTEGER,
        confidence      REAL,
        edge            REAL,
        hit_rate        REAL,
        result          TEXT,           -- win/loss/void/scalar
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Generic event log
    CREATE TABLE IF NOT EXISTS events (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        event_time      TEXT NOT NULL,
        event_type      TEXT,           -- rfq_submitted, quote_received, etc
        ticker          TEXT,
        details         TEXT,           -- JSON blob
        created_at      TEXT DEFAULT (datetime('now'))
    );

    -- Indexes
    CREATE INDEX IF NOT EXISTS idx_signals_ticker    ON signals(ticker);
    CREATE INDEX IF NOT EXISTS idx_signals_strategy  ON signals(strategy);
    CREATE INDEX IF NOT EXISTS idx_signals_time      ON signals(signal_time);
    CREATE INDEX IF NOT EXISTS idx_orders_ticker     ON orders(ticker);
    CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders(status);
    CREATE INDEX IF NOT EXISTS idx_fills_ticker      ON fills(ticker);
    CREATE INDEX IF NOT EXISTS idx_positions_source  ON positions(source);
    CREATE INDEX IF NOT EXISTS idx_settlements_source ON settlements(source);
    CREATE INDEX IF NOT EXISTS idx_settlements_time  ON settlements(settled_time);
    """)
    conn.commit()
    conn.close()
    log.info(f"[PositionsDB] Initialized")


# ── Writers ────────────────────────────────────────────────────────────────

def record_signal(ticker: str, strategy: str, side: str, price_cents: int,
                  confidence: float = 0, edge: float = 0, hit_rate: float = 0,
                  reason: str = '', source: str = 'bot', acted_on: bool = False,
                  skip_reason: str = '') -> int:
    """Record a signal. Returns signal_id."""
    series   = ticker.split('-')[0]
    category = _categorize(ticker)
    conn = get_db()
    try:
        cur = conn.execute("""
            INSERT INTO signals
            (signal_time, ticker, series, category, strategy, side,
             price_cents, confidence, edge, hit_rate, reason,
             source, acted_on, skip_reason)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (now(), ticker, series, category, strategy, side,
              price_cents, confidence, edge, hit_rate, reason,
              source, int(acted_on), skip_reason))
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


def record_order(order_id: str, client_order_id: str, ticker: str,
                 strategy: str, side: str, price_cents: int,
                 contracts: int, source: str = 'bot',
                 signal_id: int = None) -> int:
    """Record an order placement."""
    category = _categorize(ticker)
    conn = get_db()
    try:
        cur = conn.execute("""
            INSERT OR IGNORE INTO orders
            (order_id, client_order_id, signal_id, ticker, category,
             strategy, side, price_cents, contracts, source,
             order_time, status)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        """, (order_id, client_order_id, signal_id, ticker, category,
              strategy, side, price_cents, contracts, source,
              now(), 'pending'))
        conn.commit()
        return cur.lastrowid
    finally:
        conn.close()


def record_fill(ticker: str, order_id: str, client_order_id: str,
                side: str, qty: int, fill_price: int,
                source: str = 'unknown', strategy: str = '',
                confidence: float = 0, edge: float = 0,
                hit_rate: float = 0, reason: str = ''):
    """Record a fill and open/update position."""
    cost_basis = qty * fill_price / 100.0
    category   = _categorize(ticker)
    fill_time  = now()
    conn = get_db()
    try:
        # Record fill
        conn.execute("""
            INSERT INTO fills
            (fill_time, ticker, order_id, side, qty,
             fill_price, cost_basis, source, strategy)
            VALUES (?,?,?,?,?,?,?,?,?)
        """, (fill_time, ticker, order_id, side, qty,
              fill_price, cost_basis, source, strategy))

        # Update order status + fill time
        conn.execute("""
            UPDATE orders SET status='filled', fill_time=?, fill_price=?
            WHERE order_id=?
        """, (fill_time, fill_price, order_id))

        # Upsert position
        conn.execute("""
            INSERT INTO positions
            (ticker, order_id, side, qty, entry_price, cost_basis,
             source, strategy, category, confidence, edge, hit_rate,
             reason, entry_time, peak_price, current_price, unrealized_pnl)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)
            ON CONFLICT(ticker) DO UPDATE SET
                qty           = qty + excluded.qty,
                cost_basis    = cost_basis + excluded.cost_basis
        """, (ticker, order_id, side, qty, fill_price, cost_basis,
              source, strategy, category, confidence, edge,
              hit_rate, reason, fill_time, fill_price, fill_price))

        conn.commit()
        log.info(f"[PositionsDB] Fill: {ticker} {side} @ {fill_price}¢ "
                f"source={source} strategy={strategy}")
    except Exception as e:
        log.warning(f"[PositionsDB] Fill failed: {e}")
    finally:
        conn.close()


def record_settlement(ticker: str, revenue: float,
                      source: str = 'unknown', strategy: str = ''):
    """Record settlement and close position."""
    category    = _categorize(ticker)
    settled_at  = now()
    conn = get_db()
    try:
        # Get position data
        pos = conn.execute(
            "SELECT * FROM positions WHERE ticker=?", (ticker,)
        ).fetchone()

        cost_basis  = pos['cost_basis']  if pos else 0
        entry_price = pos['entry_price'] if pos else 0
        confidence  = pos['confidence']  if pos else 0
        edge        = pos['edge']        if pos else 0
        hit_rate    = pos['hit_rate']    if pos else 0
        src         = pos['source']      if pos else source
        strat       = pos['strategy']    if pos else strategy

        pnl    = revenue - cost_basis
        result = 'win' if revenue > cost_basis else 'loss' if revenue == 0 else 'scalar'

        conn.execute("""
            INSERT INTO settlements
            (settled_time, ticker, category, revenue, cost_basis, pnl,
             source, strategy, entry_price, confidence, edge, hit_rate, result)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (settled_at, ticker, category, revenue, cost_basis, pnl,
              src, strat, entry_price, confidence, edge, hit_rate, result))

        # Remove closed position
        conn.execute("DELETE FROM positions WHERE ticker=?", (ticker,))

        conn.commit()
        log.info(f"[PositionsDB] Settlement: {ticker} "
                f"revenue=${revenue:.2f} pnl=${pnl:.2f} result={result}")
    except Exception as e:
        log.warning(f"[PositionsDB] Settlement failed: {e}")
    finally:
        conn.close()


def record_exit(ticker: str, order_id: str, exit_reason: str,
                entry_price: int, exit_price: int, contracts: int,
                pnl: float, source: str = 'bot', strategy: str = ''):
    """Record an exit event."""
    conn = get_db()
    try:
        # Calculate hold time
        pos = conn.execute(
            "SELECT entry_time FROM positions WHERE ticker=?", (ticker,)
        ).fetchone()
        hold_mins = 0
        if pos and pos['entry_time']:
            from datetime import datetime
            try:
                entry = datetime.fromisoformat(pos['entry_time'])
                hold_mins = int((datetime.now(timezone.utc) - entry).total_seconds() / 60)
            except Exception:
                pass

        conn.execute("""
            INSERT INTO exits
            (exit_time, ticker, order_id, exit_reason, entry_price,
             exit_price, contracts, pnl, hold_time_mins, source, strategy)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, (now(), ticker, order_id, exit_reason, entry_price,
              exit_price, contracts, pnl, hold_mins, source, strategy))
        conn.commit()
    except Exception as e:
        log.warning(f"[PositionsDB] Exit record failed: {e}")
    finally:
        conn.close()


def log_event(event_type: str, ticker: str = '', details: dict = None):
    """Log a generic event."""
    import json
    conn = get_db()
    try:
        conn.execute("""
            INSERT INTO events (event_time, event_type, ticker, details)
            VALUES (?,?,?,?)
        """, (now(), event_type, ticker,
              json.dumps(details) if details else None))
        conn.commit()
    except Exception:
        pass
    finally:
        conn.close()


# ── Readers ────────────────────────────────────────────────────────────────

def get_open_positions(source: str = None) -> list:
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM positions WHERE source=? ORDER BY entry_time DESC",
                (source,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM positions ORDER BY entry_time DESC"
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_pnl_summary() -> dict:
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT source,
                   COUNT(*)  as n,
                   SUM(CASE WHEN result='win' THEN 1 ELSE 0 END) as wins,
                   SUM(revenue)  as revenue,
                   SUM(pnl)      as pnl,
                   AVG(pnl)      as avg_pnl
            FROM settlements
            GROUP BY source
        """).fetchall()
        result = {}
        for r in rows:
            n = r['n'] or 1
            result[r['source']] = {
                'n':        r['n'],
                'wins':     r['wins'],
                'revenue':  round(r['revenue'] or 0, 2),
                'pnl':      round(r['pnl'] or 0, 2),
                'avg_pnl':  round(r['avg_pnl'] or 0, 2),
                'win_rate': round((r['wins'] or 0) / n * 100, 1),
            }
        return result
    finally:
        conn.close()


def get_strategy_performance() -> list:
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT strategy,
                   COUNT(*)   as n,
                   SUM(CASE WHEN result='win' THEN 1 ELSE 0 END) as wins,
                   SUM(pnl)   as total_pnl,
                   AVG(pnl)   as avg_pnl,
                   AVG(confidence) as avg_conf
            FROM settlements
            WHERE strategy != ''
            GROUP BY strategy
            ORDER BY total_pnl DESC
        """).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_recent_settlements(limit: int = 20, source: str = None) -> list:
    conn = get_db()
    try:
        if source:
            rows = conn.execute(
                "SELECT * FROM settlements WHERE source=? ORDER BY settled_time DESC LIMIT ?",
                (source, limit)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM settlements ORDER BY settled_time DESC LIMIT ?",
                (limit,)
            ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_signal_stats() -> dict:
    """How many signals generated vs acted on."""
    conn = get_db()
    try:
        row = conn.execute("""
            SELECT COUNT(*) as total,
                   SUM(acted_on) as acted,
                   COUNT(DISTINCT strategy) as strategies
            FROM signals
        """).fetchone()
        return dict(row) if row else {}
    finally:
        conn.close()


def get_fill_time_stats() -> dict:
    """Average time from order to fill."""
    conn = get_db()
    try:
        row = conn.execute("""
            SELECT AVG(time_to_fill_secs) as avg_secs,
                   MIN(time_to_fill_secs) as min_secs,
                   MAX(time_to_fill_secs) as max_secs,
                   COUNT(*) as n
            FROM orders
            WHERE status='filled' AND time_to_fill_secs IS NOT NULL
        """).fetchone()
        return dict(row) if row else {}
    finally:
        conn.close()


# ── Helpers ────────────────────────────────────────────────────────────────

def now() -> str:
    return datetime.now(timezone.utc).isoformat()[:19]


def _categorize(ticker: str) -> str:
    if 'MULTIGAME' in ticker or 'CROSSCATEGORY' in ticker:
        return 'combo'
    series = ticker.split('-')[0]
    if series in ('KXNBAPTS','KXNBAREB','KXNBAAST',
                  'KXNBA3PT','KXNBASTL','KXNBABLK'):
        return 'prop'
    if 'NBAGAME' in series or 'NBASPR' in series:
        return 'game'
    if 'ATP' in series or 'WTA' in series:
        return 'tennis'
    if 'MLB' in series:
        return 'mlb'
    return 'other'


init_db()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/positions_db.py) lines"
python3 -m py_compile data/positions_db.py && echo "Syntax OK"
python3 -c "
from data.positions_db import init_db, get_signal_stats, get_pnl_summary
print('DB OK')
print('Signals:', get_signal_stats())
print('PNL:', get_pnl_summary())
"
rm /root/kalshi-bot-v2/data/positions.db
python3 -c "
from data.positions_db import init_db, get_signal_stats, get_pnl_summary
print('DB OK')
print('Signals:', get_signal_stats())
print('PNL:', get_pnl_summary())
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'r')
c = f.read()
f.close()

old = '''        # One trade per player per session
        player_key = f"{player}_{stat}"
        if player_key in self._traded_players:
            return None
        self._traded_players.add(player_key)
        self._session_trades += 1

        log.info(
            f"[PropNBA] {player} {thr}+ {stat} YES @ {yes_price}c "
            f"conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%} "
            f"[{self._session_trades}/{self.MAX_TRADES_PER_SESSION}]"
        )

        return make_signal('''

new = '''        # One trade per player per session
        player_key = f"{player}_{stat}"
        if player_key in self._traded_players:
            return None
        self._traded_players.add(player_key)
        self._session_trades += 1

        log.info(
            f"[PropNBA] {player} {thr}+ {stat} YES @ {yes_price}c "
            f"conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%} "
            f"[{self._session_trades}/{self.MAX_TRADES_PER_SESSION}]"
        )

        # Record signal to DB
        try:
            from data.positions_db import record_signal
            record_signal(
                ticker      = ticker,
                strategy    = self.name,
                side        = 'yes',
                price_cents = yes_price,
                confidence  = conf,
                edge        = edge,
                hit_rate    = hit_rate,
                reason      = l.reasoning if hasattr(result, "reasoning") else f"{player} {thr}+ {stat}",
                source      = 'bot',
                acted_on    = True,
            )
        except Exception as _e:
            log.debug(f"[PropNBA] Signal DB record failed: {_e}")

        return make_signal('''

c = c.replace(old, new)

# Also record skipped signals
old2 = '''        if hit_rate < MIN_HIT_RATE and hit_rate > 0:
            return None'''

new2 = '''        if hit_rate < MIN_HIT_RATE and hit_rate > 0:
            try:
                from data.positions_db import record_signal
                record_signal(ticker=ticker, strategy=self.name, side='yes',
                    price_cents=yes_price, confidence=conf, edge=edge,
                    hit_rate=hit_rate, source='bot', acted_on=False,
                    skip_reason=f"hit_rate {hit_rate:.0%} below {MIN_HIT_RATE:.0%}")
            except Exception:
                pass
            return None'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'w').write(c)
print("Done")
PYEOF

# Wire record_order into bot.py after place_order succeeds
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

old = '''                            reconciler.register_bot_order(order_id, client_order_id)'''
new = '''                            reconciler.register_bot_order(order_id, client_order_id)
                            try:
                                from data.positions_db import record_order
                                record_order(
                                    order_id        = order_id,
                                    client_order_id = client_order_id,
                                    ticker          = trade_signal.market_ticker,
                                    strategy        = trade_signal.strategy_name,
                                    side            = str(trade_signal.side).split(".")[-1].lower(),
                                    price_cents     = trade_signal.price,
                                    contracts       = trade_signal.contracts,
                                    source          = 'bot',
                                )
                            except Exception as _dbe:
                                log.debug(f"[Bot] DB order record failed: {_dbe}")'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile strategies/prop_nba.py && echo "prop_nba OK"
python3 -m py_compile bot.py && echo "bot OK"
python3 -m py_compile order_manager.py && echo "order_manager OK"
systemctl restart kalshi-bot-v2
sleep 15
tail -10 kalshi_bot.log | grep -E "PropNBA|FILLED|PENDING|PositionsDB|Cycle done|Error"
python3 -c "
from data.positions_db import get_open_positions, get_signal_stats, get_pnl_summary

print('=== SIGNALS ===')
stats = get_signal_stats()
print(f'Total: {stats[\"total\"]} | Acted on: {stats[\"acted\"]} | Strategies: {stats[\"strategies\"]}')

print()
print('=== OPEN POSITIONS ===')
positions = get_open_positions()
print(f'Count: {len(positions)}')
for p in positions:
    print(f'  {p[\"ticker\"][-30:]} {p[\"side\"]} @ {p[\"entry_price\"]}c '
          f'cost=\${p[\"cost_basis\"]:.2f} source={p[\"source\"]} conf={p[\"confidence\"]:.2f}')

print()
print('=== PNL ===')
print(get_pnl_summary())
" 2>&1 | grep -v DEBUG | grep -v WARNING
grep -n "record_fill\|PositionsDB" /root/kalshi-bot-v2/order_manager.py | head -10
systemctl stop kalshi-bot-v2
python3 -c "
import kalshi_python, time
from core.kalshi_client import get_client
pa = kalshi_python.PortfolioApi(api_client=get_client())
orders = pa.get_orders(status='resting')
all_orders = orders.orders or []
print(f'Cancelling {len(all_orders)}...')
for o in all_orders:
    try:
        pa.cancel_order(o.order_id)
        time.sleep(0.05)
    except: pass
print('Done')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'r')
c = f.read()
f.close()

old = '''        # Hard cap — stop after MAX_TRADES_PER_SESSION
        if self._session_trades >= self.MAX_TRADES_PER_SESSION:
            return None'''

new = '''        # Hard cap — check Kalshi directly for resting orders
        if self._session_trades >= self.MAX_TRADES_PER_SESSION:
            return None

        # Also check reconciler exposure as safety net
        try:
            from core.reconciler import reconciler
            if reconciler.get_total_exposure() >= self.MAX_TRADES_PER_SESSION:
                return None
        except Exception:
            pass'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'w').write(c)
print("Done")
PYEOF

# Clear state and restart
rm -f data/pending_orders.json data/open_positions.json data/cooldowns.json data/bot_orders.json
python3 -m py_compile strategies/prop_nba.py && echo "OK"
systemctl start kalshi-bot-v2
sleep 15
tail -5 kalshi_bot.log | grep -E "PropNBA|Cycle done|position limit|exposure"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'r')
c = f.read()
f.close()

old = '''        # Hard cap — stop after MAX_TRADES_PER_SESSION
        if self._session_trades >= self.MAX_TRADES_PER_SESSION:
            return None'''

new = '''        # Hard cap — check Kalshi directly for resting orders
        if self._session_trades >= self.MAX_TRADES_PER_SESSION:
            return None

        # Also check reconciler exposure as safety net
        try:
            from core.reconciler import reconciler
            if reconciler.get_total_exposure() >= self.MAX_TRADES_PER_SESSION:
                return None
        except Exception:
            pass'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/strategies/prop_nba.py', 'w').write(c)
print("Done")
PYEOF

# Clear state and restart
rm -f data/pending_orders.json data/open_positions.json data/cooldowns.json data/bot_orders.json
python3 -m py_compile strategies/prop_nba.py && echo "OK"
systemctl start kalshi-bot-v2
sleep 15
tail -5 kalshi_bot.log | grep -E "PropNBA|Cycle done|position limit|exposure"
tail -20 /root/kalshi-bot-v2/kalshi_bot.log | grep -E "PropNBA|Cycle|position|exposure|Error|PENDING|FILLED"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client
pa = kalshi_python.PortfolioApi(api_client=get_client())
r = pa.get_orders(status='resting')
p = pa.get_positions()
print(f'Resting: {len(r.orders or [])}')
print(f'Positions: {len(p.positions or [])}')
for pos in (p.positions or []):
    qty  = getattr(pos, 'position', 0)
    cost = (getattr(pos, 'total_cost', 0) or 0) / 100
    val  = (getattr(pos, 'market_value', 0) or 0) / 100
    print(f'  {str(pos.ticker)[-32:]} qty={qty} cost=\${cost:.2f} val=\${val:.2f}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 combo_scanner.py --live       # live execution
