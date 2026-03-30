    warm_cache()
    log.info("Fetching today's NBA schedule...")'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scheduler.py', 'w').write(c)
print("Done")
PYEOF

git add combo_scheduler.py && git commit -m "feat: auto cache warm on scheduler startup" && git push origin master
screen -S combo -X quit
screen -S combo bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 combo_scheduler.py; exec bash'
screen -ls && /root/kalshi-bot/bin/python3 -c "from data.persistent_cache import cache_stats; cache_stats()"
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py
python3 telegram_bot.py
soururce kalshi-bot/bin/activate
source /root/kalshi-bot/bin/activate
screen -ls
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

# Fix stats to show v2 not v1
c = c.replace(
    'v2_log = "/root/kalshi-bot-v2/data/trade_log.csv"',
    'v2_log = "/root/kalshi-bot-v2/data/trade_log.csv"  # v2 trades'
)
c = c.replace(
    '"*V2 Bot (live)*"',
    '"*V2 Bot*"'
)

# Fix /menu command — it's triggering positions instead of menu
# The issue is cmd_menu sends wrong initial message
old = '''async def cmd_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 *Kalshi Bot v2*",
        parse_mode="Markdown",
        reply_markup=main_menu_keyboard()
    )'''

new = '''async def cmd_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 *Kalshi Bot v2* — What would you like to do?",
        parse_mode="Markdown",
        reply_markup=main_menu_keyboard()
    )'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/bot.py', 'r')
c = f.read()
f.close()
c = c.replace(
    'if cycle % 10 == 0:',
    'if cycle % 50 == 0:'
)
open('/root/kalshi-bot-v2/bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
systemctl restart kalshi-bot-v2
git add -A && git commit -m "fix: menu command, cycle report frequency, stats v2" && git push origin master
screen -ls | grep tgbot
screen -r tgbot
grep -A 15 "elif data == \"stats\":" /root/kalshi-bot-v2/telegram_bot.py | head -20
cd /root/kalshi-bot-v2
python3 << 'PYEOF'
f = open('telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''            # V1 live stats
            if os.path.exists(v1_file):
                rows = list(csv.DictReader(open(v1_file)))
                total_pnl = sum(float(r.get('pnl',0) or 0) for r in rows)
                lines.append(f"*V1 Bot (live)*")
                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\n")'''

new = '''            # V2 live stats
            v2_log = "/root/kalshi-bot-v2/data/trade_log.csv"
            if os.path.exists(v2_log):
                rows = list(csv.DictReader(open(v2_log)))
                total_pnl = sum(float(r.get('pnl',0) or 0) for r in rows)
                lines.append(f"*V2 Bot*")
                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\\n")
            else:
                lines.append("*V2 Bot*\\nNo live trades yet\\n")'''

c = c.replace(old, new)
open('telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen tgbot -r
screen -r
screen -r tgbot
grep "V2 Bot\|v2_log\|V1 Bot" /root/kalshi-bot-v2/telegram_bot.py | head -5
cd /root/kalshi-bot-v2
grep -n "V1 Bot\|v1_file\|V2 Bot\|v2_log" telegram_bot.py | head -10
sed -n '220,240p' /root/kalshi-bot-v2/telegram_bot.py
python3 << 'PYEOF'
with open('/root/kalshi-bot-v2/telegram_bot.py', 'r') as f:
    lines = f.readlines()

new_lines = []
skip_until = None
i = 0
while i < len(lines):
    line = lines[i]
    if '            v1_file    = "/root/trade_log.csv"' in line:
        # Replace the whole V1 block
        new_lines.append('            v2_log = "/root/kalshi-bot-v2/data/trade_log.csv"\n')
        i += 1
        continue
    elif '            # V1 live stats' in line:
        # Skip V1 block, replace with V2
        new_lines.append('            # V2 live stats\n')
        new_lines.append('            if os.path.exists(v2_log):\n')
        new_lines.append('                rows = list(csv.DictReader(open(v2_log)))\n')
        new_lines.append('                total_pnl = sum(float(r.get(\'pnl\',0) or 0) for r in rows)\n')
        new_lines.append('                lines.append(f"*V2 Bot*")\n')
        new_lines.append('                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\\n")\n')
        new_lines.append('            else:\n')
        new_lines.append('                lines.append("*V2 Bot*\\nNo live trades yet\\n")\n')
        # Skip old V1 lines until V2 paper stats
        i += 1
        while i < len(lines) and '# V2 paper stats' not in lines[i]:
            i += 1
        continue
    else:
        new_lines.append(line)
    i += 1

with open('/root/kalshi-bot-v2/telegram_bot.py', 'w') as f:
    f.writelines(new_lines)
print("Done")
PYEOF

grep -n "V1 Bot\|V2 Bot\|v2_log" /root/kalshi-bot-v2/telegram_bot.py | head -5
screen -r tgbot
grep -n "positions" /root/kalshi-bot-v2/telegram_bot.py | grep -i "path\|file\|json"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '"📋 No positions file found"',
    '"📋 No open positions"'
)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 telegram_bot.py &
git add -A && git commit -m "fix: stats v2, positions message, menu buttons" && git push origin master
pkill -f telegram_bot.py
sleep 2
screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
source /root/kalshi-bot/bin/activate &&
source /root/kalshi-bot/bin/activate
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && echo "=== V2 BOT ===" && systemctl status kalshi-bot-v2 | grep Active && echo "" && echo "=== BALANCE ===" && python3 -c "from core.kalshi_client import get_balance; print(f'\${get_balance():.2f}')" && echo "" && echo "=== V2 PAPER STATS ===" && python3 paper_trader.py --stats && echo "" && echo "=== V1 PAPER STATS ===" && cd /root && python3 paper_trader.py --stats
screen -r combo
screen -r paper-v2
cd /root/kalshi-bot-v2 && python3 << 'PYEOF'
f = open('combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) >= 0.02 and q.get(\'status\')==\'open\']',
    '            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) >= 0.05 and q.get(\'status\')==\'open\']'
)
open('combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

git add -A && git commit -m "fix: min quote 5c to avoid resting orders at garbage prices" && git push origin master
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 -c "
from data.nba_stats import score_prop_leg

legs = [
    ('Kawhi Leonard 2+ threes',   'KXNBA3PT-26MAR29LACMIL-LACKLEONARD2-2'),
    ('Darius Garland 6+ assists', 'KXNBAAST-26MAR29LACMIL-LACDGARLAND10-6'),
    ('John Collins 10+ points',   'KXNBAPTS-26MAR29LACMIL-LACJCOLLINS20-10'),
    ('Kawhi Leonard 25+ points',  'KXNBAPTS-26MAR29LACMIL-LACKLEONARD2-25'),
    ('Myles Turner 10+ points',   'KXNBAPTS-26MAR29LACMIL-LACMTURNER33-10'),
    ('Mathurin 2+ rebounds',      'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2'),
    ('John Collins 4+ rebounds',  'KXNBAREB-26MAR29LACMIL-LACJCOLLINS20-4'),
    ('Tyler Herro 2+ threes',     'KXNBA3PT-26MAR29MIAIND-MIATHERRO14-2'),
    ('Wiggins 10+ points',        'KXNBAPTS-26MAR29MIAIND-MIAAWIGGINS22-10'),
    ('Adebayo 15+ points',        'KXNBAPTS-26MAR29MIAIND-MIABADEBAYO13-15'),
    ('Kel el Ware 6+ rebounds',   'KXNBAREB-26MAR29MIAIND-INDKWARE5-6'),
    ('Desmond Bane 2+ threes',    'KXNBA3PT-26MAR29ORLTORR-TORDBANEE0-2'),
    ('DeRozan 2+ assists',        'KXNBAAST-26MAR29SACBKN-SACDDEROZA0-2'),
    ('Noah Clowney 10+ points',   'KXNBAPTS-26MAR29SACBKN-BKNNCLOWNEY0-10'),
    ('DeRozan 15+ points',        'KXNBAPTS-26MAR29SACBKN-SACDDEROZA0-15'),
    ('Nic Claxton 2+ rebounds',   'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2'),
    ('Knueppel 15+ points',       'KXNBAPTS-26MAR29BOSCHA-CHAKKNUEPPEL7-15'),
    ('LaMelo 15+ points',         'KXNBAPTS-26MAR29BOSCHA-CHALBALL1-15'),
    ('Miles Bridges 10+ points',  'KXNBAPTS-26MAR29BOSCHA-CHAMBRIDGES8-10'),
    ('Aaron Gordon 10+ points',   'KXNBAPTS-26MAR30GSDEN-DENAGORDON15-10'),
    ('Jokic 20+ points',          'KXNBAPTS-26MAR30GSDEN-DENNJOKIC15-20'),
]

from functools import reduce
total_conf = 1.0
print(f'{\"Leg\":<28} {\"Avg\":>5} {\"Thr\":>4} {\"HR\":>5} {\"Conf\":>6}')
print('-'*55)
for name, ticker in legs:
    try:
        r = score_prop_leg(ticker)
        conf = r.get('confidence', 0)
        avg  = r.get('avg_stat', 0)
        thr  = r.get('threshold', 0)
        hr_str = ''
        if 'hr=' in r.get('reason',''):
            hr_str = r['reason'].split('hr=')[1].split(')')[0]
        total_conf *= conf if conf > 0 else 0.5
        flag = ' ⚠️' if conf < 0.65 else ' ✅'
        print(f'{name:<28} {avg:>5.1f} {thr:>4.0f} {hr_str:>5} {conf:>6.2f}{flag}')
    except Exception as e:
        print(f'{name:<28} ERROR')
print('-'*55)
print(f'Combined model conf: {total_conf:.4f} = {total_conf*100:.2f}%')
print(f'Market implied prob: {4.97/1162*100:.2f}%')
print(f'EV ratio: {(total_conf * 1162/4.97):.2f}x')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && python3 -c "
from data.nba_stats import _parse_ticker, _cached_find_player, TEAM_CODE_MAP

tickers = [
    'KXNBAPTS-26MAR29LACMIL-LACMTURNER33-10',
    'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2',
    'KXNBAREB-26MAR29MIAIND-INDKWARE5-6',
    'KXNBA3PT-26MAR29ORLTORR-TORDBANEE0-2',
    'KXNBAAST-26MAR29SACBKN-SACDDEROZA0-2',
    'KXNBAPTS-26MAR29SACBKN-BKNNCLAXTONN0-10',
    'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2',
]
for t in tickers:
    parsed = _parse_ticker(t)
    if parsed:
        team, code = parsed
        espn_team = TEAM_CODE_MAP.get(team, team)
        espn_id, name = _cached_find_player(espn_team, code)
        print(f'{t[-22:]} → team={team} espn={espn_team} code={code} found={name}')
    else:
        print(f'{t[-22:]} → PARSE FAILED')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import requests
checks = [
    ('LAC', ['turner', 'mathurin']),
    ('IND', ['mathurin', 'ware']),
    ('TOR', ['bane']),
    ('SAC', ['derozan']),
    ('BKN', ['claxton']),
]
for team, names in checks:
    r = requests.get(f'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/{team}/roster', timeout=6)
    athletes = r.json().get('athletes', [])
    for a in athletes:
        last = a.get('lastName','').lower()
        if any(n in last for n in names):
            print(f'{team}: {a[\"fullName\"]} id={a[\"id\"]} last={last}')
" 2>&1 | grep -v DEBUG
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''        # Reverse partial — last name contains player code fragment
        if len(code) >= 4 and code[:4] in last:
            return (athlete['id'], full)'''

new = '''        # Reverse partial — last name contains player code fragment
        if len(code) >= 4 and code[:4] in last:
            return (athlete['id'], full)

        # Handle double-letter codes e.g. nclaxtonn -> claxton
        stripped = code.rstrip(code[-1]) if code else code
        if len(stripped) >= 4 and (stripped in last or last in stripped):
            return (athlete['id'], full)

        # Handle missing vowels / truncation e.g. dderoza -> derozan
        if len(code) >= 5 and (code[1:] in last or last in code[1:]):
            return (athlete['id'], full)'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg

tests = [
    ('DeRozan 15+ pts',    'KXNBAPTS-26MAR29SACBKN-SACDDEROZA0-15'),
    ('Claxton 2+ reb',     'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2'),
    ('Mathurin 2+ reb',    'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2'),
    ('Turner 10+ pts',     'KXNBAPTS-26MAR29LACMIL-LACMTURNER33-10'),
]
for name, ticker in tests:
    r = score_prop_leg(ticker)
    print(f'{name}: conf={r[\"confidence\"]:.2f} avg={r.get(\"avg_stat\",0):.1f} | {r[\"reason\"][:50]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.nba_stats import _find_player

# Test each directly
tests = [
    ('SAC', 'dderoza'),
    ('BKN', 'nclaxtonn'),
    ('IND', 'bmathurin'),
    ('LAC', 'mturner'),
]
for team, code in tests:
    result = _find_player(team, code)
    print(f'{team} {code}: {result}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
grep -n "return None\|return (None" /root/kalshi-bot-v2/data/nba_stats.py | head -20
sed -n '75,85p' /root/kalshi-bot-v2/data/nba_stats.py
python3 -c "
import re
tickers = [
    'KXNBAPTS-26MAR29SACBKN-SACDDEROZA0-15',
    'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2',
    'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2',
]
for t in tickers:
    m = re.search(r'-([A-Z]{3})([A-Z]+)(\d+)-(\d+)$', t)
    if m:
        print(f'{t[-25:]} → team={m.group(1)} player={m.group(2)} num={m.group(3)} thr={m.group(4)}')
    else:
        print(f'{t[-25:]} → NO MATCH')
"
python3 -c "
from data.persistent_cache import get_roster
from data.nba_stats import TEAM_CODE_MAP

# Check SAC roster for derozan
roster = get_roster('SAC')
print(f'SAC roster size: {len(roster)}')
code = 'dderoza'
for a in roster:
    last = a.get('lastName','').lower().replace('-','').replace(\"'\",'')
    full = a.get('fullName','')
    if 'dero' in last or 'dero' in code:
        print(f'  Candidate: last={last} full={full}')
        print(f'    endswith: {code.endswith(last)}')
        print(f'    last in code: {last in code}')
        print(f'    last[:4] in code: {last[:4] in code}')
        print(f'    code[1:] in last: {code[1:] in last}')
"
grep -n "stripped\|code\[1:\]\|rstrip" /root/kalshi-bot-v2/data/nba_stats.py | head -10
python3 -c "
from data.persistent_cache import get_roster

roster = get_roster('SAC')
for a in roster:
    raw_last = a.get('lastName', '')
    cleaned  = raw_last.lower().replace('-','').replace(\"'\",'')
    if 'dero' in cleaned:
        print(f'raw={raw_last!r} cleaned={cleaned!r}')
        code = 'dderoza'
        print(f'last[:4]={cleaned[:4]!r} in code={cleaned[:4] in code}')
        print(f'code[1:]={code[1:]!r} in last={code[1:] in cleaned}')
"
python3 -c "
import sqlite3, json
conn = sqlite3.connect('/root/kalshi-bot-v2/data/cache.db')
row = conn.execute('SELECT data FROM rosters WHERE team=\"SAC\"').fetchone()
roster = json.loads(row[0])
for a in roster:
    if 'dero' in a.get('lastName','').lower():
        import json as j
        print(j.dumps(a, indent=2)[:300])
"
python3 -c "
from data.persistent_cache import get_roster

espn_team = 'SAC'
player_code = 'dderoza'

roster = get_roster(espn_team, max_age_secs=86400)
print(f'Roster size: {len(roster)}')

code = player_code.replace('-','').replace(\"'\",'')
for athlete in roster:
    last = athlete.get('lastName', '').lower().replace('-','').replace(\"'\",'')
    full = athlete.get('fullName', '')
    
    c1 = code.endswith(last)
    c2 = last in code
    c3 = len(last) >= 4 and last[:4] in code
    c4 = len(code) >= 4 and code[:4] in last
    
    if any([c1,c2,c3,c4]):
        print(f'MATCH: {full} last={last}')
        print(f'  c1={c1} c2={c2} c3={c3} c4={c4}')
        break
" 2>&1 | grep -v DEBUG
sed -n '85,175p' /root/kalshi-bot-v2/data/nba_stats.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''        except Exception as e:
            log.warning(f"[NBAStats] Roster fetch failed {espn_team}: {e}")
            return (None, None)


def _cached_find_player(espn_team: str, player_code: str) -> tuple:
    """Wrapper around _find_player with persistent ID caching."""
    key = f"{espn_team}_{player_code}"
    espn_id, full_name = get_player_id(key)
    if espn_id:
        return espn_id, full_name
    result = _find_player(espn_team, player_code)
    if result is None:
        return (None, None)
    espn_id, full_name = result
    if espn_id:
        set_player_id(key, espn_id, full_name)
    return espn_id, full_name

    # Match player_code against last names
    for athlete in roster:'''

new = '''        except Exception as e:
            log.warning(f"[NBAStats] Roster fetch failed {espn_team}: {e}")
            return (None, None)

    # Match player_code against last names
    for athlete in roster:'''

c = c.replace(old, new)

# Now add _cached_find_player after _find_player's closing return
old2 = '''    return (None, None)


def get_injury_status'''

new2 = '''    return (None, None)


def _cached_find_player(espn_team: str, player_code: str) -> tuple:
    """Wrapper around _find_player with persistent ID caching."""
    key = f"{espn_team}_{player_code}"
    espn_id, full_name = get_player_id(key)
    if espn_id:
        return espn_id, full_name
    result = _find_player(espn_team, player_code)
    if result is None:
        return (None, None)
    espn_id, full_name = result
    if espn_id:
        set_player_id(key, espn_id, full_name)
    return espn_id, full_name


def get_injury_status'''

c = c.replace(old2, new2, 1)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg
tests = [
    ('DeRozan 15+ pts',   'KXNBAPTS-26MAR29SACBKN-SACDDEROZA0-15'),
    ('Claxton 2+ reb',    'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2'),
    ('Mathurin 2+ reb',   'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2'),
]
for name, ticker in tests:
    r = score_prop_leg(ticker)
    print(f'{name}: conf={r[\"confidence\"]:.2f} avg={r.get(\"avg_stat\",0):.1f} | {r[\"reason\"][:55]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
git add -A && git commit -m "fix: _find_player matching code was outside function scope — major bug fix" && git push origin master
python3 -c "
from data.prop_scanner import scan_edges, build_edge_combo
from functools import reduce
import time

t0 = time.time()
legs = scan_edges()
combo = build_edge_combo(legs)
print(f'Scan: {time.time()-t0:.1f}s | {len(legs)} edge legs')
if combo:
    payout = 1/reduce(lambda a,b: a*b, [l[\"market_price\"] for l in combo], 1.0)
    avg_edge = sum(l[\"edge\"] for l in combo)/len(combo)
    print(f'Combo: {len(combo)} legs | {payout:.1f}x | avg edge={avg_edge:+.3f} | \$5->\${5*payout:.0f}')
    for l in combo:
        print(f'  edge={l[\"edge\"]:+.3f} mkt={l[\"market_price\"]:.2f} | {l[\"reasoning\"][:60]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && python3 -c "
from data.nba_stats import score_prop_leg

legs = [
    ('Kawhi 2+ threes',      'KXNBA3PT-26MAR29LACMIL-LACKLEONARD2-2'),
    ('Garland 6+ assists',   'KXNBAAST-26MAR29LACMIL-LACDGARLAND10-6'),
    ('Collins 10+ pts',      'KXNBAPTS-26MAR29LACMIL-LACJCOLLINS20-10'),
    ('Kawhi 25+ pts',        'KXNBAPTS-26MAR29LACMIL-LACKLEONARD2-25'),
    ('Turner 10+ pts',       'KXNBAPTS-26MAR29LACMIL-LACMTURNER33-10'),
    ('Mathurin 2+ reb',      'KXNBAREB-26MAR29LACMIL-INDBMATHURIN9-2'),
    ('Collins 4+ reb',       'KXNBAREB-26MAR29LACMIL-LACJCOLLINS20-4'),
    ('Herro 2+ threes',      'KXNBA3PT-26MAR29MIAIND-MIATHERRO14-2'),
    ('Wiggins 10+ pts',      'KXNBAPTS-26MAR29MIAIND-MIAAWIGGINS22-10'),
    ('Adebayo 15+ pts',      'KXNBAPTS-26MAR29MIAIND-MIABADEBAYO13-15'),
    ('Kel el Ware 6+ reb',   'KXNBAREB-26MAR29MIAIND-INDKWARE5-6'),
    ('Bane 2+ threes',       'KXNBA3PT-26MAR29ORLTORR-TORDBANEE0-2'),
    ('DeRozan 2+ ast',       'KXNBAAST-26MAR29SACBKN-SACDDEROZA0-2'),
    ('Clowney 10+ pts',      'KXNBAPTS-26MAR29SACBKN-BKNNCLOWNEY0-10'),
    ('DeRozan 15+ pts',      'KXNBAPTS-26MAR29SACBKN-SACDDEROZA0-15'),
    ('Claxton 2+ reb',       'KXNBAREB-26MAR29SACBKN-BKNNCLAXTONN0-2'),
    ('Knueppel 15+ pts',     'KXNBAPTS-26MAR29BOSCHA-CHAKKNUEPPEL7-15'),
    ('LaMelo 15+ pts',       'KXNBAPTS-26MAR29BOSCHA-CHALBALL1-15'),
    ('Miles Bridges 10+ pts','KXNBAPTS-26MAR29BOSCHA-CHAMBRIDGES8-10'),
    ('Aaron Gordon 10+ pts', 'KXNBAPTS-26MAR30GSDEN-DENAGORDON15-10'),
    ('Jokic 20+ pts',        'KXNBAPTS-26MAR30GSDEN-DENNJOKIC15-20'),
]

from functools import reduce
results = []
for name, ticker in legs:
    r = score_prop_leg(ticker)
    conf = r.get('confidence', 0)
    avg  = r.get('avg_stat', 0)
    hr   = r.get('reason','')
    hr_str = hr.split('hr=')[1].split(')')[0] if 'hr=' in hr else '?'
    results.append((name, conf, avg, hr_str))

print(f'{'Leg':<25} {'Avg':>5} {'HR':>5} {'Conf':>6} {'Verdict'}')
print('-'*60)
true_prob = 1.0
for name, conf, avg, hr in results:
    flag = '✅' if conf >= 0.75 else '⚠️ ' if conf >= 0.65 else '❌'
    true_prob *= conf if conf > 0 else 0.45
    print(f'{name:<25} {avg:>5.1f} {hr:>5} {conf:>6.2f} {flag}')

print('-'*60)
print(f'True probability: {true_prob*100:.3f}%')
print(f'Market implied:   0.43%')
print(f'EV: {true_prob * 1162/4.97:.2f}x (>1.0 = positive EV)')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''# Combo sizing
MIN_COMBO_LEGS       = 6
MAX_COMBO_LEGS       = 12
MIN_COMBINED_CONF    = 0.005   # 2% floor
MIN_PAYOUT_MULT      = 15.0    # Minimum expected payout multiplier'''

new = '''# Combo sizing — MOONSHOT mode (default)
MIN_COMBO_LEGS       = 6
MAX_COMBO_LEGS       = 12
MIN_COMBINED_CONF    = 0.005
MIN_PAYOUT_MULT      = 15.0

# HIGH CONFIDENCE mode thresholds
HC_MIN_CONF          = 0.82    # Only legs with 82%+ model confidence
HC_MAX_LEGS          = 30      # No cap — take all qualifying legs
HC_MIN_PAYOUT        = 2.0     # Low payout floor, we want hit rate'''

c = c.replace(old, new)

old2 = '''def build_best_combo(legs: list[ComboLeg]) -> Optional[ComboCandidate]:
    """
    Build the best combo from available legs.
    Pick legs that maximize payout while keeping combined confidence above floor.
    """
    if len(legs) < MIN_COMBO_LEGS:
        log.info(f"[Combo] Not enough legs: {len(legs)} < {MIN_COMBO_LEGS}")
        return None

    # Take top legs by payout contribution up to MAX_COMBO_LEGS
    selected = legs[:MAX_COMBO_LEGS]

    candidate = ComboCandidate(MVE_COLLECTION, selected)

    if candidate.combined_confidence < MIN_COMBINED_CONF:
        log.info(f"[Combo] Combined conf too low: {candidate.combined_confidence:.3f}")
        return None

    if candidate.expected_payout < MIN_PAYOUT_MULT:
        log.info(f"[Combo] Payout too low: {candidate.expected_payout:.1f}x")
        return None

    log.info(f"[Combo] CANDIDATE: {len(selected)} legs, "
             f"conf={candidate.combined_confidence:.3f}, "
             f"payout={candidate.expected_payout:.1f}x")
    for leg in selected:
        log.info(f"  {leg.ticker} yes={leg.implied_prob:.2f} conf={leg.confidence:.2f} | {leg.reasoning[:60]}")

    return candidate'''

new2 = '''def build_best_combo(legs: list[ComboLeg]) -> Optional[ComboCandidate]:
    """
    MOONSHOT mode: maximize payout, top 12 edge-sorted legs.
    """
    if len(legs) < MIN_COMBO_LEGS:
        log.info(f"[Combo] Not enough legs: {len(legs)} < {MIN_COMBO_LEGS}")
        return None

    selected  = legs[:MAX_COMBO_LEGS]
    candidate = ComboCandidate(MVE_COLLECTION, selected)

    if candidate.combined_confidence < MIN_COMBINED_CONF:
        log.info(f"[Combo] Combined conf too low: {candidate.combined_confidence:.3f}")
        return None

    if candidate.expected_payout < MIN_PAYOUT_MULT:
        log.info(f"[Combo] Payout too low: {candidate.expected_payout:.1f}x")
        return None

    log.info(f"[Combo] MOONSHOT: {len(selected)} legs, "
             f"conf={candidate.combined_confidence:.3f}, "
             f"payout={candidate.expected_payout:.1f}x")
    for leg in selected:
        log.info(f"  {leg.ticker} yes={leg.implied_prob:.2f} conf={leg.confidence:.2f} | {leg.reasoning[:60]}")

    return candidate


def build_highconf_combo(legs: list[ComboLeg]) -> Optional[ComboCandidate]:
    """
    HIGH CONFIDENCE mode: take ALL legs above confidence threshold.
    Maximizes hit rate over payout size.
    """
    # Filter to only high confidence legs, sorted by confidence desc
    hc_legs = sorted(
        [l for l in legs if l.confidence >= HC_MIN_CONF],
        key=lambda x: x.confidence,
        reverse=True
    )[:HC_MAX_LEGS]

    if len(hc_legs) < 2:
        log.info(f"[Combo] HC: not enough high-conf legs ({len(hc_legs)})")
        return None

    candidate = ComboCandidate(MVE_COLLECTION, hc_legs)

    if candidate.expected_payout < HC_MIN_PAYOUT:
        log.info(f"[Combo] HC payout too low: {candidate.expected_payout:.1f}x")
        return None

    log.info(f"[Combo] HIGH CONF: {len(hc_legs)} legs, "
             f"conf={candidate.combined_confidence:.3f}, "
             f"payout={candidate.expected_payout:.1f}x")
    for leg in hc_legs:
        log.info(f"  {leg.ticker} yes={leg.implied_prob:.2f} conf={leg.confidence:.2f} | {leg.reasoning[:60]}")

    return candidate'''

c = c.replace(old2, new2)

old3 = '''def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
    """
    Main entry point. Scan all props, build best combo, execute if EV+.
    """
    log.info("[Combo] Starting combo scan")
    candidates = []

    if not dry_run and already_traded_today():
        log.info("[Combo] Already placed a combo today — skipping")
        return candidates

    legs      = scan_all_props()
    candidate = build_best_combo(legs)

    if not candidate:
        log.info("[Combo] No valid combo found")
        return candidates

    candidates.append(candidate)

    if dry_run:
        log.info(f"[Combo] DRY RUN — would submit RFQ")
        return candidates

    quote = submit_rfq(candidate)
    if quote:
        log.info(f"[Combo] EXECUTED")
        _log_combo_trade(candidate, quote)

    return candidates'''

new3 = '''def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
    """
    Main entry point. Runs both MOONSHOT and HIGH CONFIDENCE combos.
    """
    log.info("[Combo] Starting combo scan — MOONSHOT + HIGH CONF modes")
    candidates = []
    legs       = scan_all_props()

    # ── MOONSHOT combo ─────────────────────────────────────────────────
    moonshot = build_best_combo(legs)
    if moonshot:
        candidates.append(moonshot)
        if not dry_run:
            log.info("[Combo] Submitting MOONSHOT RFQ...")
            quote = submit_rfq(moonshot)
            if quote:
                log.info("[Combo] MOONSHOT EXECUTED")
                _log_combo_trade(moonshot, quote, mode="moonshot")

    # ── HIGH CONFIDENCE combo ──────────────────────────────────────────
    highconf = build_highconf_combo(legs)
    if highconf:
        candidates.append(highconf)
        if not dry_run:
            log.info("[Combo] Submitting HIGH CONF RFQ...")
            quote = submit_rfq(highconf)
            if quote:
                log.info("[Combo] HIGH CONF EXECUTED")
                _log_combo_trade(highconf, quote, mode="highconf")

    if not candidates:
        log.info("[Combo] No valid combos found")

    return candidates'''

c = c.replace(old3, new3)

# Update _log_combo_trade to accept mode
old4 = '''def _log_combo_trade(candidate: ComboCandidate, quote: dict):'''
new4 = '''def _log_combo_trade(candidate: ComboCandidate, quote: dict, mode: str = "moonshot"):'''
c = c.replace(old4, new4)

old5 = '''    entry = {
        "time":               datetime.now(timezone.utc).isoformat(),
        "collection_ticker":  candidate.collection_ticker,'''
new5 = '''    entry = {
        "time":               datetime.now(timezone.utc).isoformat(),
        "mode":               mode,
        "collection_ticker":  candidate.collection_ticker,'''
c = c.replace(old5, new5)

open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
from functools import reduce

legs     = scan_all_props()
moonshot = build_best_combo(legs)
highconf = build_highconf_combo(legs)

if moonshot:
    p = moonshot.expected_payout
    print(f'MOONSHOT:  {len(moonshot.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} | conf={moonshot.combined_confidence:.3f}')

if highconf:
    p = highconf.expected_payout
    print(f'HIGH CONF: {len(highconf.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} | conf={highconf.combined_confidence:.3f}')
    print('Legs:')
    for l in highconf.legs:
        print(f'  conf={l.confidence:.2f} | {l.reasoning[:60]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
grep -n "build_highconf_combo\|HIGH CONF\|HC_MIN_CONF" /root/kalshi-bot-v2/combo_scanner.py | head -10
cat >> /root/kalshi-bot-v2/combo_scanner.py << 'PYEOF'


def build_highconf_combo(legs: list[ComboLeg]) -> Optional[ComboCandidate]:
    """
    HIGH CONFIDENCE mode: take ALL legs above confidence threshold.
    Maximizes hit rate over payout size.
    """
    hc_legs = sorted(
        [l for l in legs if l.confidence >= HC_MIN_CONF],
        key=lambda x: x.confidence,
        reverse=True
    )[:HC_MAX_LEGS]

    if len(hc_legs) < 2:
        log.info(f"[Combo] HC: not enough high-conf legs ({len(hc_legs)})")
        return None

    candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', hc_legs)

    if candidate.expected_payout < HC_MIN_PAYOUT:
        log.info(f"[Combo] HC payout too low: {candidate.expected_payout:.1f}x")
        return None

    log.info(f"[Combo] HIGH CONF: {len(hc_legs)} legs, "
             f"conf={candidate.combined_confidence:.3f}, "
             f"payout={candidate.expected_payout:.1f}x")
    for leg in hc_legs:
        log.info(f"  conf={leg.confidence:.2f} | {leg.reasoning[:60]}")

    return candidate
PYEOF

python3 -c "
from combo_scanner import scan_all_props, build_best_combo, build_highconf_combo
from functools import reduce

legs     = scan_all_props()
moonshot = build_best_combo(legs)
highconf = build_highconf_combo(legs)

if moonshot:
    p = moonshot.expected_payout
    print(f'MOONSHOT:  {len(moonshot.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} | conf={moonshot.combined_confidence:.3f}')

if highconf:
    p = highconf.expected_payout
    print(f'HIGH CONF: {len(highconf.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} | conf={highconf.combined_confidence:.3f}')
    for l in highconf.legs:
        print(f'  conf={l.confidence:.2f} | {l.reasoning[:55]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '''    import re as _re
    # Filter high conf legs, dedupe by player (one leg per player total)
    seen_players = {}
    for l in sorted(legs, key=lambda x: x.confidence, reverse=True):
        if l.confidence < HC_MIN_CONF:
            continue
        pm = _re.search(
            r\'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|\'
            r\'CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)\'
            r\'[A-Z0-9]+)-\', l.ticker
        )
        player_key = pm.group(1) if pm else l.ticker
        if player_key not in seen_players:
            seen_players[player_key] = l
    hc_legs = list(seen_players.values())[:HC_MAX_LEGS]''',
    '''    import re as _re
    # Filter high conf legs, dedupe by player+stat (one threshold per stat per player)
    seen = {}
    for l in sorted(legs, key=lambda x: x.confidence, reverse=True):
        if l.confidence < HC_MIN_CONF:
            continue
        series = l.ticker.split(\'-\')[0]  # e.g. KXNBAPTS
        pm = _re.search(
            r\'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|\'
            r\'CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)\'
            r\'[A-Z0-9]+)-\', l.ticker
        )
        player_key = pm.group(1) if pm else l.ticker
        key = f\'{series}-{player_key}\'  # unique per player per stat
        if key not in seen:
            seen[key] = l
    hc_legs = list(seen.values())[:HC_MAX_LEGS]'''
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
legs     = scan_all_props()
highconf = build_highconf_combo(legs)
if highconf:
    p = highconf.expected_payout
    print(f'HIGH CONF: {len(highconf.legs)} legs | {p:.1f}x | \$5->\${5*p:.0f} | conf={highconf.combined_confidence:.4f}')
    for l in highconf.legs:
        print(f'  conf={l.confidence:.2f} | {l.reasoning[:60]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
git add -A && git commit -m "feat: high confidence combo mode — all 90%+ legs, one per player per stat" && git push origin master
python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Dynamic|RFQ|Quote|No quote|EXECUTED" | head -20
grep "yes_bid.*0.05\|MIN.*quote\|>= 0.05\|>= 0.02" /root/kalshi-bot-v2/combo_scanner.py | head -5
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) > 0 and q.get(\'status\')==\'open\']'''
new = '''            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) >= 0.05 and q.get(\'status\')==\'open\']'''
c = c.replace(old, new)

open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

grep "yes_bid" /root/kalshi-bot-v2/combo_scanner.py | grep "0.05\|0.02"
python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
print(f'Total combos placed: {len(trades)}')
for t in trades[-3:]:
    mode = t.get('mode', 'unknown')
    legs = len(t.get('legs', []))
    quote = t.get('quote', {})
    bid = quote.get('yes_bid_dollars', '?')
    print(f'  {t[\"time\"][:16]} | {mode} | {legs} legs | bid=\${bid}')
"
grep -n "MOONSHOT\|HIGH CONF\|build_highconf\|build_best" /root/kalshi-bot-v2/combo_scanner.py | tail -20
sed -n '550,590p' /root/kalshi-bot-v2/combo_scanner.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
    """
    Main entry point. Scan all props, build best combo, execute if EV+.
    """
    log.info("[Combo] Starting combo scan")
    candidates = []

    legs      = scan_all_props()
    candidate = build_best_combo(legs)

    if not candidate:
        log.info("[Combo] No valid combo found")
        return candidates

    candidates.append(candidate)

    if dry_run:
        log.info(f"[Combo] DRY RUN — would submit RFQ")
        return candidates

    quote = submit_rfq(candidate)
    if quote:
        log.info(f"[Combo] EXECUTED")
        _log_combo_trade(candidate, quote)

    return candidates'''

new = '''def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
    """
    Main entry point. Runs MOONSHOT + HIGH CONFIDENCE combos.
    """
    log.info("[Combo] Starting combo scan — MOONSHOT + HIGH CONF modes")
    candidates = []
    legs       = scan_all_props()

    # ── MOONSHOT ───────────────────────────────────────────────────────
    moonshot = build_best_combo(legs)
    if moonshot:
        candidates.append(moonshot)
        if dry_run:
            log.info(f"[Combo] DRY RUN — MOONSHOT {len(moonshot.legs)} legs {moonshot.expected_payout:.1f}x")
        else:
            log.info("[Combo] Submitting MOONSHOT...")
            quote = submit_rfq(moonshot)
            if quote:
                log.info("[Combo] MOONSHOT EXECUTED")
                _log_combo_trade(moonshot, quote, mode="moonshot")

    # ── HIGH CONFIDENCE ────────────────────────────────────────────────
    highconf = build_highconf_combo(legs)
    if highconf:
        candidates.append(highconf)
        if dry_run:
            log.info(f"[Combo] DRY RUN — HIGH CONF {len(highconf.legs)} legs {highconf.expected_payout:.1f}x")
        else:
            log.info("[Combo] Submitting HIGH CONF...")
            quote = submit_rfq(highconf)
            if quote:
                log.info("[Combo] HIGH CONF EXECUTED")
                _log_combo_trade(highconf, quote, mode="highconf")

    if not candidates:
        log.info("[Combo] No valid combos found")

    return candidates'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py 2>&1 | grep -E "MOONSHOT|HIGH CONF|DRY RUN|No valid"
grep -n "HC_MAX_LEGS\|HC_MIN_CONF\|HC_MIN_PAYOUT" /root/kalshi-bot-v2/combo_scanner.py
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo, HC_MIN_CONF
legs = scan_all_props()
hc = [l for l in legs if l.confidence >= HC_MIN_CONF]
print(f'Total legs: {len(legs)}')
print(f'HC qualified (>={HC_MIN_CONF}): {len(hc)}')
if hc:
    for l in hc[:5]:
        print(f'  conf={l.confidence:.2f} price={l.implied_prob:.2f} | {l.reasoning[:50]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from combo_scanner import scan_all_props, HC_MIN_CONF, HC_MAX_LEGS, HC_MIN_PAYOUT
from combo_scanner import ComboCandidate
import re

legs = scan_all_props()

# Replicate build_highconf_combo logic
seen = {}
for l in sorted(legs, key=lambda x: x.confidence, reverse=True):
    if l.confidence < HC_MIN_CONF:
        continue
    series = l.ticker.split('-')[0]
    pm = re.search(r'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-', l.ticker)
    player_key = pm.group(1) if pm else l.ticker
    key = f'{series}-{player_key}'
    if key not in seen:
        seen[key] = l

hc_legs = list(seen.values())[:HC_MAX_LEGS]
print(f'HC legs after dedup: {len(hc_legs)}')

candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', hc_legs)
print(f'Payout: {candidate.expected_payout:.1f}x')
print(f'Min payout required: {HC_MIN_PAYOUT}')
print(f'Passes: {candidate.expected_payout >= HC_MIN_PAYOUT}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "from combo_scanner import build_highconf_combo; print('OK')"
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
legs = scan_all_props()
print(f'Legs: {len(legs)}')
result = build_highconf_combo(legs)
print(f'Result: {result}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
grep -n "def scan_and_execute\|def build_highconf_combo\|def build_best_combo" /root/kalshi-bot-v2/combo_scanner.py
sed -n '553,620p' /root/kalshi-bot-v2/combo_scanner.py
python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
from combo_scanner import scan_and_execute
scan_and_execute(dry_run=True)
" 2>&1 | grep -E "MOONSHOT|HIGH|Combo|valid"
git add -A && git commit -m "feat: dual combo modes — MOONSHOT 12-leg + HIGH CONF 30-leg, min quote 5c" && git push origin master
screen -S combo -X quit
screen -S combo bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 combo_scheduler.py; exec bash'
cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 combo_scanner.py --live 2>&1 | grep -E "MOONSHOT|HIGH CONF|Dynamic|RFQ|Quote|No quote|EXECUTED|legs" | head -20
python3 -c "
from data.prop_scanner import scan_edges
from combo_scanner import build_highconf_combo, scan_all_props, HC_MIN_CONF
import re

legs = scan_all_props()
hc   = build_highconf_combo(legs)

if not hc:
    print('No HC combo')
else:
    print(f'HIGH CONF: {len(hc.legs)} legs | {hc.expected_payout:.1f}x | \$5->\${5*hc.expected_payout:.0f}')
    print()
    
    # Group by game
    games = {}
    for l in hc.legs:
        m = re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', l.ticker.split('-')[1])
        code = m.group(1) if m else '??????'
        t1, t2 = code[:3], code[3:6]
        game = f'{t1} vs {t2}'
        games.setdefault(game, []).append(l)
    
    for game, game_legs in games.items():
        print(f'{game}:')
        for l in game_legs:
            thr    = l.ticker.split('-')[-1]
            series = l.ticker.split('-')[0]
            stat   = {'KXNBAPTS':'pts','KXNBAREB':'reb','KXNBAAST':'ast','KXNBA3PT':'3s','KXNBASTL':'stl','KXNBABLK':'blk'}.get(series,'?')
            player = l.reasoning.split(' avg')[0]
            price  = int(l.implied_prob * 100)
            hr     = l.reasoning.split('hr=')[1].split(')')[0] if 'hr=' in l.reasoning else '?'
            print(f'  {player} {thr}+ {stat} @ {price}¢  (HR:{hr} conf:{l.confidence:.2f})')
        print()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from combo_scanner import scan_all_props, build_highconf_combo
import re

legs = scan_all_props()
hc   = build_highconf_combo(legs)

if hc:
    print(f'HIGH CONF: {len(hc.legs)} legs | {hc.expected_payout:.1f}x | \$5->\${5*hc.expected_payout:.0f}')
    print()
    games = {}
    for l in hc.legs:
        m = re.search(r'\d{2}[A-Z]{3}\d{2}([A-Z]{6})', l.ticker.split('-')[1])
        code = m.group(1) if m else '??????'
        t1, t2 = code[:3], code[3:6]
        games.setdefault(f'{t1} vs {t2}', []).append(l)
    for game, gl in games.items():
        print(f'{game}:')
        for l in gl:
            thr    = l.ticker.split('-')[-1]
            series = l.ticker.split('-')[0]
            stat   = {'KXNBAPTS':'pts','KXNBAREB':'reb','KXNBAAST':'ast','KXNBA3PT':'3s','KXNBASTL':'stl','KXNBABLK':'blk'}.get(series,'?')
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
