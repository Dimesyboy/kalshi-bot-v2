        content,
        count=1,
        flags=re.DOTALL
    )
    with open('tennis_context.py', 'w') as f:
        f.write(content)
    print("✅ tennis_context.py patched — ticker parser fixed")
else:
    print("❌ Function not found — check tennis_context.py manually")
EOF

python /tmp/tennis_patch.py
cat > /tmp/tennis_patch.py << 'PYEOF'
import re

with open('tennis_context.py', 'r') as f:
    content = f.read()

new_fn = '''def _parse_ticker_players(ticker: str) -> Tuple[str, str]:
    """
    Kalshi tennis ticker format:
    KXATPMATCH-26MAR17PLAYERA-PLAYERB
    parts[0]=series, parts[1]=date+P1, parts[2]=P2
    """
    try:
        parts = ticker.split("-")
        if len(parts) < 3:
            return "", ""
        event_segment = parts[1]
        date_match = re.match(r\\'^\d{2}[A-Z]{3}\d{2}\\', event_segment)
        if not date_match:
            return "", ""
        p1 = event_segment[date_match.end():]
        p2 = parts[2]
        if not p1 or not p2:
            return "", ""
        log.debug(f"[Tennis] Parsed ticker {ticker} -> P1={p1} P2={p2}")
        return p1.upper(), p2.upper()
    except Exception as e:
        log.debug(f"[Tennis] Ticker parse error {ticker}: {e}")
        return "", ""'''

if '_parse_ticker_players' in content:
    content = re.sub(
        r'def _parse_ticker_players\(ticker[\s\S]*?return "", ""\n',
        new_fn + '\n',
        content,
        count=1
    )
    with open('tennis_context.py', 'w') as f:
        f.write(content)
    print("tennis_context.py patched OK")
else:
    print("Function not found - check file manually")
PYEOF

python /tmp/tennis_patch.py
python3 - << 'PYEOF'
import re

with open('tennis_context.py', 'r') as f:
    content = f.read()

new_fn = (
    "def _parse_ticker_players(ticker: str) -> Tuple[str, str]:\n"
    "    try:\n"
    "        parts = ticker.split(\"-\")\n"
    "        if len(parts) < 3:\n"
    "            return \"\", \"\"\n"
    "        event_segment = parts[1]\n"
    "        date_match = re.match(r'^\\d{2}[A-Z]{3}\\d{2}', event_segment)\n"
    "        if not date_match:\n"
    "            return \"\", \"\"\n"
    "        p1 = event_segment[date_match.end():]\n"
    "        p2 = parts[2]\n"
    "        if not p1 or not p2:\n"
    "            return \"\", \"\"\n"
    "        log.debug(f\"[Tennis] Parsed ticker {ticker} -> P1={p1} P2={p2}\")\n"
    "        return p1.upper(), p2.upper()\n"
    "    except Exception as e:\n"
    "        log.debug(f\"[Tennis] Ticker parse error {ticker}: {e}\")\n"
    "        return \"\", \"\"\n"
)

content = re.sub(
    r'def _parse_ticker_players\(ticker[\s\S]*?return "", ""\n',
    new_fn,
    content,
    count=1
)

with open('tennis_context.py', 'w') as f:
    f.write(content)

print("✅ tennis_context.py patched")
PYEOF

python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    lines = f.readlines()

# Find the function start
start = None
for i, line in enumerate(lines):
    if 'def _parse_ticker_players' in line:
        start = i
        break

if start is None:
    print("Function not found")
    exit(1)

# Find the function end (next def or end of file)
end = None
for i in range(start + 1, len(lines)):
    if lines[i].startswith('def ') or lines[i].startswith('class '):
        end = i
        break
if end is None:
    end = len(lines)

print(f"Found function at lines {start+1}-{end}")

new_fn = [
    'def _parse_ticker_players(ticker: str) -> Tuple[str, str]:\n',
    '    try:\n',
    '        parts = ticker.split("-")\n',
    '        if len(parts) < 3:\n',
    '            return "", ""\n',
    '        event_segment = parts[1]\n',
    '        import re as _re\n',
    '        date_match = _re.match(r"^\\d{2}[A-Z]{3}\\d{2}", event_segment)\n',
    '        if not date_match:\n',
    '            return "", ""\n',
    '        p1 = event_segment[date_match.end():]\n',
    '        p2 = parts[2]\n',
    '        if not p1 or not p2:\n',
    '            return "", ""\n',
    '        log.debug(f"[Tennis] Parsed {ticker} -> P1={p1} P2={p2}")\n',
    '        return p1.upper(), p2.upper()\n',
    '    except Exception as e:\n',
    '        log.debug(f"[Tennis] Ticker parse error {ticker}: {e}")\n',
    '        return "", ""\n',
    '\n',
]

lines[start:end] = new_fn

with open('tennis_context.py', 'w') as f:
    f.writelines(lines)

print("✅ tennis_context.py patched successfully")
PYEOF

python3 - << 'PYEOF'
with open('espn_data.py', 'r') as f:
    lines = f.readlines()

start = None
for i, line in enumerate(lines):
    if 'ESPN_URLS' in line and '=' in line:
        start = i
        break

if start is None:
    print("ESPN_URLS not found")
    exit(1)

end = None
for i in range(start + 1, len(lines)):
    if lines[i].strip() == '}':
        end = i + 1
        break

print(f"Found ESPN_URLS at lines {start+1}-{end}")

new_urls = [
    'ESPN_URLS = {\n',
    '    "NBA": "http://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",\n',
    '    "MLB": "http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",\n',
    '    # Tennis removed - data comes from api-tennis.com not ESPN\n',
    '}\n',
]

lines[start:end] = new_urls

with open('espn_data.py', 'w') as f:
    f.writelines(lines)

print("✅ espn_data.py patched successfully")
PYEOF

git add espn_data.py tennis_context.py && git commit -m "fix: remove wasted ESPN tennis pulls + fix ticker player name parsing" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 8 && tail -25 kalshi_bot.log
python3 - << 'PYEOF'
import re

tickers = [
    "KXATPMATCH-26MAR17SHAVAN-VAN",
    "KXATPMATCH-26MAR17BERBRO-BER",
    "KXWTAMATCH-26MAR17ARASEL-ARA",
    "KXATPCHALLENGERMATCH-26MAR18OLIFAR-OLI",
    "KXATPCHALLENGERMATCH-26MAR18DEJHOU-HOU",
]

for ticker in tickers:
    parts = ticker.split("-")
    print(f"Ticker: {ticker}")
    print(f"  parts: {parts}")
    if len(parts) >= 3:
        event_segment = parts[1]
        date_match = re.match(r'^\d{2}[A-Z]{3}\d{2}', event_segment)
        if date_match:
            p1 = event_segment[date_match.end():]
            p2 = parts[2]
            print(f"  -> P1={p1} P2={p2}")
        else:
            print(f"  -> no date match on: {event_segment}")
    print()
PYEOF

python3 - << 'PYEOF'
import requests, json

r = requests.get("https://api.api-tennis.com/tennis/?method=get_livescore&APIkey=d5a36c825abb6150aa2b7b90bcf353b5e94da8400f477f02c02727ff068b2b87", timeout=8)
matches = r.json().get("result", [])
print(f"Live matches: {len(matches)}\n")
for m in matches:
    p1 = m.get("event_first_player", "")
    p2 = m.get("event_second_player", "")
    live = m.get("event_live", "0")
    scores = m.get("scores", [])
    score_str = " ".join(f"{s.get('score_first','?')}-{s.get('score_second','?')}" for s in scores)
    print(f"  [{live}] {p1} vs {p2} | {score_str}")
PYEOF

python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    lines = f.readlines()

start = None
for i, line in enumerate(lines):
    if 'def _name_matches_fragment' in line:
        start = i
        break

end = None
for i in range(start + 1, len(lines)):
    if lines[i].startswith('def ') or lines[i].startswith('class '):
        end = i
        break
if end is None:
    end = len(lines)

print(f"Found _name_matches_fragment at lines {start+1}-{end}")

new_fn = [
    'def _name_matches_fragment(fragment: str, full_name: str) -> bool:\n',
    '    if not fragment or not full_name:\n',
    '        return False\n',
    '    # Require minimum fragment length to avoid false positives\n',
    '    if len(fragment) < 4:\n',
    '        return False\n',
    '    frag = fragment.upper()\n',
    '    name = full_name.upper()\n',
    '    # Direct substring match\n',
    '    if frag in name:\n',
    '        return True\n',
    '    # Word-level match - fragment must match start of a word with 4+ chars\n',
    '    for word in re.split(r\'[\\s.\\-]\', name):\n',
    '        if len(word) >= 4 and word.startswith(frag[:4]):\n',
    '            return True\n',
    '    return False\n',
    '\n',
]

lines[start:end] = new_fn

with open('tennis_context.py', 'w') as f:
    f.writelines(lines)

print("✅ _name_matches_fragment tightened")
PYEOF

python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    content = f.read()

old = 'if not best_match or best_score < 2:'
new = 'if not best_match or best_score < 3:'

if old in content:
    content = content.replace(old, new)
    with open('tennis_context.py', 'w') as f:
        f.write(content)
    print("✅ Match score threshold raised to 3")
else:
    print("❌ Pattern not found")
PYEOF

git add tennis_context.py && git commit -m "fix: tighten tennis fuzzy matching - min 4 char fragments + score threshold 3" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 8 && tail -20 kalshi_bot.log
screen -r
tail -30 kalshi_bot.log
python kalshi_bot.py -status
grep "SHAVAN\|BERBRO\|No match for" kalshi_bot.log | tail -20
python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    content = f.read()

old = '''    best_match = None
    best_score = 0
    for match in live_matches:
        p1n = (match.get("event_first_player") or "").upper()
        p2n = (match.get("event_second_player") or "").upper()
        score = 0
        if _name_matches_fragment(p1_frag, p1n): score += 2
        if _name_matches_fragment(p2_frag, p2n): score += 2
        if _name_matches_fragment(p1_frag, p2n): score += 1
        if _name_matches_fragment(p2_frag, p1n): score += 1
        if score > best_score:
            best_score = score
            best_match = match
    if not best_match or best_score < 3:'''

new = '''    best_match = None
    best_score = 0
    for match in live_matches:
        p1n = (match.get("event_first_player") or "").upper()
        p2n = (match.get("event_second_player") or "").upper()
        # Both fragments must match — one for each player
        p1_hits = _name_matches_fragment(p1_frag, p1n) or _name_matches_fragment(p1_frag, p2n)
        p2_hits = _name_matches_fragment(p2_frag, p2n) or _name_matches_fragment(p2_frag, p1n)
        if not p1_hits or not p2_hits:
            continue  # require BOTH players to match something
        score = 0
        if _name_matches_fragment(p1_frag, p1n): score += 2
        if _name_matches_fragment(p2_frag, p2n): score += 2
        if _name_matches_fragment(p1_frag, p2n): score += 1
        if _name_matches_fragment(p2_frag, p1n): score += 1
        if score > best_score:
            best_score = score
            best_match = match
    if not best_match or best_score < 3:'''

if old in content:
    content = content.replace(old, new)
    with open('tennis_context.py', 'w') as f:
        f.write(content)
    print("✅ tennis_context.py - both-players-must-match fix applied")
else:
    print("❌ Pattern not found - check indentation in tennis_context.py")
PYEOF

grep -n "best_match\|best_score\|p1_hits\|name_matches_fragment\|not best_match" tennis_context.py | head -20
python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    lines = f.readlines()

# Insert the both-players-must-match check before line 317 (0-indexed: 316)
# Lines 311-325 are the match loop (0-indexed 310-324)
# We need to add p1_hits/p2_hits check inside the loop, after p1n/p2n are set

new_loop = [
    '    best_match = None\n',
    '    best_score = 0\n',
    '    for match in live_matches:\n',
    '        p1n = (match.get("event_first_player") or "").upper()\n',
    '        p2n = (match.get("event_second_player") or "").upper()\n',
    '        # Both fragments must match something — prevents dead matches cross-firing\n',
    '        p1_hits = _name_matches_fragment(p1_frag, p1n) or _name_matches_fragment(p1_frag, p2n)\n',
    '        p2_hits = _name_matches_fragment(p2_frag, p2n) or _name_matches_fragment(p2_frag, p1n)\n',
    '        if not p1_hits or not p2_hits:\n',
    '            continue\n',
    '        score = 0\n',
    '        if _name_matches_fragment(p1_frag, p1n): score += 2\n',
    '        if _name_matches_fragment(p2_frag, p2n): score += 2\n',
    '        if _name_matches_fragment(p1_frag, p2n): score += 1\n',
    '        if _name_matches_fragment(p2_frag, p1n): score += 1\n',
    '        if score > best_score:\n',
    '            best_score = score\n',
    '            best_match = match\n',
]

# Replace lines 310-323 (0-indexed), which is lines 311-324 in the file
lines[310:324] = new_loop

with open('tennis_context.py', 'w') as f:
    f.writelines(lines)

print("✅ tennis_context.py patched by line number")
PYEOF

git add tennis_context.py && git commit -m "fix: tennis match requires both player fragments to hit" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 10 && grep "SHAVAN\|BERBRO\|No match for" kalshi_bot.log | tail -10
tail -30 kalshi_bot.log
grep "SHAVAN\|BERBRO\|ARASEL" kalshi_bot.log | tail -10
python kalshi_bot.py -status
2026-03-18 17:47:09,731 [INFO] [Tennis] KXWTAMATCH-26MAR17ARASEL-ARA -> A. Guillen Meza vs G. Cadenasso [3-4] R207/300 H2H:Meza 0-0 Cadenasso | live=True pct=33% sets_down=1 conf=0.61
2026-03-18 17:47:17,430 [INFO] [Tennis] KXATPMATCH-26MAR17SHAVAN-VAN -> S. Rodriguez Taverna vs L. E. Ambrogi [4-2] R229/999 H2H:Taverna 0-1 Ambrogi | live=True pct=33% sets_down=1 conf=0.59
2026-03-18 17:54:00,425 [INFO] [Strategy:exit] KXWTAMATCH-26MAR17ARASEL-ARA - Stale: 7234s, 2c move, PNL=$-0.10
2026-03-18 17:54:00,779 [INFO] [LIVE ORDER PLACED] bc23fb73-cbda-4560-a6df-402ae5714f92 | KXWTAMATCH-26MAR17ARASEL-ARA YES @ 28c
2026-03-18 17:54:00,779 [INFO] [LIVE] Position closed: KXWTAMATCH-26MAR17ARASEL-ARA PNL $-0.1000 (session $-3.3600)
2026-03-18 17:54:00,781 [INFO] [TradeTiming] ── SELL KXWTAMATCH-26MAR17ARASEL-ARA ───────────────── total=353.9ms
2026-03-18 17:54:23,839 [INFO] [Strategy:exit] KXWTAMATCH-26MAR17ARASEL-ARA - Stale: 7258s, 2c move, PNL=$-0.10
2026-03-18 17:54:24,138 [INFO] [LIVE ORDER PLACED] 6c0f339d-0a43-459a-8c59-6ec702290e17 | KXWTAMATCH-26MAR17ARASEL-ARA YES @ 28c
2026-03-18 17:54:24,138 [INFO] [LIVE] Position closed: KXWTAMATCH-26MAR17ARASEL-ARA PNL $-0.1000 (session $-3.6400)
2026-03-18 17:54:24,140 [INFO] [TradeTiming] ── SELL KXWTAMATCH-26MAR17ARASEL-ARA ───────────────── total=298.8ms
====================================================================
--------------------------------------------------------------------
====================================================================
(kalshi-bot) root@Kalshi-bot:~#
python3 - << 'PYEOF'
import requests
r = requests.get("https://api.api-tennis.com/tennis/?method=get_livescore&APIkey=d5a36c825abb6150aa2b7b90bcf353b5e94da8400f477f02c02727ff068b2b87", timeout=8)
for m in r.json().get("result", []):
    p1 = m.get("event_first_player", "")
    p2 = m.get("event_second_player", "")
    scores = m.get("scores", [])
    score_str = " ".join(f"{s.get('score_first','?')}-{s.get('score_second','?')}" for s in scores)
    if "Guillen" in p1 or "Cadenasso" in p2 or "Guillen" in p2:
        print(f"FOUND: {p1} vs {p2} | {score_str}")
        print(f"Live: {m.get('event_live')} | Status: {m.get('event_status')}")
PYEOF

python3 - << 'PYEOF'
import requests
r = requests.get("https://api.elections.kalshi.com/trade-api/v2/markets/KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI", timeout=8)
m = r.json().get("market", {})
print(f"Yes bid: {m.get('yes_bid_dollars')}")
print(f"Yes ask: {m.get('yes_ask_dollars')}")
print(f"Status: {m.get('status')}")
PYEOF

python3 - << 'PYEOF'
import os, sys
os.environ.setdefault("KALSHI_API_KEY_ID", "test")

# Patch execute so nothing trades
import unittest.mock as mock

from kalshi_bot import (
    get_live_sports_snapshot, analyze_snapshot, Config
)
from strategies import (
    strategy_value_fade, strategy_prop_nba, strategy_tennis_underdog,
    strategy_quarter_winner, strategy_mlb_underdog, ESPNContextCache
)

Config.DRY_RUN = True

print("Fetching live snapshot...")
snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

print(f"\nTotal markets in watchlist: {len(watchlist)}")
print(f"Flagged as SIGNAL: {sum(1 for w in watchlist if w['flag'] == 'SIGNAL')}")
print(f"Flagged as WATCHLIST: {sum(1 for w in watchlist if w['flag'] == 'WATCHLIST')}")

espn = ESPNContextCache()
espn.refresh(max_age=0)

strategies = [
    ("value_fade",       strategy_value_fade),
    ("prop_nba",         strategy_prop_nba),
    ("tennis_underdog",  strategy_tennis_underdog),
    ("quarter_winner",   strategy_quarter_winner),
    ("mlb_underdog",     strategy_mlb_underdog),
]

print("\n=== STRATEGY GATE DIAGNOSTICS ===\n")
fired = {name: [] for name, _ in strategies}
skipped = {name: 0 for name, _ in strategies}

for item in watchlist:
    m = item["market"]
    for name, fn in strategies:
        try:
            sig = fn(item, espn_cache=espn)
            if sig:
                fired[name].append(sig)
            else:
                skipped[name] += 1
        except Exception as e:
            print(f"  ERROR in {name} on {m.ticker}: {e}")

for name, _ in strategies:
    sigs = fired[name]
    print(f"--- {name} ---")
    print(f"  Fired: {len(sigs)}  |  Skipped: {skipped[name]}")
    for s in sigs[:5]:  # show first 5
        print(f"  SIGNAL: {s.market_ticker} {s.side.upper()} @ {s.price}c x{s.contracts} conf={s.confidence} | {s.reason}")
    if len(sigs) > 5:
        print(f"  ... and {len(sigs)-5} more")
    print()
PYEOF

python3 - << 'PYEOF'
import os
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import ESPNContextCache, _allowed, _is_prop, _is_tennis, _is_nba_mlb
Config.DRY_RUN = True

import time; time.sleep(5)  # avoid 429

print("Fetching snapshot...")
snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

espn = ESPNContextCache()
espn.refresh(max_age=0)

print("\n=== VALUE FADE GATE TRACE (first 20 markets) ===")
count = 0
for item in watchlist:
    m = item["market"]
    if not any(m.ticker.startswith(s) for s in ["KXNBAGAME","KXMLBGAME","KXATPMATCH","KXWTAMATCH","KXATPCHALLENGERMATCH","KXWTACHALLENGERMATCH","KXNBA1HWINNER","KXNBA2HWINNER","KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER"]):
        continue
    if _is_prop(m.ticker):
        continue
    count += 1
    if count > 20:
        break
    reasons = []
    if m.yes_bid < 0.95: reasons.append(f"yes_bid={m.yes_bid:.2f} < 0.95")
    if m.spread > 3: reasons.append(f"spread={m.spread} > 3")
    no_bid_cents = max(1, int(m.no_bid * 100))
    if no_bid_cents < 5: reasons.append(f"no_bid={no_bid_cents}c < 5")
    vol_ok = m.volume >= 8000
    if not vol_ok: reasons.append(f"vol={int(m.volume)} < 8000")
    if reasons:
        print(f"  SKIP {m.ticker[:50]} | {' | '.join(reasons)}")
    else:
        print(f"  PASS {m.ticker[:50]} | bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread}")

print("\n=== TENNIS UNDERDOG GATE TRACE ===")
for item in watchlist:
    m = item["market"]
    if not _is_tennis(m.ticker): continue
    reasons = []
    if item.get("market_status","active") != "active" and item.get("market_status") != "open":
        reasons.append(f"status={item.get('market_status')}")
    if m.yes_bid < 0.20 or m.yes_bid > 0.38: reasons.append(f"yes_bid={m.yes_bid:.2f} not in 0.20-0.38")
    if m.volume < 8000: reasons.append(f"vol={int(m.volume)} < 8000")
    if m.spread > 3: reasons.append(f"spread={m.spread} > 3")
    if reasons:
        print(f"  SKIP {m.ticker[:50]} | {' | '.join(reasons)}")
    else:
        print(f"  PASS {m.ticker[:50]} | bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread} status={item.get('market_status')}")
PYEOF

python3 - << 'PYEOF'
from tennis_context import get_tennis_context

tickers = [
    "KXATPMATCH-26MAR17MPEUGO-UGO",
    "KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI",
    "KXATPCHALLENGERMATCH-26MAR18RODAMB-AMB",
    "KXATPMATCH-26MAR17BERBRO-BER",
    "KXATPMATCH-26MAR17SHAVAN-VAN",
]

for t in tickers:
    ctx = get_tennis_context(t)
    if ctx:
        print(f"MATCH  {t} -> {ctx.p1_name} vs {ctx.p2_name} | live={ctx.is_live} conf={ctx.underdog_conf}")
    else:
        print(f"NO CTX {t}")
PYEOF

python3 - << 'PYEOF'
import requests, re

tickers = [
    "KXATPMATCH-26MAR17MPEUGO-UGO",
    "KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI",
    "KXATPCHALLENGERMATCH-26MAR18RODAMB-AMB",
]

print("=== TICKER FRAGMENTS ===")
for ticker in tickers:
    parts = ticker.split("-")
    if len(parts) >= 3:
        event_segment = parts[1]
        date_match = re.match(r'^\d{2}[A-Z]{3}\d{2}', event_segment)
        if date_match:
            p1 = event_segment[date_match.end():]
            p2 = parts[2]
            print(f"  {ticker}")
            print(f"    P1={p1}  P2={p2}")

print("\n=== LIVE MATCHES FROM API-TENNIS ===")
r = requests.get("https://api.api-tennis.com/tennis/?method=get_livescore&APIkey=d5a36c825abb6150aa2b7b90bcf353b5e94da8400f477f02c02727ff068b2b87", timeout=8)
for m in r.json().get("result", []):
    p1 = m.get("event_first_player", "")
    p2 = m.get("event_second_player", "")
    scores = m.get("scores", [])
    score_str = " ".join(f"{s.get('score_first','?')}-{s.get('score_second','?')}" for s in scores)
    print(f"  [{m.get('event_live')}] {p1} vs {p2} | {score_str}")
PYEOF

python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    lines = f.readlines()

start = None
for i, line in enumerate(lines):
    if 'def _parse_ticker_players' in line:
        start = i
        break

end = None
for i in range(start + 1, len(lines)):
    if lines[i].startswith('def ') or lines[i].startswith('class '):
        end = i
        break
if end is None:
    end = len(lines)

print(f"Replacing lines {start+1}-{end}")

new_fn = [
    'def _parse_ticker_players(ticker: str) -> Tuple[str, str]:\n',
    '    """\n',
    '    Kalshi tennis ticker format:\n',
    '    KXATPMATCH-26MAR17GUICAD-GUI\n',
    '    The middle segment after date = P1code+P2code concatenated\n',
    '    The last segment = P1code (3 chars)\n',
    '    So P1code = parts[2], P2code = middle[-(len(parts[2])):]\n',
    '    Example: GUICAD-GUI -> P1=GUI, P2=CAD\n',
    '    """\n',
    '    try:\n',
    '        parts = ticker.split("-")\n',
    '        if len(parts) < 3:\n',
    '            return "", ""\n',
    '        event_segment = parts[1]  # e.g. 26MAR17GUICAD\n',
    '        p1_code = parts[2]        # e.g. GUI (always the last segment)\n',
    '        import re as _re\n',
    '        date_match = _re.match(r"^\\d{2}[A-Z]{3}\\d{2}", event_segment)\n',
    '        if not date_match:\n',
    '            return "", ""\n',
    '        combined = event_segment[date_match.end():]  # e.g. GUICAD\n',
    '        # P2 code is whatever is left after removing P1 code from combined\n',
    '        if combined.startswith(p1_code):\n',
    '            p2_code = combined[len(p1_code):]\n',
    '        else:\n',
    '            # fallback: split combined in half\n',
    '            mid = len(combined) // 2\n',
    '            p2_code = combined[mid:]\n',
    '        if not p1_code or not p2_code:\n',
    '            return "", ""\n',
    '        log.debug(f"[Tennis] Parsed {ticker} -> P1={p1_code} P2={p2_code}")\n',
    '        return p1_code.upper(), p2_code.upper()\n',
    '    except Exception as e:\n',
    '        log.debug(f"[Tennis] Ticker parse error {ticker}: {e}")\n',
    '        return "", ""\n',
    '\n',
]

lines[start:end] = new_fn

with open('tennis_context.py', 'w') as f:
    f.writelines(lines)

print("✅ Parser fixed - now correctly splits P1/P2 from combined segment")

# Quick test
import re
test_cases = [
    ("KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI", "GUI", "CAD"),
    ("KXATPCHALLENGERMATCH-26MAR18RODAMB-ROD", "ROD", "AMB"),
    ("KXATPMATCH-26MAR17SHAVAN-SHA", "SHA", "VAN"),
    ("KXATPMATCH-26MAR17BERBRO-BER", "BER", "BRO"),
]
print("\n=== PARSER TEST ===")
for ticker, exp_p1, exp_p2 in test_cases:
    parts = ticker.split("-")
    p1_code = parts[2]
    event_segment = parts[1]
    date_match = re.match(r'^\d{2}[A-Z]{3}\d{2}', event_segment)
    combined = event_segment[date_match.end():]
    p2_code = combined[len(p1_code):] if combined.startswith(p1_code) else combined[len(combined)//2:]
    status = "✅" if p1_code == exp_p1 and p2_code == exp_p2 else "❌"
    print(f"  {status} {ticker} -> P1={p1_code} P2={p2_code} (expected {exp_p1}/{exp_p2})")
PYEOF

git add tennis_context.py && git commit -m "fix: correct ticker parser - P1=last segment, P2=remainder of combined" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 10 && python3 - << 'PYEOF'
from tennis_context import get_tennis_context

tickers = [
    "KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI",
    "KXATPCHALLENGERMATCH-26MAR18RODAMB-AMB",
    "KXATPMATCH-26MAR17SHAVAN-VAN",
    "KXATPMATCH-26MAR17BERBRO-BER",
]

for t in tickers:
    ctx = get_tennis_context(t)
    if ctx:
        print(f"✅ MATCH  {t}")
        print(f"         {ctx.p1_name} vs {ctx.p2_name} | live={ctx.is_live} sets_down={ctx.sets_down} conf={ctx.underdog_conf}")
    else:
        print(f"❌ NO CTX {t}")
PYEOF

grep -A 20 "def _parse_ticker_players" tennis_context.py | head -25
python3 - << 'PYEOF'
with open('tennis_context.py', 'r') as f:
    content = f.read()

old = '    if len(fragment) < 4:\n        return False\n'
new = '    if len(fragment) < 3:\n        return False\n'

if old in content:
    content = content.replace(old, new)
    with open('tennis_context.py', 'w') as f:
        f.write(content)
    print("✅ Min fragment length lowered to 3")
else:
    print("❌ Pattern not found")
PYEOF

python3 - << 'PYEOF'
from tennis_context import get_tennis_context

tickers = [
    "KXATPCHALLENGERMATCH-26MAR18GUICAD-GUI",
    "KXATPCHALLENGERMATCH-26MAR18RODAMB-ROD",
    "KXATPMATCH-26MAR17SHAVAN-SHA",
]

for t in tickers:
    ctx = get_tennis_context(t)
    if ctx:
        print(f"✅ {t} -> {ctx.p1_name} vs {ctx.p2_name} | live={ctx.is_live} conf={ctx.underdog_conf}")
    else:
        print(f"❌ NO CTX {t}")
PYEOF

git add tennis_context.py && git commit -m "fix: lower fragment min to 3 chars + correct P1/P2 parser" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 15 && tail -20 kalshi_bot.log
pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted at 0.58 conf" && sleep 15 && tail -10 kalshi_bot.log
source kalshi-bot/bin/activate
screen -S kalshi
python3 - << 'PYEOF'
import os, time
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
time.sleep(3)

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import (strategy_value_fade, strategy_prop_nba,
    strategy_tennis_underdog, strategy_quarter_winner,
    strategy_mlb_underdog, ESPNContextCache)

Config.DRY_RUN = True

print("Fetching snapshot...")
snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

espn = ESPNContextCache()
espn.refresh(max_age=0)

strategies = [
    ("value_fade",      strategy_value_fade),
    ("prop_nba",        strategy_prop_nba),
    ("tennis_underdog", strategy_tennis_underdog),
    ("quarter_winner",  strategy_quarter_winner),
    ("mlb_underdog",    strategy_mlb_underdog),
]

print(f"\nWatchlist: {len(watchlist)} | Signals: {sum(1 for w in watchlist if w['flag']=='SIGNAL')}\n")
print("=== STRATEGY RESULTS ===\n")

for name, fn in strategies:
    fired, skipped = [], 0
    for item in watchlist:
        try:
            sig = fn(item, espn_cache=espn)
            if sig: fired.append(sig)
            else: skipped += 1
        except Exception as e:
            print(f"  ERROR {name} on {item['market'].ticker}: {e}")
    print(f"--- {name}: {len(fired)} fired / {skipped} skipped ---")
    for s in fired:
        print(f"  ✅ {s.market_ticker} {s.side.upper()} @ {s.price}c x{s.contracts} conf={s.confidence}")
        print(f"     {s.reason}")
    if not fired:
        print(f"  (none fired)")
    print()
PYEOF

python3 - << 'PYEOF'
import os, time
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
time.sleep(3)

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import ESPNContextCache, _is_tennis, _is_live
from tennis_context import get_tennis_context

Config.DRY_RUN = True

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn = ESPNContextCache()
espn.refresh(max_age=0)

print("=== TENNIS UNDERDOG DEEP TRACE ===\n")
for item in watchlist:
    m = item["market"]
    if not _is_tennis(m.ticker): continue
    if m.yes_bid < 0.20 or m.yes_bid > 0.38: continue
    if m.volume < 8000: continue
    if m.spread > 3: continue

    # passed all basic gates - now check context
    sport = item.get("sport","")
    status = item.get("market_status","active")
    live = _is_live(status, sport, m.ticker)
    print(f"GATE PASS: {m.ticker}")
    print(f"  bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread} live={live} status={status}")

    if not live:
        print(f"  ❌ SKIP: not live")
        continue

    tctx = get_tennis_context(m.ticker, espn)
    if not tctx:
        print(f"  ❌ SKIP: no tennis context")
        continue

    print(f"  Context: {tctx.p1_name} vs {tctx.p2_name} | live={tctx.is_live} sets_down={tctx.sets_down} conf={tctx.underdog_conf}")

    if not tctx.is_live:
        print(f"  ❌ SKIP: tctx.is_live=False")
        continue
    if tctx.sets_down >= 2:
        print(f"  ❌ SKIP: sets_down={tctx.sets_down} >= 2")
        continue
    if abs(tctx.p1_games - tctx.p2_games) > 3:
        print(f"  ❌ SKIP: game diff={abs(tctx.p1_games-tctx.p2_games)} > 3")
        continue
    if tctx.underdog_conf < 0.60:
        print(f"  ❌ SKIP: conf={tctx.underdog_conf} < 0.60")
        continue

    print(f"  ✅ WOULD FIRE")
    print()
PYEOF

python3 - << 'PYEOF'
import os, time
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
time.sleep(3)

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import ESPNContextCache, _is_prop, _is_nba_mlb, _allowed
from nba_context import find_game_for_ticker, nba_value_fade_check

Config.DRY_RUN = True

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn = ESPNContextCache()
espn.refresh(max_age=0)

print("=== VALUE FADE TRACE (NBA/MLB games only) ===\n")
fade_candidates = []
for item in watchlist:
    m = item["market"]
    if not any(m.ticker.startswith(s) for s in ["KXNBAGAME","KXMLBGAME","KXMLBSTGAME"]):
        continue
    if _is_prop(m.ticker):
        continue
    reasons = []
    if m.yes_bid < 0.95: reasons.append(f"yes_bid={m.yes_bid:.2f} < 0.95")
    if m.spread > 3: reasons.append(f"spread={m.spread} > 3")
    if m.volume < 8000: reasons.append(f"vol={int(m.volume)} < 8000")
    no_bid_cents = max(1, int(m.no_bid * 100))
    if no_bid_cents < 5: reasons.append(f"no_bid={no_bid_cents}c < 5c")
    if not reasons:
        fade_candidates.append(item)
        print(f"  ✅ PASSES GATES: {m.ticker}")
        print(f"     yes_bid={m.yes_bid:.2f} no_bid={no_bid_cents}c vol={int(m.volume)} sprd={m.spread}")
    else:
        # show near misses only
        if m.yes_bid >= 0.85:
            print(f"  NEAR MISS: {m.ticker}")
            print(f"     {' | '.join(reasons)}")

print(f"\nTotal fade candidates: {len(fade_candidates)}")

print("\n=== NBA PROPS TRACE ===\n")
prop_candidates = []
for item in watchlist:
    m = item["market"]
    if not _is_prop(m.ticker): continue
    reasons = []
    if m.yes_bid < 0.55 or m.yes_bid > 0.80: reasons.append(f"yes_bid={m.yes_bid:.2f} not in 0.55-0.80")
    if m.volume < 5000: reasons.append(f"vol={int(m.volume)} < 5000")
    if m.spread > 5: reasons.append(f"spread={m.spread} > 5")
    if not reasons:
        prop_candidates.append(item)
        print(f"  ✅ PASSES GATES: {m.ticker}")
        print(f"     yes_bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread}")
    else:
        if m.yes_bid >= 0.50 and m.yes_bid <= 0.85:
            print(f"  NEAR MISS: {m.ticker[:60]}")
            print(f"     {' | '.join(reasons)}")

print(f"\nTotal prop candidates: {len(prop_candidates)}")

print("\n=== MLB SPRING TRAINING TRACE ===\n")
for item in watchlist:
    m = item["market"]
    if not m.ticker.startswith("KXMLBSTGAME"): continue
    reasons = []
    if m.yes_bid < 0.33 or m.yes_bid > 0.65: reasons.append(f"yes_bid={m.yes_bid:.2f} not in 0.33-0.65")
    if m.volume < 400: reasons.append(f"vol={int(m.volume)} < 400")
    if m.spread > 3: reasons.append(f"spread={m.spread} > 3")
    if not reasons:
        print(f"  ✅ PASSES GATES: {m.ticker}")
        print(f"     yes_bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread}")
    else:
        print(f"  SKIP: {m.ticker[:60]} | {' | '.join(reasons)}")

print("\n=== QUARTER/HALF WINNER TRACE ===\n")
for item in watchlist:
    m = item["market"]
    if not any(m.ticker.startswith(s) for s in [
        "KXNBA1QWINNER","KXNBA2QWINNER","KXNBA3QWINNER","KXNBA4QWINNER",
        "KXNBA1HWINNER","KXNBA2HWINNER"]): continue
    reasons = []
    if item.get("market_status") != "open": reasons.append(f"status={item.get('market_status')} not open")
    if m.yes_bid < 0.40 or m.yes_bid > 0.60: reasons.append(f"yes_bid={m.yes_bid:.2f} not in 0.40-0.60")
    if m.volume < 2000: reasons.append(f"vol={int(m.volume)} < 2000")
    if m.spread > 5: reasons.append(f"spread={m.spread} > 5")
    if not reasons:
        print(f"  ✅ PASSES GATES: {m.ticker}")
        print(f"     yes_bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread} status={item.get('market_status')}")
    else:
        print(f"  SKIP: {m.ticker[:60]} | {' | '.join(reasons)}")
PYEOF

python3 - << 'PYEOF'
from mlb_props import get_mlb_context

tickers = [
    ("KXMLBSTGAME-26MAR181605SFLAD-SF", 0.43),
    ("KXMLBSTGAME-26MAR181605SFLAD-LAD", 0.57),
    ("KXMLBSTGAME-26MAR181305BOSNYY-BOS", 0.44),
    ("KXMLBSTGAME-26MAR181305HOUSTL-STL", 0.54),
    ("KXMLBSTGAME-26MAR181305HOUSTL-HOU", 0.44),
]

for ticker, bid in tickers:
    ctx = get_mlb_context(ticker, bid)
    if ctx:
        print(f"✅ {ticker}")
        print(f"   should_enter={ctx.should_enter} conf={ctx.confidence} | {ctx.summary()}")
    else:
        print(f"❌ NO CTX {ticker}")
PYEOF

grep -n "should_enter\|conf\|edge\|threshold\|MIN\|min_conf" mlb_props.py | head -30
grep -n "cooldown\|COOLDOWN\|signal_cache\|price_cache\|drift\|momentum\|last_price\|prev" kalshi_bot.py | head -30
grep -n "cooldown\|COOLDOWN\|cache" strategies.py | head -20
screen -r
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
screen -S kalshi
source kalshi-bot/bin/activate
screen -r
python kalshi_bot.py
python3 - << 'PYEOF'
with open('strategies.py', 'r') as f:
    content = f.read()

old = '    if side=="no": return None # NO positions settle naturally\n'
new = '    if side=="no": return None # NO positions settle naturally\n    if pos.get("is_bot") is False: return None # never auto-exit manual positions\n'

if old in content:
    content = content.replace(old, new)
    with open('strategies.py', 'w') as f:
        f.write(content)
    print("✅ Manual positions excluded from auto-exit")
else:
    print("❌ Pattern not found")
PYEOF

grep -n "NO positions settle naturally\|is_bot\|manual" strategies.py | head -10
grep -n "side.*no.*return None\|settle naturally" strategies.py
sed -n '568,573p' strategies.py
python3 - << 'PYEOF'
with open('strategies.py', 'r') as f:
    lines = f.readlines()

# Line 570 is index 569
for i, line in enumerate(lines):
    if line.strip() == 'if side=="no": return None':
        insert_at = i + 1
        break

lines.insert(insert_at, '    if pos.get("is_bot") is False: return None  # never auto-exit manual positions\n')

with open('strategies.py', 'w') as f:
    f.writelines(lines)

print(f"✅ Manual position guard inserted at line {insert_at+1}")
PYEOF

screen -S kalshi
python kalshi_bot.py -status
grep "LIVE ORDER\|Position closed\|PNL" kalshi_bot.log | tail -40
pkill -f kalshi_bot.py && echo "✅ Bot stopped"
grep -n "peak_price\|Position closed\|del open_positions\|del.*positions" kalshi_bot.py | head -20
grep -n "pending_tickers\|signal_cooldown\|already in open\|ticker in open_positions" kalshi_bot.py | head -20
grep -n "MAX_CONTRACTS\|base_contracts\|int.*MAX_POSITION" strategies.py | head -20
python3 - << 'PYEOF'
with open('kalshi_bot.py', 'r') as f:
    content = f.read()

# BUG 2 FIX — cooldown being wiped every cycle
old = '            signal_cooldown = {}  # cooldown disabled — bot re-enters freely\n'
new = '            # signal_cooldown preserved across cycles — do not reset\n'

if old in content:
    content = content.replace(old, new)
    print("✅ Bug 2 fixed — cooldown no longer wiped each cycle")
else:
    print("❌ Bug 2 pattern not found")

with open('kalshi_bot.py', 'w') as f:
    f.write(content)
PYEOF

python3 - << 'PYEOF'
# BUG 1 FIX — ghost exit in price watcher
# Find execute_signal for sell path and add existence check
with open('kalshi_bot.py', 'r') as f:
    lines = f.readlines()

# Find the line that checks signal.market_ticker in open_positions for sell
for i, line in enumerate(lines):
    if 'if signal.market_ticker in open_positions:' in line and i > 1220:
        print(f"Found sell gate at line {i+1}: {line.rstrip()}")
        # Check a few lines around it
        for j in range(i-2, i+5):
            print(f"  {j+1}: {lines[j].rstrip()}")
        break
PYEOF

sed -n '1255,1280p' kalshi_bot.py
python3 - << 'PYEOF'
with open('kalshi_bot.py', 'r') as f:
    lines = f.readlines()

# BUG 1 FIX — add duplicate sell guard before position delete
# Find line with "del open_positions[signal.market_ticker]" in sell path (around 1260)
for i, line in enumerate(lines):
    if 'del open_positions[signal.market_ticker]' in line and i > 1250:
        # Insert a check two lines before the del
        print(f"Found position delete at line {i+1}")
        # The guard is already at line 1225 — problem is watcher thread races
        # Add a re-check right before delete
        lines[i] = (
            '                        if signal.market_ticker in open_positions:\n'
            '                            del open_positions[signal.market_ticker]\n'
        )
        print("✅ Bug 1 fixed — double-delete guard added")
        break

with open('kalshi_bot.py', 'w') as f:
    f.writelines(lines)
PYEOF

python3 - << 'PYEOF'
with open('strategies.py', 'r') as f:
    content = f.read()

# BUG 3 FIX — cap contracts at sensible number for low price markets
# The formula int(MAX_POSITION_USD / yes_ask) explodes at low prices
# Add a MAX_CONTRACTS_LOW_PRICE cap of 20 for any market under 15c

old = (
    '    base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.01)), Config.MAX_CONTRACTS))\n'
    '    contracts = _scale_contracts(base_contracts, conf)\n'
    '    ev = _scale_contracts(base_contracts, conf)\n'
)

# Fix each occurrence of the base_contracts formula
import re

# Replace all base_contracts calculations to cap at 20 contracts max regardless
old_pattern = r'base_contracts = max\(1, min\(int\(Config\.MAX_POSITION_USD / max\(m\.yes_ask, 0\.01\)\), Config\.MAX_CONTRACTS\)\)'
new_pattern = 'base_contracts = max(1, min(int(Config.MAX_POSITION_USD / max(m.yes_ask, 0.15)), Config.MAX_CONTRACTS))'

# The key fix: use max(yes_ask, 0.15) instead of max(yes_ask, 0.01)
# This means at any price below 15c we calculate as if price is 15c
# So max contracts = MAX_POSITION_USD / 0.15 = 3.44/0.15 = ~22, capped at MAX_CONTRACTS=20
# At 5c actual price that was 3.44/0.05 = 68 contracts — now safely capped

count = 0
new_content = re.sub(old_pattern, new_pattern, content)
count = content.count('max(m.yes_ask, 0.01)') 
actual = new_content.count('max(m.yes_ask, 0.15)')

if actual > 0:
    with open('strategies.py', 'w') as f:
        f.write(new_content)
    print(f"✅ Bug 3 fixed — {actual} contract calculations capped (min price floor 15c)")
else:
    print("❌ Pattern not found")
PYEOF

python3 - << 'PYEOF'
with open('strategies.py', 'r') as f:
    content = f.read()

import re
old = r'base_contracts=max\(1,min\(int\(Config\.MAX_POSITION_USD/max\(m\.no_bid,0\.01\)\),Config\.MAX_CONTRACTS\)\)'
new = 'base_contracts=max(1,min(int(Config.MAX_POSITION_USD/max(m.no_bid,0.15)),Config.MAX_CONTRACTS))'

new_content = re.sub(old, new, content)
if new_content != content:
    with open('strategies.py', 'w') as f:
        f.write(new_content)
    print("✅ value_fade no_bid contract cap fixed")
else:
    print("❌ Pattern not found")
PYEOF

python3 -c "
import ast
for f in ['kalshi_bot.py', 'strategies.py']:
    with open(f) as fh: src = fh.read()
    try:
        ast.parse(src)
        print(f'✅ {f} syntax OK')
    except SyntaxError as e:
        print(f'❌ {f}: {e}')
" && git add kalshi_bot.py strategies.py && git commit -m "fix: ghost exit double-sell + cooldown wipe + contract count explosion at low prices" && git push && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 10 && tail -15 kalshi_bot.log
python kalshi_bot.py
python3 - << 'PYEOF'
import os, time
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
time.sleep(3)

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import _is_prop

Config.DRY_RUN = True

print("Fetching snapshot...")
snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)

props = [item for item in watchlist if _is_prop(item["market"].ticker)]
print(f"\nTotal prop markets in watchlist: {len(props)}")

if props:
    print("\n=== NBA PROP MARKETS ===")
    for item in props[:30]:
        m = item["market"]
        print(f"  {m.ticker[:60]}")
        print(f"    bid={m.yes_bid:.2f} vol={int(m.volume)} sprd={m.spread} status={item.get('market_status')}")
else:
    print("\nNo prop markets in watchlist at all.")
    print("\nChecking raw NBA snapshot for props...")
    nba = snapshot.get("NBA", {})
    prop_series = ["KXNBAPTS","KXNBAREB","KXNBAAST","KXNBA3PT","KXNBAPRA","KXNBASTL","KXNBABLK"]
    found = 0
    for event_ticker, game in nba.items():
        for label, markets in game.markets.items():
            for m in markets:
                if any(m.ticker.startswith(s) for s in prop_series):
                    found += 1
                    if found <= 10:
                        print(f"  RAW: {m.ticker[:60]} bid={m.yes_bid:.2f} vol={int(m.volume)}")
    print(f"\nTotal raw prop markets found: {found}")
PYEOF

python3 - << 'PYEOF'
import os, time
os.environ.setdefault("KALSHI_API_KEY_ID", "test")
time.sleep(3)

from kalshi_bot import get_live_sports_snapshot, analyze_snapshot, Config
from strategies import ESPNContextCache, _is_prop
from nba_props import get_nba_prop_context

Config.DRY_RUN = True

snapshot = get_live_sports_snapshot()
watchlist = analyze_snapshot(snapshot)
espn = ESPNContextCache()
espn.refresh(max_age=0)

print("=== NBA PROP DEEP TRACE ===\n")
for item in watchlist:
    m = item["market"]
    if not _is_prop(m.ticker): continue

    reasons = []
    if not any(m.ticker.startswith(s) for s in ["KXNBAPTS","KXNBA3PT"]):
        reasons.append("not PTS or 3PT series")
    if m.yes_bid < 0.55 or m.yes_bid > 0.80:
        reasons.append(f"yes_bid={m.yes_bid:.2f} not in 0.55-0.80")
    if m.volume < 5000:
        reasons.append(f"vol={int(m.volume)} < 5000")
    if m.spread > 5:
        reasons.append(f"spread={m.spread} > 5")

    if reasons:
        print(f"GATE FAIL: {m.ticker[:60]}")
        print(f"  {' | '.join(reasons)}")
        continue

    print(f"GATE PASS: {m.ticker[:60]}")
    ctx = get_nba_prop_context(m.ticker, m.yes_bid, espn)
    if ctx:
        print(f"  should_enter={ctx.should_enter} conf={ctx.confidence} edge={ctx.edge:+.3f}")
        print(f"  reason: {ctx.reason}")
    else:
        print(f"  ❌ No prop context returned")
    print()
PYEOF

python3 - << 'PYEOF'
from nba_props import get_nba_prop_context, _parse_prop_ticker
from strategies import ESPNContextCache

espn = ESPNContextCache()
espn.refresh(max_age=0)

ticker = "KXNBAPTS-26MAR18GSWBOS-BOSJTATUM0-20"
bid = 0.60

print(f"Parsing ticker: {ticker}")
parsed = _parse_prop_ticker(ticker)
print(f"Parsed: {parsed}")

print(f"\nCalling get_nba_prop_context...")
ctx = get_nba_prop_context(ticker, bid, espn)
if ctx:
    print(f"should_enter={ctx.should_enter} conf={ctx.confidence}")
    print(f"reason: {ctx.reason}")
else:
    print("Returned None")
PYEOF

python3 - << 'PYEOF'
from nba_props import _parse_prop_ticker, _load_player_stats, _find_player

ticker = "KXNBAPTS-26MAR18GSWBOS-BOSJTATUM0-20"
stat_type, team, last_name, first_initial, threshold = _parse_prop_ticker(ticker)

print(f"stat={stat_type} team={team} player={first_initial}.{last_name} threshold={threshold}")

stats = _load_player_stats()
print(f"Total players loaded: {len(stats)}")

player = _find_player(stats, last_name, first_initial, team)
if player:
    print(f"Found: {player}")
else:
    print("❌ Player not found in stats")
    # Show similar names
    matches = [p for p in stats if last_name.upper() in str(p).upper()]
    print(f"Similar entries: {matches[:5]}")
PYEOF

grep -n "^def " nba_props.py | head -20
python3 - << 'PYEOF'
from nba_props import _parse_prop_ticker, _fetch_all_players, _find_player

ticker = "KXNBAPTS-26MAR18GSWBOS-BOSJTATUM0-20"
parsed = _parse_prop_ticker(ticker)
print(f"Parsed: {parsed}")
stat_type, team, player_frag, threshold = parsed

print(f"\nstat={stat_type} team={team} player_frag={player_frag} threshold={threshold}")

print("\nFetching players...")
all_players = _fetch_all_players()
print(f"Total players: {len(all_players)}")

print(f"\nSearching for {player_frag} on {team}...")
player = _find_player(player_frag, team, all_players)
if player:
    print(f"Found: {player}")
else:
    print("❌ Not found")
    # Show all BOS players
    bos = {k:v for k,v in all_players.items() if v.get('team') == 'BOS'}
    print(f"\nAll BOS players in stats ({len(bos)}):")
    for name, data in list(bos.items())[:10]:
        print(f"  {name}: {data}")
PYEOF

python3 - << 'PYEOF'
from nba_props import _parse_prop_ticker, _fetch_all_players, _find_player

ticker = "KXNBAPTS-26MAR18GSWBOS-BOSJTATUM0-20"
parsed = _parse_prop_ticker(ticker)
print(f"Parsed: {parsed}")
stat_type, team, last_name, first_initial, threshold = parsed

print(f"stat={stat_type} team={team} last={last_name} initial={first_initial} threshold={threshold}")

print("\nFetching players...")
all_players = _fetch_all_players()
print(f"Total players: {len(all_players)}")

player_frag = first_initial + last_name  
print(f"\nSearching for fragment={player_frag} team={team}...")
player = _find_player(player_frag, team, all_players)
if player:
    print(f"Found: {player}")
else:
    print("❌ Not found")
    bos = {k:v for k,v in all_players.items() if v.get('team') == 'BOS'}
    print(f"\nAll BOS players ({len(bos)}):")
    for name, data in list(bos.items())[:10]:
        print(f"  {name}: {data}")
PYEOF

sed -n '242,310p' nba_props.py
sed -n '337,410p' nba_props.py
python3 - << 'PYEOF'
from nba_props import _parse_prop_ticker, _fetch_all_players, _find_player

ticker = "KXNBAPTS-26MAR18GSWBOS-BOSJTATUM0-20"
stat, prop_team, player_frag, player_initial, threshold = _parse_prop_ticker(ticker)
print(f"stat={stat} team={prop_team} frag={player_frag} initial={player_initial} threshold={threshold}")

all_players = _fetch_all_players()
player = _find_player(player_frag, prop_team, all_players, player_initial)

if player:
    gp = int(player.get("games", 0) or 0)
    points = float(player.get("points", 0) or 0)
    mins = float(player.get("minutesPg", 0) or 0)
    print(f"Found: {player.get('playerName')} gp={gp} pts={points} mins_total={mins}")
    print(f"avg_pg={points/max(gp,1):.1f} mins_pg={mins/max(gp,1):.1f}")
    print(f"isPlayoff={player.get('isPlayoff')}")
    if gp < 10:
        print("❌ BLOCKED: gp < 10")
    mins_pg = mins / max(gp, 1)
    if mins_pg < 20:
        print(f"❌ BLOCKED: mins_pg={mins_pg:.1f} < 20")
else:
    print("❌ Player not found")
PYEOF

python3 - << 'PYEOF'
from nba_props import _fetch_all_players

all_players = _fetch_all_players()

# Check what season/type data we have for a few star players
for name in ["JAYSON TATUM", "STEPHEN CURRY", "NIKOLA JOKIC", "LEBRON JAMES"]:
    p = all_players.get(name)
    if p:
        print(f"{name}: games={p.get('games')} season={p.get('season')} playoff={p.get('isPlayoff')} pts={p.get('points')}")
    else:
        print(f"{name}: NOT FOUND")
PYEOF

sed -n '86,116p' nba_props.py
python3 - << 'PYEOF'
with open('nba_props.py', 'r') as f:
    content = f.read()

old = '''        r = requests.get(f"{BASE_URL}/playertotals", params={
            "season":   2025,
            "sortBy":   "points",
            "pageSize": 500,
        }, timeout=TIMEOUT)'''

new = '''        r = requests.get(f"{BASE_URL}/playertotals", params={
            "season":   2025,
            "sortBy":   "points",
            "pageSize": 500,
            "seasonType": "regular",
        }, timeout=TIMEOUT)'''

if old in content:
    content = content.replace(old, new)
    with open('nba_props.py', 'w') as f:
        f.write(content)
    print("✅ seasonType=regular added to stats fetch")
else:
    print("❌ Pattern not found")
PYEOF

python3 - << 'PYEOF'
# Clear the module cache and re-fetch
import importlib
import nba_props
nba_props._all_players = {}
nba_props._all_players_ts = 0

players = nba_props._fetch_all_players()

for name in ["JAYSON TATUM", "STEPHEN CURRY", "NIKOLA JOKIC", "LEBRON JAMES"]:
    p = players.get(name)
    if p:
        gp = p.get('games')
        pts = p.get('points')
        avg = round(pts/max(gp,1), 1)
        print(f"✅ {name}: games={gp} avg={avg}pts playoff={p.get('isPlayoff')}")
    else:
        print(f"❌ {name}: NOT FOUND")
PYEOF

python3 - << 'PYEOF'
import requests

BASE_URL = "https://api.pbpstats.com/get-totals/nba"

# Try different param names
for param in [
    {"season": 2025, "seasonType": "regular", "sortBy": "points", "pageSize": 10},
    {"season": 2025, "type": "regular", "sortBy": "points", "pageSize": 10},
    {"season": 2025, "playoffs": "false", "sortBy": "points", "pageSize": 10},
    {"season": 2025, "postseason": 0, "sortBy": "points", "pageSize": 10},
]:
    try:
        r = requests.get(f"https://api.pbpstats.com/get-totals/nba", 
                        params=param, timeout=8)
        data = r.json().get("data", [])
        if data:
            sample = data[0]
            print(f"Params {param}")
            print(f"  First player: {sample.get('playerName')} games={sample.get('games')} playoff={sample.get('isPlayoff')}")
            print()
    except Exception as e:
        print(f"Error: {e}")
PYEOF

python3 - << 'PYEOF'
import requests

# Try the base URL to see what it returns
urls = [
    "https://api.pbpstats.com/get-totals/nba",
    "https://www.pbpstats.com/api/get-totals/nba",
]

for url in urls:
    try:
        r = requests.get(url, params={"season": 2025, "sortBy": "points", "pageSize": 5}, timeout=8)
        print(f"URL: {url}")
        print(f"Status: {r.status_code}")
        print(f"Response: {r.text[:300]}")
        print()
    except Exception as e:
        print(f"URL: {url} ERROR: {e}")
PYEOF

python3 - << 'PYEOF'
with open('nba_props.py', 'r') as f:
    content = f.read()

old = '''        r = requests.get(f"{BASE_URL}/playertotals", params={
            "season":   2025,
            "sortBy":   "points",
            "pageSize": 500,
            "seasonType": "regular",
        }, timeout=TIMEOUT)'''

new = '''        r = requests.get(BASE_URL, params={
            "Season":     "2024-25",
            "SeasonType": "Regular Season",
            "Type":       "player",
            "sortBy":     "points",
            "pageSize":   500,
        }, timeout=TIMEOUT)'''

if old in content:
    content = content.replace(old, new)
    with open('nba_props.py', 'w') as f:
        f.write(content)
    print("✅ API params fixed")
else:
    print("❌ Pattern not found — checking what's there")
    # show current fetch params
    idx = content.find('_fetch_all_players')
    print(content[idx:idx+400])
PYEOF

python3 - << 'PYEOF'
import requests
r = requests.get("https://api.pbpstats.com/get-totals/nba", params={
    "Season": "2024-25",
    "SeasonType": "Regular Season", 
    "Type": "player",
    "sortBy": "points",
    "pageSize": 5,
}, timeout=8)
print(f"Status: {r.status_code}")
data = r.json().get("data", [])
for p in data[:5]:
    print(f"  {p.get('playerName')} games={p.get('games')} pts={p.get('points')} playoff={p.get('isPlayoff')}")
PYEOF

python3 - << 'PYEOF'
import requests

# The error said Season, SeasonType, Type are all required
# Let's try different values
attempts = [
    {"Season": "2024-25", "SeasonType": "Regular Season", "Type": "player"},
    {"Season": "2024-25", "SeasonType": "RegularSeason", "Type": "player"},
    {"Season": "2024-25", "SeasonType": "regular", "Type": "player"},
    {"Season": "2025", "SeasonType": "Regular Season", "Type": "player"},
    {"Season": "2024-25", "SeasonType": "Regular Season", "Type": "Player"},
    {"Season": "2024-25", "SeasonType": "Regular Season", "Type": "totals"},
]

for params in attempts:
    r = requests.get("https://api.pbpstats.com/get-totals/nba", 
                    params=params, timeout=8)
    if r.status_code == 200:
        data = r.json().get("data", [])
        print(f"✅ SUCCESS: {params}")
        if data:
            print(f"   First: {data[0].get('playerName')} games={data[0].get('games')}")
        break
    else:
        print(f"❌ {r.status_code}: {params} -> {r.text[:100]}")
PYEOF

python3 - << 'PYEOF'
with open('nba_props.py', 'r') as f:
    content = f.read()

# Find and replace the entire params block
import re
old = re.search(r'r = requests\.get\(.*?playertotals.*?\)', content, re.DOTALL)
if old:
    print(f"Found old fetch: {old.group()[:100]}")

# Replace whatever params are currently there
new_fetch = '''        r = requests.get(BASE_URL, params={
            "Season":     "2024-25",
            "SeasonType": "Regular Season",
            "Type":       "Player",
            "pageSize":   500,
        }, timeout=TIMEOUT)'''

# Find the requests.get call inside _fetch_all_players
lines = content.split('\n')
start = None
end = None
for i, line in enumerate(lines):
    if 'requests.get' in line and 'BASE_URL' in line or 'requests.get' in line and 'playertotals' in line:
        if start is None:
            start = i
    if start and line.strip().endswith(', timeout=TIMEOUT)'):
        end = i
        break
    if start and line.strip().endswith(', timeout=TIMEOUT),'):
        end = i
        break

print(f"Found fetch at lines {start}-{end}")
for i in range(start, end+1):
    print(f"  {i}: {lines[i]}")
PYEOF

python3 - << 'PYEOF'
with open('nba_props.py', 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if '"Type":       "player"' in line:
        lines[i] = line.replace('"player"', '"Player"')
        print(f"✅ Fixed line {i+1}: {lines[i].rstrip()}")
        break

with open('nba_props.py', 'w') as f:
    f.writelines(lines)
PYEOF

python3 - << 'PYEOF'
import nba_props
nba_props._all_players = {}
nba_props._all_players_ts = 0

players = nba_props._fetch_all_players()
for name in ["JAYSON TATUM", "STEPHEN CURRY", "NIKOLA JOKIC", "LEBRON JAMES"]:
    p = players.get(name)
    if p:
        gp = p.get('games')
        pts = p.get('points')
        print(f"✅ {name}: games={gp} avg={round(pts/max(gp,1),1)}pts playoff={p.get('isPlayoff')}")
    else:
        print(f"❌ {name}: NOT FOUND")
PYEOF

grep -n "BASE_URL\|pbpstats\|nbaapi" nba_props.py | head -10
python3 - << 'PYEOF'
with open('nba_props.py', 'r') as f:
    content = f.read()

old = 'BASE_URL  = "https://api.server.nbaapi.com/api"'
new = 'BASE_URL  = "https://api.pbpstats.com/get-totals/nba"'

if old in content:
    content = content.replace(old, new)
    with open('nba_props.py', 'w') as f:
        f.write(content)
    print("✅ BASE_URL fixed to pbpstats")
else:
    print("❌ Pattern not found")
PYEOF

python3 - << 'PYEOF'
import nba_props
nba_props._all_players = {}
nba_props._all_players_ts = 0

players = nba_props._fetch_all_players()
for name in ["JAYSON TATUM", "STEPHEN CURRY", "NIKOLA JOKIC", "LEBRON JAMES"]:
    p = players.get(name)
    if p:
        gp = p.get('games')
        pts = p.get('points')
        print(f"✅ {name}: games={gp} avg={round(pts/max(gp,1),1)}pts playoff={p.get('isPlayoff')}")
    else:
        print(f"❌ {name}: NOT FOUND")
PYEOF

python3 - << 'PYEOF'
import requests
r = requests.get("https://api.pbpstats.com/get-totals/nba", params={
    "Season": "2024-25",
    "SeasonType": "Regular Season",
    "Type": "Player",
    "pageSize": 5,
}, timeout=30)
print(f"Status: {r.status_code}")
data = r.json().get("data", [])
for p in data[:5]:
    print(f"  {p.get('playerName')} games={p.get('games')} pts={p.get('points')}")
PYEOF

python3 - << 'PYEOF'
import requests

# NBA official stats API - free, no key needed
headers = {
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://www.nba.com/",
    "Accept": "application/json",
}

r = requests.get(
    "https://stats.nba.com/stats/leaguedashplayerstats",
    params={
        "Season": "2024-25",
        "SeasonType": "Regular Season",
        "PerMode": "PerGame",
        "LeagueID": "00",
        "MeasureType": "Base",
        "PaceAdjust": "N",
        "PlusMinus": "N",
        "Rank": "N",
        "Outcome": "",
        "Location": "",
        "Month": "0",
        "SeasonSegment": "",
        "DateFrom": "",
        "DateTo": "",
        "OpponentTeamID": "0",
        "VsConference": "",
        "VsDivision": "",
        "GameSegment": "",
        "Period": "0",
        "LastNGames": "0",
        "GameScope": "",
        "PlayerExperience": "",
        "PlayerPosition": "",
        "StarterBench": "",
        "TwoWay": "0",
        "Conference": "",
        "Division": "",
        "DraftYear": "",
        "DraftPick": "",
        "College": "",
        "Country": "",
        "Height": "",
        "Weight": "",
    },
    headers=headers,
    timeout=30,
)
print(f"Status: {r.status_code}")
if r.status_code == 200:
    rs = r.json().get("resultSets", [{}])[0]
    headers_list = rs.get("headers", [])
    rows = rs.get("rowSet", [])
    print(f"Players: {len(rows)}")
    # Find Tatum
    name_idx = headers_list.index("PLAYER_NAME")
    pts_idx = headers_list.index("PTS")
    gp_idx = headers_list.index("GP")
    for row in rows[:5]:
        print(f"  {row[name_idx]} gp={row[gp_idx]} pts={row[pts_idx]}")
PYEOF

python3 - << 'PYEOF'
import requests

# balldontlie - free tier, no auth
r = requests.get(
    "https://api.balldontlie.io/v1/season_averages",
    params={"season": 2024, "player_ids[]": [115, 140, 237]},  # Tatum, Curry, LeBron
    timeout=15,
)
print(f"Status: {r.status_code}")
print(r.text[:300])
PYEOF

python3 - << 'PYEOF'
import requests

# ESPN player stats - free, no auth
r = requests.get(
    "https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/statistics/byathlete",
    params={
        "region": "us",
        "lang": "en",
        "contentorigin": "espn",
        "isqualified": "true",
        "page": 1,
        "limit": 50,
        "sort": "general.pts:desc",
        "season": 2025,
        "seasontype": 2,
    },
    timeout=15,
)
print(f"Status: {r.status_code}")
if r.status_code == 200:
    data = r.json()
    athletes = data.get("athletes", [])
    print(f"Players returned: {len(athletes)}")
    for a in athletes[:5]:
        name = a.get("athlete", {}).get("displayName", "?")
        stats = a.get("categories", [{}])[0].get("values", [])
        print(f"  {name}: {stats[:5]}")
PYEOF

python3 - << 'PYEOF'
import requests

# Try nba_api package which handles NBA.com headers properly
try:
    from nba_api.stats.endpoints import leaguedashplayerstats
    stats = leaguedashplayerstats.LeagueDashPlayerStats(
        season='2024-25',
        season_type_all_star='Regular Season',
        per_mode_simple='PerGame'
    )
    df = stats.get_data_frames()[0]
    print(f"✅ nba_api works - {len(df)} players")
    tatum = df[df['PLAYER_NAME'].str.contains('Tatum')]
    print(tatum[['PLAYER_NAME','GP','PTS']].to_string())
except ImportError:
    print("nba_api not installed - trying install")
except Exception as e:
    print(f"Error: {e}")
PYEOF

pip install nba_api --break-system-packages --quiet && python3 - << 'PYEOF'
from nba_api.stats.endpoints import leaguedashplayerstats
stats = leaguedashplayerstats.LeagueDashPlayerStats(
    season='2024-25',
    season_type_all_star='Regular Season',
    per_mode_simple='PerGame'
)
df = stats.get_data_frames()[0]
print(f"✅ {len(df)} players loaded")
for name in ["Jayson Tatum", "Stephen Curry", "LeBron James", "Nikola Jokic"]:
    row = df[df['PLAYER_NAME'] == name]
    if not row.empty:
        print(f"  {name}: GP={row.iloc[0]['GP']} PTS={row.iloc[0]['PTS']}")
    else:
        print(f"  {name}: NOT FOUND")
PYEOF

python3 - << 'PYEOF'
from nba_api.stats.endpoints import leaguedashplayerstats
import inspect
sig = inspect.signature(leaguedashplayerstats.LeagueDashPlayerStats.__init__)
params = list(sig.parameters.keys())
print("Available params:")
for p in params:
    print(f"  {p}")
PYEOF

python3 - << 'PYEOF'
from nba_api.stats.endpoints import leaguedashplayerstats

stats = leaguedashplayerstats.LeagueDashPlayerStats(
    season='2024-25',
    season_type_all_star='Regular Season',
    per_mode_detailed='PerGame',
    timeout=30,
)
df = stats.get_data_frames()[0]
print(f"✅ {len(df)} players loaded")
for name in ["Jayson Tatum", "Stephen Curry", "LeBron James", "Nikola Jokic"]:
    row = df[df['PLAYER_NAME'] == name]
    if not row.empty:
        print(f"  {name}: GP={row.iloc[0]['GP']} PTS={row.iloc[0]['PTS']:.1f}")
    else:
        print(f"  {name}: NOT FOUND")
PYEOF

pip install sports-reference --break-system-packages --quiet 2>/dev/null; python3 - << 'PYEOF'
try:
    from sportsreference.nba.roster import Player
    print("sports-reference available")
except ImportError:
    pass

# Try sportsdata.io free tier
import requests
r = requests.get(
    "https://api.sportsdata.io/v3/nba/stats/json/PlayerSeasonStats/2025",
    headers={"Ocp-Apim-Subscription-Key": ""},
    timeout=10
)
print(f"sportsdata: {r.status_code}")

# Try mysportsfeeds
r2 = requests.get(
    "https://api.mysportsfeeds.com/v2.1/pull/nba/2024-2025-regular/player_stats.json",
    timeout=10
)
print(f"mysportsfeeds: {r2.status_code}")
PYEOF

python3 - << 'PYEOF'
import requests
from bs4 import BeautifulSoup

headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
r = requests.get(
    "https://www.basketball-reference.com/leagues/NBA_2025_per_game.html",
    headers=headers,
    timeout=15
)
print(f"Status: {r.status_code}")
if r.status_code == 200:
    soup = BeautifulSoup(r.text, 'html.parser')
    table = soup.find('table', {'id': 'per_game_stats'})
    if table:
        rows = table.find('tbody').find_all('tr', class_=lambda x: x != 'thead')
        players = {}
        for row in rows:
            name_td = row.find('td', {'data-stat': 'name_display'})
            pts_td = row.find('td', {'data-stat': 'pts_per_g'})
            gp_td = row.find('td', {'data-stat': 'g'})
            team_td = row.find('td', {'data-stat': 'team_name_abbr'})
            if name_td and pts_td and gp_td:
                name = name_td.get_text(strip=True)
                pts = pts_td.get_text(strip=True)
                gp = gp_td.get_text(strip=True)
                team = team_td.get_text(strip=True) if team_td else ''
                players[name.upper()] = {'pts': float(pts or 0), 'gp': int(gp or 0), 'team': team}

        print(f"Total players: {len(players)}")
        for name in ["JAYSON TATUM", "STEPHEN CURRY", "LEBRON JAMES", "NIKOLA JOKIC"]:
            p = players.get(name)
            if p:
                print(f"  ✅ {name}: GP={p['gp']} PTS={p['pts']} team={p['team']}")
            else:
                print(f"  ❌ {name}: not found")
    else:
        print("❌ Table not found")
else:
    print(f"❌ Failed: {r.status_code}")
PYEOF

pip install beautifulsoup
Traceback (most recent call last):
ModuleNotFoundError: No module named 'bs4'
(kalshi-bot) root@Kalshi-bot:~#
python3 - << 'PYEOF'
import requests
from bs4 import BeautifulSoup
headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
r = requests.get("https://www.basketball-reference.com/leagues/NBA_2025_per_game.html", headers=headers, timeout=15)
print(f"Status: {r.status_code}")
if r.status_code == 200:
    soup = BeautifulSoup(r.text, 'html.parser')
    table = soup.find('table', {'id': 'per_game_stats'})
    print(f"Table found: {table is not None}")
    if table:
        rows = table.find('tbody').find_all('tr')
        print(f"Rows: {len(rows)}")
        for row in rows[:3]:
            name_td = row.find('td', {'data-stat': 'name_display'})
            if name_td:
                print(f"  Sample: {name_td.get_text(strip=True)}")
PYEOF

pip install beautifulsoup4 --break-system-packages --quiet && python3 - << 'PYEOF'
import requests
from bs4 import BeautifulSoup
headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
r = requests.get("https://www.basketball-reference.com/leagues/NBA_2025_per_game.html", headers=headers, timeout=15)
print(f"Status: {r.status_code}")
if r.status_code == 200:
    soup = BeautifulSoup(r.text, 'html.parser')
    table = soup.find('table', {'id': 'per_game_stats'})
    print(f"Table found: {table is not None}")
    if table:
        rows = table.find('tbody').find_all('tr')
        players = {}
        for row in rows:
            name_td = row.find('td', {'data-stat': 'name_display'})
            pts_td = row.find('td', {'data-stat': 'pts_per_g'})
            gp_td = row.find('td', {'data-stat': 'g'})
            team_td = row.find('td', {'data-stat': 'team_name_abbr'})
            if name_td and pts_td:
                name = name_td.get_text(strip=True).upper()
                try:
                    pts = float(pts_td.get_text(strip=True) or 0)
                    gp = int(gp_td.get_text(strip=True) or 0)
                    team = team_td.get_text(strip=True) if team_td else ''
                    players[name] = {'pts': pts, 'gp': gp, 'team': team}
                except: pass
        print(f"Total players: {len(players)}")
        for name in ["JAYSON TATUM", "STEPHEN CURRY", "LEBRON JAMES", "NIKOLA JOKIC"]:
            p = players.get(name)
            if p:
                print(f"  ✅ {name}: GP={p['gp']} PTS={p['pts']} team={p['team']}")
            else:
                print(f"  ❌ {name}: not found")
PYEOF

python3 - << 'PYEOF'
import requests, time

for attempt in range(3):
    try:
        r = requests.get(
            "https://api.pbpstats.com/get-totals/nba",
            params={
                "Season": "2024-25",
                "SeasonType": "Regular Season",
                "Type": "Player",
                "pageSize": 500,
            },
            timeout=30,
        )
        print(f"Attempt {attempt+1}: Status {r.status_code}")
        if r.status_code == 200:
            data = r.json().get("data", [])
            print(f"Players: {len(data)}")
            for name in ["Jayson Tatum", "Stephen Curry", "LeBron James", "Nikola Jokic"]:
                p = next((x for x in data if x.get("playerName") == name), None)
                if p:
                    gp = p.get("games", 0)
                    pts = p.get("points", 0)
                    print(f"  ✅ {name}: GP={gp} avg={round(pts/max(gp,1),1)}pts playoff={p.get('isPlayoff')}")
                else:
                    print(f"  ❌ {name}: not found")
            break
        else:
            print(f"  Error: {r.text[:100]}")
            time.sleep(3)
    except Exception as e:
        print(f"Attempt {attempt+1} failed: {e}")
        time.sleep(3)
PYEOF

pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 8 && tail -10 kalshi_bot.log
python kalshi_bot.py
grep -n "is_bot.*False.*manual" strategies.py
ps aux | grep kalshi_bot | grep -v grep
nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot started" && sleep 10 && tail -10 kalshi_bot.log
python kalshi_bot.py -status
python kalshi_bot.py
git add nba_props.py strategies.py kalshi_bot.py && git commit -m "fix: nba props now uses pbpstats API with correct fields - regular season data working" && git push && pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 15 && tail -20 kalshi_bot.log
python kalshi_bot.py
pkill -f kalshi_bot.py && sleep 2 && nohup python kalshi_bot.py > /dev/null 2>&1 & echo "✅ Bot restarted" && sleep 15 && tail -20 kalshi_bot.log
pkill -f kalshi_bot.py
python kalshi_bot.py
pkill -f kalshi_bot.py
echo "Bot stopped"
sleep 2
python3 /root/kalshi_bot.py
python kalshi_bot.py
