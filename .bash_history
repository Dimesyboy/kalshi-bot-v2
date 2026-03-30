            player = l.reasoning.split(' avg')[0]
            price  = int(l.implied_prob * 100)
            hr     = l.reasoning.split('hr=')[1].split(')')[0] if 'hr=' in l.reasoning else '?'
            print(f'  {player} {thr}+ {stat} @ {price}c  HR:{hr} conf:{l.confidence:.2f}')
        print()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && python3 << 'PYEOF'
f = open('telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''        [InlineKeyboardButton("🎯 Best Parlay", callback_data="parlay"),
         InlineKeyboardButton("📊 Stats",       callback_data="stats")],'''

new = '''        [InlineKeyboardButton("🎯 Moonshot",    callback_data="parlay"),
         InlineKeyboardButton("💪 Monster",     callback_data="highconf")],
        [InlineKeyboardButton("📊 Stats",       callback_data="stats"),
         InlineKeyboardButton("💵 Balance",     callback_data="balance")],'''

c = c.replace(old, new)

# Remove balance from second row since it moved up
old2 = '''        [InlineKeyboardButton("💵 Balance",     callback_data="balance"),
         InlineKeyboardButton("📋 Positions",   callback_data="positions")],'''
new2 = '''        [InlineKeyboardButton("📋 Positions",   callback_data="positions"),
         InlineKeyboardButton("⚙️ Settings",    callback_data="settings")],'''
c = c.replace(old2, new2)

old3 = '''        [InlineKeyboardButton("⚙️ Settings",    callback_data="settings"),
         InlineKeyboardButton("🔄 Refresh",     callback_data="menu")],'''
new3 = '''        [InlineKeyboardButton("🔄 Refresh",     callback_data="menu")],'''
c = c.replace(old3, new3)

# Add highconf handler
old4 = '''    elif data == "stats":'''
new4 = '''    elif data == "highconf":
        await query.edit_message_text("🔍 Finding monster combo...")
        try:
            from combo_scanner import scan_all_props, build_highconf_combo
            legs      = scan_all_props()
            candidate = build_highconf_combo(legs)
            if not candidate:
                await query.edit_message_text(
                    "❌ No high confidence combo right now.",
                    reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]])
                )
                return
            await query.edit_message_text(f"✅ Found {len(candidate.legs)}-leg monster — analysing...")
            legs_with_reasons = [(leg, explain_leg(leg)) for leg in candidate.legs]
            msg = format_parlay(candidate, legs_with_reasons)
            await query.edit_message_text(
                msg, parse_mode="Markdown",
                reply_markup=InlineKeyboardMarkup([[
                    InlineKeyboardButton("🔄 Rescan", callback_data="highconf"),
                    InlineKeyboardButton("🔙 Menu",   callback_data="menu")
                ]])
            )
        except Exception as e:
            await query.edit_message_text(f"❌ Error: {str(e)[:100]}",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Menu", callback_data="menu")]]))

    elif data == "stats":'''

c = c.replace(old4, new4)
open('telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

git add -A && git commit -m "feat: monster combo button on TG, dual combo modes live" && git push origin master
screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
screen -r tgbot
cd /root/kalshi-bot-v2
python3 << 'PYEOF'
f = open('bot.py', 'r')
c = f.read()
f.close()
# Disable cycle reports entirely
c = c.replace(
    'if cycle % 50 == 0:',
    'if False and cycle % 50 == 0:  # disabled'
)
open('bot.py', 'w').write(c)
print("Done")
PYEOF

systemctl restart kalshi-bot-v2
systemctl restart kalshi-bot-v2 && sleep 3 && systemctl status kalshi-bot-v2 | grep Active
cd /root/kalshi-bot-v2 && python3 << 'PYEOF'
f = open('bot.py', 'r')
c = f.read()
f.close()
c = c.replace(
    'send_startup(balance',
    '# send_startup(balance'
)
open('bot.py', 'w').write(c)
print("Done")
PYEOF

git add -A && git commit -m "fix: disable cycle reports and startup spam in Telegram" && git push origin master
systemctl restart kalshi-bot-v2
cd /root/kalshi-bot-v2 && python3 << 'PYEOF'
f = open('telegram_bot.py', 'r')
c = f.read()
f.close()

# Add timeout to scan calls
old = '''    elif data == "parlay":
        await query.edit_message_text("🔍 Scanning props... give me a sec")
        try:
            from combo_scanner import scan_all_props, build_best_combo
            legs      = scan_all_props()
            candidate = build_best_combo(legs)'''

new = '''    elif data == "parlay":
        await query.edit_message_text("🔍 Scanning props... (~10s)")
        try:
            import asyncio
            from combo_scanner import scan_all_props, build_best_combo
            legs      = await asyncio.get_event_loop().run_in_executor(None, scan_all_props)
            candidate = build_best_combo(legs)'''

c = c.replace(old, new)

old2 = '''    elif data == "highconf":
        await query.edit_message_text("🔍 Finding monster combo...")
        try:
            from combo_scanner import scan_all_props, build_highconf_combo
            legs      = scan_all_props()
            candidate = build_highconf_combo(legs)'''

new2 = '''    elif data == "highconf":
        await query.edit_message_text("💪 Building monster combo... (~10s)")
        try:
            import asyncio
            from combo_scanner import scan_all_props, build_highconf_combo
            legs      = await asyncio.get_event_loop().run_in_executor(None, scan_all_props)
            candidate = build_highconf_combo(legs)'''

c = c.replace(old2, new2)
open('telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
from combo_scanner import scan_all_props, build_highconf_combo, submit_rfq, _log_combo_trade

legs = scan_all_props()
candidate = build_highconf_combo(legs)

if candidate:
    print(f'Monster: {len(candidate.legs)} legs | {candidate.expected_payout:.1f}x | \$5->\${5*candidate.expected_payout:.0f}')
    quote = submit_rfq(candidate)
    if quote:
        print(f'EXECUTED — quote: {quote.get(\"yes_bid_dollars\")}')
        _log_combo_trade(candidate, quote, mode='highconf')
    else:
        print('No quote received')
else:
    print('No monster combo found')
" 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace('QUOTE_TIMEOUT_SECS = 5', 'QUOTE_TIMEOUT_SECS = 15')
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

# Check which legs are from which games
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
import re

legs = scan_all_props()
hc = build_highconf_combo(legs)
games = {}
for l in hc.legs:
    m = re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', l.ticker.split('-')[1])
    code = m.group(1) if m else '??????'
    games.setdefault(code, []).append(l.ticker)

for game, tickers in games.items():
    print(f'{game[:3]} vs {game[3:6]}: {len(tickers)} legs')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
from combo_scanner import scan_all_props, build_highconf_combo, submit_rfq, _log_combo_trade, ComboCandidate
import re

legs = scan_all_props()
hc   = build_highconf_combo(legs)

# Filter out GSW/DEN legs (too early for quotes)
filtered = [l for l in hc.legs if 'GSDEN' not in l.ticker and 'DENGS' not in l.ticker]
print(f'Legs after removing GSW/DEN: {len(filtered)}')

candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', filtered)
print(f'Payout: {candidate.expected_payout:.1f}x | \$5->\${5*candidate.expected_payout:.0f}')

quote = submit_rfq(candidate)
if quote:
    print(f'EXECUTED — bid={quote.get(\"yes_bid_dollars\")}')
    _log_combo_trade(candidate, quote, mode='highconf')
else:
    print('No quote received')
" 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
from core.kalshi_client import _signed_get
import re

legs = scan_all_props()
hc   = build_highconf_combo(legs)

print('Checking live market prices for each leg:')
print()
quotable = []
for l in hc.legs:
    try:
        data    = _signed_get(f'/trade-api/v2/markets/{l.ticker}')
        market  = data.get('market', {})
        yes_bid = float(market.get('yes_bid_dollars', 0) or 0)
        yes_ask = float(market.get('yes_ask_dollars', 0) or 0)
        volume  = float(market.get('volume_fp', 0) or 0)
        spread  = yes_ask - yes_bid if yes_ask > 0 else 1.0
        player  = l.reasoning.split(' avg')[0]
        thr     = l.ticker.split('-')[-1]
        series  = l.ticker.split('-')[0]
        stat    = {'KXNBAPTS':'pts','KXNBAREB':'reb','KXNBAAST':'ast','KXNBA3PT':'3s','KXNBASTL':'stl','KXNBABLK':'blk'}.get(series,'?')
        active  = '✅' if yes_bid > 0 and spread < 0.15 else '⚠️ ' if yes_bid > 0 else '❌'
        print(f'{active} {player} {thr}+ {stat} | bid={yes_bid:.2f} ask={yes_ask:.2f} vol={volume:.0f}')
        if yes_bid > 0:
            quotable.append(l)
    except Exception as e:
        print(f'❌ {l.ticker[-20:]}: {e}')

print(f'Quotable legs: {len(quotable)}/{len(hc.legs)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
import kalshi_python, uuid
from core.kalshi_client import get_client
from combo_scanner import scan_all_props, build_highconf_combo
from core.kalshi_client import _signed_get
import requests, base64, time, re
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

# Build the combo market
legs = scan_all_props()
hc   = build_highconf_combo(legs)

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts, 'Content-Type': 'application/json'}

def event_ticker(t):
    m = re.match(r'(KXNBA[A-Z0-9]+-\d{2}[A-Z]{3}\d{2}[A-Z]+)', t)
    return m.group(1) if m else t.rsplit('-', 2)[0]

# Create dynamic market
selected = [{'market_ticker': l.ticker, 'event_ticker': event_ticker(l.ticker), 'side': 'yes'} for l in hc.legs]
cp = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
rc = requests.post(f'https://api.elections.kalshi.com{cp}',
     headers=pss_headers('POST', cp),
     json={'selected_markets': selected, 'with_market_payload': True}, timeout=8)
market_ticker = rc.json().get('market_ticker')
print(f'Market: {market_ticker}')

# Get current ask price
md = _signed_get(f'/trade-api/v2/markets/{market_ticker}')
m  = md.get('market', {})
yes_ask = m.get('yes_ask_dollars', 1.0)
print(f'Yes ask: {yes_ask}')

# Place market order at ask
client = get_client()
pa     = kalshi_python.PortfolioApi(api_client=client)
order  = pa.create_order(
    ticker          = market_ticker,
    action          = 'buy',
    side            = 'yes',
    type            = 'market',
    count           = 1,
    client_order_id = str(uuid.uuid4()),
)
print(f'Order: {order.order.status} @ {order.order.yes_price}c')
"  2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
import kalshi_python, uuid, requests, base64, time, re
from functools import reduce
from core.kalshi_client import get_client, _signed_get
from combo_scanner import scan_all_props, build_highconf_combo
from core.config import config
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding

legs = scan_all_props()
hc   = build_highconf_combo(legs)

# Calculate fair price from individual leg prices
fair_price = reduce(lambda a,b: a*b, [l.implied_prob for l in hc.legs], 1.0)
price_cents = max(1, int(fair_price * 100))
print(f'Fair price: {fair_price:.4f} = {price_cents}c')
print(f'Payout if hit: {1/fair_price:.1f}x')

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts  = str(int(time.time() * 1000))
    sig = private_key.sign((ts+method+path).encode(),
          asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()),
          salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(),
            'KALSHI-ACCESS-TIMESTAMP': ts, 'Content-Type': 'application/json'}

def event_ticker(t):
    m = re.match(r'(KXNBA[A-Z0-9]+-\d{2}[A-Z]{3}\d{2}[A-Z]+)', t)
    return m.group(1) if m else t.rsplit('-', 2)[0]

selected = [{'market_ticker': l.ticker, 'event_ticker': event_ticker(l.ticker), 'side': 'yes'} for l in hc.legs]
cp = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
rc = requests.post(f'https://api.elections.kalshi.com{cp}',
     headers=pss_headers('POST', cp),
     json={'selected_markets': selected, 'with_market_payload': True}, timeout=8)
market_ticker = rc.json().get('market_ticker')
print(f'Market: {market_ticker}')

client = get_client()
pa     = kalshi_python.PortfolioApi(api_client=client)
order  = pa.create_order(
    ticker          = market_ticker,
    action          = 'buy',
    side            = 'yes',
    type            = 'limit',
    yes_price       = price_cents,
    count           = 1,
    client_order_id = str(uuid.uuid4()),
)
print(f'Order: {order.order.status} id={order.order.order_id}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
import kalshi_python
from core.kalshi_client import get_client

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
pa.cancel_order('379e6885-e44e-4594-a4ce-864c52f13eba')
print('Cancelled')
"
python3 -c "
import time, logging
logging.basicConfig(level=logging.WARNING)
from combo_scanner import scan_all_props, build_highconf_combo, submit_rfq, ComboCandidate

legs = scan_all_props()
hc   = build_highconf_combo(legs)
all_legs = hc.legs

print(f'Testing leg counts from 4 to {len(all_legs)}...')
print()

for n in [4, 6, 8, 10, 12, 15, 18, 20, 25, 30]:
    if n > len(all_legs):
        break
    subset    = all_legs[:n]
    candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', subset)
    payout    = candidate.expected_payout
    
    print(f'Testing {n:2d} legs | {payout:6.1f}x | \$5->\${5*payout:6.0f}...')
    quote = submit_rfq(candidate)
    if quote:
        bid = quote.get('yes_bid_dollars', '?')
        print(f'  ✅ QUOTED at {bid}')
    else:
        print(f'  ❌ No quote')
    time.sleep(2)
" 2>&1 | grep -E "Testing|QUOTED|No quote"
Testing leg counts from 4 to 30...
Testing  4 legs |    2.1x | $5->$    10...
Testing  6 legs |    2.9x | $5->$    14...
Testing  8 legs |    3.8x | $5->$    19...
Testing 10 legs |    4.7x | $5->$    24...
Testing 12 legs |    5.8x | $5->$    29...
Testing 15 legs |    7.5x | $5->$    38...
Testing 18 legs |   15.0x | $5->$    75...
Testing 20 legs |   24.3x | $5->$   121...
Testing 25 legs |   92.2x | $5->$   461...
Testing 30 legs |  329.6x | $5->$  1648...
(kalshi-bot) root@Kalshi-bot:~/kalshi-bot-v2#
cd /root/kalshi-bot-v2 && python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
print(f'Total combos: {len(trades)}')
print()
for t in trades[-5:]:
    mode    = t.get('mode', 'unknown')
    legs    = len(t.get('legs', []))
    payout  = t.get('expected_payout', 0)
    quote   = t.get('quote', {})
    bid     = quote.get('yes_bid_dollars', '?')
    time_   = t['time'][:16]
    print(f'{time_} | {mode:10s} | {legs} legs | {payout:.1f}x | quote bid=\${bid}')
"
grep "0.05\|min.*quote\|quote.*min" /root/kalshi-bot-v2/combo_scanner.py | head -5
python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
for t in trades[-3:]:
    mode   = t.get('mode','?')
    legs   = t.get('legs',[])
    payout = t.get('expected_payout',0)
    bid    = t.get('quote',{}).get('yes_bid_dollars','?')
    print(f'{t[\"time\"][:16]} | {mode} | {len(legs)} legs | {payout:.1f}x | bid=\${bid}')
    for l in legs[:5]:
        print(f'  {l[-30:]}')
"
python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
print(f'Total: {len(trades)}')
for t in trades:
    bid = float(t.get('quote',{}).get('yes_bid_dollars',0) or 0)
    print(f'{t[\"time\"][:16]} | {len(t.get(\"legs\",[]))} legs | {t.get(\"expected_payout\",0):.1f}x | bid=\${bid:.4f} | {\"✅\" if bid >= 0.05 else \"❌ garbage\"}')
"
sed -n '395,430p' /root/kalshi-bot-v2/combo_scanner.py
sed -n '355,400p' /root/kalshi-bot-v2/combo_scanner.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''    if ev <= 0:
        log.info(f"[Combo] Quote rejected — negative EV")
        return None'''

new = '''    # Minimum payout check — reject if less than 10x
    min_payout = 10.0
    actual_payout = stake_dollars / yes_bid if yes_bid > 0 else 0
    if actual_payout < min_payout:
        log.info(f"[Combo] Quote rejected — payout {actual_payout:.1f}x below {min_payout}x minimum")
        return None

    if ev <= 0:
        log.info(f"[Combo] Quote rejected — negative EV")
        return None'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

git add -A && git commit -m "fix: minimum 10x payout before accepting quote" && git push origin master
cd /root/kalshi-bot-v2 && python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|quote|EXECUTED|rejected|payout" | head -20
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''            injuries = athlete.get('injuries', [])
            if injuries:
                s = str(injuries[0].get('status', 'Active')).lower()
            else:
                status = athlete.get('status', {})
                if isinstance(status, dict):
                    type_val = status.get('type', 'active')
                    s = str(type_val).lower() if not isinstance(type_val, dict) else 'active'
                else:
                    s = str(status).lower()'''

new = '''            injuries = athlete.get('injuries', [])
            if injuries:
                s = str(injuries[0].get('status', 'Active')).lower()
            else:
                status = athlete.get('status', {})
                if isinstance(status, dict):
                    type_val = status.get('type', 'active')
                    s = str(type_val).lower() if not isinstance(type_val, dict) else 'active'
                else:
                    s = str(status).lower()
            # Also check deactivated flag
            if athlete.get('deactivated', False):
                s = 'out'
            # Check active flag
            if not athlete.get('active', True):
                s = 'out' '''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
total_spent = 0
garbage = 0
for t in trades:
    bid    = float(t.get('quote',{}).get('yes_bid_dollars',0) or 0)
    stake  = 5.0
    payout = stake / bid if bid > 0 else 0
    total_spent += stake
    if payout < 10:
        garbage += stake
        print(f'GARBAGE: {t[\"time\"][:16]} | {payout:.1f}x payout | \${stake} wasted')

print(f'Total spent on combos: \${total_spent:.2f}')
print(f'Spent on garbage combos: \${garbage:.2f}')

from core.kalshi_client import get_balance
bal = get_balance()
print(f'Current balance: \${bal:.2f}')
"
screen -S combo -X quit
echo "Combo scheduler stopped — balance too low"
cd /root/kalshi-bot-v2 && python3 -c "
from core.kalshi_client import _signed_get

# Find Turner's prop market and get last price
tickers = [
    'KXNBAPTS-26MAR29LACMIL-LACMTURNER33-10',  # 10+ pts
    'KXNBAREB-26MAR29LACMIL-MILMTURNER3-4',    # 4+ reb
]
for t in tickers:
    try:
        d = _signed_get(f'/trade-api/v2/markets/{t}')
        m = d.get('market', {})
        print(f'{t[-20:]}')
        print(f'  yes_bid={m.get(\"yes_bid_dollars\")} yes_ask={m.get(\"yes_ask_dollars\")} last={m.get(\"last_price_dollars\")}')
    except Exception as e:
        print(f'{t[-20:]}: {e}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cat > /root/kalshi-bot-v2/data/price_monitor.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/price_monitor.py
─────────────────────────────────────────────────────────────────────────────
Monitors leg prices over a window and returns a confidence adjustment.

Logic:
    - Sample yes_bid at start and end of window
    - Calculate drift (end - start)
    - Apply penalty/boost to confidence
    - If drift exceeds threshold, trigger LLM investigation
"""

import logging
import time
import requests as req
from core.kalshi_client import _signed_get
from core.config import config

log = logging.getLogger("kalshi_bot.price_monitor")

ANTHROPIC_URL    = "https://api.anthropic.com/v1/messages"
SAMPLE_INTERVAL  = 60    # seconds between samples
MIN_SAMPLES      = 3     # minimum samples before deciding
DRIFT_WARN       = -0.03 # -3¢ triggers LLM investigation
DRIFT_SKIP       = -0.08 # -8¢ automatic confidence kill
DRIFT_BOOST      = 0.03  # +3¢ adds confidence


def get_yes_bid(ticker: str) -> float:
    """Fetch current yes_bid for a market."""
    try:
        data = _signed_get(f'/trade-api/v2/markets/{ticker}')
        return float(data.get('market', {}).get('yes_bid_dollars', 0) or 0)
    except Exception:
        return 0.0


def sample_prices(tickers: list[str], window_secs: int = 300) -> dict[str, list[float]]:
    """
    Sample prices for all tickers over the window.
    Returns {ticker: [price1, price2, ...]}
    """
    samples = {t: [] for t in tickers}
    n_samples = max(MIN_SAMPLES, window_secs // SAMPLE_INTERVAL)
    interval  = window_secs / n_samples

    log.info(f"[PriceMonitor] Sampling {len(tickers)} legs over {window_secs}s ({n_samples} samples)")

    for i in range(n_samples):
        for ticker in tickers:
            price = get_yes_bid(ticker)
            if price > 0:
                samples[ticker].append(price)
        if i < n_samples - 1:
            time.sleep(interval)

    return samples


def analyze_drift(samples: dict[str, list[float]]) -> dict[str, dict]:
    """
    Analyze price drift for each ticker.
    Returns {ticker: {drift, trend, adjustment, investigate}}
    """
    results = {}
    for ticker, prices in samples.items():
        if len(prices) < 2:
            results[ticker] = {
                'drift': 0.0, 'trend': 'unknown',
                'adjustment': 0.0, 'investigate': False
            }
            continue

        start   = prices[0]
        end     = prices[-1]
        drift   = round(end - start, 3)
        avg     = sum(prices) / len(prices)
        volatility = max(prices) - min(prices)

        # Determine trend
        if drift >= DRIFT_BOOST:
            trend = 'rising'
        elif drift <= DRIFT_SKIP:
            trend = 'collapsing'
        elif drift <= DRIFT_WARN:
            trend = 'falling'
        elif abs(drift) < 0.01:
            trend = 'stable'
        else:
            trend = 'noise'

        # Calculate confidence adjustment
        if trend == 'rising':
            adjustment = min(0.05, drift * 1.5)   # boost up to +5%
        elif trend == 'collapsing':
            adjustment = -0.15                     # hard penalty
        elif trend == 'falling':
            adjustment = drift * 2                 # proportional penalty
        elif trend == 'stable':
            adjustment = 0.02                      # small stability bonus
        else:
            adjustment = 0.0

        investigate = trend in ('falling', 'collapsing')

        results[ticker] = {
            'drift':       drift,
            'trend':       trend,
            'adjustment':  round(adjustment, 3),
            'investigate': investigate,
            'start':       start,
            'end':         end,
            'volatility':  round(volatility, 3),
        }

        log.info(f"[PriceMonitor] {ticker[-25:]} "
                 f"drift={drift:+.3f} trend={trend} adj={adjustment:+.3f}")

    return results


def llm_investigate(ticker: str, drift: float, player_name: str, stat: str) -> str:
    """
    Ask Claude Haiku why a price is falling.
    Returns: 'skip', 'caution', or 'hold'
    """
    if not config.ANTHROPIC_API_KEY:
        return 'caution'

    prompt = f"""A Kalshi NBA prop market is falling in price pre-game.

Player: {player_name}
Prop: {stat}
Price drift: {drift:+.3f} in last 5 minutes

Possible reasons:
1. Player injury/DNP announced
2. Lineup change
3. Low volume noise
4. Market maker adjustment
5. Sharp money fading

Based on typical NBA pre-game dynamics, what is the most likely reason?
Respond with ONLY one word: skip, caution, or hold
- skip: likely injury/DNP, avoid this leg
- caution: uncertain, reduce confidence
- hold: probably noise, keep the leg"""

    try:
        r = req.post(ANTHROPIC_URL, headers={
            "x-api-key":         config.ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type":      "application/json",
        }, json={
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 10,
            "messages":   [{"role": "user", "content": prompt}],
        }, timeout=8)
        response = r.json().get("content", [{}])[0].get("text", "caution").strip().lower()
        if response not in ('skip', 'caution', 'hold'):
            return 'caution'
        log.info(f"[PriceMonitor] LLM verdict for {player_name}: {response}")
        return response
    except Exception as e:
        log.debug(f"[PriceMonitor] LLM error: {e}")
        return 'caution'


def get_price_adjustments(legs: list, window_secs: int = 300) -> dict[str, float]:
    """
    Main entry point. Monitor prices and return confidence adjustments per ticker.

    Args:
        legs: list of ComboLeg objects
        window_secs: how long to monitor (default 5 min)

    Returns:
        {ticker: confidence_adjustment}  e.g. {'KXNBA...': -0.08}
    """
    tickers  = [l.ticker for l in legs]
    leg_map  = {l.ticker: l for l in legs}
    samples  = sample_prices(tickers, window_secs)
    analysis = analyze_drift(samples)

    adjustments = {}
    for ticker, result in analysis.items():
        adj = result['adjustment']

        # LLM investigation for falling prices
        if result['investigate'] and ticker in leg_map:
            leg        = leg_map[ticker]
            player     = leg.reasoning.split(' avg')[0] if ' avg' in leg.reasoning else ticker
            series     = ticker.split('-')[0]
            stat       = {'KXNBAPTS':'points','KXNBAREB':'rebounds','KXNBAAST':'assists',
                         'KXNBA3PT':'threes','KXNBASTL':'steals','KXNBABLK':'blocks'}.get(series,'stat')
            verdict    = llm_investigate(ticker, result['drift'], player, stat)

            if verdict == 'skip':
                adj = -1.0   # effectively removes leg
            elif verdict == 'caution':
                adj = min(adj, -0.05)
            elif verdict == 'hold':
                adj = max(adj, -0.01)  # near zero

        adjustments[ticker] = adj

    return adjustments
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/price_monitor.py) lines"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/prop_scanner.py', 'r')
c = f.read()
f.close()

old = '''def build_edge_combo(legs: list[dict], max_legs: int = 12,
                     min_payout: float = 20.0) -> list[dict]:'''

new = '''def apply_price_monitoring(legs: list, window_secs: int = 300) -> list:
    """
    Monitor prices and adjust confidence scores.
    Removes or penalizes legs where price is falling significantly.
    """
    from data.price_monitor import get_price_adjustments
    from combo_scanner import ComboLeg

    # Convert dicts to ComboLeg-like objects for price monitor
    class _Leg:
        def __init__(self, d):
            self.ticker    = d['ticker']
            self.reasoning = d['reasoning']

    leg_objs    = [_Leg(l) for l in legs]
    adjustments = get_price_adjustments(leg_objs, window_secs)

    adjusted = []
    for leg in legs:
        adj      = adjustments.get(leg['ticker'], 0.0)
        new_conf = leg['model_conf'] + adj

        if new_conf <= 0 or adj <= -0.99:
            log.info(f"[PropScanner] Dropping leg after price monitor: {leg['ticker'][-25:]}")
            continue

        leg = dict(leg)
        leg['model_conf'] = round(max(0, new_conf), 3)
        leg['edge']       = round(leg['model_conf'] - leg['market_price'], 3)
        leg['price_adj']  = adj
        adjusted.append(leg)

    log.info(f"[PropScanner] Price monitor: {len(legs)} -> {len(adjusted)} legs")
    return adjusted


def build_edge_combo(legs: list[dict], max_legs: int = 12,
                     min_payout: float = 20.0) -> list[dict]:'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/prop_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''    log.info("[Combo] Starting combo scan — MOONSHOT + HIGH CONF modes")
    candidates = []
    legs       = scan_all_props()'''

new = '''    log.info("[Combo] Starting combo scan — MOONSHOT + HIGH CONF modes")
    candidates = []
    legs       = scan_all_props()

    # ── Price monitoring (5 min window) ───────────────────────────────
    if not dry_run and legs:
        log.info("[Combo] Running price monitor (5 min)...")
        from data.prop_scanner import apply_price_monitoring
        # Convert ComboLegs to dicts for price monitor
        leg_dicts = [{
            'ticker':     l.ticker,
            'model_conf': l.confidence,
            'market_price': l.implied_prob,
            'edge':       l.confidence - l.implied_prob,
            'reasoning':  l.reasoning,
        } for l in legs]
        monitored = apply_price_monitoring(leg_dicts, window_secs=300)
        # Rebuild ComboLegs with adjusted confidence
        legs = [ComboLeg(
            ticker            = d['ticker'],
            collection_ticker = 'KXMVESPORTSMULTIGAMEEXTENDED-R',
            confidence        = d['model_conf'],
            implied_prob      = d['market_price'],
            is_yes_only       = True,
            reasoning         = d['reasoning'],
        ) for d in monitored if d['edge'] >= 0.02]
        log.info(f"[Combo] After price monitor: {len(legs)} legs remain")'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "from data.price_monitor import get_price_adjustments; print('OK')"
git add -A && git commit -m "feat: price monitoring — watch leg prices pre-entry, LLM investigates drops" && git push origin master
cd /root/kalshi-bot-v2 && python3 combo_scanner.py 2>&1 | grep -E "Combo|Monitor|PropScanner" | head -15
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
legs = scan_all_props()
hc = build_highconf_combo(legs)
if hc:
    print(f'HC: {len(hc.legs)} legs | {hc.expected_payout:.1f}x')
else:
    from combo_scanner import HC_MIN_CONF
    qualified = [l for l in legs if l.confidence >= HC_MIN_CONF]
    print(f'HC qualified legs: {len(qualified)} (need 2+)')
    print(f'HC_MIN_CONF: {HC_MIN_CONF}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
screen -ls
python3 -c "
from datetime import datetime, timezone
scans = [
    '2026-03-29T21:00Z',  # 9 PM UTC - 30min before NYK/OKC
    '2026-03-29T22:30Z',  # 10:30 PM UTC - 2hr before HOU/NOP  
    '2026-03-29T23:00Z',  # 11 PM UTC - 30min before HOU/NOP
    '2026-03-30T00:00Z',  # midnight - 2hr before GSW/DEN
    '2026-03-30T01:30Z',  # 1:30 AM - 30min before GSW/DEN
]
now = datetime.now(timezone.utc)
for s in scans:
    dt = datetime.fromisoformat(s.replace('Z','+00:00'))
    if dt > now:
        diff = int((dt-now).total_seconds()/60)
        print(f'  {dt.strftime(\"%I:%M %p UTC\")} — in {diff} min')
"
screen -S combo bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 combo_scheduler.py; exec bash'
python3 -c "
import requests
ids = ['4432068', '6442', '4432452', '3074752', '6606']
for espn_id in ids:
    r = requests.get(f'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/athletes/{espn_id}', timeout=6)
    if r.status_code == 200:
        a = r.json().get('athlete', {})
        print(f'{espn_id}: {a.get(\"fullName\",\"?\")} — active={a.get(\"active\")} team={a.get(\"team\",{}).get(\"abbreviation\",\"none\")}')
    else:
        print(f'{espn_id}: HTTP {r.status_code}')
"
source /root/kalshi-bot/bin/activate
pip install fastapi uvicorn --break-system-packages
cat > /root/kalshi-bot-v2/api_server.py << 'PYEOF'
#!/usr/bin/env python3
"""
api_server.py
─────────────────────────────────────────────────────────────────────────────
FastAPI server exposing kalshi-bot-v2 data to the mobile app.
Read-only — never touches trading logic.

Run: uvicorn api_server:app --host 0.0.0.0 --port 8080
"""

import os
import json
import sys
sys.path.insert(0, '/root/kalshi-bot-v2')

from fastapi import FastAPI, HTTPException, Header
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime, timezone

app = FastAPI(title="Kalshi Bot API", version="1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Auth ───────────────────────────────────────────────────────────────────

API_KEY = os.getenv("BOT_API_KEY", "changeme123")

def verify_key(x_api_key: str = Header(...)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


# ── Routes ─────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/api/balance")
def get_balance(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from core.kalshi_client import get_balance
        bal = get_balance()
        return {"balance": round(bal, 2)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/combos")
def get_combos(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    log_file = "/root/kalshi-bot-v2/data/combo_trades.json"
    if not os.path.exists(log_file):
        return {"combos": []}
    try:
        combos = json.load(open(log_file))
        return {"combos": combos[-10:]}  # Last 10
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/parlay/moonshot")
def get_moonshot(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from combo_scanner import scan_all_props, build_best_combo
        legs      = scan_all_props()
        candidate = build_best_combo(legs)
        if not candidate:
            return {"found": False, "legs": [], "payout": 0, "confidence": 0}
        return {
            "found":      True,
            "mode":       "moonshot",
            "leg_count":  len(candidate.legs),
            "payout":     round(candidate.expected_payout, 1),
            "confidence": round(candidate.combined_confidence * 100, 2),
            "stake":      5.0,
            "win_amount": round(5.0 * candidate.expected_payout, 0),
            "legs": [{
                "ticker":     l.ticker,
                "player":     l.reasoning.split(' avg')[0],
                "reasoning":  l.reasoning,
                "confidence": round(l.confidence * 100, 1),
                "market_price": round(l.implied_prob * 100, 0),
                "edge":       round((l.confidence - l.implied_prob) * 100, 1),
            } for l in candidate.legs]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/parlay/monster")
def get_monster(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        from combo_scanner import scan_all_props, build_highconf_combo
        legs      = scan_all_props()
        candidate = build_highconf_combo(legs)
        if not candidate:
            return {"found": False, "legs": [], "payout": 0, "confidence": 0}
        return {
            "found":      True,
            "mode":       "monster",
            "leg_count":  len(candidate.legs),
            "payout":     round(candidate.expected_payout, 1),
            "confidence": round(candidate.combined_confidence * 100, 2),
            "stake":      5.0,
            "win_amount": round(5.0 * candidate.expected_payout, 0),
            "legs": [{
                "ticker":     l.ticker,
                "player":     l.reasoning.split(' avg')[0],
                "reasoning":  l.reasoning,
                "confidence": round(l.confidence * 100, 1),
                "market_price": round(l.implied_prob * 100, 0),
                "edge":       round((l.confidence - l.implied_prob) * 100, 1),
            } for l in candidate.legs]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/schedule")
def get_schedule(x_api_key: str = Header(...)):
    verify_key(x_api_key)
    try:
        import requests
        from datetime import date
        today = date.today().strftime("%Y%m%d")
        r = requests.get(
            f"https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates={today}",
            timeout=6
        )
        games = []
        for event in r.json().get("events", []):
            comps = event.get("competitions", [{}])[0]
            teams = comps.get("competitors", [])
            status = comps.get("status", {}).get("type", {})
            games.append({
                "name":    event.get("name", ""),
                "date":    event.get("date", ""),
                "status":  status.get("name", ""),
                "completed": status.get("completed", False),
                "teams":   [{"abbr": t.get("team",{}).get("abbreviation",""),
                             "score": t.get("score","0")} for t in teams]
            })
        return {"games": games}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats")
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

    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/api_server.py) lines"
echo "BOT_API_KEY=$(openssl rand -hex 16)" >> /root/.env
grep "BOT_API_KEY" /root/.env | tail -1
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 api_server.py &
sleep 3
# Test health endpoint
curl -s http://localhost:8080/health | python3 -m json.tool
# Get the API key
API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d'=' -f2)
echo "API Key: $API_KEY"
# Test balance
curl -s http://localhost:8080/api/balance -H "x-api-key: $API_KEY" | python3 -m json.tool
# Test schedule
curl -s http://localhost:8080/api/schedule -H "x-api-key: $API_KEY" | python3 -m json.tool | head -30
kill %1
source /root/kalshi-bot/bin/activate
cd /root/kalshi-bot-v2
API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d'=' -f2)
echo "Key: $API_KEY"
BOT_API_KEY=$API_KEY python3 api_server.py &
sleep 3
curl -s http://localhost:8080/api/balance -H "x-api-key: $API_KEY" | python3 -m json.tool
API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d'=' -f2)
# Stats
curl -s http://localhost:8080/api/stats -H "x-api-key: $API_KEY" | python3 -m json.tool
# Schedule
curl -s http://localhost:8080/api/schedule -H "x-api-key: $API_KEY" | python3 -m json.tool | head -40
# Combos
curl -s http://localhost:8080/api/combos -H "x-api-key: $API_KEY" | python3 -m json.tool | head -20
kill %1
screen -S api bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && BOT_API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d"=" -f2) python3 api_server.py; exec bash'
git add api_server.py && git commit -m "feat: REST API server for mobile app — balance, combos, parlay, schedule, stats" && git push origin master
grep "BOT_API_KEY" /root/.env | tail -1
mkdir -p /root/kalshi-bot-v2/app
cat > /root/kalshi-bot-v2/app/index.html << 'PYEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Kalshi Bot">
  <title>Kalshi Bot</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0a0a0a;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      padding-bottom: 80px;
    }
    .header {
      background: linear-gradient(135deg, #1a1a2e, #16213e);
      padding: 50px 20px 20px;
      border-bottom: 1px solid #333;
    }
    .header h1 { font-size: 28px; font-weight: 700; }
    .header p  { color: #888; font-size: 13px; margin-top: 4px; }
    .balance-card {
      background: linear-gradient(135deg, #00b894, #00cec9);
      margin: 16px;
      border-radius: 16px;
      padding: 20px;
    }
    .balance-card .label { font-size: 12px; opacity: 0.8; text-transform: uppercase; letter-spacing: 1px; }
    .balance-card .amount { font-size: 42px; font-weight: 700; margin-top: 4px; }
    .balance-card .sub { font-size: 12px; opacity: 0.8; margin-top: 4px; }
    .section { margin: 16px; }
    .section-title {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      color: #666;
      margin-bottom: 10px;
    }
    .btn-row { display: flex; gap: 10px; }
    .btn {
      flex: 1;
      padding: 16px;
      border-radius: 14px;
      border: none;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
      transition: opacity 0.2s;
    }
    .btn:active { opacity: 0.7; }
    .btn .icon { font-size: 28px; }
    .btn-moonshot { background: linear-gradient(135deg, #6c5ce7, #a29bfe); color: #fff; }
    .btn-monster  { background: linear-gradient(135deg, #e17055, #d63031); color: #fff; }
    .card {
      background: #1a1a1a;
      border-radius: 14px;
      padding: 16px;
      margin-bottom: 10px;
      border: 1px solid #2a2a2a;
    }
    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
    }
    .card-title { font-size: 16px; font-weight: 600; }
    .badge {
      font-size: 11px;
      padding: 4px 10px;
      border-radius: 20px;
      font-weight: 600;
    }
    .badge-green  { background: #00b894; color: #fff; }
    .badge-purple { background: #6c5ce7; color: #fff; }
    .badge-red    { background: #d63031; color: #fff; }
    .leg {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 0;
      border-bottom: 1px solid #2a2a2a;
      font-size: 13px;
    }
    .leg:last-child { border-bottom: none; }
    .leg-name { color: #ddd; flex: 1; }
    .leg-conf { color: #00b894; font-weight: 600; font-size: 12px; margin-left: 8px; }
    .leg-edge { color: #6c5ce7; font-size: 11px; margin-left: 6px; }
    .payout-row {
      display: flex;
      justify-content: space-between;
      margin-top: 12px;
      padding-top: 12px;
      border-top: 1px solid #2a2a2a;
    }
    .payout-label { color: #888; font-size: 13px; }
    .payout-value { font-size: 20px; font-weight: 700; color: #00b894; }
    .game-card {
      background: #1a1a1a;
      border-radius: 14px;
      padding: 14px 16px;
      margin-bottom: 8px;
      border: 1px solid #2a2a2a;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .game-teams { font-size: 14px; font-weight: 600; }
    .game-score { font-size: 18px; font-weight: 700; color: #00b894; }
    .game-status { font-size: 11px; color: #888; margin-top: 2px; }
    .loading {
      text-align: center;
      padding: 40px;
      color: #666;
    }
    .spinner {
      width: 32px; height: 32px;
      border: 3px solid #333;
      border-top-color: #00b894;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 12px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .nav {
      position: fixed;
      bottom: 0; left: 0; right: 0;
      background: #111;
      border-top: 1px solid #2a2a2a;
      display: flex;
      padding-bottom: env(safe-area-inset-bottom);
    }
    .nav-item {
      flex: 1;
      padding: 12px 0;
      text-align: center;
      cursor: pointer;
      font-size: 10px;
      color: #666;
      transition: color 0.2s;
    }
    .nav-item.active { color: #00b894; }
    .nav-item .nav-icon { font-size: 22px; display: block; margin-bottom: 2px; }
    .screen { display: none; }
    .screen.active { display: block; }
    .error { color: #e17055; font-size: 13px; text-align: center; padding: 20px; }
    .refresh-btn {
      background: #1a1a1a;
      border: 1px solid #333;
      color: #888;
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 12px;
      cursor: pointer;
      margin-top: 8px;
    }
  </style>
</head>
<body>

<!-- HOME -->
<div id="screen-home" class="screen active">
  <div class="header">
    <h1>🤖 Kalshi Bot</h1>
    <p id="last-updated">Loading...</p>
  </div>

  <div class="balance-card">
    <div class="label">Portfolio Balance</div>
    <div class="amount" id="balance-amount">--</div>
    <div class="sub" id="combo-sub">Loading...</div>
  </div>

  <div class="section">
    <div class="section-title">Find Best Combo</div>
    <div class="btn-row">
      <button class="btn btn-moonshot" onclick="showParlay('moonshot')">
        <span class="icon">🎯</span>
        <span>Moonshot</span>
      </button>
      <button class="btn btn-monster" onclick="showParlay('monster')">
        <span class="icon">💪</span>
        <span>Monster</span>
      </button>
    </div>
  </div>

  <div class="section">
    <div class="section-title">Tonight's Games</div>
    <div id="games-list"><div class="loading"><div class="spinner"></div>Loading...</div></div>
  </div>
</div>

<!-- PARLAY -->
<div id="screen-parlay" class="screen">
  <div class="header">
    <h1 id="parlay-title">🎯 Moonshot</h1>
    <p id="parlay-sub">Scanning props...</p>
  </div>
  <div class="section" id="parlay-content">
    <div class="loading"><div class="spinner"></div>Scanning props...</div>
  </div>
</div>

<!-- COMBOS -->
<div id="screen-combos" class="screen">
  <div class="header">
    <h1>📋 My Combos</h1>
    <p>Recent combo trades</p>
  </div>
  <div class="section" id="combos-content">
    <div class="loading"><div class="spinner"></div>Loading...</div>
  </div>
</div>

<!-- STATS -->
<div id="screen-stats" class="screen">
  <div class="header">
    <h1>📊 Stats</h1>
    <p>Trading performance</p>
  </div>
  <div class="section" id="stats-content">
    <div class="loading"><div class="spinner"></div>Loading...</div>
  </div>
</div>

<!-- NAV -->
<nav class="nav">
  <div class="nav-item active" onclick="showScreen('home')">
    <span class="nav-icon">🏠</span>Home
  </div>
  <div class="nav-item" onclick="showScreen('parlay-select')">
    <span class="nav-icon">🎯</span>Parlay
  </div>
  <div class="nav-item" onclick="showScreen('combos')">
    <span class="nav-icon">📋</span>Combos
  </div>
  <div class="nav-item" onclick="showScreen('stats')">
    <span class="nav-icon">📊</span>Stats
  </div>
</nav>

<script>
const API_BASE = 'http://137.184.84.50:8080';
const API_KEY  = 'REPLACE_ME';

async function api(path) {
  const r = await fetch(API_BASE + path, {
    headers: { 'x-api-key': API_KEY }
  });
  if (!r.ok) throw new Error(await r.text());
  return r.json();
}

function showScreen(name) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

  if (name === 'parlay-select') {
    document.getElementById('screen-home').classList.add('active');
    document.querySelectorAll('.nav-item')[1].classList.add('active');
    document.querySelector('.section').scrollIntoView({behavior:'smooth'});
    return;
  }

  const screens = ['home','parlay','combos','stats'];
  const idx = screens.indexOf(name);
  document.getElementById('screen-' + name).classList.add('active');
  if (idx >= 0) document.querySelectorAll('.nav-item')[idx].classList.add('active');

  if (name === 'combos') loadCombos();
  if (name === 'stats')  loadStats();
  if (name === 'home')   loadHome();
}

async function loadHome() {
  try {
    const [bal, sched] = await Promise.all([api('/api/balance'), api('/api/schedule')]);
    document.getElementById('balance-amount').textContent = '$' + bal.balance.toFixed(2);
    document.getElementById('last-updated').textContent = 'Updated ' + new Date().toLocaleTimeString();

    // Games
    const gamesList = document.getElementById('games-list');
    const games = sched.games.filter(g => !g.completed || g.status === 'STATUS_IN_PROGRESS');
    if (!games.length) {
      gamesList.innerHTML = '<div class="error">No games in progress</div>';
    } else {
      gamesList.innerHTML = games.map(g => {
        const t = g.teams;
        const score = t.length === 2 ? `${t[0].score} - ${t[1].score}` : '';
        const status = g.status === 'STATUS_IN_PROGRESS' ? '🔴 LIVE' :
                       g.status === 'STATUS_SCHEDULED' ? '⏰ Soon' : '✅ Final';
        return `<div class="game-card">
          <div>
            <div class="game-teams">${g.name.replace(' at ', ' @ ')}</div>
            <div class="game-status">${status}</div>
          </div>
          <div class="game-score">${score}</div>
        </div>`;
      }).join('');
    }

    // Combo sub
    const combos = await api('/api/combos');
    document.getElementById('combo-sub').textContent =
      `${combos.combos.length} combos placed`;
  } catch(e) {
    document.getElementById('balance-amount').textContent = 'Error';
  }
}

async function showParlay(mode) {
  showScreen('parlay');
  const title = mode === 'monster' ? '💪 Monster Combo' : '🎯 Moonshot Combo';
  document.getElementById('parlay-title').textContent = title;
  document.getElementById('parlay-sub').textContent = 'Scanning props...';
  document.getElementById('parlay-content').innerHTML =
    '<div class="loading"><div class="spinner"></div>Scanning (~10s)...</div>';

  try {
    const data = await api('/api/parlay/' + mode);
    document.getElementById('parlay-sub').textContent =
      `${data.leg_count} legs · ${data.confidence}% conf`;

    if (!data.found) {
      document.getElementById('parlay-content').innerHTML =
        '<div class="error">No qualifying combo right now. Try closer to game time.</div>';
      return;
    }

    const legsHtml = data.legs.map(l => {
      const player = l.player || l.ticker;
      const thr = l.ticker.split('-').pop();
      const series = l.ticker.split('-')[0];
      const statMap = {KXNBAPTS:'pts',KXNBAREB:'reb',KXNBAAST:'ast',
                       KXNBA3PT:'3s',KXNBASTL:'stl',KXNBABLK:'blk'};
      const stat = statMap[series] || '';
      return `<div class="leg">
        <span class="leg-name">${player} ${thr}+ ${stat}</span>
        <span class="leg-conf">${l.confidence}%</span>
        <span class="leg-edge">+${l.edge}¢</span>
      </div>`;
    }).join('');

    document.getElementById('parlay-content').innerHTML = `
      <div class="card">
        <div class="card-header">
          <span class="card-title">${data.leg_count} Legs</span>
          <span class="badge badge-green">${data.payout}x</span>
        </div>
        ${legsHtml}
        <div class="payout-row">
          <span class="payout-label">$5 stake → potential</span>
          <span class="payout-value">$${data.win_amount}</span>
        </div>
      </div>
      <button class="refresh-btn" onclick="showParlay('${mode}')">🔄 Rescan</button>`;
  } catch(e) {
    document.getElementById('parlay-content').innerHTML =
      '<div class="error">Error: ' + e.message + '</div>';
  }
}

async function loadCombos() {
  try {
    const data = await api('/api/combos');
    const combos = data.combos.reverse();
    if (!combos.length) {
      document.getElementById('combos-content').innerHTML =
        '<div class="error">No combos placed yet</div>';
      return;
    }
    document.getElementById('combos-content').innerHTML = combos.map(c => {
      const date = new Date(c.time).toLocaleDateString();
      const payout = c.expected_payout ? c.expected_payout.toFixed(1) : '?';
      const mode = c.mode || 'combo';
      return `<div class="card">
        <div class="card-header">
          <span class="card-title">${c.legs.length}-leg ${mode}</span>
          <span class="badge badge-purple">${payout}x</span>
        </div>
        <div style="color:#888;font-size:12px">${date} · ${c.legs.length} legs</div>
      </div>`;
    }).join('');
  } catch(e) {
    document.getElementById('combos-content').innerHTML =
      '<div class="error">Error loading combos</div>';
  }
}

async function loadStats() {
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
}

// Boot
loadHome();
</script>
</body>
</html>
PYEOF

echo "Written"
API_KEY=$(grep "BOT_API_KEY" /root/.env | tail -1 | cut -d'=' -f2)
sed -i "s/REPLACE_ME/$API_KEY/" /root/kalshi-bot-v2/app/index.html
echo "Key injected"
# Serve the app on port 3000
cd /root/kalshi-bot-v2/app && python3 -m http.server 3000 &
echo "App running at http://137.184.84.50:3000"
cd /root/kalshi-bot-v2 && python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
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
