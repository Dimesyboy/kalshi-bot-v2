from functools import reduce

legs     = scan_all_props()
moonshot = build_best_combo(legs)
monster  = build_highconf_combo(legs)

if moonshot:
    p = moonshot.expected_payout
    print(f'MOONSHOT: {len(moonshot.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f}')

if monster:
    p = monster.expected_payout
    print(f'MONSTER:  {len(monster.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f}')
" 2>&1 | grep -E "MOONSHOT|MONSTER|No"
python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
import re

legs     = scan_all_props()
moonshot = build_best_combo(legs)
monster  = build_highconf_combo(legs)

for label, candidate in [('MOONSHOT', moonshot), ('MONSTER', monster)]:
    if not candidate:
        continue
    p = candidate.expected_payout
    print(f'--- {label}: {len(candidate.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} ---')
    for l in candidate.legs:
        thr    = l.ticker.split('-')[-1]
        series = l.ticker.split('-')[0]
        stat   = {'KXNBAPTS':'pts','KXNBAREB':'reb','KXNBAAST':'ast','KXNBA3PT':'3s','KXNBASTL':'stl','KXNBABLK':'blk'}.get(series,'?')
        player = l.reasoning.split(' avg')[0]
        hr     = l.reasoning.split('hr=')[1].split(')')[0] if 'hr=' in l.reasoning else '?'
        edge   = round((l.confidence - l.implied_prob)*100, 1)
        print(f'  {player} {thr}+ {stat} | HR:{hr} edge:+{edge}c conf:{l.confidence:.2f}')
    print()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Dynamic|RFQ|Quote|No quote|EXECUTED|rejected|payout" | head -20
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '    # ── Price monitoring (5 min window) ───────────────────────────────\n    if not dry_run and legs:',
    '    # ── Price monitoring DISABLED ─────────────────────────────────────\n    if False and not dry_run and legs:'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Dynamic|RFQ|Quote|No quote|EXECUTED|rejected" | head -20
python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
legs = scan_all_props()
m = build_best_combo(legs)
h = build_highconf_combo(legs)
print(f'Moonshot: {len(m.legs)} legs' if m else 'No moonshot')
print(f'Monster: {len(h.legs)} legs' if h else 'No monster')
" 2>&1 | grep -E "Moonshot|Monster"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace('QUOTE_TIMEOUT_SECS = 15', 'QUOTE_TIMEOUT_SECS = 20')
c = c.replace('MAX_COMBO_LEGS       = 12', 'MAX_COMBO_LEGS       = 10')
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Dynamic|RFQ|Quote|No quote|EXECUTED|rejected" | head -20
grep "QUOTE_TIMEOUT" /root/kalshi-bot-v2/combo_scanner.py
sed -i 's/QUOTE_TIMEOUT_SECS    = 5/QUOTE_TIMEOUT_SECS    = 20/' /root/kalshi-bot-v2/combo_scanner.py
grep "QUOTE_TIMEOUT_SECS" /root/kalshi-bot-v2/combo_scanner.py | head -1
python combo_scanner.py
python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Quote|No quote|EXECUTED|rejected" | head -20
grep -n "def build_highconf_combo" /root/kalshi-bot-v2/combo_scanner.py
python3 -c "from combo_scanner import build_highconf_combo; print('OK')"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '    # ── HIGH CONFIDENCE ────────────────────────────────────────────────\n    highconf = build_highconf_combo(legs)',
    '    # ── HIGH CONFIDENCE ────────────────────────────────────────────────\n    from combo_scanner import build_highconf_combo as _bhc\n    highconf = _bhc(legs)'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py 2>&1 | grep -E "MOONSHOT|HIGH CONF|DRY RUN|No valid"
python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Quote|No quote|EXECUTED|rejected|payout" | head -20
python3 -c "
import requests, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

path = '/trade-api/v2/communications/rfqs'
r = requests.get(f'https://api.elections.kalshi.com{path}',
    headers=pss_headers('GET', path), timeout=8)
print(r.status_code)
import json
data = r.json()
rfqs = data.get('rfqs', [])
print(f'Open RFQs: {len(rfqs)}')
for rfq in rfqs[:3]:
    print(f'  {rfq.get(\"id\")} status={rfq.get(\"status\")} created={rfq.get(\"created_ts\",\"\")[:19]}')
" 2>&1 | grep -v DEBUG
python3 -c "
import requests, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

BASE = 'https://api.elections.kalshi.com'

# Get all open RFQs
path = '/trade-api/v2/communications/rfqs'
r = requests.get(f'{BASE}{path}', headers=pss_headers('GET', path), timeout=8)
rfqs = r.json().get('rfqs', [])
print(f'Cancelling {len(rfqs)} RFQs...')

cancelled = 0
for rfq in rfqs:
    rfq_id = rfq.get('id')
    cp = f'/trade-api/v2/communications/rfqs/{rfq_id}/cancel'
    r2 = requests.put(f'{BASE}{cp}', headers=pss_headers('PUT', cp), timeout=8)
    if r2.status_code in (200, 204):
        cancelled += 1
    time.sleep(0.1)

print(f'Cancelled {cancelled}/{len(rfqs)} RFQs')
" 2>&1 | grep -v DEBUG
python3 -c "
import requests, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

BASE = 'https://api.elections.kalshi.com'

# Try one RFQ with different methods
path = '/trade-api/v2/communications/rfqs'
r = requests.get(f'{BASE}{path}', headers=pss_headers('GET', path), timeout=8)
rfqs = r.json().get('rfqs', [])
rfq_id = rfqs[0]['id']
print(f'Testing RFQ: {rfq_id}')

for method in ['DELETE', 'PUT', 'POST']:
    cp = f'/trade-api/v2/communications/rfqs/{rfq_id}'
    if method == 'PUT':
        cp += '/cancel'
    fn = getattr(requests, method.lower())
    r2 = fn(f'{BASE}{cp}', headers=pss_headers(method, cp), timeout=8)
    print(f'{method}: {r2.status_code} {r2.text[:100]}')
" 2>&1 | grep -v DEBUG
python3 -c "
import requests, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts,
            'Content-Type': 'application/json'}

BASE = 'https://api.elections.kalshi.com'
path = '/trade-api/v2/communications/rfqs'
r = requests.get(f'{BASE}{path}', headers=pss_headers('GET', path), timeout=8)
rfqs = r.json().get('rfqs', [])
print(f'Cancelling {len(rfqs)} RFQs...')

cancelled = 0
for rfq in rfqs:
    rfq_id = rfq.get('id')
    cp = f'/trade-api/v2/communications/rfqs/{rfq_id}/cancel'
    r2 = requests.put(f'{BASE}{cp}', headers=pss_headers('PUT', cp), json={}, timeout=8)
    if r2.status_code in (200, 204):
        cancelled += 1
    time.sleep(0.1)

print(f'Cancelled {cancelled}/{len(rfqs)}')

# Verify
r3 = requests.get(f'{BASE}{path}', headers=pss_headers('GET', path), timeout=8)
print(f'Remaining open: {len(r3.json().get(\"rfqs\", []))}')
" 2>&1 | grep -v DEBUG
python3 -c "
import requests, base64, time, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

BASE = 'https://api.elections.kalshi.com'
path = '/trade-api/v2/communications/rfqs'
r = requests.get(f'{BASE}{path}', headers=pss_headers('GET', path), timeout=8)
rfqs = r.json().get('rfqs', [])
# Show first RFQ in full
print(json.dumps(rfqs[0], indent=2)[:400])
" 2>&1 | grep -v DEBUG
python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote" | head -10
python3 -c "
import requests, base64, time
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

BASE    = 'https://api.elections.kalshi.com'
rfq_id  = 'da115c59-2bf4-4a21-8173-77ff52f797c1'
user_id = config.KALSHI_USER_ID
path    = '/trade-api/v2/communications/quotes'
url     = f'{BASE}{path}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}'
r = requests.get(url, headers=pss_headers('GET', path), timeout=8)
print(f'Status: {r.status_code}')
import json
data = r.json()
quotes = data.get('quotes', [])
print(f'Quotes returned: {len(quotes)}')
if quotes:
    print(json.dumps(quotes[0], indent=2)[:300])
else:
    print('No quotes — market makers not responding')
    print(json.dumps(data, indent=2)[:200])
" 2>&1 | grep -v DEBUG
python3 -c "
import requests, base64, time, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts}

BASE    = 'https://api.elections.kalshi.com'
rfq_id  = 'da115c59-2bf4-4a21-8173-77ff52f797c1'
user_id = config.KALSHI_USER_ID
path    = '/trade-api/v2/communications/quotes'
url     = f'{BASE}{path}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}'
r = requests.get(url, headers=pss_headers('GET', path), timeout=8)
quotes = r.json().get('quotes', [])
for q in quotes:
    print(json.dumps(q, indent=2))
    print('---')
" 2>&1 | grep -v DEBUG
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) >= 0.05 and q.get(\'status\')==\'open\']
            if yes_q:
                quote = max(yes_q, key=lambda q: float(q.get(\'yes_bid_dollars\',0)))
                log.info(f"[Combo] Best quote: yes_bid={quote[\'yes_bid_dollars\']} contracts={quote.get(\'yes_contracts_fp\')}")
                break'''

new = '''            # Accept YES quotes OR NO quotes (convert no_bid to implied yes price)
            valid_q = []
            for q in qs:
                if q.get('status') != 'open':
                    continue
                yes_bid = float(q.get('yes_bid_dollars', 0) or 0)
                no_bid  = float(q.get('no_bid_dollars', 0) or 0)
                # If yes_bid available use it, else derive from no_bid
                if yes_bid >= 0.05:
                    q['_effective_yes'] = yes_bid
                    valid_q.append(q)
                elif no_bid > 0:
                    implied_yes = round(1.0 - no_bid, 4)
                    if implied_yes >= 0.05:
                        q['_effective_yes'] = implied_yes
                        valid_q.append(q)
            if valid_q:
                quote = max(valid_q, key=lambda q: q['_effective_yes'])
                eff   = quote['_effective_yes']
                log.info(f"[Combo] Best quote: effective_yes={eff:.4f} contracts={quote.get('no_contracts_fp') or quote.get('yes_contracts_fp')}")
                break'''

c = c.replace(old, new)

# Also fix the evaluation to use effective yes price
old2 = '''    yes_bid   = float(quote.get(\'yes_bid_dollars\', 0) or 0)
    contracts = float(quote.get(\'yes_contracts_fp\', 1) or 1)
    ev        = _evaluate_quote(candidate, yes_bid, stake_dollars)
    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")

    # Minimum payout check — reject if less than 10x
    min_payout = 10.0
    actual_payout = stake_dollars / yes_bid if yes_bid > 0 else 0'''

new2 = '''    yes_bid   = float(quote.get('_effective_yes', 0) or quote.get('yes_bid_dollars', 0) or 0)
    contracts = float(quote.get('no_contracts_fp') or quote.get('yes_contracts_fp', 1) or 1)
    ev        = _evaluate_quote(candidate, yes_bid, stake_dollars)
    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")

    # Minimum payout check — reject if less than 10x
    min_payout = 10.0
    actual_payout = stake_dollars / yes_bid if yes_bid > 0 else 0'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote|rejected|payout" | head -15
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace('    min_payout = 10.0', '    min_payout = 5.0')
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "Quote|EXECUTED|rejected|payout" | head -10
git add -A && git commit -m "fix: accept NO-side quotes, convert to implied yes price" && git push origin master
python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
import re

legs = scan_all_props()
print(f'Total legs: {len(legs)}')

games = {}
for l in legs:
    m = re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', l.ticker.split('-')[1])
    code = m.group(1) if m else '????'
    t1, t2 = code[:3], code[3:6]
    games.setdefault(f'{t1} vs {t2}', []).append(l)

for game, gl in sorted(games.items()):
    print(f'{game}: {len(gl)} legs')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
screen -r combo
cd /root/kalshi-bot-v2 && grep "from combo_scanner import build_highconf_combo" combo_scanner.py | head -3
source /root/kalshi-bot/bin/activate
python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote" | head -10
python combo_scanner.py
cd /root/kalshi-bot-v2 && python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote" | head -10
python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote" | head -10
cd /root/kalshi-bot-v2 && python3 combo_scanner.py --live 2>&1 | grep -E "RFQ|Quote|EXECUTED|No quote" | head -10
source /root/kalshi-bot/bin/activate
cd /root/kalshi-bot-v2 && echo "=== SYNTAX CHECK ===" && python3 -m py_compile bot.py && echo "bot.py OK" && python3 -m py_compile combo_scanner.py && echo "combo_scanner.py OK" && python3 -m py_compile data/nba_stats.py && echo "nba_stats.py OK" && python3 -m py_compile data/prop_scanner.py && echo "prop_scanner.py OK" && python3 -m py_compile data/player_stats.py && echo "player_stats.py OK" && python3 -m py_compile data/price_monitor.py && echo "price_monitor.py OK" && python3 -m py_compile data/persistent_cache.py && echo "persistent_cache.py OK" && python3 -m py_compile api_server.py && echo "api_server.py OK" && python3 -m py_compile telegram_bot.py && echo "telegram_bot.py OK"
echo "=== V2 BOT STATUS ===" && systemctl status kalshi-bot-v2 | grep -E "Active|PID" && echo "" && echo "=== SCREENS ===" && screen -ls && echo "" && echo "=== BALANCE ===" && python3 -c "from core.kalshi_client import get_balance; print(f'\${get_balance():.2f}')" && echo "" && echo "=== V2 BOT TRADES ===" && python3 -c "
import csv, os
f = 'data/trade_log.csv'
if os.path.exists(f):
    rows = list(csv.DictReader(open(f)))
    print(f'{len(rows)} trades placed')
else:
    print('No trade log yet')
" && echo "" && echo "=== COMBO TRADES ===" && python3 -c "
import json, os
f = 'data/combo_trades.json'
if os.path.exists(f):
    trades = json.load(open(f))
    good = [t for t in trades if float(t.get('quote',{}).get('_effective_yes', t.get('quote',{}).get('yes_bid_dollars',0)) or 0) >= 0.05]
    print(f'{len(trades)} total combos placed')
    print(f'{len(good)} at real prices')
else:
    print('No combos yet')
" && echo "" && echo "=== CACHE HEALTH ===" && python3 -c "from data.persistent_cache import cache_stats; cache_stats()" && echo "" && echo "=== PAPER TRADER ===" && python3 paper_trader.py --stats
screen -r paper-v2
tail -20 /root/kalshi-bot-v2/kalshi_bot.log | grep -E "signal|trade|LLM|gate|strategy|confidence"
grep -n "strategy\|evaluate\|signal\|confidence\|MIN_CONF\|threshold" /root/kalshi-bot-v2/strategies/nba.py | head -20
grep -n "score\|threshold\|MIN\|PASS\|FAIL\|gate" /root/kalshi-bot-v2/confidence/llm_gate.py | head -20
sed -n '25,45p' /root/kalshi-bot-v2/confidence/llm_gate.py
grep -n "NBA_CONF_GATE\|TENNIS_CONF_GATE\|MLB_CONF_GATE" /root/kalshi-bot-v2/core/config.py
tail -100 /root/kalshi-bot-v2/kalshi_bot.log | grep -E "LLM|conf|gate|signal|NBA|fade|momentum" | head -20
sed -n '74,145p' /root/kalshi-bot-v2/strategies/nba.py
python3 -c "
from data.espn import get_game_context
# Test with a live game ticker
result = get_game_context('KXNBAGAME-26MAR29GSWDEN')
print(result)
" 2>&1 | grep -v DEBUG
grep -n "get_game_context" /root/kalshi-bot-v2/strategies/nba.py | head -5
python3 -c "
from data.nba import get_game_context
result = get_game_context('KXNBAGAME-26MAR29GSWDEN')
print(result)
" 2>&1 | grep -v DEBUG
sed -n '1,60p' /root/kalshi-bot-v2/data/nba.py
grep -n "def get_game_context" /root/kalshi-bot-v2/data/nba.py
sed -n '81,140p' /root/kalshi-bot-v2/data/nba.py
python3 -c "
from core.kalshi_client import get_markets
markets = get_markets()
series = {}
for m in markets:
    s = m.ticker.split('-')[0]
    series[s] = series.get(s, 0) + 1
for k,v in sorted(series.items(), key=lambda x: -x[1])[:15]:
    print(f'  {k}: {v}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
from core.kalshi_client import _signed_get
data = _signed_get('/trade-api/v2/markets?limit=200&status=open')
markets = data.get('markets', [])
series = {}
for m in markets:
    s = m.get('ticker','').split('-')[0]
    series[s] = series.get(s, 0) + 1
for k,v in sorted(series.items(), key=lambda x: -x[1])[:15]:
    print(f'  {k}: {v}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
grep -n "series_ticker\|KXNBA\|fetch" /root/kalshi-bot-v2/core/kalshi_client.py | head -20
grep -n "KXNBA\|series\|fetch_markets\|get_markets" /root/kalshi-bot-v2/bot.py | head -20
python3 -c "
from core.kalshi_client import get_markets
markets = get_markets('KXNBAGAME', limit=100)
print(f'KXNBAGAME markets: {len(markets)}')
for m in markets[:5]:
    print(f'  {m.get(\"ticker\")} yes_bid={m.get(\"yes_bid_dollars\")}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
grep -E "Cycle [0-9]+ done.*[1-9] signal|NBAFade|NBAMomentum|is_live|fade_zone|spread_ok|volume_ok" /root/kalshi-bot-v2/kalshi_bot.log | head -20
sed -n '330,400p' /root/kalshi-bot-v2/bot.py
python3 -c "
from bot import fetch_markets
markets = fetch_markets()
print(f'Total markets: {len(markets)}')
sports = {}
for m in markets:
    s = str(m.sport)
    sports[s] = sports.get(s, 0) + 1
print('By sport:')
for k,v in sports.items():
    print(f'  {k}: {v}')

# Show a few NBA markets
nba = [m for m in markets if 'NBA' in str(m.sport)]
print(f'NBA markets: {len(nba)}')
for m in nba[:3]:
    print(f'  {m.ticker} sport={m.sport} yes_bid={m.yes_bid}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
from core.kalshi_client import _signed_get
# Check if any of tonight's game markets exist
games = ['GSWDEN', 'NYKOKC', 'HOUNOP', 'BOSKCHA', 'SACBKN', 'ORLTOR', 'PORWAS']
for g in games:
    try:
        data = _signed_get(f'/trade-api/v2/markets?series_ticker=KXNBAGAME&limit=10&status=open')
        markets = [m for m in data.get('markets',[]) if g in m.get('ticker','')]
        if markets:
            print(f'{g}: {markets[0][\"ticker\"]} yes_bid={markets[0][\"yes_bid_dollars\"]}')
        else:
            print(f'{g}: no market found')
    except Exception as e:
        print(f'{g}: error {e}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cat > /root/kalshi-bot-v2/strategies/prop_nba.py << 'PYEOF'
#!/usr/bin/env python3
"""
strategies/prop_nba.py
─────────────────────────────────────────────────────────────────────────────
NBA prop trading strategy for v2 bot.

Uses the same edge-based model as the combo scanner but trades
individual prop markets directly instead of parlays.

Entry logic:
    - Scan open NBA prop markets
    - Score each using hit rate + season avg + injury filter
    - Only trade legs with positive edge (model_conf > market_price)
    - Minimum edge threshold to ensure quality
    - One position per player per stat category
    - Exit via existing TP/SL/time exit manager
"""

import logging
from typing import Optional
from core.models import Market, TradeSignal, Sport, Side
from strategies.base import BaseStrategy, make_signal, calculate_contracts, calculate_ev
from core.config import config

log = logging.getLogger("kalshi_bot.strategy.prop_nba")

# ── Config ─────────────────────────────────────────────────────────────────
MIN_EDGE          = 0.08   # Minimum model_conf - market_price
MIN_HIT_RATE      = 0.80   # Minimum last-10 hit rate
MIN_MARKET_PRICE  = 0.55   # Skip legs below 55¢ (too risky)
MAX_MARKET_PRICE  = 0.90   # Skip legs above 90¢ (too little payout)
MIN_CONF          = 0.76   # Minimum model confidence

PROP_SERIES = [
    'KXNBAPTS', 'KXNBAREB', 'KXNBAAST',
    'KXNBA3PT', 'KXNBASTL', 'KXNBABLK'
]

STAT_MAP = {
    'KXNBAPTS': 'pts', 'KXNBAREB': 'reb', 'KXNBAAST': 'ast',
    'KXNBA3PT': 'threes', 'KXNBASTL': 'stl', 'KXNBABLK': 'blk'
}


class NBAPropStrategy(BaseStrategy):
    """
    Trades individual NBA prop markets with positive edge.
    Buys YES on props where our model confidence > market price.
    """

    name  = "prop_nba"
    sport = Sport.NBA

    def __init__(self):
        super().__init__()
        self._scanned_tickers = set()  # avoid re-evaluating same market

    def evaluate(
        self,
        market: Market,
        price_history: list,
        context: Optional[dict] = None,
    ) -> Optional[TradeSignal]:

        ticker = market.ticker
        series = ticker.split('-')[0]

        # Only handle prop markets
        if series not in PROP_SERIES:
            return None

        # Skip already evaluated
        if ticker in self._scanned_tickers:
            return None
        self._scanned_tickers.add(ticker)

        yes_bid = market.yes_bid
        if not (MIN_MARKET_PRICE <= yes_bid <= MAX_MARKET_PRICE):
            return None

        # Score this prop
        try:
            from data.nba_stats import score_prop_leg
            result = score_prop_leg(ticker)
        except Exception as e:
            log.debug(f"[PropNBA] Score failed {ticker}: {e}")
            return None

        conf = result.get('confidence', 0.0)
        if conf < MIN_CONF:
            return None

        # Check for injury
        if result.get('injured'):
            return None

        edge = conf - yes_bid
        if edge < MIN_EDGE:
            return None

        # Check hit rate
        reasoning = result.get('reason', '')
        hit_rate = 0.0
        if 'hr=' in reasoning:
            try:
                hr_str = reasoning.split('hr=')[1].split(')')[0].replace('%','')
                hit_rate = float(hr_str) / 100.0
            except Exception:
                pass

        if hit_rate < MIN_HIT_RATE and hit_rate > 0:
            return None

        # Build signal
        yes_price  = int(yes_bid * 100)
        balance    = context.get('balance', 20.0) if context else 20.0
        contracts  = calculate_contracts(balance, yes_price)
        ev         = calculate_ev(contracts, yes_price, conf)

        if ev <= 0:
            return None

        player = reasoning.split(' avg')[0] if ' avg' in reasoning else ticker
        stat   = STAT_MAP.get(series, 'stat')
        thr    = ticker.split('-')[-1]

        log.info(
            f"[PropNBA] {player} {thr}+ {stat} YES @ {yes_price}c "
            f"conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%}"
        )

        return make_signal(
            market        = market,
            side          = Side.YES,
            price_cents   = yes_price,
            contracts     = contracts,
            strategy_name = self.name,
            confidence    = conf,
            reason        = f"{player} {thr}+ {stat} | conf={conf:.2f} edge={edge:+.2f} hr={hit_rate:.0%}",
        )

    def reset_cycle(self):
        """Call at start of each bot cycle to allow re-evaluation."""
        self._scanned_tickers.clear()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/strategies/prop_nba.py) lines"
python3 -m py_compile strategies/prop_nba.py && echo "Syntax OK"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()

# Add import
old = 'from strategies.nba import NBAFade, NBAMomentumReversal'
new = 'from strategies.nba import NBAFade, NBAMomentumReversal\nfrom strategies.prop_nba import NBAPropStrategy'
c = c.replace(old, new)

# Add to strategies list
old2 = 'STRATEGIES = ['
new2 = 'STRATEGIES = [\n    NBAPropStrategy(),'
c = c.replace(old2, new2, 1)

# Add prop series to fetcher
old3 = 'NBA_SERIES    = ["KXNBAGAME"]'
new3 = 'NBA_SERIES    = ["KXNBAGAME", "KXNBAPTS", "KXNBAREB", "KXNBAAST", "KXNBA3PT", "KXNBASTL", "KXNBABLK"]'
c = c.replace(old3, new3)

# Reset prop strategy each cycle
old4 = '            markets = fetch_markets()'
new4 = '            markets = fetch_markets()\n            # Reset prop strategy dedup cache each cycle\n            for s in STRATEGIES:\n                if hasattr(s, "reset_cycle"): s.reset_cycle()'
c = c.replace(old4, new4)

open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

python3 -m py_compile bot.py && echo "Syntax OK"
python3 -c "
from bot import fetch_markets, STRATEGIES
from core.models import Sport

markets = fetch_markets()
nba_props = [m for m in markets if any(s in m.ticker for s in ['KXNBAPTS','KXNBAREB','KXNBAAST','KXNBA3PT','KXNBASTL','KXNBABLK'])]
print(f'Total markets: {len(markets)}')
print(f'NBA prop markets: {len(nba_props)}')
print(f'Strategies: {[s.name for s in STRATEGIES]}')

# Test prop strategy on a few markets
from strategies.prop_nba import NBAPropStrategy
strat = NBAPropStrategy()
signals = 0
for m in nba_props[:20]:
    sig = strat.evaluate(m, [], {'balance': 30.0})
    if sig:
        signals += 1
        print(f'  SIGNAL: {sig.reason}')
print(f'Signals from first 20 props: {signals}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats | grep -v Fetcher
systemctl restart kalshi-bot-v2
sleep 3
systemctl status kalshi-bot-v2 | grep Active
cd /root/kalshi-bot-v2 && python3 -c "
import json, os
from datetime import datetime

trades = json.load(open('data/combo_trades.json'))
print(f'Total combos placed: {len(trades)}')
print(f'Total spent: \${len(trades)*5:.2f}')
print()

for i, t in enumerate(trades):
    time    = t['time'][:16]
    legs    = len(t.get('legs', []))
    payout  = t.get('expected_payout', 0)
    mode    = t.get('mode', 'unknown')
    quote   = t.get('quote', {})
    bid     = float(quote.get('yes_bid_dollars') or quote.get('_effective_yes') or 0)
    actual_payout = 5.0 / bid if bid > 0 else 0
    print(f'{i+1}. {time} | {mode:10s} | {legs} legs | model={payout:.1f}x | actual={actual_payout:.1f}x | bid=\${bid:.4f}')
"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
positions = pa.get_positions()
combo_positions = [p for p in positions.market_positions 
                   if 'MULTIGAME' in p.ticker or 'CROSSCATEGORY' in p.ticker]
print(f'Open combo positions: {len(combo_positions)}')
for p in combo_positions:
    print(f'  {p.ticker[-40:]}')
    print(f'  position={p.position} cost=\${p.total_cost:.2f} value=\${p.market_value:.2f}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
positions = pa.get_positions()
print(dir(positions))
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
positions = pa.get_positions()
all_pos = positions.positions or []
combo_pos = [p for p in all_pos if 'MULTIGAME' in str(p) or 'CROSSCATEGORY' in str(p)]
print(f'Total positions: {len(all_pos)}')
print(f'Combo positions: {len(combo_pos)}')
for p in combo_pos[:5]:
    print(p)
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)

# Get portfolio history
history = pa.get_portfolio_history()
print(type(history))
print(dir(history))
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
# Check available methods
methods = [m for m in dir(pa) if not m.startswith('_')]
print(methods)
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)

# Get settlements — shows resolved positions
settlements = pa.get_settlements(limit=20)
items = settlements.settlements or []
print(f'Settlements: {len(items)}')
for s in items:
    ticker = getattr(s, 'market_ticker', '?')
    revenue = getattr(s, 'revenue', 0)
    pnl = getattr(s, 'profit_loss', getattr(s, 'pnl', '?'))
    settled = getattr(s, 'settled_time', getattr(s, 'created_time', '?'))
    if 'MULTIGAME' in str(ticker) or 'CROSSCATEGORY' in str(ticker):
        print(f'  COMBO: {str(ticker)[-35:]} revenue=\${revenue} pnl={pnl}')
    else:
        print(f'  {str(ticker)[-35:]} revenue=\${revenue}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
settlements = pa.get_settlements(limit=5)
items = settlements.settlements or []
for s in items:
    print(s)
    print('---')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
settlements = pa.get_settlements(limit=50)
items = settlements.settlements or []

total_revenue = 0
wins = 0
losses = 0
combos_won = []
combos_lost = []

for s in items:
    ticker  = s.ticker or '?'
    revenue = s.revenue or 0
    total_revenue += revenue
    is_combo = 'MULTIGAME' in ticker or 'CROSSCATEGORY' in ticker or 'MVECROSS' in ticker

    if revenue > 0:
        wins += 1
        if is_combo:
            combos_won.append((ticker[-30:], revenue))
        else:
            print(f'WIN:  {ticker[-35:]} +\${revenue/100:.2f}')
    else:
        losses += 1
        if is_combo:
            combos_lost.append(ticker[-30:])

print(f'Total settlements: {len(items)}')
print(f'Wins: {wins} | Losses: {losses}')
print(f'Total revenue: \${total_revenue/100:.2f}')
print(f'Combos won: {len(combos_won)}')
for t, r in combos_won:
    print(f'  {t} +\${r/100:.2f}')
print(f'Combos lost: {len(combos_lost)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
# Revenue is in cents based on what we see
# $99.68 total revenue from settlements
# We spent $35 on 7 logged combos but there are clearly more combos from earlier

# From settlements: 13 wins + 11 losses = 24 combo settlements
# Revenue: $99.68

# But we need to know cost basis
# Each combo cost somewhere between $0.001 and $5

revenue = 99.68
print(f'Total revenue from combos: \${revenue:.2f}')

# The manual combos you placed yourself
manual_combos = [
    ('4-leg', 2.20),
    ('13-leg', 10.00),
    ('10-leg', 2.97),  # 555 payout
    ('10-leg', 5.00),  # 70 payout
    ('31-leg', 5.97),
    ('24-leg', 4.98),
    ('10-leg', 9.91),
    ('7-leg', 2.81),
]
manual_spent = sum(c[1] for c in manual_combos)
print(f'Manual combos spent: \${manual_spent:.2f}')
print(f'Bot combos spent: \$35.00')
print(f'Total spent (est): \${manual_spent + 35:.2f}')
print(f'Net PNL (est): \${revenue - manual_spent - 35:.2f}')
print()
print(f'Big winner: \$25 combo — what was that?')
"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client, _signed_get

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
settlements = pa.get_settlements(limit=50)

for s in settlements.settlements or []:
    if (s.revenue or 0) >= 2000:  # $20+
        ticker = s.ticker
        print(f'Big winner: {ticker}')
        print(f'Revenue: \${(s.revenue or 0)/100:.2f}')
        print(f'Settled: {s.settled_time}')
        # Try to get market details
        try:
            data = _signed_get(f'/trade-api/v2/markets/{ticker}')
            m = data.get('market', {})
            print(f'Title: {m.get(\"title\",\"?\")}')
            print(f'Result: {m.get(\"result\",\"?\")}')
        except:
            pass
        print()
" 2>&1 | grep -v DEBUG | grep -v WARNING
cd /root/kalshi-bot-v2 && git add -A && git commit -m "feat: NBAPropStrategy live, combo PNL +\$20.84, system audit clean" && git push origin master
cat > /root/kalshi-bot-v2/data/pnl_report.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/pnl_report.py
─────────────────────────────────────────────────────────────────────────────
Comprehensive PNL report using Kalshi settlements API.
Covers combos, single props, and overall account performance.
"""

import logging
import json
import os
from datetime import datetime, timezone
from collections import defaultdict

log = logging.getLogger("kalshi_bot.pnl")


def get_full_pnl() -> dict:
    """
    Pull all settlements from Kalshi and compute comprehensive PNL.
    Returns structured report dict.
    """
    from core.kalshi_client import get_client
    import kalshi_python

    client = get_client()
    pa     = kalshi_python.PortfolioApi(api_client=client)

    # Fetch all settlements (paginate)
    all_settlements = []
    cursor = None
    while True:
        try:
            kwargs = {"limit": 100}
            if cursor:
                kwargs["cursor"] = cursor
            resp = pa.get_settlements(**kwargs)
            batch = resp.settlements or []
            all_settlements.extend(batch)
            cursor = resp.cursor
            if not cursor or len(batch) < 100:
                break
        except Exception as e:
            log.warning(f"Settlement fetch failed: {e}")
            break

    # Categorize
    combos   = []
    props    = []
    games    = []
    other    = []

    for s in all_settlements:
        ticker  = s.ticker or ''
        revenue = (s.revenue or 0) / 100.0  # convert cents to dollars
        settled = s.settled_time

        entry = {
            'ticker':   ticker,
            'revenue':  round(revenue, 2),
            'settled':  str(settled)[:16] if settled else '',
            'won':      revenue > 0,
        }

        if 'MULTIGAME' in ticker or 'CROSSCATEGORY' in ticker:
            combos.append(entry)
        elif any(s in ticker for s in ['KXNBAPTS','KXNBAREB','KXNBAAST',
                                        'KXNBA3PT','KXNBASTL','KXNBABLK']):
            props.append(entry)
        elif 'KXNBAGAME' in ticker or 'KXMLB' in ticker:
            games.append(entry)
        else:
            other.append(entry)

    def summarize(trades):
        if not trades:
            return {'n': 0, 'wins': 0, 'losses': 0, 'win_rate': 0,
                    'revenue': 0, 'spent': 0, 'pnl': 0}
        wins    = sum(1 for t in trades if t['won'])
        revenue = sum(t['revenue'] for t in trades)
        return {
            'n':        len(trades),
            'wins':     wins,
            'losses':   len(trades) - wins,
            'win_rate': round(wins / len(trades) * 100, 1),
            'revenue':  round(revenue, 2),
        }

    # Load combo cost basis from trade log
    combo_spent = 0.0
    combo_log   = "/root/kalshi-bot-v2/data/combo_trades.json"
    if os.path.exists(combo_log):
        logged = json.load(open(combo_log))
        combo_spent = len(logged) * 5.0  # $5 per bot combo

    combo_summary = summarize(combos)
    prop_summary  = summarize(props)
    game_summary  = summarize(games)

    # Best and worst trades
    all_trades = combos + props + games + other
    winners    = sorted([t for t in all_trades if t['won']],
                        key=lambda x: x['revenue'], reverse=True)
    losers     = sorted([t for t in all_trades if not t['won']],
                        key=lambda x: x['revenue'])

    total_revenue = sum(t['revenue'] for t in all_trades)

    return {
        'generated_at':  datetime.now(timezone.utc).isoformat()[:16],
        'total_trades':  len(all_trades),
        'total_revenue': round(total_revenue, 2),
        'combos':        combo_summary,
        'props':         prop_summary,
        'games':         game_summary,
        'top_winners':   winners[:3],
        'recent':        sorted(all_trades, key=lambda x: x['settled'],
                                reverse=True)[:5],
    }


def format_pnl_telegram(report: dict) -> str:
    """Format PNL report for Telegram."""
    lines = [
        f"📊 *PNL Report*",
        f"_{report['generated_at']} UTC_",
        f"",
        f"💰 *Total Revenue: ${report['total_revenue']:.2f}*",
        f"Total Settled: {report['total_trades']} trades",
        f"",
    ]

    c = report['combos']
    if c['n']:
        lines += [
            f"🎯 *Combos*",
            f"  {c['wins']}W / {c['losses']}L ({c['win_rate']}%) | Revenue: ${c['revenue']:.2f}",
            f"",
        ]

    p = report['props']
    if p['n']:
        lines += [
            f"🏀 *Props*",
            f"  {p['wins']}W / {p['losses']}L ({p['win_rate']}%) | Revenue: ${p['revenue']:.2f}",
            f"",
        ]

    g = report['games']
    if g['n']:
        lines += [
            f"🏆 *Game Lines*",
            f"  {g['wins']}W / {g['losses']}L ({g['win_rate']}%) | Revenue: ${g['revenue']:.2f}",
            f"",
        ]

    if report['top_winners']:
        lines.append(f"🥇 *Top Wins*")
        for w in report['top_winners']:
            lines.append(f"  +${w['revenue']:.2f} | {w['ticker'][-25:]}")

    return "\n".join(lines)
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/pnl_report.py) lines"
python3 -c "
from data.pnl_report import get_full_pnl, format_pnl_telegram
report = get_full_pnl()
print(format_pnl_telegram(report))
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''    elif data == "stats":
        try:
            import csv
            from collections import defaultdict

            paper_file = "/root/kalshi-bot-v2/data/paper_trades.csv"
            v1_file    = "/root/trade_log.csv"
            lines      = ["📊 *Trading Stats*\n"]

            # V2 live stats
            v2_log = "/root/kalshi-bot-v2/data/trade_log.csv"
            if os.path.exists(v2_log):
                rows = list(csv.DictReader(open(v2_log)))
                total_pnl = sum(float(r.get('pnl',0) or 0) for r in rows)
                lines.append(f"*V2 Bot*")
                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\\n")
            else:
                lines.append("*V2 Bot*\\nNo live trades yet\\n")

            # V2 paper stats
            if os.path.exists(paper_file):
                rows     = list(csv.DictReader(open(paper_file)))
                resolved = [r for r in rows if r.get('resolved','') not in ('','no')]
                if resolved:
                    wins    = sum(1 for r in resolved if float(r.get('hyp_pnl',0) or 0) > 0)
                    pnl     = sum(float(r.get('hyp_pnl',0) or 0) for r in resolved)
                    wr      = wins/len(resolved)*100
                    lines.append(f"*V2 Paper*")
                    lines.append(f"Resolved: {len(resolved)} | WR={wr:.0f}% | PNL=${pnl:+.2f}")
                else:
                    lines.append("*V2 Paper*\\nNo resolved trades yet")

            # Combo stats
            combo_file = "/root/kalshi-bot-v2/data/combo_trades.json"
            if os.path.exists(combo_file):
                import json as _json
                combos = _json.load(open(combo_file))
                spent  = len(combos) * 5.0
                lines.append(f"\\n*Combos*\\nPlaced: {len(combos)} | Spent: ${spent:.0f}")

            await query.edit_message_text(
                "\\n".join(lines),
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
            )'''

new = '''    elif data == "stats":
        await query.edit_message_text("📊 Loading PNL report...")
        try:
            from data.pnl_report import get_full_pnl, format_pnl_telegram
            report = get_full_pnl()
            msg    = format_pnl_telegram(report)
            await query.edit_message_text(
                msg,
                parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("🔄 Refresh", callback_data="stats"),
                    InlineKeyboardButton("🔙 Menu",    callback_data="menu")
                ]])
            )'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/api_server.py', 'r')
c = f.read()
f.close()

old = '''@app.get("/api/stats")
def get_stats(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    import csv
    from collections import defaultdict

    result = {}

    # Paper trades v2
    paper_file = "/root/kalshi-bot-v2/data/paper_trades.csv"
    if os.path.exists(paper_file):
        rows     = list(csv.DictReader(open(paper_file)))
        resolved = [r for r in rows if r.get('resolved','') not in ('','no')]
        wins     = sum(1 for r in resolved if float(r.get('hyp_pnl',0) or 0) > 0)
        pnl      = sum(float(r.get('hyp_pnl',0) or 0) for r in resolved)
        result["paper"] = {
            "total":    len(rows),
            "resolved": len(resolved),
            "wins":     wins,
            "win_rate": round(wins/len(resolved)*100, 1) if resolved else 0,
            "pnl":      round(pnl, 2)
        }

    # Combo stats
    combo_file = "/root/kalshi-bot-v2/data/combo_trades.json"
    if os.path.exists(combo_file):
        combos = json.load(open(combo_file))
        result["combos"] = {
            "total":  len(combos),
            "spent":  len(combos) * 5.0,
        }

    return result'''

new = '''@app.get("/api/stats")
def get_stats(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from data.pnl_report import get_full_pnl
        return get_full_pnl()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/api_server.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/app/index.html', 'r')
c = f.read()
f.close()

old = '''async function loadStats() {
  try {
    const data = await api('/api/stats');
    let html = '';
    if (data.paper) {
      const p = data.paper;
      html += `<div class="card">
        <div class="card-header">
          <span class="card-title">V2 Paper Trader</span>
          <span class="badge ${p.pnl >= 0 ? 'badge-green' : 'badge-red'}">
            $${p.pnl >= 0 ? '+' : ''}${p.pnl}
          </span>
        </div>
        <div class="leg"><span class="leg-name">Win Rate</span><span class="leg-conf">${p.win_rate}%</span></div>
        <div class="leg"><span class="leg-name">Resolved</span><span class="leg-conf">${p.resolved}/${p.total}</span></div>
      </div>`;
    }
    if (data.combos) {
      html += `<div class="card">
        <div class="card-header">
          <span class="card-title">Combo Trades</span>
          <span class="badge badge-purple">${data.combos.total} placed</span>
        </div>
        <div class="leg"><span class="leg-name">Total Spent</span><span class="leg-conf">$${data.combos.spent}</span></div>
      </div>`;
    }
    document.getElementById('stats-content').innerHTML = html || '<div class="error">No stats yet</div>';
  } catch(e) {
    document.getElementById('stats-content').innerHTML =
      '<div class="error">Error loading stats</div>';
  }
}'''

new = '''async function loadStats() {
  try {
    const data = await api('/api/stats');
    let html = '';

    // Total revenue banner
    const rev = data.total_revenue || 0;
    html += `<div class="balance-card" style="margin:0 0 12px">
      <div class="label">Total Revenue</div>
      <div class="amount">$${rev.toFixed(2)}</div>
      <div class="sub">${data.total_trades || 0} settled trades</div>
    </div>`;

    // Combos
    const c = data.combos;
    if (c && c.n) {
      const pnl = c.revenue;
      html += `<div class="card">
        <div class="card-header">
          <span class="card-title">🎯 Combos</span>
          <span class="badge ${pnl >= 0 ? 'badge-green' : 'badge-red'}">$${pnl.toFixed(2)}</span>
        </div>
        <div class="leg"><span class="leg-name">Record</span><span class="leg-conf">${c.wins}W / ${c.losses}L</span></div>
        <div class="leg"><span class="leg-name">Win Rate</span><span class="leg-conf">${c.win_rate}%</span></div>
      </div>`;
    }

    // Props
    const p = data.props;
    if (p && p.n) {
      html += `<div class="card">
        <div class="card-header">
          <span class="card-title">🏀 Props</span>
          <span class="badge ${p.revenue >= 0 ? 'badge-green' : 'badge-red'}">$${p.revenue.toFixed(2)}</span>
        </div>
        <div class="leg"><span class="leg-name">Record</span><span class="leg-conf">${p.wins}W / ${p.losses}L</span></div>
        <div class="leg"><span class="leg-name">Win Rate</span><span class="leg-conf">${p.win_rate}%</span></div>
      </div>`;
    }

    // Game lines
    const g = data.games;
    if (g && g.n) {
      html += `<div class="card">
        <div class="card-header">
          <span class="card-title">🏆 Game Lines</span>
          <span class="badge ${g.revenue >= 0 ? 'badge-green' : 'badge-red'}">$${g.revenue.toFixed(2)}</span>
        </div>
        <div class="leg"><span class="leg-name">Record</span><span class="leg-conf">${g.wins}W / ${g.losses}L</span></div>
        <div class="leg"><span class="leg-name">Win Rate</span><span class="leg-conf">${g.win_rate}%</span></div>
      </div>`;
    }

    // Top winners
    if (data.top_winners && data.top_winners.length) {
      html += `<div class="card"><div class="card-header"><span class="card-title">🥇 Top Wins</span></div>`;
      data.top_winners.forEach(w => {
        html += `<div class="leg"><span class="leg-name">${w.ticker.slice(-20)}</span><span class="leg-conf">+$${w.revenue.toFixed(2)}</span></div>`;
      });
      html += `</div>`;
    }

    document.getElementById('stats-content').innerHTML = html || '<div class="error">No stats yet</div>';
  } catch(e) {
    document.getElementById('stats-content').innerHTML =
      '<div class="error">Error: ' + e.message + '</div>';
  }
}'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/app/index.html', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
screen -S api -X quit  
screen -S api bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && BOT_API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d"=" -f2) python3 api_server.py; exec bash'
git add -A && git commit -m "feat: full PNL report from settlements API — Telegram + web app" && git push origin master
cat > /root/kalshi-bot-v2/data/model_audit.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/model_audit.py
─────────────────────────────────────────────────────────────────────────────
Nightly model audit system.

Compares model predictions vs actual outcomes to identify:
- Which stat types the model over/underestimates
- Which confidence ranges are actually profitable
- Which players the model is consistently wrong on
- Which edge thresholds work
- Recommendations for confidence model adjustments

Runs nightly, outputs JSON report + Telegram-formatted summary.
Stores audit history in SQLite for trend tracking.
"""

import logging
import json
import os
import sqlite3
import time
import requests as req
from datetime import datetime, timezone, timedelta
from collections import defaultdict

log = logging.getLogger("kalshi_bot.model_audit")

DB_PATH    = "/root/kalshi-bot-v2/data/cache.db"
AUDIT_PATH = "/root/kalshi-bot-v2/data/audit_history.json"

STAT_LABELS = {
    'KXNBAPTS': 'points', 'KXNBAREB': 'rebounds',
    'KXNBAAST': 'assists', 'KXNBA3PT': 'threes',
    'KXNBASTL': 'steals',  'KXNBABLK': 'blocks',
}


# ── Data collection ────────────────────────────────────────────────────────

def get_recent_prop_settlements(days: int = 7) -> list[dict]:
    """
    Get settled prop trades from Kalshi with their outcomes.
    Cross-references with our confidence scores from cache.
    """
    from core.kalshi_client import get_client
    import kalshi_python

    client = get_client()
    pa     = kalshi_python.PortfolioApi(api_client=client)

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    trades = []
    cursor = None

    while True:
        try:
            kwargs = {"limit": 100}
            if cursor:
                kwargs["cursor"] = cursor
            resp  = pa.get_settlements(**kwargs)
            batch = resp.settlements or []

            for s in batch:
                settled = s.settled_time
                if settled and settled < cutoff:
                    cursor = None
                    break

                ticker  = s.ticker or ''
                series  = ticker.split('-')[0]

                if series not in STAT_LABELS:
                    continue

                revenue = (s.revenue or 0) / 100.0
                won     = revenue > 0

                # Get our model's confidence score for this ticker
                model_conf, market_price, edge, player, hit_rate = _get_model_data(ticker)

                trades.append({
                    'ticker':       ticker,
                    'series':       series,
                    'stat':         STAT_LABELS.get(series, '?'),
                    'player':       player,
                    'revenue':      round(revenue, 2),
                    'won':          won,
                    'model_conf':   model_conf,
                    'market_price': market_price,
                    'edge':         edge,
                    'hit_rate':     hit_rate,
                    'settled':      str(settled)[:10],
                })

            cursor = resp.cursor
            if not cursor or not batch:
                break

        except Exception as e:
            log.warning(f"Settlement fetch error: {e}")
            break

    return trades


def _get_model_data(ticker: str) -> tuple:
    """
    Try to score the ticker with current model to get confidence.
    Returns (model_conf, market_price, edge, player_name, hit_rate)
    """
    try:
        from data.nba_stats import score_prop_leg
        from core.kalshi_client import _signed_get

        result = score_prop_leg(ticker)
        conf   = result.get('confidence', 0)
        player = result.get('player_name', ticker.split('-')[2][:10] if len(ticker.split('-')) > 2 else '?')
        reason = result.get('reason', '')

        # Extract hit rate
        hit_rate = 0.0
        if 'hr=' in reason:
            try:
                hr_str   = reason.split('hr=')[1].split(')')[0].replace('%','')
                hit_rate = float(hr_str) / 100.0
            except Exception:
                pass

        # Get market price
        try:
            data  = _signed_get(f'/trade-api/v2/markets/{ticker}')
            price = float(data.get('market',{}).get('yes_bid_dollars', 0) or 0)
        except Exception:
            price = 0.0

        edge = round(conf - price, 3)
        return conf, price, edge, player, hit_rate

    except Exception:
        return 0.0, 0.0, 0.0, '?', 0.0


# ── Analysis ───────────────────────────────────────────────────────────────

def analyze_trades(trades: list[dict]) -> dict:
    """
    Analyze trade outcomes vs model predictions.
    Returns comprehensive audit report.
    """
    if not trades:
        return {'error': 'No trades to analyze'}

    # By stat type
    by_stat = defaultdict(lambda: {'n':0,'wins':0,'revenue':0.0,
                                    'model_conf_sum':0.0,'hit_rate_sum':0.0})
    for t in trades:
        s = by_stat[t['stat']]
        s['n']              += 1
        s['wins']           += int(t['won'])
        s['revenue']        += t['revenue']
        s['model_conf_sum'] += t['model_conf']
        s['hit_rate_sum']   += t['hit_rate']

    stat_report = {}
    for stat, d in by_stat.items():
        actual_wr  = d['wins'] / d['n'] * 100 if d['n'] else 0
        avg_conf   = d['model_conf_sum'] / d['n'] * 100 if d['n'] else 0
        avg_hr     = d['hit_rate_sum'] / d['n'] * 100 if d['n'] else 0
        calibration = actual_wr - avg_conf  # positive = model underestimates
        stat_report[stat] = {
            'n':           d['n'],
            'wins':        d['wins'],
            'actual_wr':   round(actual_wr, 1),
            'avg_model_conf': round(avg_conf, 1),
            'avg_hit_rate':   round(avg_hr, 1),
            'calibration': round(calibration, 1),  # + means model is conservative
            'revenue':     round(d['revenue'], 2),
        }

    # By edge bucket
    edge_buckets = {
        'negative':  {'range': (-99, 0),   'n':0,'wins':0},
        'small':     {'range': (0, 0.05),  'n':0,'wins':0},
        'medium':    {'range': (0.05,0.15),'n':0,'wins':0},
        'large':     {'range': (0.15,0.25),'n':0,'wins':0},
        'huge':      {'range': (0.25,99),  'n':0,'wins':0},
    }
    for t in trades:
        edge = t['edge']
        for name, b in edge_buckets.items():
            lo, hi = b['range']
            if lo <= edge < hi:
                b['n']    += 1
                b['wins'] += int(t['won'])
                break

    edge_report = {}
    for name, b in edge_buckets.items():
        wr = b['wins'] / b['n'] * 100 if b['n'] else 0
        edge_report[name] = {
            'n':      b['n'],
            'wins':   b['wins'],
            'win_rate': round(wr, 1),
        }

    # By confidence bucket
    conf_buckets = defaultdict(lambda: {'n':0,'wins':0})
    for t in trades:
        conf = t['model_conf']
        if conf >= 0.90:   bucket = '90-100%'
        elif conf >= 0.80: bucket = '80-90%'
        elif conf >= 0.70: bucket = '70-80%'
        elif conf >= 0.60: bucket = '60-70%'
        else:              bucket = '<60%'
        conf_buckets[bucket]['n']    += 1
        conf_buckets[bucket]['wins'] += int(t['won'])

    conf_report = {}
    for bucket, d in sorted(conf_buckets.items(), reverse=True):
        wr = d['wins'] / d['n'] * 100 if d['n'] else 0
        conf_report[bucket] = {
            'n':        d['n'],
            'wins':     d['wins'],
            'win_rate': round(wr, 1),
        }

    # By player (min 3 trades)
    by_player = defaultdict(lambda: {'n':0,'wins':0,'model_conf_sum':0.0})
    for t in trades:
        p = by_player[t['player']]
        p['n']              += 1
        p['wins']           += int(t['won'])
        p['model_conf_sum'] += t['model_conf']

    player_report = {}
    for player, d in by_player.items():
        if d['n'] < 3 or player == '?':
            continue
        actual_wr = d['wins'] / d['n'] * 100
        avg_conf  = d['model_conf_sum'] / d['n'] * 100
        diff      = actual_wr - avg_conf
        player_report[player] = {
            'n':        d['n'],
            'wins':     d['wins'],
            'actual_wr':   round(actual_wr, 1),
            'model_conf':  round(avg_conf, 1),
            'calibration': round(diff, 1),
        }

    # Generate recommendations
    recommendations = _generate_recommendations(stat_report, edge_report,
                                                 conf_report, player_report)

    return {
        'generated_at':  datetime.now(timezone.utc).isoformat()[:16],
        'trade_count':   len(trades),
        'date_range':    f"Last 7 days",
        'by_stat':       stat_report,
        'by_edge':       edge_report,
        'by_confidence': conf_report,
        'by_player':     dict(sorted(player_report.items(),
                             key=lambda x: abs(x[1]['calibration']),
                             reverse=True)[:10]),
        'recommendations': recommendations,
    }


def _generate_recommendations(stat_r, edge_r, conf_r, player_r) -> list[str]:
    """Generate specific actionable recommendations."""
    recs = []

    # Stat calibration
    for stat, d in stat_r.items():
        cal = d['calibration']
        if d['n'] >= 5:
            if cal < -15:
                recs.append(f"❌ {stat}: Model overestimates by {abs(cal):.0f}% "
                           f"(model {d['avg_model_conf']}% vs actual {d['actual_wr']}%) "
                           f"— reduce {stat} confidence by 10-15%")
            elif cal > 15:
                recs.append(f"✅ {stat}: Model underestimates by {cal:.0f}% "
                           f"— consider lowering {stat} edge threshold")

    # Edge bucket analysis
    for bucket, d in edge_r.items():
        if d['n'] >= 5:
            if bucket == 'negative' and d['win_rate'] > 50:
                recs.append(f"⚠️ Negative edge trades winning {d['win_rate']}% "
                           f"— edge calculation may need recalibration")
            if bucket in ('large', 'huge') and d['win_rate'] < 40:
                recs.append(f"⚠️ High edge trades ({bucket}) only winning {d['win_rate']}% "
                           f"— market may be smarter than model thinks")

    # Confidence calibration
    for bucket, d in conf_r.items():
        if d['n'] >= 5:
            conf_val = float(bucket.split('-')[0].replace('%','').replace('<',''))
            if d['win_rate'] < conf_val - 20:
                recs.append(f"❌ {bucket} confidence: only {d['win_rate']}% actual win rate "
                           f"— model is overconfident in this range")

    # Player-specific
    for player, d in list(player_r.items())[:3]:
        cal = d['calibration']
        if abs(cal) > 20 and d['n'] >= 3:
            direction = "overestimates" if cal < 0 else "underestimates"
            recs.append(f"🏀 {player}: Model {direction} by {abs(cal):.0f}% "
                       f"({d['model_conf']}% model vs {d['actual_wr']}% actual)")

    if not recs:
        recs.append("✅ Model appears well calibrated — no major issues detected")

    return recs


# ── Formatting ─────────────────────────────────────────────────────────────

def format_audit_telegram(report: dict) -> str:
    """Format audit report for Telegram."""
    if 'error' in report:
        return f"❌ Audit error: {report['error']}"

    lines = [
        f"🔬 *Model Audit Report*",
        f"_{report['generated_at']} UTC · {report['trade_count']} trades_",
        f"",
    ]

    # Stat performance
    lines.append("*By Stat Type:*")
    for stat, d in sorted(report['by_stat'].items(),
                          key=lambda x: x[1]['actual_wr'], reverse=True):
        if d['n'] < 3:
            continue
        cal_str = f"{d['calibration']:+.0f}%" if d['calibration'] else ""
        flag = "✅" if abs(d['calibration']) < 10 else "⚠️" if abs(d['calibration']) < 20 else "❌"
        lines.append(f"{flag} {stat}: {d['actual_wr']}% WR "
                    f"(model {d['avg_model_conf']}%) {cal_str}")
    lines.append("")

    # Edge buckets
    lines.append("*By Edge Size:*")
    for bucket, d in report['by_edge'].items():
        if d['n'] < 2:
            continue
        lines.append(f"  {bucket}: {d['win_rate']}% WR ({d['n']} trades)")
    lines.append("")

    # Recommendations
    lines.append("*Recommendations:*")
    for rec in report['recommendations'][:5]:
        lines.append(rec)

    return "\n".join(lines)


def save_audit(report: dict):
    """Save audit to history file."""
    history = []
    if os.path.exists(AUDIT_PATH):
        try:
            history = json.load(open(AUDIT_PATH))
        except Exception:
            pass
    history.append(report)
    history = history[-30:]  # Keep last 30 audits
    json.dump(history, open(AUDIT_PATH, 'w'), indent=2)


def run_audit(days: int = 7) -> dict:
    """Main entry point — run full audit."""
    log.info("[Audit] Starting model audit...")
    trades = get_recent_prop_settlements(days)
    log.info(f"[Audit] Analyzing {len(trades)} trades")
    report = analyze_trades(trades)
    save_audit(report)
    log.info("[Audit] Done")
    return report


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    report = run_audit()
    print(format_audit_telegram(report))
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/model_audit.py) lines"
python3 -m py_compile data/model_audit.py && echo "Syntax OK"
cd /root/kalshi-bot-v2 && python3 data/model_audit.py 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && python3 -m data.model_audit 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/model_audit.py', 'r')
c = f.read()
f.close()

old = '''            for s in batch:
                settled = s.settled_time
                if settled and settled < cutoff:
                    cursor = None
                    break

                ticker  = s.ticker or ''
                series  = ticker.split('-')[0]

                if series not in STAT_LABELS:
                    continue'''

new = '''            for s in batch:
                settled = s.settled_time
                ticker  = s.ticker or ''
                series  = ticker.split('-')[0]

                if series not in STAT_LABELS:
                    continue

                # Skip if older than cutoff
                if settled and settled < cutoff:
                    continue'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/model_audit.py', 'w').write(c)
print("Done")
PYEOF

python3 -m data.model_audit 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from core.kalshi_client import get_client
import kalshi_python

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
resp = pa.get_settlements(limit=100)
items = resp.settlements or []
print(f'Total settlements: {len(items)}')

series_count = {}
for s in items:
    ticker = s.ticker or ''
    series = ticker.split('-')[0]
    series_count[series] = series_count.get(series, 0) + 1

for k,v in sorted(series_count.items(), key=lambda x: -x[1])[:15]:
    print(f'  {k}: {v}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/model_audit.py', 'r')
c = f.read()
f.close()

old = '''                if series not in STAT_LABELS:
                    continue'''

new = '''                # Include combos and game lines too
                is_prop  = series in STAT_LABELS
                is_combo = 'MULTIGAME' in ticker or 'CROSSCATEGORY' in ticker
                is_game  = series in ('KXNBAGAME','KXNBASPREAD','KXMLBGAME','KXMLBSPREAD')

                if not (is_prop or is_combo or is_game):
                    continue

                category = 'prop' if is_prop else 'combo' if is_combo else 'game'
                stat     = STAT_LABELS.get(series, category)'''

c = c.replace(old, new)

# Also fix the trade dict to include category
old2 = '''                trades.append({
                    'ticker':       ticker,
                    'series':       series,
                    'stat':         STAT_LABELS.get(series, '?'),'''

new2 = '''                trades.append({
                    'ticker':       ticker,
                    'series':       series,
                    'stat':         stat,
                    'category':     category,'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/data/model_audit.py', 'w').write(c)
print("Done")
PYEOF

python3 -m data.model_audit 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

# Add audit button to menu
old = '''        [InlineKeyboardButton("🔄 Refresh",     callback_data="menu")],'''
new = '''        [InlineKeyboardButton("🔬 Model Audit",  callback_data="audit"),
         InlineKeyboardButton("🔄 Refresh",     callback_data="menu")],'''
c = c.replace(old, new)

# Add audit handler
old2 = '''    elif data == "stats":'''
new2 = '''    elif data == "audit":
        await query.edit_message_text("🔬 Running model audit...")
        try:
            from data.model_audit import run_audit, format_audit_telegram
            report = run_audit(days=7)
            msg    = format_audit_telegram(report)
            await query.edit_message_text(
                msg, parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("🔄 Refresh", callback_data="audit"),
                    InlineKeyboardButton("🔙 Menu",    callback_data="menu")
                ]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ Audit error: {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "stats":'''
c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scheduler.py', 'r')
c = f.read()
f.close()

old = '''def main():
    log.info("Combo Scheduler starting")
    warm_cache()'''

new = '''def run_nightly_audit():
    """Run model audit and send results to Telegram."""
    try:
        from data.model_audit import run_audit, format_audit_telegram
        from telegram_bot import send_telegram
        log.info("Running nightly model audit...")
        report = run_audit(days=7)
        msg    = format_audit_telegram(report)
        # Send via Telegram
        from core.config import config
        import requests
        url = f"https://api.telegram.org/bot{config.TELEGRAM_BOT_TOKEN}/sendMessage"
        requests.post(url, json={
            "chat_id":    config.TELEGRAM_CHAT_ID,
            "text":       msg,
            "parse_mode": "Markdown"
        }, timeout=8)
        log.info("Nightly audit sent to Telegram")
    except Exception as e:
        log.warning(f"Nightly audit failed: {e}")


def main():
    log.info("Combo Scheduler starting")
    warm_cache()
    run_nightly_audit()'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scheduler.py', 'w').write(c)
print("Done")
PYEOF

# Restart tgbot with new audit button
screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
git add -A && git commit -m "feat: model audit system — nightly calibration reports, Telegram button" && git push origin master
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''    elif data == "positions":
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
                    "📋 No open positions",
                    reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
                )
        except Exception as e:
            await query.edit_message_text(f"❌ {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))'''

new = '''    elif data == "positions":
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

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
