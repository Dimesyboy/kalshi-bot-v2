c = c.replace('LEG_MIN_BID = 0.60',           'LEG_MIN_BID = 0.58')
c = c.replace('LEG_MAX_BID = 0.88',           'LEG_MAX_BID = 0.85')
c = c.replace('MIN_COMBO_LEGS       = 4',     'MIN_COMBO_LEGS       = 6')
c = c.replace('MAX_COMBO_LEGS       = 8',     'MAX_COMBO_LEGS       = 12')
c = c.replace('MIN_COMBINED_CONF    = 0.02',  'MIN_COMBINED_CONF    = 0.005')
c = c.replace('MIN_PAYOUT_MULT      = 5.0',   'MIN_PAYOUT_MULT      = 15.0')

open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

# Quick test
python3 -c "
from combo_scanner import scan_all_props, build_best_combo
from functools import reduce
legs = scan_all_props()
print(f'Total legs: {len(legs)}')
candidate = build_best_combo(legs)
if candidate:
    print(f'Combo: {len(candidate.legs)} legs, {candidate.expected_payout:.1f}x, conf={candidate.combined_confidence:.3f}')
    print(f'\$5 stake -> \${5*candidate.expected_payout:.0f}')
    for l in candidate.legs:
        print(f'  {l.implied_prob:.2f} conf={l.confidence:.2f} | {l.reasoning[:55]}')
else:
    print('No combo found')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 combo_scanner.py --live 2>&1 | grep -E "Combo|Dynamic|RFQ|Quote|Accept|No quote" | head -15
python3 -c "
from data.nba_stats import score_prop_leg, get_injury_status

# Test all legs from the combo
tickers = [
    'KXNBAAST-26MAR29NYKOKC-NYKJBRUNSON11-2',
    'KXNBAREB-26MAR29LACMIL-LACJCOLLINS20-4',
    'KXNBA3PT-26MAR29NYKOKC-NYKPPRITCHARD11-4',
    'KXNBAPTS-26MAR29MIAIND-MIAAWIGGINS22-10',
    'KXNBAREB-26MAR29LACMIL-LACMTURNER33-4',
    'KXNBA3PT-26MAR29LACMIL-LACKLEONARD2-2',
    'KXNBASTL-26MAR29MIAIND-INDBMATHURIN9-1',
    'KXNBA3PT-26MAR29NYKOKC-NYKJHART3-1',
    'KXNBAAST-26MAR29HOUNOP-NOPDQUEEN0-2',
    'KXNBASTL-26MAR29HOUNOP-HOUTEASON9-1',
    'KXNBAAST-26MAR29LACMIL-LACDGARLAND10-2',
    'KXNBAPTS-26MAR29OKCCLE-OKCCJSUGGS14-10',
]
for t in tickers:
    r = score_prop_leg(t)
    injured = r.get('injured', False)
    status_note = ' ⚠️ INJURED' if injured else ''
    print(f'conf={r[\"confidence\"]:.2f}{status_note} | {r[\"reason\"][:65]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.nba_stats import _parse_ticker, _find_player, TEAM_CODE_MAP

tests = [
    'KXNBA3PT-26MAR29NYKOKC-NYKPPRITCHARD11-4',
    'KXNBAREB-26MAR29LACMIL-LACMTURNER33-4',
    'KXNBASTL-26MAR29MIAIND-INDBMATHURIN9-1',
    'KXNBAPTS-26MAR29OKCCLE-OKCCJSUGGS14-10',
]
for t in tests:
    parsed = _parse_ticker(t)
    if parsed:
        team, code = parsed
        espn_team = TEAM_CODE_MAP.get(team, team)
        espn_id, name = _find_player(espn_team, code)
        print(f'{t[-20:]} → team={team} code={code} espn={espn_team} found={name}')
    else:
        print(f'{t[-20:]} → parse failed')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import requests
for team in ['NY', 'LAC', 'IND', 'OKC']:
    r = requests.get(f'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/{team}/roster', timeout=6)
    athletes = r.json().get('athletes', [])
    names = [a.get('lastName','').lower() for a in athletes]
    print(f'{team}: {[n for n in names if any(x in n for x in [\"pritchard\",\"turner\",\"mathurin\",\"suggs\"])]}')
"
python3 -c "
import requests
r = requests.get('https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/OKC/roster', timeout=6)
data = r.json()
print('Keys:', list(data.keys()))
athletes = data.get('athletes', [])
print(f'Athletes: {len(athletes)}')
if athletes:
    print('First:', athletes[0].get('fullName'))
"
python3 -c "
import requests
r = requests.get('https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/OKC/roster', timeout=6)
athletes = r.json().get('athletes', [])
for a in athletes:
    print(a.get('lastName','').lower(), '|', a.get('fullName',''))
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''    # Match player_code against last names
    for athlete in roster:
        last = athlete.get('lastName', '').lower()
        full = athlete.get('fullName', '')

        # Direct last name match
        if player_code.endswith(last) or last in player_code:
            return (athlete['id'], full)

        # Partial match — player_code contains significant part of last name
        if len(last) >= 4 and last[:4] in player_code:
            return (athlete['id'], full)

    return (None, None)'''

new = '''    # Match player_code against last names
    for athlete in roster:
        last = athlete.get('lastName', '').lower().replace('-','').replace("'",'')
        full = athlete.get('fullName', '')
        code = player_code.replace('-','').replace("'",'')

        # Direct last name match
        if code.endswith(last) or last in code:
            return (athlete['id'], full)

        # Partial match — player_code contains significant part of last name
        if len(last) >= 4 and last[:4] in code:
            return (athlete['id'], full)

        # Reverse partial — last name contains player code fragment
        if len(code) >= 4 and code[:4] in last:
            return (athlete['id'], full)

    # Not found on primary team — search all NBA teams (handles trades)
    all_teams = list(TEAM_CODE_MAP.values())
    for team in all_teams:
        if team == espn_team:
            continue
        try:
            r2 = requests.get(f"{ESPN_BASE}/teams/{team}/roster", timeout=4)
            r2.raise_for_status()
            for athlete in r2.json().get('athletes', []):
                last = athlete.get('lastName', '').lower().replace('-','').replace("'",'')
                full = athlete.get('fullName', '')
                code = player_code.replace('-','').replace("'",'')
                if code.endswith(last) or last in code:
                    log.debug(f"[NBAStats] Found {full} on {team} (traded from {espn_team})")
                    return (athlete['id'], full)
                if len(last) >= 4 and last[:4] in code:
                    log.debug(f"[NBAStats] Found {full} on {team} (traded from {espn_team})")
                    return (athlete['id'], full)
        except Exception:
            continue

    return (None, None)'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg
for t in [
    'KXNBA3PT-26MAR29NYKOKC-NYKPPRITCHARD11-4',
    'KXNBAPTS-26MAR29OKCCLE-OKCCJSUGGS14-10',
    'KXNBASTL-26MAR29MIAIND-INDBMATHURIN9-1',
]:
    r = score_prop_leg(t)
    print(f'conf={r[\"confidence\"]:.2f} | {r[\"reason\"][:60]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from combo_scanner import scan_all_props, build_best_combo
legs = scan_all_props()
candidate = build_best_combo(legs)
if candidate:
    print(f'{len(candidate.legs)} legs | {candidate.expected_payout:.1f}x | \$5->\${5*candidate.expected_payout:.0f}')
    for l in candidate.legs:
        print(f'  {l.implied_prob:.2f} conf={l.confidence:.2f} | {l.reasoning[:60]}')
else:
    print('No combo')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.nba_stats import get_injury_status, _find_player, TEAM_CODE_MAP
# Turner is on LAC in this ticker
espn_id, name = _find_player('LAC', 'mturner')
print(f'Found: {name} id={espn_id}')
if espn_id:
    status = get_injury_status(espn_id, 'LAC')
    print(f'Status: {status}')
" 2>&1 | grep -v DEBUG
git add combo_scanner.py data/nba_stats.py && git commit -m "fix: traded player lookup, stronger fuzzy match, 12-leg combos targeting 100x+" && git push origin master && python3 combo_scanner.py --live 2>&1 | grep -E "Combo|Dynamic|RFQ|Quote|Accept|No quote|EXECUTED" | head -15
echo "=== V2 BOT STATUS ===" && systemctl status kalshi-bot-v2 | grep -E "Active|PID" && echo "" && echo "=== SCREENS ===" && screen -ls && echo "" && echo "=== BALANCE ===" && cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 -c "from core.kalshi_client import get_balance; print(f'\${get_balance():.2f}')" && echo "" && echo "=== OPEN POSITIONS ===" && python3 -c "import json; p=json.load(open('data/positions.json')); print(f'{len(p)} open positions')" 2>/dev/null || echo "No positions file" && echo "" && echo "=== RECENT BOT LOG ===" && tail -8 /root/kalshi-bot-v2/kalshi_bot.log && echo "" && echo "=== COMBO TRADES ===" && python3 -c "import json,os; f='data/combo_trades.json'; print(json.dumps(json.load(open(f)), indent=2)[:500]) if os.path.exists(f) else print('No combo trades logged')" && echo "" && echo "=== V2 PAPER STATS ===" && python3 paper_trader.py --stats
grep -n "FileHandler\|StreamHandler\|basicConfig\|addHandler" /root/kalshi-bot-v2/bot.py | head -10
cat > /etc/systemd/system/kalshi-bot-v2.service << 'EOF'
[Unit]
Description=Kalshi Trading Bot v2
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/kalshi-bot-v2
ExecStart=/root/kalshi-bot/bin/python3 /root/kalshi-bot-v2/bot.py
Restart=always
RestartSec=10
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl restart kalshi-bot-v2 && sleep 3 && tail -5 /root/kalshi-bot-v2/kalshi_bot.log
python3 -c "
import json
trades = json.load(open('data/combo_trades.json'))
print(f'Combo trades placed: {len(trades)}')
for t in trades:
    legs = len(t.get('legs',[]))
    cost = t.get('quote',{}).get('rfq_target_cost_dollars','?')
    print(f'  {t[\"time\"][:16]} | {legs} legs | cost=\${cost}')
"
screen -r tgbot
screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
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
                lines.append(f"*V2 Bot (live)*")
                lines.append(f"Trades: {len(rows)} | PNL: ${total_pnl:+.2f}\n")
            else:
                lines.append("*V2 Bot*\\nNo trades yet\\n")'''

c = c.replace(old, new)

# Also add combo stats
old2 = '''            else:
                lines.append("*V2 Paper*\\nNo resolved trades yet")'''

new2 = '''            else:
                lines.append("*V2 Paper*\\nNo resolved trades yet")

            # Combo stats
            combo_file = "/root/kalshi-bot-v2/data/combo_trades.json"
            if os.path.exists(combo_file):
                import json as _json
                combos = _json.load(open(combo_file))
                spent  = len(combos) * 5.0
                lines.append(f"\\n*Combos*\\nPlaced: {len(combos)} | Spent: ${spent:.0f}")'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit
screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
python3 -c "
from data.nba_stats import score_prop_leg
from core.kalshi_client import _signed_get

legs = [
    ('KXNBA3PT-26MAR29LACMIL-INDBMATHURIN9-1',  'Mathurin 1+ threes'),
    ('KXNBA3PT-26MAR29LACMIL-LACDGARLAND10-1',  'Garland 1+ threes'),
    ('KXNBA3PT-26MAR29LACMIL-LACKLEONARD2-3',   'Kawhi 3+ threes'),
    ('KXNBAAST-26MAR29LACMIL-LACDGARLAND10-7',  'Garland 7+ assists'),
    ('KXNBAPTS-26MAR29LACMIL-INDBMATHURIN9-15', 'Mathurin 15+ points'),
    ('KXNBAREB-26MAR29LACMIL-LACJCOLLINS20-8',  'Collins 8+ rebounds'),
    ('KXNBA3PT-26MAR29MIAIND-MIATHERRO14-3',    'Herro 3+ threes'),
    ('KXNBAAST-26MAR29MIAIND-INDDMITCHELL45-4', 'Mitchell 4+ assists'),
    ('KXNBAPTS-26MAR29MIAIND-MIAAWIGGINS22-15', 'Wiggins 15+ points'),
    ('KXNBAPTS-26MAR29MIAIND-MIABADEBAYO13-15', 'Adebayo 15+ points'),
]

from functools import reduce
total_conf = 1.0
print(f'{'Leg':<30} {'Avg':>6} {'Thr':>5} {'Ratio':>6} {'Conf':>6} {'Price':>6}')
print('-'*65)
for ticker, name in legs:
    try:
        r = score_prop_leg(ticker)
        avg   = r.get('avg_stat', 0)
        thr   = r.get('threshold', 0)
        ratio = r.get('ratio', 0)
        conf  = r.get('confidence', 0)
        # get market price
        d = _signed_get(f'/trade-api/v2/markets/{ticker}')
        price = float(d.get('market',{}).get('yes_bid_dollars',0) or 0)
        total_conf *= max(conf, price) if conf > 0 else price
        print(f'{name:<30} {avg:>6.1f} {thr:>5.0f} {ratio:>6.2f} {conf:>6.2f} {price:>5.0%}')
    except Exception as e:
        print(f'{name:<30} ERROR: {e}')
print('-'*65)
print(f'Combined confidence: {total_conf:.4f} = {total_conf*100:.2f}%')
print(f'Expected payout: {1/total_conf:.1f}x')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

# Full prop range for Kawhi and Garland
for event, players in [
    ('KXNBA3PT-26MAR29LACMIL', ['LACKLEONARD2', 'LACDGARLAND10']),
    ('KXNBAPTS-26MAR29LACMIL', ['LACKLEONARD2', 'LACDGARLAND10']),
]:
    data = _signed_get(f'/trade-api/v2/markets?event_ticker={event}&limit=20&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not any(p in ticker for p in players):
            continue
        result = score_prop_leg(ticker)
        conf   = result.get('confidence', 0)
        edge   = conf - yes_bid
        print(f'{ticker[-25:]:25} market={yes_bid:.2f} model={conf:.2f} edge={edge:+.2f}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cat > /root/kalshi-bot-v2/data/prop_scanner.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/prop_scanner.py
─────────────────────────────────────────────────────────────────────────────
Scans all NBA prop markets and finds legs where our model disagrees
with the market price (positive edge).

Edge = model_confidence - market_price

Positive edge = market underpricing the probability = good leg
Negative edge = market overpricing = avoid

For each player+stat combo, picks the threshold with the highest edge.
"""

import logging
import re
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

log = logging.getLogger("kalshi_bot.prop_scanner")

PROP_SERIES = [
    'KXNBAPTS', 'KXNBAREB', 'KXNBAAST',
    'KXNBA3PT', 'KXNBASTL', 'KXNBABLK'
]

# Only consider legs where market price is in this range
# Too cheap = market knows something we don't
# Too expensive = barely adds to payout
MIN_MARKET_PRICE = 0.55
MAX_MARKET_PRICE = 0.92

# Minimum edge to qualify
MIN_EDGE = 0.02

# Minimum model confidence
MIN_CONF = 0.65


def get_player_key(ticker: str) -> str:
    """Extract player+stat key for deduplication."""
    series = ticker.split('-')[0]
    m = re.search(
        r'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|'
        r'CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)'
        r'[A-Z0-9]+)-',
        ticker
    )
    player = m.group(1) if m else ticker
    return f"{series}-{player}"


def scan_edges() -> list[dict]:
    """
    Scan all prop markets and return legs with positive edge,
    best threshold per player per stat.

    Returns list of dicts sorted by edge descending:
    {
        ticker, player_key, market_price, model_conf,
        edge, avg_stat, threshold, ratio, reasoning
    }
    """
    # Collect all markets
    all_markets = []
    for series in PROP_SERIES:
        try:
            data = _signed_get(
                f'/trade-api/v2/markets?series_ticker={series}'
                f'&limit=200&status=open'
            )
            all_markets.extend(data.get('markets', []))
        except Exception as e:
            log.warning(f"[PropScanner] {series} fetch failed: {e}")

    log.info(f"[PropScanner] Scoring {len(all_markets)} markets")

    # Score each market
    candidates = {}  # player_key → best leg dict

    for m in all_markets:
        ticker   = m.get('ticker', '')
        yes_bid  = float(m.get('yes_bid_dollars', 0) or 0)

        if not (MIN_MARKET_PRICE <= yes_bid <= MAX_MARKET_PRICE):
            continue

        result = score_prop_leg(ticker)
        conf   = result.get('confidence', 0.0)

        if conf < MIN_CONF:
            continue

        if result.get('injured'):
            continue

        edge = conf - yes_bid

        if edge < MIN_EDGE:
            continue

        player_key = get_player_key(ticker)

        leg = {
            'ticker':       ticker,
            'player_key':   player_key,
            'market_price': yes_bid,
            'model_conf':   conf,
            'edge':         round(edge, 3),
            'avg_stat':     result.get('avg_stat', 0),
            'threshold':    result.get('threshold', 0),
            'ratio':        result.get('ratio', 0),
            'reasoning':    result.get('reason', ''),
        }

        # Keep best edge per player+stat
        if player_key not in candidates or edge > candidates[player_key]['edge']:
            candidates[player_key] = leg

    results = sorted(candidates.values(), key=lambda x: x['edge'], reverse=True)
    log.info(f"[PropScanner] Found {len(results)} positive-edge legs")
    return results


def build_edge_combo(legs: list[dict], max_legs: int = 12,
                     min_payout: float = 20.0) -> list[dict]:
    """
    Build optimal combo from edge-sorted legs.
    Maximizes combined edge while targeting minimum payout.
    """
    if not legs:
        return []

    selected = []
    combined_price = 1.0

    for leg in legs:
        if len(selected) >= max_legs:
            break
        selected.append(leg)
        combined_price *= leg['market_price']

    payout = 1.0 / combined_price if combined_price > 0 else 0
    if payout < min_payout:
        log.info(f"[PropScanner] Payout {payout:.1f}x below {min_payout}x floor")
        return []

    log.info(f"[PropScanner] Combo: {len(selected)} legs, "
             f"payout={payout:.1f}x, "
             f"avg_edge={sum(l['edge'] for l in selected)/len(selected):.3f}")

    return selected
PYEOF

python3 -c "
from data.prop_scanner import scan_edges, build_edge_combo
legs = scan_edges()
print(f'Positive-edge legs: {len(legs)}')
for l in legs[:10]:
    print(f'  edge={l[\"edge\"]:+.3f} market={l[\"market_price\"]:.2f} model={l[\"model_conf\"]:.2f} | {l[\"reasoning\"][:55]}')
combo = build_edge_combo(legs)
if combo:
    from functools import reduce
    payout = 1/reduce(lambda a,b: a*b, [l[\"market_price\"] for l in combo], 1.0)
    print(f'Combo: {len(combo)} legs, {payout:.1f}x payout')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''def scan_all_props() -> list[ComboLeg]:
    """
    Scan all open NBA prop markets across all games.
    Score each leg, dedupe by player, return sorted by payout contribution.
    """
    import re
    all_legs = []
    seen_players = {}  # player_key → best leg'''

new = '''def scan_all_props() -> list[ComboLeg]:
    """
    Scan all open NBA prop markets using edge-based selection.
    Finds legs where our model disagrees with market price (positive edge).
    Edge = model_confidence - market_price
    """
    from data.prop_scanner import scan_edges
    edge_legs = scan_edges()

    combo_legs = []
    for leg in edge_legs:
        combo_legs.append(ComboLeg(
            ticker            = leg['ticker'],
            collection_ticker = 'KXMVESPORTSMULTIGAMEEXTENDED-R',
            confidence        = leg['model_conf'],
            implied_prob      = leg['market_price'],
            is_yes_only       = True,
            reasoning         = leg['reasoning'],
        ))

    log.info(f"[Combo] {len(combo_legs)} edge-qualified legs")
    return combo_legs


def scan_all_props_legacy() -> list[ComboLeg]:
    """Legacy price-sorted scanner — kept for reference."""
    import re
    all_legs = []
    seen_players = {}  # player_key → best leg'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from combo_scanner import scan_all_props, build_best_combo
legs = scan_all_props()
candidate = build_best_combo(legs)
if candidate:
    payout = candidate.expected_payout
    print(f'{len(candidate.legs)} legs | {payout:.1f}x | \$5->\${5*payout:.0f}')
    for l in candidate.legs:
        print(f'  edge={l.confidence-l.implied_prob:+.2f} mkt={l.implied_prob:.2f} mdl={l.confidence:.2f} | {l.reasoning[:55]}')
else:
    print('No combo')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''        from combo_scanner import scan_all_props, build_best_combo
            legs      = scan_all_props()
            candidate = build_best_combo(legs)'''

new = '''        from combo_scanner import scan_all_props, build_best_combo
            legs      = scan_all_props()
            candidate = build_best_combo(legs)
            # Attach edge info to legs for display
            if candidate:
                for leg in candidate.legs:
                    leg.edge = round(leg.confidence - leg.implied_prob, 3)'''

c = c.replace(old, new)

# Update format_parlay to show edge
old2 = '''            lines.append(f"• {player} {threshold}+ {stat} _{price}¢_ — avg {avg}")'''
new2 = '''            edge_str = f" +{int(getattr(leg, 'edge', 0)*100)}¢ edge" if getattr(leg, 'edge', 0) > 0 else ""
            lines.append(f"• {player} {threshold}+ {stat} _{price}¢_{edge_str} — avg {avg}")'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -S tgbot -X quit && screen -S tgbot bash -c 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py; exec bash'
cd /root/kalshi-bot-v2 && git add -A && git commit -m "feat: edge-based prop scanner — picks legs where model disagrees with market" && git push origin master
cat > /root/kalshi-bot-v2/data/player_stats.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/player_stats.py
─────────────────────────────────────────────────────────────────────────────
Rich player context for prop scoring.

Sources:
    - ESPN game logs (last 10 games, hit rates per threshold)
    - ESPN splits (home/away)
    - Matchup data (opponent defensive rankings)
    - Team pace data
    - Usage when teammates out
"""

import logging
import requests
from data.cache import TTLCache

log     = logging.getLogger("kalshi_bot.player_stats")
cache   = TTLCache(default_ttl=3600)

ESPN_CORE = "https://sports.core.api.espn.com/v2/sports/basketball/leagues/nba"
ESPN_SITE = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"


# ── Last N game hit rates ──────────────────────────────────────────────────

def get_last_n_games(espn_id: str, n: int = 10) -> list[dict]:
    """
    Fetch last N game stats for a player.
    Returns list of game dicts with pts, reb, ast, stl, blk, threes.
    """
    cache_key = f"gamelog_{espn_id}_{n}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        r = requests.get(
            f"{ESPN_CORE}/athletes/{espn_id}/gamelog",
            timeout=8
        )
        r.raise_for_status()
        data   = r.json()
        events = data.get('events', {})

        games = []
        for event_id, event_data in events.items():
            stats = event_data.get('stats', [])
            if not stats:
                continue
            # ESPN gamelog stat order: min,fg,fga,3pt,3pta,ft,fta,oreb,dreb,reb,ast,stl,blk,to,pf,pts
            try:
                s = stats
                game = {
                    'pts':    float(s[15]) if len(s) > 15 else 0,
                    'reb':    float(s[9])  if len(s) > 9  else 0,
                    'ast':    float(s[10]) if len(s) > 10 else 0,
                    'stl':    float(s[11]) if len(s) > 11 else 0,
                    'blk':    float(s[12]) if len(s) > 12 else 0,
                    'threes': float(s[3])  if len(s) > 3  else 0,
                    'min':    float(str(s[0]).split(':')[0]) if s[0] else 0,
                }
                games.append(game)
            except (IndexError, ValueError):
                continue

        games = games[-n:]  # Last N
        cache.set(cache_key, games, ttl=3600)
        return games

    except Exception as e:
        log.warning(f"[PlayerStats] Gamelog fetch failed {espn_id}: {e}")
        return []


def get_hit_rate(espn_id: str, stat: str, threshold: float, n: int = 10) -> float:
    """
    Return fraction of last N games where player exceeded threshold.
    stat: 'pts', 'reb', 'ast', 'stl', 'blk', 'threes'
    """
    games = get_last_n_games(espn_id, n)
    if not games:
        return 0.0
    hits = sum(1 for g in games if g.get(stat, 0) >= threshold)
    return round(hits / len(games), 3)


def get_recent_avg(espn_id: str, stat: str, n: int = 5) -> float:
    """Return average of stat over last N games."""
    games = get_last_n_games(espn_id, n)
    if not games:
        return 0.0
    vals = [g.get(stat, 0) for g in games]
    return round(sum(vals) / len(vals), 2)


# ── Home/Away splits ───────────────────────────────────────────────────────

def get_home_away_splits(espn_id: str) -> dict:
    """
    Return home and away averages for key stats.
    """
    cache_key = f"splits_{espn_id}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        r = requests.get(
            f"{ESPN_CORE}/athletes/{espn_id}/splits",
            timeout=8
        )
        r.raise_for_status()
        data = r.json()

        result = {'home': {}, 'away': {}}
        for split in data.get('splits', {}).get('categories', []):
            for row in split.get('rows', []):
                name = row.get('displayName', '').lower()
                if 'home' in name or 'away' in name:
                    key = 'home' if 'home' in name else 'away'
                    stats = row.get('stats', [])
                    labels = split.get('labels', [])
                    for i, label in enumerate(labels):
                        if i < len(stats):
                            result[key][label.lower()] = stats[i]

        cache.set(cache_key, result, ttl=7200)
        return result

    except Exception as e:
        log.debug(f"[PlayerStats] Splits fetch failed {espn_id}: {e}")
        return {'home': {}, 'away': {}}


# ── Team pace data ─────────────────────────────────────────────────────────

def get_team_pace(team_abbr: str) -> float:
    """
    Return team pace (possessions per game).
    Higher pace = more opportunities for counting stats.
    """
    cache_key = f"pace_{team_abbr}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    try:
        r = requests.get(
            f"{ESPN_SITE}/teams/{team_abbr}/statistics",
            timeout=6
        )
        r.raise_for_status()
        data = r.json()

        for cat in data.get('results', {}).get('stats', {}).get('categories', []):
            for stat in cat.get('stats', []):
                if 'pace' in stat.get('name', '').lower():
                    val = float(stat.get('value', 100))
                    cache.set(cache_key, val, ttl=7200)
                    return val

        cache.set(cache_key, 100.0, ttl=7200)
        return 100.0

    except Exception as e:
        log.debug(f"[PlayerStats] Pace fetch failed {team_abbr}: {e}")
        return 100.0


# ── Opponent defensive rankings ────────────────────────────────────────────

def get_opponent_def_rank(opp_team: str, stat: str) -> int:
    """
    Return opponent's defensive rank for allowing a given stat to position.
    Lower rank = better defense = harder to hit prop.
    Returns 1-30, where 30 = worst defense (easiest for offense).
    """
    cache_key = f"defrank_{opp_team}_{stat}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    # Default middle ranking if we can't fetch
    try:
        r = requests.get(
            f"{ESPN_SITE}/teams/{opp_team}/statistics",
            timeout=6
        )
        r.raise_for_status()
        # Simplified — return 15 (middle) for now, enhance later
        cache.set(cache_key, 15, ttl=7200)
        return 15
    except Exception:
        return 15


# ── Usage boost detection ──────────────────────────────────────────────────

def get_usage_boost(espn_id: str, team_abbr: str, injured_teammates: list) -> float:
    """
    Estimate usage boost when key teammates are out.
    Returns multiplier (1.0 = no boost, 1.15 = 15% boost).
    """
    if not injured_teammates:
        return 1.0

    # Each missing star adds ~5-8% usage boost to remaining players
    # Simplified linear model
    boost = 1.0 + (len(injured_teammates) * 0.06)
    return min(boost, 1.25)  # Cap at 25% boost


# ── Combined context ───────────────────────────────────────────────────────

STAT_MAP = {
    'KXNBAPTS': 'pts',
    'KXNBAREB': 'reb',
    'KXNBAAST': 'ast',
    'KXNBASTL': 'stl',
    'KXNBABLK': 'blk',
    'KXNBA3PT': 'threes',
}

def get_full_context(espn_id: str, series: str, threshold: float,
                     team: str, opp_team: str, is_home: bool,
                     injured_teammates: list) -> dict:
    """
    Get full context for a prop leg.
    Returns rich dict used by confidence model.
    """
    stat = STAT_MAP.get(series, 'pts')

    hit_rate_10  = get_hit_rate(espn_id, stat, threshold, n=10)
    hit_rate_5   = get_hit_rate(espn_id, stat, threshold, n=5)
    recent_avg   = get_recent_avg(espn_id, stat, n=5)
    usage_boost  = get_usage_boost(espn_id, team, injured_teammates)
    def_rank     = get_opponent_def_rank(opp_team, stat)

    # Home/away adjustment
    splits       = get_home_away_splits(espn_id)
    location_key = 'home' if is_home else 'away'

    return {
        'hit_rate_10':      hit_rate_10,   # Hit rate last 10 games
        'hit_rate_5':       hit_rate_5,    # Hit rate last 5 games (recent form)
        'recent_avg':       recent_avg,    # Avg over last 5 games
        'usage_boost':      usage_boost,   # Multiplier from teammate injuries
        'def_rank':         def_rank,      # Opponent defensive rank (1-30)
        'is_home':          is_home,
        'stat':             stat,
        'threshold':        threshold,
    }
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/player_stats.py) lines"
python3 -c "
from data.nba_stats import _find_player
from data.player_stats import get_last_n_games, get_hit_rate, get_recent_avg

# Test with KAT
espn_id, name = _find_player('NY', 'ktowns')
print(f'Player: {name} id={espn_id}')
games = get_last_n_games(espn_id, 10)
print(f'Last 10 games fetched: {len(games)}')
if games:
    print(f'Last game: {games[-1]}')
    print(f'Hit rate 15+ pts last 10: {get_hit_rate(espn_id, \"pts\", 15)}')
    print(f'Recent avg pts (last 5): {get_recent_avg(espn_id, \"pts\", 5)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import requests

espn_id = '3136195'  # KAT

urls = [
    f'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/athletes/{espn_id}/gamelog',
    f'https://sports.core.api.espn.com/v2/sports/basketball/leagues/nba/seasons/2026/athletes/{espn_id}/eventlog',
    f'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog',
]
for url in urls:
    r = requests.get(url, timeout=6)
    print(f'{r.status_code} {url[-60:]}')
    if r.status_code == 200:
        data = r.json()
        print(list(data.keys())[:5])
"
python3 -c "
import requests, json

espn_id = '3136195'

# Check the common/v3 gamelog
r = requests.get(
    f'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog',
    timeout=6
)
data = r.json()
print('Labels:', data.get('labels', []))
print('Names:', data.get('names', []))
events = data.get('events', {})
print(f'Events type: {type(events)}')
if isinstance(events, dict):
    first_key = list(events.keys())[0]
    print(f'First event: {json.dumps(events[first_key], indent=2)[:400]}')
elif isinstance(events, list):
    print(f'First event: {json.dumps(events[0], indent=2)[:400]}')
"
python3 -c "
import requests, json

espn_id = '3136195'
r = requests.get(
    f'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog',
    timeout=6
)
data = r.json()
events = data.get('events', {})
first_key = list(events.keys())[0]
event = events[first_key]
print(json.dumps(event, indent=2)[:800])
"
python3 -c "
import requests, json

espn_id = '3136195'
r = requests.get(
    f'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog',
    timeout=6
)
data = r.json()
# Check top level keys more carefully
print('Top keys:', list(data.keys()))
print('Filters:', data.get('filters', [{}])[0].get('displayName',''))
events = data.get('events', {})
first_key = list(events.keys())[0]
event = events[first_key]
print('Event keys:', list(event.keys()))
# Look for stats
for k,v in event.items():
    if isinstance(v, list) and len(v) > 5:
        print(f'{k}: {v[:5]}')
"
python3 -c "
import requests, json

espn_id = '3136195'
r = requests.get(
    f'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog',
    timeout=6
)
data = r.json()
season_types = data.get('seasonTypes', [])
print(f'Season types: {len(season_types)}')
if season_types:
    st = season_types[0]
    print('ST keys:', list(st.keys()))
    categories = st.get('categories', [])
    print(f'Categories: {len(categories)}')
    if categories:
        cat = categories[0]
        print('Cat keys:', list(cat.keys()))
        events = cat.get('events', [])
        print(f'Events: {len(events)}')
        if events:
            print('First event keys:', list(events[0].keys()))
            print('Stats:', events[0].get('stats', [])[:5])
"
Season types: 2
ST keys: ['displayName', 'displayTeam', 'categories', 'summary']
Categories: 6
Cat keys: ['displayName', 'type', 'splitType', 'events', 'totals']
Events: 13
First event keys: ['eventId', 'stats']
Stats: ['22', '5-8', '62.5', '1-1', '100.0']
(kalshi-bot) root@Kalshi-bot:~/kalshi-bot-v2# ^C
(kalshi-bot) root@Kalshi-bot:~/kalshi-bot-v2#
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/player_stats.py', 'r')
c = f.read()
f.close()

old = '''    try:
        r = requests.get(
            f"{ESPN_CORE}/athletes/{espn_id}/gamelog",
            timeout=8
        )
        r.raise_for_status()
        data   = r.json()
        events = data.get('events', {})

        games = []
        for event_id, event_data in events.items():
            stats = event_data.get('stats', [])
            if not stats:
                continue
            # ESPN gamelog stat order: min,fg,fga,3pt,3pta,ft,fta,oreb,dreb,reb,ast,stl,blk,to,pf,pts
            try:
                s = stats
                game = {
                    'pts':    float(s[15]) if len(s) > 15 else 0,
                    'reb':    float(s[9])  if len(s) > 9  else 0,
                    'ast':    float(s[10]) if len(s) > 10 else 0,
                    'stl':    float(s[11]) if len(s) > 11 else 0,
                    'blk':    float(s[12]) if len(s) > 12 else 0,
                    'threes': float(s[3])  if len(s) > 3  else 0,
                    'min':    float(str(s[0]).split(':')[0]) if s[0] else 0,
                }
                games.append(game)
            except (IndexError, ValueError):
                continue

        games = games[-n:]  # Last N
        cache.set(cache_key, games, ttl=3600)
        return games

    except Exception as e:
        log.warning(f"[PlayerStats] Gamelog fetch failed {espn_id}: {e}")
        return []'''

new = '''    try:
        r = requests.get(
            f"https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/{espn_id}/gamelog",
            timeout=8
        )
        r.raise_for_status()
        data = r.json()

        # Labels: MIN,FG,FG%,3PT,3P%,FT,FT%,REB,AST,BLK,STL,PF,TO,PTS
        # Index:   0   1  2   3   4   5  6   7   8   9   10  11 12  13
        games = []
        for season_type in data.get('seasonTypes', []):
            if 'regular' not in season_type.get('displayName','').lower():
                continue
            for category in season_type.get('categories', []):
                if category.get('type') != 'total':
                    continue
                for event in category.get('events', []):
                    stats = event.get('stats', [])
                    if len(stats) < 14:
                        continue
                    try:
                        def parse_made(s):
                            # Handle "1-3" format or plain number
                            return float(str(s).split('-')[0]) if '-' in str(s) else float(s or 0)
                        game = {
                            'pts':    float(stats[13] or 0),
                            'reb':    float(stats[7]  or 0),
                            'ast':    float(stats[8]  or 0),
                            'blk':    float(stats[9]  or 0),
                            'stl':    float(stats[10] or 0),
                            'threes': parse_made(stats[3]),
                            'min':    float(str(stats[0]).split(':')[0] or 0),
                        }
                        games.append(game)
                    except (IndexError, ValueError):
                        continue

        games = games[-n:]
        cache.set(cache_key, games, ttl=3600)
        return games

    except Exception as e:
        log.warning(f"[PlayerStats] Gamelog fetch failed {espn_id}: {e}")
        return []'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/player_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import _find_player
from data.player_stats import get_last_n_games, get_hit_rate, get_recent_avg

espn_id, name = _find_player('NY', 'ktowns')
print(f'Player: {name}')
games = get_last_n_games(espn_id, 10)
print(f'Games fetched: {len(games)}')
if games:
    print(f'Last 3 games:')
    for g in games[-3:]:
        print(f'  pts={g[\"pts\"]} reb={g[\"reb\"]} ast={g[\"ast\"]} 3s={g[\"threes\"]}')
    print(f'Hit rate 15+ pts: {get_hit_rate(espn_id, \"pts\", 15)}')
    print(f'Recent avg pts (L5): {get_recent_avg(espn_id, \"pts\", 5)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import requests, json

r = requests.get(
    'https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/3136195/gamelog',
    timeout=6
)
data = r.json()
for st in data.get('seasonTypes', []):
    print(f'SeasonType: {st[\"displayName\"]}')
    for cat in st.get('categories', []):
        events = cat.get('events', [])
        print(f'  Cat: {cat[\"displayName\"]} type={cat[\"type\"]} events={len(events)}')
        if events:
            print(f'  First stats: {events[0].get(\"stats\", [])[:5]}')
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/player_stats.py', 'r')
c = f.read()
f.close()

old = "            if category.get('type') != 'total':\n                    continue"
new = "            if category.get('type') != 'event':\n                    continue"

c = c.replace(old, new)

# Also fix regular season filter
old2 = "            if 'regular' not in season_type.get('displayName','').lower():"
new2 = "            if 'preseason' in season_type.get('displayName','').lower():"

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/data/player_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import _find_player
from data.player_stats import get_last_n_games, get_hit_rate, get_recent_avg

espn_id, name = _find_player('NY', 'ktowns')
games = get_last_n_games(espn_id, 10)
print(f'{name} — {len(games)} games')
for g in games[-3:]:
    print(f'  pts={g[\"pts\"]} reb={g[\"reb\"]} 3s={g[\"threes\"]} ast={g[\"ast\"]}')
print(f'Hit 15+ pts: {get_hit_rate(espn_id, \"pts\", 15)} ({int(get_hit_rate(espn_id, \"pts\", 15)*10)}/10)')
print(f'L5 avg pts: {get_recent_avg(espn_id, \"pts\", 5)}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''    # Confidence based on ratio
    if ratio >= 2.0:
        confidence = 0.88
    elif ratio >= 1.7:
        confidence = 0.82
    elif ratio >= 1.5:
        confidence = 0.76
    elif ratio >= 1.3:
        confidence = 0.70
    else:
        confidence = 0.0  # Too close — skip

    # Apply questionable penalty
    injury_note = ""
    if confidence > 0:
        parsed2 = _parse_ticker(ticker)
        espn_id2 = avgs.get("espn_id", "")
        if parsed2 and espn_id2:
            team_code2 = parsed2[0]
            espn_team2 = TEAM_CODE_MAP.get(team_code2, team_code2)
            status2    = get_injury_status(espn_id2, espn_team2)
            if status2 == "questionable":
                confidence = round(max(0, confidence - 0.10), 2)
                injury_note = " [questionable]"

    reason = (f"{avgs[\'player_name\']} avg {avg_stat:.1f} vs threshold {threshold} "
              f"(ratio={ratio:.2f}) → conf={confidence:.2f}{injury_note}")'''

new = '''    # ── Hit rate from last 10 games (primary signal) ──────────────────
    hit_rate   = 0.0
    recent_avg = 0.0
    espn_id2   = avgs.get("espn_id", "")
    stat_key   = {"KXNBAPTS":"pts","KXNBAREB":"reb","KXNBAAST":"ast",
                  "KXNBASTL":"stl","KXNBABLK":"blk","KXNBA3PT":"threes"}.get(series,"pts")
    if espn_id2:
        try:
            from data.player_stats import get_hit_rate as _hit_rate, get_recent_avg as _recent_avg
            hit_rate   = _hit_rate(espn_id2, stat_key, threshold, n=10)
            recent_avg = _recent_avg(espn_id2, stat_key, n=5)
        except Exception:
            pass

    # ── Confidence model ───────────────────────────────────────────────
    # Use hit rate as primary signal if we have it, ratio as fallback
    if hit_rate > 0:
        # Blend hit rate (70%) with ratio-based confidence (30%)
        if ratio >= 2.0:   ratio_conf = 0.88
        elif ratio >= 1.7: ratio_conf = 0.82
        elif ratio >= 1.5: ratio_conf = 0.76
        elif ratio >= 1.3: ratio_conf = 0.70
        else:              ratio_conf = 0.60

        confidence = round(hit_rate * 0.70 + ratio_conf * 0.30, 3)

        # Minimum threshold — don\'t include legs below 65%
        if confidence < 0.65:
            confidence = 0.0
    else:
        # Fallback to ratio only
        if ratio >= 2.0:   confidence = 0.88
        elif ratio >= 1.7: confidence = 0.82
        elif ratio >= 1.5: confidence = 0.76
        elif ratio >= 1.3: confidence = 0.70
        else:              confidence = 0.0

    # ── Injury penalty ─────────────────────────────────────────────────
    injury_note = ""
    if confidence > 0:
        parsed2 = _parse_ticker(ticker)
        if parsed2 and espn_id2:
            team_code2 = parsed2[0]
            espn_team2 = TEAM_CODE_MAP.get(team_code2, team_code2)
            status2    = get_injury_status(espn_id2, espn_team2)
            if status2 == "questionable":
                confidence = round(max(0, confidence - 0.08), 3)
                injury_note = " [questionable]"

    hit_str = f" hr={hit_rate:.0%}" if hit_rate > 0 else ""
    reason = (f"{avgs[\'player_name\']} avg {avg_stat:.1f} vs threshold {threshold} "
              f"(ratio={ratio:.2f}{hit_str}) → conf={confidence:.2f}{injury_note}")'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg

tests = [
    'KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15',
    'KXNBAPTS-26MAR29NYKOKC-NYKJBRUNSON11-20',
    'KXNBAAST-26MAR29NYKOKC-NYKJBRUNSON11-7',
]
for t in tests:
    r = score_prop_leg(t)
    print(f'conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:70]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.prop_scanner import scan_edges, build_edge_combo
legs = scan_edges()
print(f'Positive-edge legs: {len(legs)}')
for l in legs[:10]:
    print(f'  edge={l[\"edge\"]:+.3f} mkt={l[\"market_price\"]:.2f} mdl={l[\"model_conf\"]:.3f} | {l[\"reasoning\"][:60]}')
combo = build_edge_combo(legs)
if combo:
    from functools import reduce
    payout = 1/reduce(lambda a,b: a*b, [l[\"market_price\"] for l in combo], 1.0)
    avg_edge = sum(l[\"edge\"] for l in combo)/len(combo)
    print(f'Combo: {len(combo)} legs | {payout:.1f}x | avg edge={avg_edge:+.3f}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cat > /root/kalshi-bot-v2/data/persistent_cache.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/persistent_cache.py
─────────────────────────────────────────────────────────────────────────────
SQLite-based persistent cache for data that doesn't change often.

Tables:
    player_averages  — season averages per player (TTL: 24h)
    game_logs        — per-game stats (never expire, append-only)
    player_ids       — ESPN ID mappings (TTL: 7 days)
    rosters          — team rosters (TTL: 24h)
"""

import sqlite3
import json
import time
import logging
import os

log = logging.getLogger("kalshi_bot.cache")

DB_PATH = "/root/kalshi-bot-v2/data/cache.db"


def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_conn() as conn:
        conn.executescript('''
            CREATE TABLE IF NOT EXISTS player_averages (
                espn_id     TEXT PRIMARY KEY,
                data        TEXT NOT NULL,
                updated_at  INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS game_logs (
                espn_id     TEXT NOT NULL,
                season      TEXT NOT NULL,
                games_json  TEXT NOT NULL,
                updated_at  INTEGER NOT NULL,
                PRIMARY KEY (espn_id, season)
            );

            CREATE TABLE IF NOT EXISTS player_ids (
                player_key  TEXT PRIMARY KEY,
                espn_id     TEXT NOT NULL,
                full_name   TEXT NOT NULL,
                updated_at  INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS rosters (
                team        TEXT PRIMARY KEY,
                data        TEXT NOT NULL,
                updated_at  INTEGER NOT NULL
            );
        ''')


def get_player_averages(espn_id: str, max_age_secs: int = 86400) -> dict:
    """Get cached player averages. Returns None if expired or missing."""
    try:
        with get_conn() as conn:
            row = conn.execute(
                'SELECT data, updated_at FROM player_averages WHERE espn_id = ?',
                (espn_id,)
            ).fetchone()
            if row and (time.time() - row['updated_at']) < max_age_secs:
                return json.loads(row['data'])
    except Exception as e:
        log.debug(f"Cache read error: {e}")
    return None


def set_player_averages(espn_id: str, data: dict):
    try:
        with get_conn() as conn:
            conn.execute(
                'INSERT OR REPLACE INTO player_averages (espn_id, data, updated_at) VALUES (?, ?, ?)',
                (espn_id, json.dumps(data), int(time.time()))
            )
    except Exception as e:
        log.debug(f"Cache write error: {e}")


def get_game_logs(espn_id: str, season: str = "2026", max_age_secs: int = 3600) -> list:
    """Get cached game logs. Returns None if expired or missing."""
    try:
        with get_conn() as conn:
            row = conn.execute(
                'SELECT games_json, updated_at FROM game_logs WHERE espn_id = ? AND season = ?',
                (espn_id, season)
            ).fetchone()
            if row and (time.time() - row['updated_at']) < max_age_secs:
                return json.loads(row['games_json'])
    except Exception as e:
        log.debug(f"Cache read error: {e}")
    return None


def set_game_logs(espn_id: str, games: list, season: str = "2026"):
    try:
        with get_conn() as conn:
            conn.execute(
                'INSERT OR REPLACE INTO game_logs (espn_id, season, games_json, updated_at) VALUES (?, ?, ?, ?)',
                (espn_id, season, json.dumps(games), int(time.time()))
            )
    except Exception as e:
        log.debug(f"Cache write error: {e}")


def get_player_id(player_key: str, max_age_secs: int = 604800) -> tuple:
    """Returns (espn_id, full_name) or (None, None)."""
    try:
        with get_conn() as conn:
            row = conn.execute(
                'SELECT espn_id, full_name, updated_at FROM player_ids WHERE player_key = ?',
                (player_key,)
            ).fetchone()
            if row and (time.time() - row['updated_at']) < max_age_secs:
                return row['espn_id'], row['full_name']
    except Exception as e:
        log.debug(f"Cache read error: {e}")
    return None, None


def set_player_id(player_key: str, espn_id: str, full_name: str):
    try:
        with get_conn() as conn:
            conn.execute(
                'INSERT OR REPLACE INTO player_ids (player_key, espn_id, full_name, updated_at) VALUES (?, ?, ?, ?)',
                (player_key, espn_id, full_name, int(time.time()))
            )
    except Exception as e:
        log.debug(f"Cache write error: {e}")


def get_roster(team: str, max_age_secs: int = 86400) -> list:
    """Returns cached roster or None."""
    try:
        with get_conn() as conn:
            row = conn.execute(
                'SELECT data, updated_at FROM rosters WHERE team = ?',
                (team,)
            ).fetchone()
            if row and (time.time() - row['updated_at']) < max_age_secs:
                return json.loads(row['data'])
    except Exception as e:
        log.debug(f"Cache read error: {e}")
    return None


def set_roster(team: str, roster: list):
    try:
        with get_conn() as conn:
            conn.execute(
                'INSERT OR REPLACE INTO rosters (team, data, updated_at) VALUES (?, ?, ?)',
                (team, json.dumps(roster), int(time.time()))
            )
    except Exception as e:
        log.debug(f"Cache write error: {e}")


def cache_stats():
    """Print cache stats."""
    try:
        with get_conn() as conn:
            players = conn.execute('SELECT COUNT(*) FROM player_averages').fetchone()[0]
            logs    = conn.execute('SELECT COUNT(*) FROM game_logs').fetchone()[0]
            ids     = conn.execute('SELECT COUNT(*) FROM player_ids').fetchone()[0]
            rosters = conn.execute('SELECT COUNT(*) FROM rosters').fetchone()[0]
            print(f"Cache: {players} player avgs, {logs} game logs, {ids} player IDs, {rosters} rosters")
    except Exception as e:
        print(f"Cache stats error: {e}")


# Initialize on import
init_db()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/data/persistent_cache.py) lines"
python3 -c "from data.persistent_cache import cache_stats; cache_stats()"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

# Add persistent cache import
old = 'from data.cache import TTLCache'
new = 'from data.cache import TTLCache\nfrom data.persistent_cache import (\n    get_player_averages as _pc_get_avgs, set_player_averages as _pc_set_avgs,\n    get_player_id, set_player_id, get_roster, set_roster\n)'
c = c.replace(old, new)

# Cache player averages in _fetch_averages
old2 = '''def _fetch_averages(espn_id: str, full_name: str) -> dict:
    """Fetch current season per-game averages from ESPN."""
    try:'''
new2 = '''def _fetch_averages(espn_id: str, full_name: str) -> dict:
    """Fetch current season per-game averages from ESPN."""
    # Check persistent cache first (24h TTL)
    cached = _pc_get_avgs(espn_id)
    if cached:
        log.debug(f"[NBAStats] Cache hit for {full_name}")
        return cached
    try:'''
c = c.replace(old2, new2)

# Save after successful fetch
old3 = '''        log.debug(f"[NBAStats] {full_name}: "
                 f"pts={avgs['avg_points']} reb={avgs['avg_rebounds']} "
                 f"ast={avgs['avg_assists']}")
        return avgs'''
new3 = '''        log.debug(f"[NBAStats] {full_name}: "
                 f"pts={avgs['avg_points']} reb={avgs['avg_rebounds']} "
                 f"ast={avgs['avg_assists']}")
        _pc_set_avgs(espn_id, avgs)
        return avgs'''
c = c.replace(old3, new3)

# Cache roster in _find_player
old4 = '''    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=3600)'''
new4 = '''    if roster is None:
        roster = get_roster(espn_team)
    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=3600)
            set_roster(espn_team, roster)'''
c = c.replace(old4, new4)

# Cache player ID lookups
old5 = '''    return (None, None)'''
new5 = '''    return (None, None)


def _cached_find_player(espn_team: str, player_code: str) -> tuple:
    """Wrapper around _find_player with persistent ID caching."""
    key = f"{espn_team}_{player_code}"
    espn_id, full_name = get_player_id(key)
    if espn_id:
        return espn_id, full_name
    espn_id, full_name = _find_player(espn_team, player_code)
    if espn_id:
        set_player_id(key, espn_id, full_name)
    return espn_id, full_name'''
c = c.replace(old5, new5, 1)  # Only replace first occurrence

# Use cached version in get_player_averages
old6 = '''    espn_id, full_name = _find_player(espn_team, last_name)'''
new6 = '''    espn_id, full_name = _cached_find_player(espn_team, last_name)'''
c = c.replace(old6, new6)

open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/player_stats.py', 'r')
c = f.read()
f.close()

old = 'from data.cache import TTLCache'
new = 'from data.cache import TTLCache\nfrom data.persistent_cache import get_game_logs, set_game_logs'
c = c.replace(old, new)

old2 = '''    cache_key = f"gamelog_{espn_id}_{n}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    try:'''
new2 = '''    cache_key = f"gamelog_{espn_id}_{n}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    # Check persistent cache
    persistent = get_game_logs(espn_id, max_age_secs=3600)
    if persistent is not None:
        result = persistent[-n:]
        cache.set(cache_key, result, ttl=3600)
        return result

    try:'''
c = c.replace(old2, new2)

old3 = '''        games = games[-n:]
        cache.set(cache_key, games, ttl=3600)
        return games'''
new3 = '''        # Store ALL games in persistent cache, return last n
        cache.set(cache_key, games, ttl=3600)
        set_game_logs(espn_id, games)
        return games[-n:]'''
c = c.replace(old3, new3)

open('/root/kalshi-bot-v2/data/player_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
import time
from data.nba_stats import score_prop_leg

# First call — will fetch and cache
t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'First call: {time.time()-t0:.2f}s conf={r[\"confidence\"]:.3f}')

# Second call — should be instant from cache
t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'Second call: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f}')

from data.persistent_cache import cache_stats
cache_stats()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '''    espn_id, full_name = _find_player(espn_team, player_code)
    if espn_id:
        set_player_id(key, espn_id, full_name)
    return espn_id, full_name''',
    '''    result = _find_player(espn_team, player_code)
    if result is None:
        return (None, None)
    espn_id, full_name = result
    if espn_id:
        set_player_id(key, espn_id, full_name)
    return espn_id, full_name'''
)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
import time
from data.nba_stats import score_prop_leg

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'First call: {time.time()-t0:.2f}s conf={r[\"confidence\"]:.3f}')

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'Cached call: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f}')

from data.persistent_cache import cache_stats
cache_stats()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.nba_stats import _parse_ticker, _find_player, _cached_find_player, TEAM_CODE_MAP

ticker = 'KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15'
parsed = _parse_ticker(ticker)
print(f'Parsed: {parsed}')
if parsed:
    team, code = parsed
    espn_team = TEAM_CODE_MAP.get(team, team)
    print(f'Team: {team} -> ESPN: {espn_team}')
    result = _find_player(espn_team, code)
    print(f'Found: {result}')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
import requests
r = requests.get('https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/NY/roster', timeout=6)
athletes = r.json().get('athletes', [])
print(f'NY roster: {len(athletes)} players')
for a in athletes:
    print(f'  {a.get(\"lastName\",\"\").lower()} | {a.get(\"fullName\")}')
" 2>&1 | grep -i "town\|kat\|karl"
python3 -c "
player_code = 'ktowns'
last = 'towns'
code = player_code

print(f'code={code} last={last}')
print(f'endswith: {code.endswith(last)}')
print(f'last in code: {last in code}')
print(f'last[:4] in code: {last[:4] in code}')
print(f'code[:4] in last: {code[:4] in last}')
"
python3 -c "
from data.persistent_cache import get_roster, set_roster
import requests

# Check what's in roster cache
r = get_roster('NY')
if r:
    print(f'Cached NY roster: {len(r)} players')
    for a in r:
        if 'town' in a.get('lastName','').lower():
            print(f'  Found: {a.get(\"fullName\")} id={a.get(\"id\")}')
else:
    print('NY not in cache')
    # Check which team IS cached
    import sqlite3
    conn = sqlite3.connect('/root/kalshi-bot-v2/data/cache.db')
    rows = conn.execute('SELECT team FROM rosters').fetchall()
    print(f'Cached teams: {[r[0] for r in rows]}')
"
sed -n '108,125p' /root/kalshi-bot-v2/data/nba_stats.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''    if roster is None:
        roster = get_roster(espn_team)
    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=3600)
            set_roster(espn_team, roster)'''

new = '''    if roster is None:
        roster = get_roster(espn_team, max_age_secs=86400)
    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=3600)
            set_roster(espn_team, roster)'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
import time
from data.nba_stats import score_prop_leg
from data.persistent_cache import cache_stats

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'First: {time.time()-t0:.2f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:50]}')

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'Cache: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f}')

cache_stats()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cat > /root/kalshi-bot-v2/data/warm_cache.py << 'PYEOF'
#!/usr/bin/env python3
"""
data/warm_cache.py
Pre-populates persistent cache with all active NBA player data.
Run once before the trading session starts.
"""
import logging
import sys
import time
sys.path.insert(0, '/root/kalshi-bot-v2')

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("warm_cache")

from data.nba_stats import TEAM_CODE_MAP, _find_player, _fetch_averages
from data.player_stats import get_last_n_games
from data.persistent_cache import (
    get_player_id, set_player_id,
    get_player_averages, set_player_averages,
    get_game_logs, set_game_logs,
    get_roster, set_roster, cache_stats
)
import requests

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"

def warm_all_rosters():
    """Cache all 30 NBA team rosters."""
    log.info("Warming rosters...")
    teams = list(set(TEAM_CODE_MAP.values()))
    for team in teams:
        if get_roster(team):
            continue
        try:
            r = requests.get(f"{ESPN_BASE}/teams/{team}/roster", timeout=6)
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            set_roster(team, roster)
            log.info(f"  {team}: {len(roster)} players cached")
            time.sleep(0.3)
        except Exception as e:
            log.warning(f"  {team} failed: {e}")

def warm_player_ids():
    """Cache ESPN ID for every player on every roster."""
    log.info("Warming player IDs...")
    teams = list(set(TEAM_CODE_MAP.values()))
    total = 0
    for team in teams:
        roster = get_roster(team) or []
        for athlete in roster:
            espn_id   = athlete.get('id', '')
            full_name = athlete.get('fullName', '')
            last_name = athlete.get('lastName', '').lower()
            if espn_id and full_name:
                key = f"{team}_{last_name}"
                if not get_player_id(key)[0]:
                    set_player_id(key, espn_id, full_name)
                    total += 1
    log.info(f"  {total} player IDs cached")

def warm_player_averages():
    """Cache season averages for all players."""
    log.info("Warming player averages...")
    teams   = list(set(TEAM_CODE_MAP.values()))
    total   = 0
    skipped = 0
    for team in teams:
        roster = get_roster(team) or []
        for athlete in roster:
            espn_id   = athlete.get('id', '')
            full_name = athlete.get('fullName', '')
            if not espn_id:
                continue
            if get_player_averages(espn_id):
                skipped += 1
                continue
            try:
                avgs = _fetch_averages(espn_id, full_name)
                if avgs:
                    total += 1
                time.sleep(0.2)
            except Exception as e:
                log.debug(f"  {full_name}: {e}")
    log.info(f"  {total} averages cached, {skipped} already cached")

def warm_game_logs():
    """Cache last 15 game logs for all players."""
    log.info("Warming game logs...")
    teams   = list(set(TEAM_CODE_MAP.values()))
    total   = 0
    skipped = 0
    for team in teams:
        roster = get_roster(team) or []
        for athlete in roster:
            espn_id   = athlete.get('id', '')
            full_name = athlete.get('fullName', '')
            if not espn_id:
                continue
            if get_game_logs(espn_id, max_age_secs=3600):
                skipped += 1
                continue
            try:
                games = get_last_n_games(espn_id, n=15)
                if games:
                    total += 1
                    log.debug(f"  {full_name}: {len(games)} games")
                time.sleep(0.2)
            except Exception as e:
                log.debug(f"  {full_name}: {e}")
    log.info(f"  {total} game logs cached, {skipped} already cached")

if __name__ == "__main__":
    log.info("Starting cache warm-up...")
    warm_all_rosters()
    warm_player_ids()
    warm_player_averages()
    warm_game_logs()
    log.info("Done!")
    cache_stats()
PYEOF

echo "Written. Running cache warmer now..."
python3 /root/kalshi-bot-v2/data/warm_cache.py
# Check progress periodically
watch -n 30 'cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 -c "from data.persistent_cache import cache_stats; cache_stats()"'
watch -n 30 'cd /root/kalshi-bot-v2 && /root/kalshi-bot/bin/python3 -c "from data.persistent_cache import cache_stats; cache_stats()"'
/root/kalshi-bot/bin/python3 -c "from data.persistent_cache import cache_stats; cache_stats()"
python3 -c "
import time
from data.nba_stats import score_prop_leg
from data.persistent_cache import cache_stats

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'KAT: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:60]}')

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKJBRUNSON11-20')
print(f'Brunson: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:60]}')

cache_stats()
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 -c "
from data.persistent_cache import get_player_id
# Check what key format was stored
import sqlite3
conn = sqlite3.connect('/root/kalshi-bot-v2/data/cache.db')
rows = conn.execute('SELECT player_key, full_name FROM player_ids WHERE full_name LIKE \"%Towns%\"').fetchall()
for r in rows:
    print(r[0], '->', r[1])
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/warm_cache.py', 'r')
c = f.read()
f.close()

old = '''            if espn_id and full_name:
                key = f"{team}_{last_name}"
                if not get_player_id(key)[0]:
                    set_player_id(key, espn_id, full_name)
                    total += 1'''

new = '''            if espn_id and full_name:
                # Store multiple key variations to handle Kalshi ticker codes
                first = athlete.get('firstName','').lower()
                # e.g. "towns", "ktowns", "katowns"
                keys = [
                    f"{team}_{last_name}",
                    f"{team}_{first[0]}{last_name}" if first else None,
                    f"{team}_{first[:2]}{last_name}" if len(first) >= 2 else None,
                ]
                for key in keys:
                    if key and not get_player_id(key)[0]:
                        set_player_id(key, espn_id, full_name)
                        total += 1'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/warm_cache.py', 'w').write(c)
print("Done")
PYEOF

# Re-run just the player ID warmup
python3 -c "
from data.warm_cache import warm_player_ids
warm_player_ids()
from data.persistent_cache import cache_stats
cache_stats()
"
python3 -c "
import time
from data.nba_stats import score_prop_leg

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'KAT: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:65]}')

t0 = time.time()
r = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKJBRUNSON11-20')
print(f'Brunson: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:65]}')

t0 = time.time()
r = score_prop_leg('KXNBA3PT-26MAR29LACMIL-LACKLEONARD2-2')
print(f'Kawhi: {time.time()-t0:.3f}s conf={r[\"confidence\"]:.3f} | {r[\"reason\"][:65]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/warm_cache.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '                games = get_last_n_games(espn_id, n=15)',
    '''                import signal as _sig
                def _timeout(s, f): raise TimeoutError()
                _sig.signal(_sig.SIGALRM, _timeout)
                _sig.alarm(3)
                try:
                    games = get_last_n_games(espn_id, n=15)
                finally:
                    _sig.alarm(0)'''
)
open('/root/kalshi-bot-v2/data/warm_cache.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.warm_cache import warm_game_logs
warm_game_logs()
from data.persistent_cache import cache_stats
cache_stats()
"
python3 -c "
import time
from data.prop_scanner import scan_edges, build_edge_combo

t0 = time.time()
legs = scan_edges()
combo = build_edge_combo(legs)
elapsed = time.time() - t0

print(f'Scan time: {elapsed:.1f}s')
print(f'Legs: {len(legs)}')
if combo:
    from functools import reduce
    payout = 1/reduce(lambda a,b: a*b, [l[\"market_price\"] for l in combo], 1.0)
    print(f'Combo: {len(combo)} legs | {payout:.1f}x | \$5->\${5*payout:.0f}')
    for l in combo[:5]:
        print(f'  edge={l[\"edge\"]:+.3f} | {l[\"reasoning\"][:60]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
cd /root/kalshi-bot-v2 && git add -A && git commit -m "feat: persistent SQLite cache, game log hit rates, edge-based prop scanner, 6s scan time" && git push origin master
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scheduler.py', 'r')
c = f.read()
f.close()

old = '''def main():
    log.info("Combo Scheduler starting")
    log.info("Fetching today's NBA schedule...")'''

new = '''def warm_cache():
    """Refresh cache with latest player data."""
    log.info("Warming cache...")
    try:
        from data.warm_cache import warm_all_rosters, warm_player_ids, warm_player_averages, warm_game_logs
        warm_all_rosters()
        warm_player_ids()
        warm_player_averages()
        warm_game_logs()
        log.info("Cache warm complete")
    except Exception as e:
        log.warning(f"Cache warm failed: {e}")


def main():
    log.info("Combo Scheduler starting")
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
