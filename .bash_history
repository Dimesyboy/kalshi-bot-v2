
echo "models.py written"
python3 -c "import ast; ast.parse(open('/root/models.py').read()); print('Syntax OK')"
python3 << 'EOF'
content = open('/root/strategies.py').read()
# Replace all deferred imports inside functions
old = "from kalshi_bot import TradeSignal, Config"
new = "from models import TradeSignal, Config"
count = content.count(old)
content = content.replace(old, new)
open('/root/strategies.py', 'w').write(content)
print(f"Replaced {count} deferred imports in strategies.py")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

# Add models import at top after existing imports
old = "from dotenv import load_dotenv"
new = "from dotenv import load_dotenv\nfrom models import Config, Market, GameEvent, TradeSignal"

if "from models import" not in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("models import added to kalshi_bot.py")
else:
    print("already imported")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import ast
for f in ['models.py','kalshi_bot.py','strategies.py']:
    try:
        ast.parse(open(f'/root/{f}').read())
        print(f'✅ {f}')
    except SyntaxError as e:
        print(f'❌ {f} line {e.lineno}: {e.msg}')
"
python3 -c "
import sys
sys.path.insert(0, '/root')
import models
print('✅ models imported')
import strategies
print('✅ strategies imported')
import kalshi_bot
print('✅ kalshi_bot imported')
print()
print('Circular import: RESOLVED')
"
python3 /root/check_stack_v2.py 2>&1 | grep -E "FAIL|WARN" | grep -v "check_stack\|POSITION_SIZE\|MAX_POSITION_HARD\|LOOP_INTERVAL\|MAX_DAILY_LOSS\|active.*400\|competitions\|integration_patch\|bare.*

python3 /root/check_stack_v2.py 2>&1 | grep -E "FAIL|WARN" | grep -v "check_stack\|POSITION_SIZE\|MAX_POSITION_HARD\|LOOP_INTERVAL\|MAX_DAILY_LOSS\|active.*400\|competitions\|integration_patch\|bare.*

python3 /root/check_stack_v2.py 2>&1 | grep -E "FAIL|WARN" | grep -v "check_stack\|POSITION_SIZE\|MAX_POSITION_HARD\|LOOP_INTERVAL\|MAX_DAILY_LOSS\|active.*400\|competitions\|integration_patch\|bare.*except\|print.*calls"
grep -n "entry_price.*20\|- 20" /root/telegram_controller.py
python3 << 'EOF'
content = open('/root/telegram_controller.py').read()
old = '                        sell_price = max(1, pos.get("entry_price", 1) - 20)'
new = '                        sell_price = max(1, pos.get("entry_price", 1))'
if old in content:
    content = content.replace(old, new)
    open('/root/telegram_controller.py', 'w').write(content)
    print("Fallback fixed")
else:
    print("Pattern not found")
EOF

grep -n "sell_price" /root/telegram_controller.py
echo "Verified"
python3 -c "import ast; ast.parse(open('/root/telegram_controller.py').read()); print('Syntax OK')"
grep -n "^class Config\|^class Market\|^class GameEvent\|^class TradeSignal" /root/kalshi_bot.py
sed -n '82,90p' /root/kalshi_bot.py
sed -n '183,188p' /root/kalshi_bot.py
sed -n '207,215p' /root/kalshi_bot.py
sed -n '215,235p' /root/kalshi_bot.py
sed -n '82,185p' /root/kalshi_bot.py | grep -n "^class\|^    OPENAI\|^    TELEGRAM\|^    FETCH\|^    LOG_MAX\|^    KALSHI_BASE"
sed -n '155,190p' /root/kalshi_bot.py
grep -n "second_entry\|^# =\|^class \|^def \|^_" /root/kalshi_bot.py | sed -n '10,25p'
python3 << 'EOF'
lines = open('/root/kalshi_bot.py').readlines()

# Remove Config class: lines 82-160 (0-indexed: 81-159)
# Remove DATA STRUCTURES section: lines 178-231 (0-indexed: 177-230)
# We'll mark ranges to remove
remove = set()
for i in range(81, 160):   # Config class
    remove.add(i)
for i in range(177, 231):  # DATA STRUCTURES + Market + GameEvent + TradeSignal
    remove.add(i)

out = [l for i, l in enumerate(lines) if i not in remove]
open('/root/kalshi_bot.py', 'w').writelines(out)
print(f"Removed {len(remove)} lines")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Verifying imports still resolve..."
python3 -c "
import sys; sys.path.insert(0,'/root')
from models import Config, Market, GameEvent, TradeSignal
import kalshi_bot
print('✅ All imports resolve')
print(f'✅ Config accessible: DRY_RUN={kalshi_bot.Config.DRY_RUN}')
print(f'✅ TradeSignal accessible: {kalshi_bot.TradeSignal}')
"
python3 /root/check_stack_v2.py 2>&1 | tail -20
python3 /root/check_stack_v2.py 2>&1 | grep "WARN"
grep -n "strategy_tennis_underdog\|tennis_underdog" /root/strategies.py | grep -v "def \|#"
python3 << 'EOF'
content = open('/root/strategies.py').read()
old = '    _wrap(strategy_tennis_underdog),'
new = '    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades'
if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("tennis_underdog disabled")
else:
    print("Pattern not found")
EOF

python3 -c "
from strategies import STRATEGIES
print('Active strategies:')
for s in STRATEGIES:
    print(f'  {s.__name__}')
"
python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
grep -n "price_watcher\|watcher\|_exiting" /root/kalshi_bot.py | grep -v "#" | head -15
grep -n "action.*sell\|is_exit\|def execute_signal" /root/kalshi_bot.py | head -15
sed -n '1653,1665p' /root/kalshi_bot.py
grep -n "execute_signal" /root/kalshi_bot.py
sed -n '1670,1695p' /root/kalshi_bot.py
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''            for signal in signals:
                placed, total_pnl = execute_signal(
                    signal, snapshot, open_positions,
                    total_pnl, pnl_log, current_date, client,
                )'''

new = '''            for signal in signals:
                # skip if watcher already exiting this ticker
                if signal.action == "sell" and signal.market_ticker in _watcher._exiting:
                    log.info(f"[Loop] Skipping sell {signal.market_ticker} — watcher already exiting")
                    continue
                placed, total_pnl = execute_signal(
                    signal, snapshot, open_positions,
                    total_pnl, pnl_log, current_date, client,
                )'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("_exiting guard added to main loop")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
python3 /root/check_stack_v2.py 2>&1 | tail -15
python kalshi_bot.py
python3 -c "
from dotenv import load_dotenv
load_dotenv('/root/.env')
import os
print('KEY_ID:', os.getenv('KALSHI_API_KEY_ID','NOT SET')[:8])
print('KEY_FILE:', os.getenv('KALSHI_PRIVATE_KEY_PATH','NOT SET'))
print('TG_TOKEN:', os.getenv('TELEGRAM_BOT_TOKEN','NOT SET')[:8])
print('TG_CHAT:', os.getenv('TELEGRAM_CHAT_ID','NOT SET'))
"
sed -n '1,75p' /root/kalshi_bot.py | grep -n "load_dotenv\|from models\|import models\|from dotenv"
python3 << 'EOF'
lines = open('/root/kalshi_bot.py').readlines()

# Find the lines
dotenv_import_line = None
models_import_line = None
load_dotenv_line = None

for i, l in enumerate(lines):
    if 'from dotenv import load_dotenv' in l:
        dotenv_import_line = i
    if 'from models import' in l:
        models_import_line = i
    if l.strip() == 'load_dotenv()':
        load_dotenv_line = i

print(f"dotenv import: {dotenv_import_line+1}")
print(f"models import: {models_import_line+1}")
print(f"load_dotenv(): {load_dotenv_line+1}")

# Remove load_dotenv() from line 75 and insert it right after the dotenv import
lines.pop(load_dotenv_line)
# insert after dotenv import (which is now at same index)
lines.insert(dotenv_import_line + 1, 'load_dotenv()\n')

open('/root/kalshi_bot.py', 'w').writelines(lines)
print("load_dotenv() moved before models import")
EOF

grep -n "load_dotenv\|from models" /root/kalshi_bot.py | head -5
echo "Verified order"
python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
python3 /root/kalshi_bot.py
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
signals = [w for w in watchlist if w['flag'] == 'SIGNAL']

print(f'Total watched: {len(watchlist)}')
print(f'Total signals: {len(signals)}')
print()
for w in signals[:20]:
    m = w['market']
    print(f\"{w['sport']:<8} {m.ticker:<45} bid={int(m.yes_bid*100):>3}c ask={int(m.yes_ask*100):>3}c vol={int(m.volume):>6} sprd={m.spread:>4}c | {w['reason']}\")
"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, load_positions
from strategies import STRATEGIES, ESPNContextCache, strategy_value_fade

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

rejected = []
fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append((strat.__name__, item['market'].ticker, sig.price, sig.confidence))
        except Exception as e:
            rejected.append((strat.__name__, item['market'].ticker, str(e)))

print(f'Fired: {len(fired)}')
for s, t, p, c in fired:
    print(f'  {s:<30} {t:<45} price={p}c conf={c}')

print(f'Errors: {len(rejected)}')
for s, t, e in rejected[:5]:
    print(f'  {s}: {t} -> {e}')
"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import ESPNContextCache, _allowed, _is_prop, _is_nba_mlb, _is_tennis

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

reasons = {}
for item in watchlist:
    m = item['market']
    sport = item.get('sport','')
    status = item.get('market_status','open')

    if not _allowed(m.ticker):
        reasons['not_allowed'] = reasons.get('not_allowed',0)+1; continue
    if m.yes_bid < 0.95:
        reasons['bid_below_95c'] = reasons.get('bid_below_95c',0)+1; continue
    if _is_prop(m.ticker):
        reasons['is_prop'] = reasons.get('is_prop',0)+1; continue

    # volume gate
    if any(m.ticker.startswith(s) for s in ['KXNBA1HWINNER','KXNBA2HWINNER','KXNBA1QWINNER','KXNBA2QWINNER','KXNBA3QWINNER','KXNBA4QWINNER']):
        min_vol = 3000
    elif m.ticker.startswith('KXMLBSTGAME'):
        min_vol = 400
    else:
        min_vol = 8000
    if m.volume < min_vol:
        reasons[f'vol_below_{min_vol}'] = reasons.get(f'vol_below_{min_vol}',0)+1; continue
    if m.spread > 3:
        reasons['spread_too_wide'] = reasons.get('spread_too_wide',0)+1; continue

    no_bid_cents = max(1, int(m.no_bid*100))
    if no_bid_cents < 5:
        reasons['no_bid_below_5c'] = reasons.get('no_bid_below_5c',0)+1; continue

    reasons['PASSED'] = reasons.get('PASSED',0)+1
    print(f'PASS: {m.ticker} bid={int(m.yes_bid*100)}c no_bid={no_bid_cents}c vol={int(m.volume)}')

print()
for r,n in sorted(reasons.items(), key=lambda x:-x[1]):
    print(f'  {r}: {n}')
"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

# Show bid distribution
from collections import Counter
buckets = Counter()
for w in watchlist:
    bid = int(w['market'].yes_bid * 100)
    if bid >= 90: buckets['90-100c'] += 1
    elif bid >= 80: buckets['80-90c'] += 1
    elif bid >= 70: buckets['70-80c'] += 1
    elif bid >= 60: buckets['60-70c'] += 1
    else: buckets['<60c'] += 1

print('Bid distribution across watched markets:')
for k,v in sorted(buckets.items()):
    print(f'  {k}: {v}')

# Show the highest bids
top = sorted(watchlist, key=lambda x: x['market'].yes_bid, reverse=True)[:5]
print()
print('Top 5 highest YES bids:')
for w in top:
    m = w['market']
    print(f'  {int(m.yes_bid*100)}c  {m.ticker}')
"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import _ev, _allowed, _is_prop
import math

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

print(f'Markets with YES bid >= 85c that pass volume/spread gates:')
print(f'{\"Ticker\":<45} {\"YES\":<5} {\"NO\":<5} {\"Vol\":<8} {\"EV@65%\":>8} {\"EV@60%\":>8} {\"BE%\":>6}')
print('-'*90)

for w in sorted(watchlist, key=lambda x: x['market'].yes_bid, reverse=True):
    m = w['market']
    if m.yes_bid < 0.85: break
    if not _allowed(m.ticker): continue
    if _is_prop(m.ticker): continue
    if m.volume < 8000: continue
    if m.spread > 3: continue

    no_bid_c = max(1, int(m.no_bid*100))
    if no_bid_c < 3: continue

    ev65 = _ev(10, no_bid_c, 0.65, is_maker=True)
    ev60 = _ev(10, no_bid_c, 0.60, is_maker=True)

    # break-even confidence
    pd = no_bid_c/100
    fee = math.ceil(0.0175*10*pd*(1-pd)*100)/100 * 2
    be = (fee/10 + pd)

    print(f'{m.ticker:<45} {int(m.yes_bid*100):>3}c  {no_bid_c:>3}c  {int(m.volume):>7}  {ev65:>8.4f}  {ev60:>8.4f}  {be:>5.1%}')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()
old = '    if m.yes_bid < 0.95: return None # lowered from 0.97 — matches manual trading edge'
new = '    if m.yes_bid < 0.92: return None # lowered from 0.95 — EV positive at 92c+, BE% < 9%'
if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Threshold lowered to 92c")
else:
    print("Pattern not found — checking exact text")
    idx = content.find('yes_bid < 0.9')
    print(repr(content[idx-5:idx+60]))
EOF

python3 << 'EOF'
content = open('/root/strategies.py').read()
old = '    if m.yes_bid < 0.95: return None'
new = '    if m.yes_bid < 0.92: return None  # lowered from 0.95 — EV positive at 92c+, BE% < 9%'
if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Threshold lowered to 92c")
else:
    print("Pattern not found")
EOF

grep -n "yes_bid < 0" /root/strategies.py | head -5
echo "Verified"
python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, load_positions
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)
open_pos = load_positions()

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append((strat.__name__, sig))
                break
        except: pass

print(f'Signals fired: {len(fired)}')
for name, sig in fired:
    print(f'  {name:<25} {sig.market_ticker:<45} {sig.side} @ {sig.price}c x{sig.contracts} conf={sig.confidence}')
"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import ESPNContextCache, strategy_value_fade, _allowed, _is_prop

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

# Trace NYK specifically
for w in watchlist:
    m = w['market']
    if 'NYK' not in m.ticker and 'DET' not in m.ticker:
        continue
    print(f'Market: {m.ticker}')
    print(f'  status={w[\"market_status\"]} yes_bid={m.yes_bid} vol={m.volume} spread={m.spread}')
    print(f'  no_bid={m.no_bid} no_bid_cents={int(m.no_bid*100)}')
    sig = strategy_value_fade(w, espn_cache=espn_cache)
    print(f'  signal={sig}')
    print()
"
python3 -c "
import requests
r = requests.get('http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard', timeout=8)
events = r.json().get('events', [])
print(f'ESPN events: {len(events)}')
for e in events[:5]:
    comps = e.get('competitions', [{}])
    status = comps[0].get('status', {}).get('type', {})
    print(f'  {e[\"name\"]} — state={status.get(\"state\")} detail={status.get(\"description\")}')
"
grep -n "_is_live\|def _is_live\|status.*active\|live" /root/strategies.py | head -20
python3 -c "
import requests

# Check a few markets to understand Kalshi status values
tickers = [
    'KXNBAGAME-26MAR20NYKBKN-NYK',  # tomorrow game
    'KXNBAGAME-26MAR19DETWAS-DET',  # tonight finished game
    'KXNBAGAME-26MAR19CLECHI-CLE',  # tonight finished game
]
for t in tickers:
    r = requests.get(f'https://api.elections.kalshi.com/trade-api/v2/markets/{t}', timeout=8)
    m = r.json().get('market', {})
    print(f'{t}')
    print(f'  status={m.get(\"status\")} close_time={m.get(\"close_time\")} open_time={m.get(\"open_time\")}')
    print()
"
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''def _is_live(status, sport, ticker):
    if status == "active": return True
    if sport == "Tennis" and status == "open": return True
    return False'''

new = '''def _is_live(status, sport, ticker):
    # Kalshi "active" just means market is open for trading — not that game is live
    # Use ESPN context to determine if game is actually in progress
    # This function now always returns False — live detection is done via ESPN ctx.is_live
    return False'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("_is_live fixed — live detection now via ESPN only")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
sed -n '67,70p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''def _is_live(status, sport, ticker):
    # Kalshi "active" just means market is open for trading — not that game is live
    # Use ESPN context to determine if game is actually in progress
    # This function now always returns False — live detection is done via ESPN ctx.is_live
    return False'''

new = '''def _is_live(status, sport, ticker, espn_cache=None):
    """
    Determine if a game is currently in progress.
    Kalshi 'active' just means the market is open for trading — not that the game is live.
    We use ESPN ctx.is_live as the source of truth when available.
    Falls back to False (pre-game assumed) if no ESPN context.
    """
    if espn_cache is not None:
        if _is_nba_mlb(ticker) and _NBA_CTX:
            ctx = find_game_for_ticker(ticker, espn_cache)
            if ctx is not None:
                return ctx.is_live
        if _is_tennis(ticker) and _TENNIS_CTX:
            from tennis_context import get_tennis_context
            tctx = get_tennis_context(ticker, espn_cache)
            if tctx is not None:
                return tctx.is_live
    return False  # assume pre-game if no ESPN context'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("_is_live fixed — ESPN is source of truth")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
content = open('/root/strategies.py').read()
# All callers currently do: live=_is_live(status, sport, m.ticker)
# Need to add espn_cache parameter
old1 = 'live=_is_live(status, sport, m.ticker)'
new1 = 'live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)'
count = content.count(old1)
content = content.replace(old1, new1)
open('/root/strategies.py', 'w').write(content)
print(f"Updated {count} _is_live callers")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, load_positions
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append((strat.__name__, sig))
                break
        except: pass

print(f'Signals fired: {len(fired)}')
for name, sig in fired:
    print(f'  {name:<25} {sig.market_ticker:<45} {sig.side} @ {sig.price}c x{sig.contracts} conf={sig.confidence}')
"
python3 /root/check_stack_v2.py 2>&1 | tail -10
python kalshi_bot.py
cd /root
git add kalshi_bot.py strategies.py price_watcher.py telegram_controller.py morning_report.py models.py check_stack_v2.py README.md tennis_context.py espn_module.py
git commit -m "fix: live detection, manual position guard, circular imports, hard close, tennis disabled, threshold 92c | $(date -u +'%Y-%m-%d %H:%M UTC')"
git push origin master
echo "Pushed"
screen -r
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
screen -S kalshi
grep -n "signal_cooldown\|cooldown" /root/kalshi_bot.py | grep -v "#" | head -20
sed -n '1675,1700p' /root/kalshi_bot.py
(kalshi-bot) root@Kalshi-bot:~# sed -n '1675,1700p' /root/kalshi_bot.py
(kalshi-bot) root@Kalshi-bot:~#
grep -n "signal_cooldown\|cooldown" /root/kalshi_bot.py | grep -v "#"
grep -n "run_strategies" /root/kalshi_bot.py
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

# Fix run_strategies signature to accept cooldown
old = 'def run_strategies(watchlist, open_positions, total_pnl, pnl_log, daily_limit_hit, espn_cache=None):'
new = 'def run_strategies(watchlist, open_positions, total_pnl, pnl_log, daily_limit_hit, espn_cache=None, signal_cooldown=None):'
content = content.replace(old, new)

# Fix the call site to pass cooldown
old2 = 'signals = run_strategies(watchlist_filtered, open_positions, total_pnl, pnl_log, daily_limit_hit or bot_paused, espn_cache=espn_cache)'
new2 = 'signals = run_strategies(watchlist_filtered, open_positions, total_pnl, pnl_log, daily_limit_hit or bot_paused, espn_cache=espn_cache, signal_cooldown=signal_cooldown)'
content = content.replace(old2, new2)

open('/root/kalshi_bot.py', 'w').write(content)
print("Signature and call site updated")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
sed -n '763,780p' /root/kalshi_bot.py
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''        if ticker in pending_tickers or daily_limit_hit:
            continue
        event_ticker = item["event_ticker"]'''

new = '''        if ticker in pending_tickers or daily_limit_hit:
            continue
        if signal_cooldown and ticker in signal_cooldown:
            continue  # cooldown active — skip this ticker
        event_ticker = item["event_ticker"]'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("Cooldown check added to run_strategies")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''                if signal.action == "buy":
                    signal_cooldown[signal.market_ticker] = now_ts + Config.SIGNAL_COOLDOWN_SECS
                elif signal.action == "sell":
                    # Block re-entry on any ticker we just exited for 30 min
                    signal_cooldown[signal.market_ticker] = now_ts + Config.SIGNAL_COOLDOWN_SECS
                    try:
                        import json as _j
                        _atomic_write_json("cooldown.json", signal_cooldown)
                    except: pass'''

new = '''                if signal.action in ("buy", "sell"):
                    signal_cooldown[signal.market_ticker] = now_ts + Config.SIGNAL_COOLDOWN_SECS
                    try:
                        _atomic_write_json("cooldown.json", signal_cooldown)
                    except: pass'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("Cooldown written on both buy and sell")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
screen -r
python3 -c "
import sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv
load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache, _is_live, _allowed, _is_prop
from nba_context import find_game_for_ticker

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

print('='*80)
print('SPORT DATA FLOW DIAGNOSTIC')
print('='*80)

# ESPN state
print()
print('ESPN CONTEXT:')
for sport in ['NBA','MLB']:
    col = espn_cache._all.get(sport)
    if col:
        live = col.live()
        pre  = [g for g in col if g.is_pre]
        post = [g for g in col if g.is_final]
        print(f'  {sport}: {len(col)} total | {len(live)} live | {len(pre)} pre-game | {len(post)} final')
        for g in live[:3]:
            print(f'    LIVE: {g.away.name} {g.away.score} @ {g.home.name} {g.home.score} | Q{g.period} {g.clock}')
        for g in pre[:3]:
            print(f'    PRE:  {g.away.name} @ {g.home.name}')

print()
print('TENNIS CONTEXT:')
from tennis_context import _fetch_livescore
try:
    matches = _fetch_livescore()
    print(f'  Live matches: {len(matches)}')
    for m in matches[:5]:
        print(f'    {m}')
except Exception as e:
    print(f'  Error: {e}')

print()
print('='*80)
print('MARKETS BY SPORT:')
print('='*80)

for sport in ['NBA','Tennis','MLB']:
    markets = [w for w in watchlist if w['sport']==sport]
    print(f'\\n{sport}: {len(markets)} markets watched')
    print(f'  {\"Ticker\":<45} {\"YES\":>5} {\"NO\":>5} {\"Vol\":>8} {\"Status\":<8} {\"ESPN Live\":<10} {\"Signal\"}')
    print(f'  {\"-\"*100}')
    for w in sorted(markets, key=lambda x: x['market'].yes_bid, reverse=True)[:10]:
        m = w['market']
        # check ESPN live status
        espn_live = 'N/A'
        if sport in ('NBA','MLB'):
            ctx = find_game_for_ticker(m.ticker, espn_cache)
            espn_live = 'LIVE' if (ctx and ctx.is_live) else ('PRE' if (ctx and ctx.is_pre) else ('FINAL' if ctx else 'no_ctx'))

        fired = None
        for strat in STRATEGIES:
            try:
                sig = strat(w, espn_cache=espn_cache)
                if sig:
                    fired = f'{sig.side}@{sig.price}c conf={sig.confidence}'
                    break
            except: pass

        print(f'  {m.ticker:<45} {int(m.yes_bid*100):>4}c {int(m.no_bid*100):>4}c {int(m.volume):>8} {w[\"market_status\"]:<8} {espn_live:<10} {fired or \"-\"}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from strategies import ESPNContextCache
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)
col = espn_cache._all.get('NBA')
if col and len(col) > 0:
    g = list(col)[0]
    print(type(g).__name__)
    print(sorted([a for a in dir(g) if not a.startswith('_')]))
    print()
    print('Sample values:')
    for a in sorted([a for a in dir(g) if not a.startswith('_')]):
        try:
            print(f'  {a} = {getattr(g,a)}')
        except: pass
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache
from nba_context import find_game_for_ticker

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

print('='*80)
print('ESPN CONTEXT')
print('='*80)
for sport in ['NBA','MLB']:
    col = espn_cache._all.get(sport)
    if col:
        live  = [g for g in col if g.is_live]
        final = [g for g in col if g.is_final]
        pre   = [g for g in col if not g.is_live and not g.is_final]
        print(f'{sport}: {len(col)} total | {len(live)} live | {len(pre)} pre | {len(final)} final')
        for g in live[:3]:
            print(f'  LIVE:  {g.away.name} {g.away.score} @ {g.home.name} {g.home.score} Q{g.nba_quarter} {g.clock}')
        for g in pre[:3]:
            print(f'  PRE:   {g.away.name} @ {g.home.name}')
        for g in final[:3]:
            print(f'  FINAL: {g.away.name} {g.away.score} @ {g.home.name} {g.home.score}')

print()
print('='*80)
print('SIGNAL TRACE BY SPORT')
print('='*80)
for sport in ['NBA','Tennis','MLB']:
    markets = [w for w in watchlist if w['sport']==sport]
    fired   = []
    blocked = {}
    for w in markets:
        m = w['market']
        sig = None
        for strat in STRATEGIES:
            try:
                sig = strat(w, espn_cache=espn_cache)
                if sig: break
            except: pass
        if sig:
            fired.append((m.ticker, sig))
        else:
            # find first blocking reason for top bid markets
            if m.yes_bid >= 0.85:
                ctx = find_game_for_ticker(m.ticker, espn_cache) if sport=='NBA' else None
                espn_state = ('LIVE' if ctx and ctx.is_live else 'FINAL' if ctx and ctx.is_final else 'PRE/NONE') if ctx else 'no_ctx'
                blocked[m.ticker] = f'bid={int(m.yes_bid*100)}c vol={int(m.volume)} espn={espn_state}'

    print(f'\n{sport}: {len(markets)} markets | {len(fired)} signals fired')
    for ticker, sig in fired:
        print(f'  FIRE: {ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence} [{sig.strategy}]')
    if blocked:
        print(f'  High-bid markets NOT firing:')
        for t,r in list(blocked.items())[:5]:
            print(f'    {t:<45} {r}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from strategies import ESPNContextCache
from nba_context import find_game_for_ticker, parse_prop_ticker

espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

ticker = 'KXNBAGAME-26MAR19DETWAS-DET'
parsed = parse_prop_ticker(ticker)
print('Parsed:', parsed)

col = espn_cache._all.get('NBA')
print('NBA games in ESPN:')
for g in col:
    print(f'  home={g.home.abbreviation} away={g.away.abbreviation} | {g.away.name} @ {g.home.name} | final={g.is_final}')

ctx = find_game_for_ticker(ticker, espn_cache)
print('Match found:', ctx)
"
grep -n "min_vol\|MIN_VOLUME\|8000\|3000\|400" /root/strategies.py | head -15
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from strategies import ESPNContextCache
from nba_context import find_game_for_ticker

espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

for ticker in ['KXNBAGAME-26MAR19CLECHI-CLE','KXNBAGAME-26MAR20NYKBKN-NYK']:
    ctx = find_game_for_ticker(ticker, espn_cache)
    if ctx:
        print(f'{ticker}')
        print(f'  is_live={ctx.is_live} is_final={ctx.is_final} score={ctx.away.score}-{ctx.home.score}')
    else:
        print(f'{ticker} -> no ESPN context')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    conf=0.65
    ctx_reason="no context"
    if _is_nba_mlb(m.ticker):
        if _is_prop(m.ticker): return None # never fade props
        if live:'''

new = '''    conf=0.65
    ctx_reason="no context"
    if _is_nba_mlb(m.ticker):
        if _is_prop(m.ticker): return None # never fade props
        # never enter on a game ESPN has already marked as final
        if espn_cache is not None:
            ctx = find_game_for_ticker(m.ticker, espn_cache)
            if ctx and ctx.is_final:
                return None
        if live:'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("is_final guard added")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
content = open('/root/strategies.py').read()
# Add WTA/ATP specific volume gate — WTA is less liquid
old = '''    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 3000 # Q/H winner markets
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 400 # Spring training — lower liquidity is normal
    else:
        min_vol = 8000 # Full season NBA/MLB game markets'''

new = '''    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 3000 # Q/H winner markets
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 400 # Spring training — lower liquidity is normal
    elif any(m.ticker.startswith(s) for s in ["KXWTAMATCH","KXWTAGAME","KXWTACHALLENGERMATCH"]):
        min_vol = 5000 # WTA naturally less liquid than ATP
    else:
        min_vol = 8000 # Full season NBA/MLB game markets'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("WTA volume threshold lowered to 5000")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
grep -n "min_vol = 3000\|min_vol = 400\|min_vol = 8000" /root/strategies.py
sed -n '319,332p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    # Volume gates by market type
    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 3000
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 400
    else:
        min_vol = 8000'''

new = '''    # Volume gates by market type — at $1-10 position sizes, 3000 vol is ample liquidity
    if any(m.ticker.startswith(s) for s in ["KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        min_vol = 2000
    elif m.ticker.startswith("KXMLBSTGAME"):
        min_vol = 300
    elif any(m.ticker.startswith(s) for s in ["KXWTAMATCH","KXWTAGAME","KXWTACHALLENGERMATCH"]):
        min_vol = 4000  # WTA less liquid than ATP
    else:
        min_vol = 5000  # NBA/MLB/ATP full game markets'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Volume gates updated")
else:
    print("Pattern not found")
    # show actual content around that area
    idx = content.find("Volume gates")
    print(repr(content[idx:idx+300]))
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
grep -n "min_vol" /root/strategies.py | head -10
sed -n '300,320p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)

    if m.yes_bid < 0.92: return None  # lowered from 0.95 — EV positive at 92c+, BE% < 9%'''

new = '''    live=_is_live(status, sport, m.ticker, espn_cache=espn_cache)

    # never enter a position on a game ESPN has already marked as finished
    if espn_cache is not None and _is_nba_mlb(m.ticker):
        from nba_context import find_game_for_ticker
        _ctx = find_game_for_ticker(m.ticker, espn_cache)
        if _ctx and _ctx.is_final:
            return None

    if m.yes_bid < 0.92: return None  # lowered from 0.95 — EV positive at 92c+, BE% < 9%'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("is_final guard added")
else:
    print("Pattern not found")
    idx = content.find("_is_live(status, sport")
    print(repr(content[idx:idx+200]))
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
grep -n "is_final" /root/strategies.py
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot
from strategies import STRATEGIES, ESPNContextCache

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn_cache = ESPNContextCache()
espn_cache.refresh(max_age=0)

fired = []
for item in watchlist:
    for strat in STRATEGIES:
        try:
            sig = strat(item, espn_cache=espn_cache)
            if sig:
                fired.append((strat.__name__, sig, item['sport']))
                break
        except: pass

print(f'Signals fired: {len(fired)}')
for name, sig, sport in fired:
    print(f'  [{sport}] {name:<25} {sig.market_ticker:<45} {sig.side}@{sig.price}c x{sig.contracts} conf={sig.confidence} | {sig.reason}')
"
grep -n "timeout\|connect timeout" /root/tennis_context.py | head -10
grep -n "^TIMEOUT\|^TENNIS_API" /root/tennis_context.py | head -5
sed -i 's/^TIMEOUT        = 8/TIMEOUT        = 3/' /root/tennis_context.py
echo "Timeout lowered to 3s"
grep -n "^TIMEOUT" /root/tennis_context.py
python3 -c "import ast; ast.parse(open('/root/tennis_context.py').read()); print('Syntax OK')"
python3 /root/check_stack_v2.py 2>&1 | tail -10
cd /root && git add kalshi_bot.py strategies.py price_watcher.py telegram_controller.py morning_report.py models.py check_stack_v2.py README.md tennis_context.py espn_module.py && git commit -m "fix: cooldown dedup, is_final guard, volume gates, WTA threshold, tennis timeout, _is_live via ESPN | $(date -u +'%Y-%m-%d %H:%M UTC')" && git push origin master && echo "Pushed"
grep -n "Token or chat\|TELEGRAM\|tg_ctrl" /root/kalshi_bot.py | head -15
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Config
print('TOKEN:', repr(Config.TELEGRAM_TOKEN[:10]) if Config.TELEGRAM_TOKEN else 'EMPTY')
print('CHAT:', repr(Config.TELEGRAM_CHAT))
print('KEY_ID:', repr(Config.KALSHI_KEY_ID[:8]) if Config.KALSHI_KEY_ID else 'EMPTY')
"
grep -n "load_dotenv\|from models import" /root/kalshi_bot.py | head -5
head -10 /root/models.py
python3 << 'EOF'
content = open('/root/models.py').read()
old = 'import os\nfrom dataclasses import dataclass, field\nfrom typing import Optional'
new = 'import os\nfrom dataclasses import dataclass, field\nfrom typing import Optional\nfrom dotenv import load_dotenv\nload_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"), override=False)\nload_dotenv("/root/.env", override=False)'
if old in content:
    content = content.replace(old, new)
    open('/root/models.py', 'w').write(content)
    print("load_dotenv added to models.py")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/models.py').read()); print('Syntax OK')"
echo "Verify Config loads correctly..."​​​​​​​​​​​​​​​​
python3 -c "
import sys; sys.path.insert(0,'/root')
from models import Config
print('TOKEN:', 'SET' if Config.TELEGRAM_TOKEN else 'EMPTY')
print('CHAT:', 'SET' if Config.TELEGRAM_CHAT else 'EMPTY')
print('KEY_ID:', 'SET' if Config.KALSHI_KEY_ID else 'EMPTY')
"
pkill -f kalshi_bot.py
echo "Stopped"
sleep 2
python3 /root/kalshi_bot.py 2>&1 | head -30
screen -r
python kalshi_bot.py
screen -r
python3 /root/kalshi_bot.py 2>&1 | grep -E "TGCtrl|Telegram|SIGNAL|PLACED|Cycle|Sleeping"
python3 /root/kalshi_bot.py 2>&1 | grep -E "Timing|TOTAL CYCLE|snapshot|ESPN|Tennis|Sleeping"
cat /root/cooldown.json
echo "---"
cat /root/positions.json
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
from strategies import _fetch_fills_raw_single

client = _get_kalshi_client()
fills = _fetch_fills_raw_single(client)
nyk = [f for f in fills if 'NYK' in str(f.get('ticker','')) or 'NYKBKN' in str(f.get('ticker',''))]
print(f'NYK fills: {len(nyk)}')
for f in nyk:
    print(f'  {f}')
"
grep -n "Position recorded\|order_placed\|bot_orders\|placed.*True" /root/kalshi_bot.py | head -20
sed -n '1075,1100p' /root/kalshi_bot.py
sed -n '1055,1080p' /root/kalshi_bot.py
grep -n "reconcile\|Removed\|ADDED\|rm\b" /root/strategies.py | grep -v "#" | head -20
sed -n '258,272p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        try:
            r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8); r.raise_for_status()
            ms=r.json().get("market",{}).get("status","")
            log.info(f"[Reconcile] {'SETTLED' if ms in ('settled','finalized') else 'CLOSED'}: {ticker}")
        except Exception as e: log.warning(f"[Reconcile] {ticker}:{e}")
        rm.append(ticker)'''

new = '''    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        # Check if there is a resting (unfilled) bot order for this ticker
        # If so, keep the position — the order just hasn't filled yet
        order_id = pos.get("order_id","")
        if order_id and bot_orders and order_id in bot_orders:
            try:
                import kalshi_python
                pa = kalshi_python.PortfolioApi(api_client=client)
                # Check order status via fills — if still resting, skip removal
                r2 = requests.get(
                    f"{kalshi_base}/portfolio/orders/{order_id}",
                    timeout=6)
                if r2.ok:
                    order_status = r2.json().get("order",{}).get("status","")
                    if order_status in ("resting","pending"):
                        log.info(f"[Reconcile] {ticker} order {order_id} still {order_status} — keeping position")
                        continue
            except Exception as e:
                log.debug(f"[Reconcile] order check {ticker}: {e}")
        try:
            r=requests.get(f"{kalshi_base}/markets/{ticker}",timeout=8); r.raise_for_status()
            ms=r.json().get("market",{}).get("status","")
            log.info(f"[Reconcile] {'SETTLED' if ms in ('settled','finalized') else 'CLOSED'}: {ticker}")
        except Exception as e: log.warning(f"[Reconcile] {ticker}:{e}")
        rm.append(ticker)'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Resting order guard added to reconcile")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client, _kalshi_rest_get
# check what orders endpoint looks like
try:
    data = _kalshi_rest_get('/trade-api/v2/portfolio/orders?limit=3')
    import json
    orders = data.get('orders',[])
    print(f'Orders: {len(orders)}')
    if orders:
        print('Sample order keys:', list(orders[0].keys()))
        print('Sample status:', orders[0].get('status'))
except Exception as e:
    print(f'Error: {e}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
try:
    orders = pa.get_orders(limit=5)
    print(type(orders))
    print(dir(orders))
except Exception as e:
    print(f'Error: {e}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=5)
orders = resp.orders or []
print(f'Orders: {len(orders)}')
for o in orders:
    print(f'  ticker={o.ticker} status={o.status} side={o.side} action={o.action} remaining={o.remaining_count}')
"
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''        order_id = pos.get("order_id","")
        if order_id and bot_orders and order_id in bot_orders:
            try:
                import kalshi_python
                pa = kalshi_python.PortfolioApi(api_client=client)
                # Check order status via fills — if still resting, skip removal
                r2 = requests.get(
                    f"{kalshi_base}/portfolio/orders/{order_id}",
                    timeout=6)
                if r2.ok:
                    order_status = r2.json().get("order",{}).get("status","")
                    if order_status in ("resting","pending"):
                        log.info(f"[Reconcile] {ticker} order {order_id} still {order_status} — keeping position")
                        continue
            except Exception as e:
                log.debug(f"[Reconcile] order check {ticker}: {e}")'''

new = '''        order_id = pos.get("order_id","")
        if order_id and bot_orders and order_id in bot_orders:
            try:
                import kalshi_python
                pa = kalshi_python.PortfolioApi(api_client=client)
                resp = pa.get_orders(limit=50)
                resting = {o.order_id for o in (resp.orders or []) if o.status in ("resting","pending")}
                if order_id in resting:
                    log.info(f"[Reconcile] {ticker} order {order_id} still resting — keeping position")
                    continue
            except Exception as e:
                log.debug(f"[Reconcile] order check {ticker}: {e}")'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("Resting order check updated to use SDK")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
import json, time, sys
sys.path.insert(0, '/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python
from datetime import datetime, timezone

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=50)
resting = [o for o in (resp.orders or []) if o.status == "resting"]

print(f"Resting orders: {len(resting)}")

# Load existing files
positions = {}
try: positions = json.load(open('/root/positions.json'))
except: pass

cooldown = {}
try: cooldown = json.load(open('/root/cooldown.json'))
except: pass

bot_orders = set()
try: bot_orders = set(json.load(open('/root/bot_orders.json')))
except: pass

now_ts = time.time()
cooldown_secs = 1800

for o in resting:
    ticker = o.ticker
    order_id = o.order_id
    print(f"  {ticker} {o.side} @ {o.yes_price or o.no_price}c — adding to positions + cooldown")
    
    # Add to positions if not already there
    if ticker not in positions:
        price = int(o.yes_price or o.no_price or 0)
        positions[ticker] = {
            "side": o.side,
            "entry_price": price,
            "contracts": int(o.client_order_id and 20 or 20),
            "strategy": "value_fade",
            "entry_time": datetime.now(timezone.utc).isoformat(),
            "event_ticker": ticker.rsplit("-", 1)[0],
            "reason": "resting order on startup",
            "entry_fee": 0.0,
            "order_id": order_id,
            "is_bot": True,
            "peak_price": price,
            "last_bid": price,
        }
    
    # Add to cooldown
    cooldown[ticker] = now_ts + cooldown_secs
    
    # Add to bot_orders
    bot_orders.add(order_id)

# Save all
json.dump(positions, open('/root/positions.json','w'), indent=2)
json.dump(cooldown, open('/root/cooldown.json','w'), indent=2)
json.dump(list(bot_orders), open('/root/bot_orders.json','w'), indent=2)

print(f"\npositions.json: {len(positions)} entries")
print(f"cooldown.json: {len(cooldown)} entries")
print(f"bot_orders.json: {len(bot_orders)} entries")
EOF

screen -ls
screen -S 156093.kalshi -X quit
echo "Old screen killed"
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Bot started in new screen"
sleep 5
screen -S kalshi -X hardcopy /tmp/kalshi_out.txt
cat /tmp/kalshi_out.txt
screen -r
screen -S kalshi -X hardcopy /tmp/kalshi_out.txt
cat /tmp/kalshi_out.txt | grep -E "Cycle|PLACED|cooldown|Loaded|Sleeping|TOTAL CYCLE|resting" | head -20
tail -30 /root/kalshi_bot.log
screen -S kalshi -X quit
echo "Stopped"
grep -n "_livescore_cache\|_fetch_livescore\|_last_fetch\|_cache" /root/tennis_context.py | head -10
sed -n '85,100p' /root/tennis_context.py
python3 << 'EOF'
content = open('/root/tennis_context.py').read()

old = '''def _fetch_livescore() -> List[dict]:
    global _livescore_cache
    now = time.time()
    if _livescore_cache and now - _livescore_cache.get("ts", 0) < LIVESCORE_TTL:
        return _livescore_cache["data"]
    data = _api({"method": "get_livescore"})
    if data and isinstance(data.get("result"), list):
        _livescore_cache = {"data": data["result"], "ts": now}
        log.info(f"[Tennis] Livescore: {len(data['result'])} live matches")
        return data["result"]
    return _livescore_cache.get("data", [])'''

new = '''FAILURE_TTL = 60  # cache failures for 60s — don't hammer API on outage

def _fetch_livescore() -> List[dict]:
    global _livescore_cache
    now = time.time()
    last_ts = _livescore_cache.get("ts", 0)
    last_ok = _livescore_cache.get("ok", True)
    ttl = LIVESCORE_TTL if last_ok else FAILURE_TTL
    if _livescore_cache and now - last_ts < ttl:
        return _livescore_cache.get("data", [])
    data = _api({"method": "get_livescore"})
    if data and isinstance(data.get("result"), list):
        _livescore_cache = {"data": data["result"], "ts": now, "ok": True}
        log.info(f"[Tennis] Livescore: {len(data['result'])} live matches")
        return data["result"]
    # cache the failure so we don't retry for FAILURE_TTL seconds
    _livescore_cache = {"data": _livescore_cache.get("data", []), "ts": now, "ok": False}
    return _livescore_cache["data"]'''

if old in content:
    content = content.replace(old, new)
    open('/root/tennis_context.py', 'w').write(content)
    print("Failure caching added to _fetch_livescore")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/tennis_context.py').read()); print('Syntax OK')"
echo "Done"
grep -n "def _fetch_rankings\|def _fetch_h2h\|def _fetch_standings" /root/tennis_context.py
sed -n '105,145p' /root/tennis_context.py
grep -n "RANKINGS_TTL\|LIVESCORE_TTL\|H2H_TTL" /root/tennis_context.py | head -5
python3 << 'EOF'
content = open('/root/tennis_context.py').read()

old = '''def _fetch_rankings() -> Dict:
    global _rankings_cache
    now = time.time()
    if _rankings_cache and now - _rankings_cache.get("ts", 0) < RANKINGS_TTL:
        return _rankings_cache
    out: Dict = {"ATP": {}, "WTA": {}, "ts": now}
    for league in ("ATP", "WTA"):
        data = _api({"method": "get_standings", "event_type": league})
        if data and isinstance(data.get("result"), list):
            for entry in data["result"]:
                try:
                    name = entry.get("player", "")
                    rank = int(entry.get("place", 999))
                    if name:
                        out[league][name.upper()] = rank
                except Exception:
                    pass
            log.info(f"[Tennis] Rankings: {league} {len(out[league])} players")
    _rankings_cache = out
    return out'''

new = '''def _fetch_rankings() -> Dict:
    global _rankings_cache
    now = time.time()
    last_ts = _rankings_cache.get("ts", 0)
    last_ok = _rankings_cache.get("ok", True)
    ttl = RANKINGS_TTL if last_ok else FAILURE_TTL
    if _rankings_cache and now - last_ts < ttl:
        return _rankings_cache
    out: Dict = {"ATP": {}, "WTA": {}, "ts": now, "ok": True}
    any_ok = False
    for league in ("ATP", "WTA"):
        data = _api({"method": "get_standings", "event_type": league})
        if data and isinstance(data.get("result"), list):
            any_ok = True
            for entry in data["result"]:
                try:
                    name = entry.get("player", "")
                    rank = int(entry.get("place", 999))
                    if name:
                        out[league][name.upper()] = rank
                except Exception:
                    pass
            log.info(f"[Tennis] Rankings: {league} {len(out[league])} players")
    if not any_ok:
        # cache failure — keep old data but mark failed
        _rankings_cache = {**_rankings_cache, "ts": now, "ok": False}
        return _rankings_cache
    _rankings_cache = out
    return out'''

if old in content:
    content = content.replace(old, new)
    open('/root/tennis_context.py', 'w').write(content)
    print("Failure caching added to _fetch_rankings")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/tennis_context.py').read()); print('Syntax OK')"
echo "Done"
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Started"
sleep 8
tail -20 /root/kalshi_bot.log
screen -r
tail -40 /root/kalshi_bot.log
cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
print(f'Positions: {len(p)}')
for t,v in p.items():
    print(f'  {t}')
    print(f'    side={v[\"side\"]} entry={v[\"entry_price\"]}c strategy={v[\"strategy\"]} is_bot={v.get(\"is_bot\")}')
"
grep -n "resting\|order_id\|bot_orders" /root/strategies.py | grep -v "#" | head -20
python3 -c "
import json
bot_orders = json.load(open('/root/bot_orders.json'))
print('bot_orders:', bot_orders)
print()
# Check what order IDs the resting orders have
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python
client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=10)
for o in (resp.orders or []):
    if o.status == 'resting':
        print(f'Resting: {o.ticker} order_id={o.order_id}')
        print(f'  In bot_orders: {o.order_id in bot_orders}')
"
grep -n "load_positions\|reconcile_positions\|purge_stale\|Startup" /root/kalshi_bot.py | head -20
sed -n '1543,1590p' /root/kalshi_bot.py
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''    open_positions = load_positions()

    # Start price watcher thread'''

new = '''    open_positions = load_positions()

    # Recover resting orders into positions on startup
    # Prevents re-entry on unfilled limit orders after restart
    try:
        import kalshi_python
        _pa = kalshi_python.PortfolioApi(api_client=client)
        _resp = _pa.get_orders(limit=50)
        _resting = [o for o in (_resp.orders or []) if o.status in ("resting","pending")]
        _recovered = 0
        for o in _resting:
            if o.ticker not in open_positions and o.order_id in _bot_orders:
                price = int(o.yes_price or o.no_price or 0)
                open_positions[o.ticker] = {
                    "side":         o.side,
                    "entry_price":  price,
                    "contracts":    int(o.client_order_id and 20 or 20),
                    "strategy":     "value_fade",
                    "entry_time":   datetime.now(timezone.utc).isoformat(),
                    "event_ticker": o.ticker.rsplit("-", 1)[0],
                    "reason":       "recovered resting order on startup",
                    "entry_fee":    0.0,
                    "order_id":     o.order_id,
                    "is_bot":       True,
                    "peak_price":   price,
                    "last_bid":     price,
                }
                _recovered += 1
        if _recovered:
            save_positions(open_positions)
            log.info(f"[Startup] Recovered {_recovered} resting order(s) into positions")
    except Exception as _e:
        log.warning(f"[Startup] Resting order recovery failed: {_e}")

    # Start price watcher thread'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("Resting order recovery added to startup")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
screen -S kalshi -X quit
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
sleep 8
tail -25 /root/kalshi_bot.log
sleep 30 && cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
print(f'Positions after reconcile: {len(p)}')
for t,v in p.items():
    print(f'  {t}')
    print(f'    side={v[\"side\"]} entry={v[\"entry_price\"]}c order_id={v.get(\"order_id\",\"none\")[:8]}...')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=10)
for o in (resp.orders or []):
    if o.status == 'resting':
        print(f'ticker={o.ticker}')
        print(f'  side={o.side} action={o.action}')
        print(f'  yes_price={o.yes_price} no_price={o.no_price}')
        print(f'  count={o.count} remaining={o.remaining_count}')
        print(f'  order_id={o.order_id}')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from kalshi_bot import _get_kalshi_client
import kalshi_python

client = _get_kalshi_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_orders(limit=10)
o = resp.orders[0]
print('All fields:')
for field in o.model_fields:
    val = getattr(o, field, None)
    if val is not None:
        print(f'  {field} = {val}')
"
python3 << 'EOF'
content = open('/root/kalshi_bot.py').read()

old = '''                price = int(o.yes_price or o.no_price or 0)
                open_positions[o.ticker] = {
                    "side":         o.side,
                    "entry_price":  price,
                    "contracts":    int(o.client_order_id and 20 or 20),
                    "strategy":     "value_fade",
                    "entry_time":   datetime.now(timezone.utc).isoformat(),
                    "event_ticker": o.ticker.rsplit("-", 1)[0],
                    "reason":       "recovered resting order on startup",
                    "entry_fee":    0.0,
                    "order_id":     o.order_id,
                    "is_bot":       True,
                    "peak_price":   price,
                    "last_bid":     price,
                }'''

new = '''                # fetch live market price since SDK doesn't return order price
                price = 0
                contracts = 20
                try:
                    _mr = requests.get(
                        f"{Config.KALSHI_BASE}/markets/{o.ticker}", timeout=6)
                    if _mr.ok:
                        _md = _mr.json().get("market", {})
                        if o.side == "no":
                            price = int(float(_md.get("no_ask_dollars", 0) or 0) * 100)
                        else:
                            price = int(float(_md.get("yes_ask_dollars", 0) or 0) * 100)
                except Exception:
                    pass
                open_positions[o.ticker] = {
                    "side":         o.side,
                    "entry_price":  price,
                    "contracts":    contracts,
                    "strategy":     "value_fade",
                    "entry_time":   datetime.now(timezone.utc).isoformat(),
                    "event_ticker": o.ticker.rsplit("-", 1)[0],
                    "reason":       "recovered resting order on startup",
                    "entry_fee":    0.0,
                    "order_id":     o.order_id,
                    "is_bot":       True,
                    "peak_price":   price,
                    "last_bid":     price,
                }'''

if old in content:
    content = content.replace(old, new)
    open('/root/kalshi_bot.py', 'w').write(content)
    print("Price lookup added to resting order recovery")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/kalshi_bot.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys, json, requests
sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')

positions = json.load(open('/root/positions.json'))

for ticker, pos in positions.items():
    if pos.get('entry_price', 0) == 0:
        r = requests.get(f'https://api.elections.kalshi.com/trade-api/v2/markets/{ticker}', timeout=6)
        if r.ok:
            m = r.json().get('market', {})
            side = pos['side']
            if side == 'no':
                price = int(float(m.get('no_ask_dollars', 0) or 0) * 100)
            else:
                price = int(float(m.get('yes_ask_dollars', 0) or 0) * 100)
            pos['entry_price'] = price
            pos['peak_price'] = price
            pos['last_bid'] = price
            print(f'Fixed {ticker}: {side} @ {price}c')

json.dump(positions, open('/root/positions.json','w'), indent=2)
print('Done')
"
screen -S kalshi -X quit
sleep 1
screen -dmS kalshi python3 /root/kalshi_bot.py
echo "Restarted"
sleep 12
tail -20 /root/kalshi_bot.log
sleep 35 && cat /root/positions.json | python3 -c "
import json,sys
p = json.load(sys.stdin)
print(f'Positions: {len(p)}')
for t,v in p.items():
    print(f'  {t} | side={v[\"side\"]} entry={v[\"entry_price\"]}c is_bot={v.get(\"is_bot\")}')
" && echo "---" && tail -5 /root/kalshi_bot.log
python3 -c "
import requests
r = requests.get('https://api.elections.kalshi.com/trade-api/v2/markets/KXNBAGAME-26MAR20NYKBKN-NYK', timeout=6)
m = r.json().get('market',{})
print('status:', m.get('status'))
print('close_time:', m.get('close_time'))
print('result:', m.get('result'))
"
python3 -c "
import requests
r = requests.get('https://api.elections.kalshi.com/trade-api/v2/markets/KXNBAGAME-26MAR20NYKBKN-NYK', timeout=6)
m = r.json().get('market',{})
print('yes_bid:', float(m.get('yes_bid_dollars',0))*100, 'c')
print('no_bid:', float(m.get('no_bid_dollars',0))*100, 'c')
print('no_ask:', float(m.get('no_ask_dollars',0))*100, 'c')
"
sed -n '350,420p' /root/price_watcher.py
grep -n "def strategy_exit" /root/strategies.py
sed -n '600,650p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''def strategy_exit(item, pos, espn_cache=None):
    from models import TradeSignal, Config
    from datetime import datetime, timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None
    if side=="no": return None
    if pos.get("is_bot") is False: return None  # never auto-exit manual positions
    bid=max(1,int(m.yes_bid*100))
    peak=max(bid,pos.get("peak_price",entry))
    pos["peak_price"]=peak
    fee_mult=0.0175
    entry_fee=pos.get("entry_fee",0.0)
    exit_fee=math.ceil(fee_mult*contracts*(bid/100)*(1-bid/100)*100)/100
    pnl=(bid-entry)*contracts/100.0-entry_fee-exit_fee
    if entry<=15: stop=max(1,peak-max(3,int(peak*0.50)))
    elif pnl>=2.00: stop=int(peak*0.88)
    elif pnl>=0.50: stop=int(peak*0.82)
    else: stop=int(entry*0.70)
    stale=False
    try:
        et=pos.get("entry_time","")
        if et:
            age=(datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            strategy_name=pos.get("strategy","")
            if "tennis" in strategy_name.lower():
                stale_min_age = 7200'''

new = '''def strategy_exit(item, pos, espn_cache=None):
    from models import TradeSignal, Config
    from datetime import datetime, timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None
    if pos.get("is_bot") is False: return None  # never auto-exit manual positions

    # unified exit — works for both YES and NO
    if side == "yes":
        bid = max(1, int(m.yes_bid * 100))
    else:
        bid = max(1, int(m.no_bid * 100))

    peak = max(bid, pos.get("peak_price", entry))
    pos["peak_price"] = peak

    fee_mult   = 0.0175
    entry_fee  = pos.get("entry_fee", 0.0)
    exit_fee   = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
    pnl        = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee

    # Trail stop — activates once 50% gain achieved (ensures fees covered)
    trail_active = bid >= entry * 1.5
    trail_stop   = int(peak * 0.80)

    # Hard stop — 40% loss from entry regardless of trail
    hard_stop = int(entry * 0.60)

    reason = None

    if trail_active and bid <= trail_stop:
        reason = f"Trail stop: {bid}c <= {trail_stop}c (peak={peak}c entry={entry}c) PNL=${pnl:.2f}"
    elif bid <= hard_stop:
        reason = f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}"

    # stale exit — position hasn't moved and is underwater after fees
    stale = False
    try:
        et = pos.get("entry_time","")
        if et:
            age = (datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            strategy_name = pos.get("strategy","")
            if "tennis" in strategy_name.lower():
                stale_min_age = 7200'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("strategy_exit updated")
else:
    print("Pattern not found")
    idx = content.find("def strategy_exit")
    print(repr(content[idx:idx+100]))
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
sed -n '624,700p' /root/strategies.py
python3 << 'EOF'
content = open('/root/strategies.py').read()

old = '''    if not (bid<=stop or stale): return None
    if stale and bid>stop:
        reason=f"Stale: {int(age)}s, {abs(bid-entry)}c move, PNL=${pnl:.2f}"
        strat=f"exit_stale_{strategy}"
    elif pnl>=0.10:
        reason=f"Trail stop: {bid}c peak={peak}c PNL=${pnl:.2f}"
        strat=f"exit_trail_{strategy}"
    else:
        reason=f"Stop loss: {bid}c<={stop}c entry={entry}c PNL=${pnl:.2f}"
        strat=f"exit_sl_{strategy}"
    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )'''

new = '''    # stale exit overrides reason if no trail/hard stop triggered
    if stale and reason is None:
        reason = f"Stale: {int(age)}s, {abs(bid-entry)}c move, PNL=${pnl:.2f}"

    if reason is None:
        return None

    # determine strategy tag
    if stale and not trail_active and bid > hard_stop:
        strat = f"exit_stale_{strategy}"
    elif trail_active and bid <= trail_stop:
        strat = f"exit_trail_{strategy}"
    else:
        strat = f"exit_sl_{strategy}"

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )'''

if old in content:
    content = content.replace(old, new)
    open('/root/strategies.py', 'w').write(content)
    print("strategy_exit cleanup done")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/strategies.py').read()); print('Syntax OK')"
echo "Done"
python3 << 'EOF'
content = open('/root/price_watcher.py').read()

old = '''            # ── Tennis: match-state aware logic ───────────────────────────
            if _is_tennis_ticker(ticker):
                if self._check_tennis_position(ticker, pos, bid):
                    continue
                pos["last_bid"] = bid
                continue

            # ── NBA / MLB: quick profit lock first, then standard logic ───
            quick_target = int(entry * self.QUICK_PROFIT_MULT)
            if bid >= quick_target and pnl > 0:
                self._place_exit(ticker, pos, bid,
                    f"Quick profit lock: {bid}c >= {quick_target}c (50% on {entry}c) PNL=${pnl:.2f}")
                continue

            if pnl >= 2.00:
                stop = int(peak * 0.88)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid,
                        f"Trail exit: ${pnl:.2f} profit, peak={peak}c")
                    continue

            if bid >= entry * 2.5:
                self._place_exit(ticker, pos, bid,
                    f"2.5x exit: {bid}c vs entry {entry}c profit=${pnl:.2f}")
                continue

            if pnl >= 0.50:
                stop = int(peak * 0.82)
                if bid <= stop:
                    self._place_exit(ticker, pos, bid,
                        f"Trail exit: ${pnl:.2f} profit, peak={peak}c stop={stop}c")
                    continue

            if bid <= int(entry * 0.70):
                self._place_exit(ticker, pos, bid,
                    f"Stop loss: {bid}c <= {int(entry*0.70)}c (entry={entry}c)")
                continue

            if bid <= 5 and entry > 15:
                self._place_exit(ticker, pos, bid, f"Floor exit: {bid}c")
                continue

            last_bid = pos.get("last_bid", entry)'''

new = '''            # ── Unified exit logic — all sports, both sides ──────────────
            # Trail activates at 50% gain (ensures fees covered)
            trail_active = bid >= entry * 1.5
            trail_stop   = int(peak * 0.80)
            hard_stop    = int(entry * 0.60)

            if trail_active and bid <= trail_stop:
                self._place_exit(ticker, pos, bid,
                    f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
                continue

            if bid <= hard_stop:
                self._place_exit(ticker, pos, bid,
                    f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
                continue

            last_bid = pos.get("last_bid", entry)'''

if old in content:
    content = content.replace(old, new)
    open('/root/price_watcher.py', 'w').write(content)
    print("price_watcher unified exit done")
else:
    print("Pattern not found")
EOF

python3 -c "import ast; ast.parse(open('/root/price_watcher.py').read()); print('Syntax OK')"
echo "Done"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market
from strategies import strategy_exit

def make_pos(side, entry, peak, contracts=10):
    return {'side':side,'entry_price':entry,'peak_price':peak,
            'contracts':contracts,'strategy':'value_fade',
            'entry_time':'2024-01-01T00:00:00+00:00',
            'event_ticker':'TEST','entry_fee':0.02,'is_bot':True}

def make_item(yes_bid, no_bid, ticker='KXATPMATCH-TEST'):
    m = Market(ticker=ticker,title='Test',yes_bid=yes_bid/100,yes_ask=(yes_bid+2)/100,
               no_bid=no_bid/100,no_ask=(no_bid+2)/100,last_price=yes_bid/100,
               volume=10000,liquidity=500,close_time=None,series='KXATPMATCH',
               label='ATP',market_status='active')
    return {'sport':'Tennis','event_ticker':'TEST','game_title':'Test',
            'market':m,'flag':'SIGNAL','reason':'test','market_status':'active'}

tests = [
    # (side, entry, peak, yes_bid, no_bid, expect_exit, desc)
    ('no',  5, 40, 92, 7,  False, 'NO peak=40c bid=7c — trail not active yet (7 < 5*1.5=7.5)'),
    ('no',  5, 40, 92, 8,  True,  'NO peak=40c bid=8c but trail stop=32c — 8<=32 TRAIL'),
    ('no',  5,  5, 92, 3,  True,  'NO bid=3c hard stop (3 <= 5*0.6=3) HARD STOP'),
    ('no',  5,  5, 92, 4,  False, 'NO bid=4c no trail active no hard stop — HOLD'),
    ('yes',70, 90, 68,30,  False, 'YES peak=90c bid=68c trail not active (68 < 70*1.5=105)'),
    ('yes',50, 90, 65,33,  True,  'YES peak=90c bid=65c trail active (65>=75) stop=72c — TRAIL'),
    ('yes',50, 50, 30,68,  True,  'YES bid=30c hard stop (30<=30) HARD STOP'),
]

print(f'{\"Test\":<55} {\"Exit?\":<8} {\"Pass?\"}')
print('-'*75)
all_pass = True
for side, entry, peak, yes_bid, no_bid, expect, desc in tests:
    pos = make_pos(side, entry, peak)
    item = make_item(yes_bid, no_bid)
    sig = strategy_exit(item, pos)
    exited = sig is not None
    passed = exited == expect
    if not passed: all_pass = False
    mark = '✅' if passed else '❌'
    reason = sig.reason[:40] if sig else 'HOLD'
    print(f'{mark} {desc:<55} {str(exited):<8} {reason}')

print()
print('All passed' if all_pass else 'SOME FAILED')
"
python3 -c "
import sys; sys.path.insert(0,'/root')
from dotenv import load_dotenv; load_dotenv('/root/.env')
from models import Market
from strategies import strategy_exit
from datetime import datetime, timezone

def make_pos(side, entry, peak, contracts=10, minutes_ago=30):
    from datetime import timedelta
    entry_time = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    return {'side':side,'entry_price':entry,'peak_price':peak,
            'contracts':contracts,'strategy':'value_fade',
            'entry_time':entry_time,
            'event_ticker':'TEST','entry_fee':0.02,'is_bot':True}

def make_item(yes_bid, no_bid, ticker='KXATPMATCH-TEST'):
    m = Market(ticker=ticker,title='Test',yes_bid=yes_bid/100,yes_ask=(yes_bid+2)/100,
               no_bid=no_bid/100,no_ask=(no_bid+2)/100,last_price=yes_bid/100,
               volume=10000,liquidity=500,close_time=None,series='KXATPMATCH',
               label='ATP',market_status='active')
    return {'sport':'Tennis','event_ticker':'TEST','game_title':'Test',
            'market':m,'flag':'SIGNAL','reason':'test','market_status':'active'}

tests = [
    # side  entry peak  yes  no   expect  desc
    ('no',  5,  40,  92,  7,  False, 'NO peak=40 bid=7 — below trail activation (7.5) HOLD'),
    ('no',  5,  40,  92,  8,  True,  'NO peak=40 bid=8 — trail active(8>=7.5) stop=32 TRAIL'),
    ('no',  5,   5,  92,  3,  True,  'NO bid=3 hard stop (3<=3) STOP'),
    ('no',  5,   5,  92,  4,  False, 'NO bid=4 no trail no hard stop HOLD'),
    ('yes',50, 100,  65, 33,  True,  'YES peak=100 bid=65 trail active(65>=75) stop=80 TRAIL'),
    ('yes',50,  50,  65, 33,  False, 'YES peak=50 bid=65 no trail (65<75) HOLD'),
    ('yes',50,  50,  30, 68,  True,  'YES bid=30 hard stop (30<=30) STOP'),
]

print(f'{\"Pass\"} {\"Exit\":<6} {\"Desc\":<55} {\"Reason\"}')
print('-'*100)
all_pass = True
for side, entry, peak, yes_bid, no_bid, expect, desc in tests:
    pos = make_pos(side, entry, peak)
    item = make_item(yes_bid, no_bid)
    sig = strategy_exit(item, pos)
    exited = sig is not None
    passed = exited == expect
    if not passed: all_pass = False
    mark = '✅' if passed else '❌'
    reason = sig.reason[:45] if sig else 'HOLD'
    print(f'{mark}  {str(exited):<6} {desc:<55} {reason}')
print()
print('All passed ✅' if all_pass else 'SOME FAILED ❌')
"
