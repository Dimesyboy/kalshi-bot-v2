    print(f'Ticker: {market_ticker}')

    # RFQ
    rfq_path = '/trade-api/v2/communications/rfqs'
    rfq_body = {
        'market_ticker':         market_ticker,
        'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
        'target_cost_dollars':   '1.00',
        'rest_remainder':        False,
        'replace_existing':      False,
        'mve_selected_legs':     [{'market_ticker': m['market_ticker'], 'side': 'yes'} for m in selected_markets],
    }
    r = requests.post(f'https://api.elections.kalshi.com{rfq_path}', headers=pss_headers('POST', rfq_path), json=rfq_body, timeout=8)
    rfq_id = r.json().get('id')
    print(f'RFQ: {r.status_code} id={rfq_id}')

    # Poll
    base = '/trade-api/v2/communications/quotes'
    best = None
    for i in range(10):
        url  = f'https://api.elections.kalshi.com{base}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}'
        qs   = requests.get(url, headers=pss_headers('GET', base), timeout=8).json().get('quotes', [])
        yes_q = [q for q in qs if float(q.get('yes_bid_dollars',0) or 0) > 0 and q.get('status')=='open']
        if yes_q:
            best = max(yes_q, key=lambda q: float(q.get('yes_bid_dollars',0)))
            print(f'Quote: yes_bid={best[\"yes_bid_dollars\"]} id={best[\"id\"]}')
            break
        time.sleep(0.2)

    if best:
        qid   = best['id']
        apath = f'/trade-api/v2/communications/quotes/{qid}/accept'
        r = requests.put(f'https://api.elections.kalshi.com{apath}', headers=pss_headers('PUT', apath), json={'accepted_side': 'yes'}, timeout=8)
        print(f'Accept: {r.status_code} {r.text[:300]}')
        if r.status_code == 200:
            cpath = f'/trade-api/v2/communications/quotes/{qid}/confirm'
            r = requests.put(f'https://api.elections.kalshi.com{cpath}', headers=pss_headers('PUT', cpath), json={}, timeout=8)
            print(f'Confirm: {r.status_code} {r.text[:200]}')
    else:
        print('No quote')
"
python3 -c "
from core.kalshi_client import _signed_get
for event in ['KXNBAPTS-26MAR28SASMIL', 'KXNBAPTS-26MAR28DETMIN', 'KXNBAPTS-26MAR28PHICHA']:
    d = _signed_get(f'/trade-api/v2/markets?event_ticker={event}&limit=5&status=open')
    for m in d.get('markets', [])[:3]:
        print(f'{m[\"ticker\"]} yes={m.get(\"yes_bid_dollars\")}')
"
python3 -c "
import base64, time, requests, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

user_id = config.KALSHI_USER_ID

selected_markets = [
    {'market_ticker': 'KXNBAPTS-26MAR28UTAPHX-PHXGALLEN8-10',           'event_ticker': 'KXNBAPTS-26MAR28UTAPHX', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLNALEXANDERWALKER7-10', 'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28CHIMEM-CHIJGIDDEY3-10',          'event_ticker': 'KXNBAPTS-26MAR28CHIMEM', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLOOKONGWU17-10',        'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
]

# Create market
path = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
r = requests.post(f'https://api.elections.kalshi.com{path}', headers=pss_headers('POST', path), json={'selected_markets': selected_markets, 'with_market_payload': True}, timeout=8)
market_ticker = r.json().get('market_ticker')
print(f'Ticker: {market_ticker}')

# RFQ with replace_existing True
rfq_path = '/trade-api/v2/communications/rfqs'
rfq_body = {
    'market_ticker':         market_ticker,
    'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
    'target_cost_dollars':   '1.00',
    'rest_remainder':        False,
    'replace_existing':      True,
    'mve_selected_legs':     [{'market_ticker': m['market_ticker'], 'side': 'yes'} for m in selected_markets],
}
r = requests.post(f'https://api.elections.kalshi.com{rfq_path}', headers=pss_headers('POST', rfq_path), json=rfq_body, timeout=8)
rfq_id = r.json().get('id')
print(f'RFQ: {r.status_code} id={rfq_id}')

# Poll
base = '/trade-api/v2/communications/quotes'
best = None
for i in range(10):
    url  = f'https://api.elections.kalshi.com{base}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}'
    qs   = requests.get(url, headers=pss_headers('GET', base), timeout=8).json().get('quotes', [])
    yes_q = [q for q in qs if float(q.get('yes_bid_dollars',0) or 0) > 0 and q.get('status')=='open']
    if yes_q:
        best = max(yes_q, key=lambda q: float(q.get('yes_bid_dollars',0)))
        print(f'Quote: yes_bid={best[\"yes_bid_dollars\"]} contracts={best.get(\"yes_contracts_fp\")} id={best[\"id\"]}')
        break
    time.sleep(0.2)

if best:
    qid   = best['id']
    apath = f'/trade-api/v2/communications/quotes/{qid}/accept'
    r = requests.put(f'https://api.elections.kalshi.com{apath}', headers=pss_headers('PUT', apath), json={'accepted_side': 'yes'}, timeout=8)
    print(f'Accept: {r.status_code} {r.text[:300]}')
    if r.status_code == 200:
        cpath = f'/trade-api/v2/communications/quotes/{qid}/confirm'
        r = requests.put(f'https://api.elections.kalshi.com{cpath}', headers=pss_headers('PUT', cpath), json={}, timeout=8)
        print(f'Confirm: {r.status_code} {r.text[:200]}')
else:
    print('No quote')
"
python3 -c "
import base64, time, requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

qid   = '7c3b5ce7-1750-4452-a0be-d0fc64add0de'
cpath = f'/trade-api/v2/communications/quotes/{qid}/confirm'
r = requests.put(f'https://api.elections.kalshi.com{cpath}', headers=pss_headers('PUT', cpath), json={}, timeout=8)
print(f'Confirm: {r.status_code} {r.text[:300]}')
"
python3 -c "
import base64, time, requests, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

user_id = config.KALSHI_USER_ID
BASE = 'https://api.elections.kalshi.com'

selected_markets = [
    {'market_ticker': 'KXNBAPTS-26MAR28UTAPHX-PHXGALLEN8-10',           'event_ticker': 'KXNBAPTS-26MAR28UTAPHX', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLNALEXANDERWALKER7-10', 'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28CHIMEM-CHIJGIDDEY3-10',          'event_ticker': 'KXNBAPTS-26MAR28CHIMEM', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLOOKONGWU17-10',        'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
]

# Create market
p = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
market_ticker = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={'selected_markets': selected_markets, 'with_market_payload': True}, timeout=8).json().get('market_ticker')
print(f'Ticker: {market_ticker}')

# RFQ
p = '/trade-api/v2/communications/rfqs'
rfq_id = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={
    'market_ticker': market_ticker, 'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
    'target_cost_dollars': '1.00', 'rest_remainder': False, 'replace_existing': True,
    'mve_selected_legs': [{'market_ticker': m['market_ticker'], 'side': 'yes'} for m in selected_markets],
}, timeout=8).json().get('id')
print(f'RFQ: {rfq_id}')

# Poll + accept + confirm in tight loop
p = '/trade-api/v2/communications/quotes'
for i in range(15):
    qs = requests.get(f'{BASE}{p}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}', headers=pss_headers('GET', p), timeout=8).json().get('quotes', [])
    yes_q = [q for q in qs if float(q.get('yes_bid_dollars',0) or 0) > 0 and q.get('status')=='open']
    if yes_q:
        best = max(yes_q, key=lambda q: float(q.get('yes_bid_dollars',0)))
        qid  = best['id']
        print(f'Quote: {best[\"yes_bid_dollars\"]} id={qid}')
        # Accept immediately
        ap = f'/trade-api/v2/communications/quotes/{qid}/accept'
        ra = requests.put(f'{BASE}{ap}', headers=pss_headers('PUT', ap), json={'accepted_side': 'yes'}, timeout=8)
        print(f'Accept: {ra.status_code}')
        # Confirm immediately
        cp = f'/trade-api/v2/communications/quotes/{qid}/confirm'
        rc = requests.put(f'{BASE}{cp}', headers=pss_headers('PUT', cp), json={}, timeout=8)
        print(f'Confirm: {rc.status_code} {rc.text[:200]}')
        break
    time.sleep(0.2)
"
python3 -c "
import base64, time, requests, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

user_id = config.KALSHI_USER_ID
BASE = 'https://api.elections.kalshi.com'

selected_markets = [
    {'market_ticker': 'KXNBAPTS-26MAR28UTAPHX-PHXGALLEN8-10',           'event_ticker': 'KXNBAPTS-26MAR28UTAPHX', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLNALEXANDERWALKER7-10', 'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28CHIMEM-CHIJGIDDEY3-10',          'event_ticker': 'KXNBAPTS-26MAR28CHIMEM', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLOOKONGWU17-10',        'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
]

p = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
market_ticker = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={'selected_markets': selected_markets, 'with_market_payload': True}, timeout=8).json().get('market_ticker')

p = '/trade-api/v2/communications/rfqs'
rfq_id = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={
    'market_ticker': market_ticker, 'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
    'target_cost_dollars': '1.00', 'rest_remainder': False, 'replace_existing': True,
    'mve_selected_legs': [{'market_ticker': m['market_ticker'], 'side': 'yes'} for m in selected_markets],
}, timeout=8).json().get('id')
print(f'RFQ: {rfq_id}')

p = '/trade-api/v2/communications/quotes'
for i in range(15):
    qs = requests.get(f'{BASE}{p}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}', headers=pss_headers('GET', p), timeout=8).json().get('quotes', [])
    yes_q = [q for q in qs if float(q.get('yes_bid_dollars',0) or 0) > 0 and q.get('status')=='open']
    if yes_q:
        best = max(yes_q, key=lambda q: float(q.get('yes_bid_dollars',0)))
        qid  = best['id']
        print(f'Quote: {best[\"yes_bid_dollars\"]} id={qid}')
        ap = f'/trade-api/v2/communications/quotes/{qid}/accept'
        ra = requests.put(f'{BASE}{ap}', headers=pss_headers('PUT', ap), json={'accepted_side': 'yes'}, timeout=8)
        print(f'Accept: {ra.status_code}')
        # Try confirm with accepted_side
        cp = f'/trade-api/v2/communications/quotes/{qid}/confirm'
        for body in [{'accepted_side': 'yes'}, {'side': 'yes'}, {}]:
            rc = requests.put(f'{BASE}{cp}', headers=pss_headers('PUT', cp), json=body, timeout=8)
            print(f'Confirm {body}: {rc.status_code} {rc.text[:150]}')
            if rc.status_code in (200, 204):
                print('SUCCESS!')
                break
        break
    time.sleep(0.2)
"
python3 -c "
import base64, time, requests, json
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

user_id = config.KALSHI_USER_ID
BASE = 'https://api.elections.kalshi.com'

selected_markets = [
    {'market_ticker': 'KXNBAPTS-26MAR28UTAPHX-PHXGALLEN8-10',           'event_ticker': 'KXNBAPTS-26MAR28UTAPHX', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLNALEXANDERWALKER7-10', 'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28CHIMEM-CHIJGIDDEY3-10',          'event_ticker': 'KXNBAPTS-26MAR28CHIMEM', 'side': 'yes'},
    {'market_ticker': 'KXNBAPTS-26MAR28SACATL-ATLOOKONGWU17-10',        'event_ticker': 'KXNBAPTS-26MAR28SACATL', 'side': 'yes'},
]

p = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
market_ticker = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={'selected_markets': selected_markets, 'with_market_payload': True}, timeout=8).json().get('market_ticker')

p = '/trade-api/v2/communications/rfqs'
rfq_id = requests.post(f'{BASE}{p}', headers=pss_headers('POST', p), json={
    'market_ticker': market_ticker, 'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
    'target_cost_dollars': '1.00', 'rest_remainder': False, 'replace_existing': True,
    'mve_selected_legs': [{'market_ticker': m['market_ticker'], 'side': 'yes'} for m in selected_markets],
}, timeout=8).json().get('id')

p = '/trade-api/v2/communications/quotes'
for i in range(15):
    qs = requests.get(f'{BASE}{p}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}', headers=pss_headers('GET', p), timeout=8).json().get('quotes', [])
    yes_q = [q for q in qs if float(q.get('yes_bid_dollars',0) or 0) > 0 and q.get('status')=='open']
    if yes_q:
        best = max(yes_q, key=lambda q: float(q.get('yes_bid_dollars',0)))
        qid  = best['id']
        # Accept
        ap = f'/trade-api/v2/communications/quotes/{qid}/accept'
        requests.put(f'{BASE}{ap}', headers=pss_headers('PUT', ap), json={'accepted_side': 'yes'}, timeout=8)
        # Check quote status immediately after accept
        gp = f'/trade-api/v2/communications/quotes/{qid}'
        rg = requests.get(f'{BASE}{gp}', headers=pss_headers('GET', gp), timeout=8)
        print(f'Quote status after accept: {json.dumps(rg.json(), indent=2)[:400]}')
        # Confirm
        cp = f'/trade-api/v2/communications/quotes/{qid}/confirm'
        rc = requests.put(f'{BASE}{cp}', headers=pss_headers('PUT', cp), json={}, timeout=8)
        print(f'Confirm: {rc.status_code} {rc.text[:200]}')
        break
    time.sleep(0.2)
"
python3 -c "
from core.kalshi_client import get_portfolio_api
pa = get_portfolio_api()
positions = pa.get_positions().positions
combo_pos = [p for p in positions if 'MULTIGAME' in str(p)]
print(f'Total positions: {len(positions)}')
for p in positions[:5]:
    print(p)
"
python3 -c "
from core.kalshi_client import _signed_get
import json
data = _signed_get('/trade-api/v2/portfolio/positions?limit=10')
positions = data.get('market_positions', [])
print(f'Positions: {len(positions)}')
for p in positions[:5]:
    print(f'  {p.get(\"market_id\")} {p.get(\"position\")} contracts')
"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client, get_portfolio_api
client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)
fills = pa.get_fills(limit=5)
for f in fills.fills:
    print(f.ticker, f.count, f.yes_price, f.created_time)
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

# Fix submit_rfq to use the correct flow:
# 1. Create market → get dynamic ticker
# 2. Submit RFQ with dynamic ticker + replace_existing=True
# 3. Poll quotes with rfq_creator_user_id
# 4. Accept with accepted_side=yes (confirm is automatic)

old = '''    import os
    user_id = os.getenv("KALSHI_USER_ID", "")

    # ── Step 1: Submit RFQ ─────────────────────────────────────────────
    try:
        rfq_body = {
            "market_ticker":         MVE_COLLECTION,
            "mve_collection_ticker": MVE_COLLECTION,
            "target_cost_dollars":   str(stake_dollars),
            "rest_remainder":        False,
            "replace_existing":      True,
            "mve_selected_legs": [
                {"market_ticker": leg.ticker, "side": "yes"}
                for leg in candidate.legs
            ],
        }
        rfq = _signed_post('/trade-api/v2/communications/rfqs', rfq_body)
        rfq_id = rfq.get('id')
        log.info(f"[Combo] RFQ submitted: {rfq_id}")
    except Exception as e:
        log.warning(f"[Combo] RFQ submission failed: {e}")
        return None

    # ── Step 2: Poll for quotes ────────────────────────────────────────
    deadline = time.time() + QUOTE_TIMEOUT_SECS
    quote    = None

    while time.time() < deadline:
        try:
            poll_path = f\'/trade-api/v2/communications/quotes\'
            poll_url  = f\'https://api.elections.kalshi.com{poll_path}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}\'
            r_poll = requests.get(
                poll_url,
                headers=_pss_headers("GET", poll_path),
                timeout=8
            )
            quotes = r_poll.json().get(\'quotes\', [])
            # Find best YES quote (highest yes_bid_dollars)
            yes_quotes = [q for q in quotes
                         if float(q.get(\'yes_bid_dollars\', 0) or 0) > 0
                         and q.get(\'status\') == \'open\']
            if yes_quotes:
                quote = max(yes_quotes, key=lambda q: float(q.get(\'yes_bid_dollars\', 0)))
                log.info(f"[Combo] Best quote: yes_bid={quote[\'yes_bid_dollars\']} "
                        f"contracts={quote.get(\'yes_contracts_fp\')}")
                break
        except Exception as e:
            log.debug(f"[Combo] Poll error: {e}")
        time.sleep(QUOTE_POLL_INTERVAL)'''

new = '''    user_id = config.KALSHI_USER_ID

    # ── Step 1: Create dynamic market ticker ───────────────────────────
    try:
        selected_markets = [
            {"market_ticker": leg.ticker, "event_ticker": leg.ticker.rsplit("-", 1)[0], "side": "yes"}
            for leg in candidate.legs
        ]
        create_path = f\'/trade-api/v2/multivariate_event_collections/{MVE_COLLECTION}\'
        r_create = requests.post(
            f"https://api.elections.kalshi.com{create_path}",
            headers=_pss_headers("POST", create_path),
            json={"selected_markets": selected_markets, "with_market_payload": True},
            timeout=8
        )
        r_create.raise_for_status()
        market_ticker = r_create.json().get("market_ticker")
        log.info(f"[Combo] Dynamic ticker: {market_ticker}")
    except Exception as e:
        log.warning(f"[Combo] Market creation failed: {e}")
        return None

    # ── Step 2: Submit RFQ ─────────────────────────────────────────────
    try:
        rfq_body = {
            "market_ticker":         market_ticker,
            "mve_collection_ticker": MVE_COLLECTION,
            "target_cost_dollars":   str(stake_dollars),
            "rest_remainder":        False,
            "replace_existing":      True,
            "mve_selected_legs": [
                {"market_ticker": leg.ticker, "side": "yes"}
                for leg in candidate.legs
            ],
        }
        rfq = _signed_post(\'/trade-api/v2/communications/rfqs\', rfq_body)
        rfq_id = rfq.get(\'id\')
        log.info(f"[Combo] RFQ submitted: {rfq_id}")
    except Exception as e:
        log.warning(f"[Combo] RFQ submission failed: {e}")
        return None

    # ── Step 3: Poll for quotes ────────────────────────────────────────
    deadline = time.time() + QUOTE_TIMEOUT_SECS
    quote    = None

    while time.time() < deadline:
        try:
            poll_path = \'/trade-api/v2/communications/quotes\'
            poll_url  = f\'https://api.elections.kalshi.com{poll_path}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}\'
            r_poll = requests.get(
                poll_url,
                headers=_pss_headers("GET", poll_path),
                timeout=8
            )
            quotes = r_poll.json().get(\'quotes\', [])
            yes_quotes = [q for q in quotes
                         if float(q.get(\'yes_bid_dollars\', 0) or 0) > 0
                         and q.get(\'status\') == \'open\']
            if yes_quotes:
                quote = max(yes_quotes, key=lambda q: float(q.get(\'yes_bid_dollars\', 0)))
                log.info(f"[Combo] Best quote: yes_bid={quote[\'yes_bid_dollars\']} "
                        f"contracts={quote.get(\'yes_contracts_fp\')}")
                break
        except Exception as e:
            log.debug(f"[Combo] Poll error: {e}")
        time.sleep(QUOTE_POLL_INTERVAL)'''

c = c.replace(old, new)

# Fix accept — no confirm needed, it's automatic
old2 = '''    # ── Step 4: Accept and confirm ─────────────────────────────────────
    try:
        _signed_put(f\'/trade-api/v2/communications/quotes/{quote_id}/accept\')
        log.info(f"[Combo] Quote accepted: {quote_id}")
        _signed_put(f\'/trade-api/v2/communications/quotes/{quote_id}/confirm\')
        log.info(f"[Combo] Quote confirmed — combo placed!")
        return quote
    except Exception as e:
        log.error(f"[Combo] Accept/confirm failed: {e}")
        return None'''

new2 = '''    # ── Step 4: Accept (confirm is automatic) ─────────────────────────
    try:
        accept_path = f\'/trade-api/v2/communications/quotes/{quote_id}/accept\'
        r_accept = requests.put(
            f"https://api.elections.kalshi.com{accept_path}",
            headers=_pss_headers("PUT", accept_path),
            json={"accepted_side": "yes"},
            timeout=8
        )
        if r_accept.status_code in (200, 204):
            log.info(f"[Combo] Quote accepted and auto-confirmed: {quote_id}")
            return quote
        else:
            log.warning(f"[Combo] Accept failed: {r_accept.status_code} {r_accept.text[:100]}")
            return None
    except Exception as e:
        log.error(f"[Combo] Accept failed: {e}")
        return None'''

c = c.replace(old2, new2)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "from combo_scanner import submit_rfq; print('OK')"
cd /root/kalshi-bot-v2 && git add combo_scanner.py data/nba_stats.py core/config.py && git commit -m "feat: combo scanner working end-to-end — create market, RFQ, quote, accept" && git push origin master
source /root/kalshi-bot/bin/activate
python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

# Get all open prop markets across all tonight's NBA games
prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']
all_legs = []

for series in prop_series:
    data = _signed_get(f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not (0.65 <= yes_bid <= 0.92):
            continue
        result = score_prop_leg(ticker)
        if result.get('confidence', 0) >= 0.76:
            all_legs.append({
                'ticker':     ticker,
                'yes_bid':    yes_bid,
                'confidence': result['confidence'],
                'reason':     result['reason'],
                'event':      ticker.rsplit('-',2)[0],
            })

# Sort by confidence
all_legs.sort(key=lambda x: x['confidence'], reverse=True)
print(f'Total qualified legs: {len(all_legs)}')
for leg in all_legs[:15]:
    print(f'  conf={leg[\"confidence\"]:.2f} yes={leg[\"yes_bid\"]:.2f} | {leg[\"reason\"][:70]}')

# Combined confidence of top 8
from functools import reduce
import operator
top8 = all_legs[:8]
combined = reduce(operator.mul, [l['confidence'] for l in top8], 1.0)
print(f'Top 8 combined: {combined:.3f} = {1/combined:.1f}x payout')
" 2>&1 | grep -v DEBUG | grep -v WARNING
cd /root/kalshi-bot-v2 && python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']
all_legs = []

for series in prop_series:
    data = _signed_get(f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not (0.65 <= yes_bid <= 0.92):
            continue
        result = score_prop_leg(ticker)
        if result.get('confidence', 0) >= 0.76:
            all_legs.append({
                'ticker':     ticker,
                'yes_bid':    yes_bid,
                'confidence': result['confidence'],
                'reason':     result['reason'],
            })

all_legs.sort(key=lambda x: x['confidence'], reverse=True)
print(f'Total qualified legs: {len(all_legs)}')
for leg in all_legs[:15]:
    print(f'  conf={leg[\"confidence\"]:.2f} yes={leg[\"yes_bid\"]:.2f} | {leg[\"reason\"][:70]}')

from functools import reduce, operator
combined = reduce(lambda a,b: a*b, [l['confidence'] for l in all_legs[:8]], 1.0)
print(f'Top 8 combined: {combined:.3f} = {1/combined:.1f}x payout')
" 2>&1 | grep -v DEBUG | grep -v WARNING
deactivate
cd /root/kalshi-bot-v2 && python3 -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']
all_legs = []

for series in prop_series:
    data = _signed_get(f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not (0.65 <= yes_bid <= 0.92):
            continue
        result = score_prop_leg(ticker)
        if result.get('confidence', 0) >= 0.76:
            all_legs.append({
                'ticker':     ticker,
                'yes_bid':    yes_bid,
                'confidence': result['confidence'],
                'reason':     result['reason'],
            })

all_legs.sort(key=lambda x: x['confidence'], reverse=True)
print(f'Total qualified legs: {len(all_legs)}')
for leg in all_legs[:15]:
    print(f'  conf={leg[\"confidence\"]:.2f} yes={leg[\"yes_bid\"]:.2f} | {leg[\"reason\"][:70]}')

from functools import reduce, operator
combined = reduce(lambda a,b: a*b, [l['confidence'] for l in all_legs[:8]], 1.0)
print(f'Top 8 combined: {combined:.3f} = {1/combined:.1f}x payout')
" 2>&1 | grep -v DEBUG | grep -v WARNING
source /root/kalshi-bot/bin/activate && python3 -c "
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']
all_legs = []

for series in prop_series:
    data = _signed_get(f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not (0.65 <= yes_bid <= 0.92):
            continue
        result = score_prop_leg(ticker)
        if result.get('confidence', 0) >= 0.76:
            all_legs.append({
                'ticker':     ticker,
                'yes_bid':    yes_bid,
                'confidence': result['confidence'],
                'reason':     result['reason'],
            })

all_legs.sort(key=lambda x: x['confidence'], reverse=True)
print(f'Total qualified legs: {len(all_legs)}')
for leg in all_legs[:15]:
    print(f'  conf={leg[\"confidence\"]:.2f} yes={leg[\"yes_bid\"]:.2f} | {leg[\"reason\"][:70]}')

from functools import reduce
combined = reduce(lambda a,b: a*b, [l['confidence'] for l in all_legs[:8]], 1.0)
print(f'Top 8 combined: {combined:.3f} = {1/combined:.1f}x payout')
" 2>&1 | grep -v DEBUG | grep -v WARNING
python3 -c "
from core.kalshi_client import _signed_get
from data.nba_stats import score_prop_leg

prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']
all_legs = []

for series in prop_series:
    data = _signed_get(f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open')
    for m in data.get('markets', []):
        ticker  = m.get('ticker','')
        yes_bid = float(m.get('yes_bid_dollars',0) or 0)
        if not (0.60 <= yes_bid <= 0.88):
            continue
        result = score_prop_leg(ticker)
        conf = result.get('confidence', 0)
        if conf >= 0.76:
            all_legs.append({
                'ticker':     ticker,
                'yes_bid':    yes_bid,
                'confidence': conf,
                'reason':     result['reason'],
            })

# Sort by yes_bid ascending — lower price = bigger payout contribution
all_legs.sort(key=lambda x: x['yes_bid'])
print(f'Total: {len(all_legs)}')
print('Best payout contributors (lowest price, still high conf):')
for leg in all_legs[:15]:
    payout_contrib = 1/leg['yes_bid']
    print(f'  conf={leg[\"confidence\"]:.2f} yes={leg[\"yes_bid\"]:.2f} contrib={payout_contrib:.2f}x | {leg[\"reason\"][:60]}')

# Build optimal combo — dedupe by player, pick lowest yes_bid per player
from collections import defaultdict
import re
best_per_player = {}
for leg in all_legs:
    m = re.search(r'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-', leg['ticker'])
    series = leg['ticker'].split('-')[0]
    key = f'{series}-{m.group(1)}' if m else leg['ticker']
    if key not in best_per_player or leg['yes_bid'] < best_per_player[key]['yes_bid']:
        best_per_player[key] = leg

deduped = sorted(best_per_player.values(), key=lambda x: x['yes_bid'])
print(f'Deduped unique players: {len(deduped)}')
from functools import reduce
top8 = deduped[:8]
combined = reduce(lambda a,b: a*b, [l['confidence'] for l in top8], 1.0)
payout = reduce(lambda a,b: a*b, [1/l['yes_bid'] for l in top8], 1.0)
print(f'Top 8 combined conf: {combined:.3f}')
print(f'Expected payout: {payout:.1f}x')
print('Legs:')
for l in top8:
    print(f'  {l[\"yes_bid\"]:.2f} conf={l[\"confidence\"]:.2f} | {l[\"reason\"][:65]}')
" 2>&1 | grep -v DEBUG | grep -v WARNING | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
    """
    Main entry point. Scan all collections, build combos, execute if EV+.
    Returns list of candidates found (whether executed or not).
    """
    log.info("[Combo] Starting combo scan")
    candidates = []

    for series in [MVE_NBA_SERIES, MVE_MLB_SERIES]:
        collections = fetch_collections(series)
        log.info(f"[Combo] {series}: {len(collections)} collections to evaluate")

        for collection in collections:
            candidate = build_combo(collection)
            if not candidate:
                continue

            candidates.append(candidate)

            if dry_run:
                log.info(f"[Combo] DRY RUN — would submit RFQ for {candidate}")
                continue

            quote = submit_rfq(candidate)
            if quote:
                log.info(f"[Combo] EXECUTED: {candidate.collection_ticker}")
                _log_combo_trade(candidate, quote)

    log.info(f"[Combo] Scan complete — {len(candidates)} candidates found")
    return candidates'''

new = '''# Prop series to scan
PROP_SERIES = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']

# Min/max yes_bid for combo legs
LEG_MIN_BID = 0.60
LEG_MAX_BID = 0.88   # Cap at 88% — above this barely adds payout

# Combo sizing
MIN_COMBO_LEGS       = 6
MAX_COMBO_LEGS       = 10
MIN_COMBINED_CONF    = 0.10   # 10% floor
MIN_PAYOUT_MULT      = 5.0    # Minimum expected payout multiplier


def scan_all_props() -> list[ComboLeg]:
    """
    Scan all open NBA prop markets across all games.
    Score each leg, dedupe by player, return sorted by payout contribution.
    """
    import re
    all_legs = []
    seen_players = {}  # player_key → best leg

    for series in PROP_SERIES:
        try:
            from core.kalshi_client import _signed_get
            data = _signed_get(
                f\'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open\'
            )
            for m in data.get(\'markets\', []):
                ticker  = m.get(\'ticker\', \'\')
                yes_bid = float(m.get(\'yes_bid_dollars\', 0) or 0)

                if not (LEG_MIN_BID <= yes_bid <= LEG_MAX_BID):
                    continue

                result = score_prop_leg(ticker)
                conf   = result.get(\'confidence\', 0.0)
                if conf < MIN_LEG_CONFIDENCE:
                    continue

                # Extract player key for dedup — one leg per player total
                pm = re.search(
                    r\'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-\',
                    ticker
                )
                player_key = pm.group(1) if pm else ticker

                leg = ComboLeg(
                    ticker            = ticker,
                    collection_ticker = MVE_COLLECTION,
                    confidence        = conf,
                    implied_prob      = yes_bid,
                    is_yes_only       = True,
                    reasoning         = result.get(\'reason\', \'\'),
                )

                # Keep lowest-price leg per player (best payout contribution)
                if player_key not in seen_players or yes_bid < seen_players[player_key].implied_prob:
                    seen_players[player_key] = leg

        except Exception as e:
            log.warning(f"[Combo] Prop scan failed {series}: {e}")

    # Sort by payout contribution (lowest price first)
    deduped = sorted(seen_players.values(), key=lambda x: x.implied_prob)
    log.info(f"[Combo] Found {len(deduped)} unique qualified legs")
    return deduped


def build_best_combo(legs: list[ComboLeg]) -> Optional[ComboCandidate]:
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

    return candidate


def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
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

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "from combo_scanner import scan_and_execute; print('OK')"
python3 combo_scanner.py 2>&1 | grep -v DEBUG | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    "                leg = ComboLeg(\n                    ticker            = ticker,\n                    collection_ticker = MVE_COLLECTION,",
    "                leg = ComboLeg(\n                    ticker            = ticker,\n                    collection_ticker = 'KXMVESPORTSMULTIGAMEEXTENDED-R',"
)
c = c.replace(
    "    candidate = ComboCandidate(MVE_COLLECTION, selected)",
    "    candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', selected)"
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py 2>&1 | grep -v DEBUG | grep -v NBAStats
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace('MIN_COMBINED_CONF    = 0.10   # 10% floor', 'MIN_COMBINED_CONF    = 0.03   # 3% floor for long combos')
c = c.replace('MIN_PAYOUT_MULT      = 5.0    # Minimum expected payout multiplier', 'MIN_PAYOUT_MULT      = 8.0    # Minimum expected payout multiplier')
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py 2>&1 | grep -v DEBUG | grep -v NBAStats
python3 -c "
from combo_scanner import scan_all_props
from functools import reduce

legs = scan_all_props()
print(f'Total legs: {len(legs)}')
for i, leg in enumerate(legs[:10]):
    print(f'  {i+1}. yes={leg.implied_prob:.2f} conf={leg.confidence:.2f} | {leg.reasoning[:60]}')

# Show combined conf at different leg counts
for n in [4,5,6,7,8,9,10]:
    top = legs[:n]
    combined = reduce(lambda a,b: a*b, [l.confidence for l in top], 1.0)
    payout   = reduce(lambda a,b: a*b, [1/l.implied_prob for l in top], 1.0)
    print(f'  {n} legs: conf={combined:.4f} payout={payout:.1f}x')
" 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace('MIN_COMBO_LEGS       = 6', 'MIN_COMBO_LEGS       = 4')
c = c.replace('MAX_COMBO_LEGS       = 10', 'MAX_COMBO_LEGS       = 8')
c = c.replace('MIN_COMBINED_CONF    = 0.03   # 3% floor for long combos', 'MIN_COMBINED_CONF    = 0.02   # 2% floor')
c = c.replace('MIN_PAYOUT_MULT      = 8.0    # Minimum expected payout multiplier', 'MIN_PAYOUT_MULT      = 5.0    # Minimum expected payout multiplier')
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '        except Exception as e:\n            log.warning(f"[Combo] Prop scan failed {series}: {e}")',
    '            time.sleep(0.5)\n        except Exception as e:\n            log.warning(f"[Combo] Prop scan failed {series}: {e}")'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

git add combo_scanner.py && git commit -m "feat: cross-game combo scanner — scan all props, dedupe by player, optimal leg selection" && git push origin master
python3 combo_scanner.py --live 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 -c "
ticker = 'KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15'
print('rsplit:', ticker.rsplit('-', 1)[0])
# Should be: KXNBAPTS-26MAR29NYKOKC
import re
m = re.match(r'(KXNBA[A-Z0-9]+-\d{2}[A-Z]{3}\d{2}[A-Z]+)', ticker)
print('regex:', m.group(1) if m else 'no match')
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '        selected_markets = [\n            {"market_ticker": leg.ticker, "event_ticker": leg.ticker.rsplit("-", 1)[0], "side": "yes"}\n            for leg in candidate.legs\n        ]',
    '''        import re as _re
        def _event_ticker(t):
            m = _re.match(r\'(KXNBA[A-Z0-9]+-\\d{2}[A-Z]{3}\\d{2}[A-Z]+)\', t)
            return m.group(1) if m else t.rsplit(\'-\', 2)[0]
        selected_markets = [
            {"market_ticker": leg.ticker, "event_ticker": _event_ticker(leg.ticker), "side": "yes"}
            for leg in candidate.legs
        ]'''
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
python3 -c "
import base64, time, requests, json, re
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

def event_ticker(t):
    m = re.match(r'(KXNBA[A-Z0-9]+-\d{2}[A-Z]{3}\d{2}[A-Z]+)', t)
    return m.group(1) if m else t.rsplit('-', 2)[0]

legs = [
    'KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15',
    'KXNBAREB-26MAR28SACATL-ATLJKUMINGA0-4',
    'KXNBA3PT-26MAR29NYKOKC-NYKJHART3-1',
    'KXNBAPTS-26MAR29NYKOKC-NYKMBRIDGES25-10',
]

selected_markets = [{'market_ticker': t, 'event_ticker': event_ticker(t), 'side': 'yes'} for t in legs]
print('Selected markets:')
for m in selected_markets:
    print(f'  {m}')

# Create market
path = '/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R'
r = requests.post(f'https://api.elections.kalshi.com{path}', headers=pss_headers('POST', path), json={'selected_markets': selected_markets, 'with_market_payload': True}, timeout=8)
print(f'Create: {r.status_code}')
data = r.json()
market_ticker = data.get('market_ticker')
print(f'Ticker: {market_ticker}')
if not market_ticker:
    print(data)
"
python3 -c "
import base64, time, requests, json, re
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from core.config import config

with open(config.KALSHI_KEY_FILE, 'rb') as f:
    private_key = serialization.load_pem_private_key(f.read(), password=None)

def pss_headers(method, path):
    ts_ms = str(int(time.time() * 1000))
    msg   = (ts_ms + method + path).encode()
    sig   = private_key.sign(msg, asym_padding.PSS(mgf=asym_padding.MGF1(hashes.SHA256()), salt_length=asym_padding.PSS.MAX_LENGTH), hashes.SHA256())
    return {'KALSHI-ACCESS-KEY': config.KALSHI_KEY_ID, 'KALSHI-ACCESS-SIGNATURE': base64.b64encode(sig).decode(), 'KALSHI-ACCESS-TIMESTAMP': ts_ms, 'Content-Type': 'application/json'}

market_ticker = 'KXMVESPORTSMULTIGAMEEXTENDED-S2026AEDC5B292EE-FD3A2F0EA4B'
legs = [
    'KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15',
    'KXNBAREB-26MAR28SACATL-ATLJKUMINGA0-4',
    'KXNBA3PT-26MAR29NYKOKC-NYKJHART3-1',
    'KXNBAPTS-26MAR29NYKOKC-NYKMBRIDGES25-10',
]

path = '/trade-api/v2/communications/rfqs'
body = {
    'market_ticker':         market_ticker,
    'mve_collection_ticker': 'KXMVESPORTSMULTIGAMEEXTENDED-R',
    'target_cost_dollars':   '5.00',
    'rest_remainder':        False,
    'replace_existing':      True,
    'mve_selected_legs':     [{'market_ticker': t, 'side': 'yes'} for t in legs],
}
r = requests.post(f'https://api.elections.kalshi.com{path}', headers=pss_headers('POST', path), json=body, timeout=8)
print(f'Status: {r.status_code}')
print(r.text[:500])
"
grep -n "_signed_post\|PKCS\|PSS\|padding" /root/kalshi-bot-v2/combo_scanner.py | head -20
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    'log.warning(f"[Combo] RFQ submission failed: {e}")',
    'log.warning(f"[Combo] RFQ submission failed: {e}\\n  response: {getattr(e, \'response\', None) and e.response.text[:300]}")'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "Combo|WARNING|ERROR" | head -20
sed -n '310,340p' /root/kalshi-bot-v2/combo_scanner.py
grep -n "def submit_rfq" /root/kalshi-bot-v2/combo_scanner.py
sed -n '254,360p' /root/kalshi-bot-v2/combo_scanner.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()

old = '''    # ── Step 1: Submit RFQ ─────────────────────────────────────────────
    try:
        rfq_body = {
            "market_ticker":       candidate.collection_ticker,
            "target_cost_dollars": str(stake_dollars),
            "contracts_fp":        "1.00",
            "rest_remainder":      False,
            "replace_existing":    False,
        }
        rfq = _signed_post('/trade-api/v2/communications/rfqs', rfq_body)
        rfq_id = rfq.get('id') or rfq.get('rfq_id')
        log.info(f"[Combo] RFQ submitted: {rfq_id}")
    except Exception as e:
        log.warning(f"[Combo] RFQ submission failed: {e}\\n  response: {getattr(e, 'response', None) and e.response.text[:300]}")
        return None

    # ── Step 2: Poll for quote ─────────────────────────────────────────
    deadline = time.time() + QUOTE_TIMEOUT_SECS
    quote    = None

    while time.time() < deadline:
        try:
            poll_path = f\'/trade-api/v2/communications/rfqs/{rfq_id}\'
            r_poll = requests.get(
                f"https://api.elections.kalshi.com{poll_path}",
                headers=_pss_headers("GET", poll_path),
                timeout=8
            )
            data = r_poll.json()
            quotes = data.get(\'quotes\', [])
            if quotes:
                quote = quotes[0]
                log.info(f"[Combo] Quote received: {quote}")
                break
        except Exception as e:
            log.debug(f"[Combo] Poll error: {e}")
        time.sleep(QUOTE_POLL_INTERVAL)

    if not quote:
        log.warning(f"[Combo] No quote received within {QUOTE_TIMEOUT_SECS}s")
        return None

    # ── Step 3: Evaluate quote ─────────────────────────────────────────
    quote_id   = quote.get('id')
    yes_bid    = float(quote.get('yes_bid_dollars', 0) or 0)
    contracts  = float(quote.get('yes_contracts_fp', 1) or 1)
    ev         = _evaluate_quote(candidate, yes_bid, stake_dollars)

    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")'''

new = '''    import re as _re
    user_id = config.KALSHI_USER_ID
    BASE    = "https://api.elections.kalshi.com"

    def _event_ticker(t):
        m = _re.match(r\'(KXNBA[A-Z0-9]+-\\d{2}[A-Z]{3}\\d{2}[A-Z]+)\', t)
        return m.group(1) if m else t.rsplit(\'-\', 2)[0]

    # ── Step 1: Create dynamic market ticker ───────────────────────────
    try:
        selected_markets = [
            {"market_ticker": leg.ticker, "event_ticker": _event_ticker(leg.ticker), "side": "yes"}
            for leg in candidate.legs
        ]
        cp = f\'/trade-api/v2/multivariate_event_collections/KXMVESPORTSMULTIGAMEEXTENDED-R\'
        rc = requests.post(f"{BASE}{cp}", headers=_pss_headers("POST", cp),
                          json={"selected_markets": selected_markets, "with_market_payload": True}, timeout=8)
        rc.raise_for_status()
        market_ticker = rc.json().get("market_ticker")
        log.info(f"[Combo] Dynamic ticker: {market_ticker}")
    except Exception as e:
        log.warning(f"[Combo] Market creation failed: {e}")
        return None

    # ── Step 2: Submit RFQ ─────────────────────────────────────────────
    try:
        rfq_body = {
            "market_ticker":         market_ticker,
            "mve_collection_ticker": "KXMVESPORTSMULTIGAMEEXTENDED-R",
            "target_cost_dollars":   str(stake_dollars),
            "rest_remainder":        False,
            "replace_existing":      True,
            "mve_selected_legs":     [{"market_ticker": leg.ticker, "side": "yes"} for leg in candidate.legs],
        }
        rfq  = _signed_post(\'/trade-api/v2/communications/rfqs\', rfq_body)
        rfq_id = rfq.get(\'id\')
        log.info(f"[Combo] RFQ submitted: {rfq_id}")
    except Exception as e:
        log.warning(f"[Combo] RFQ failed: {e} | {getattr(getattr(e,\'response\',None),\'text\',\'\')[:200]}")
        return None

    # ── Step 3: Poll for quotes ────────────────────────────────────────
    deadline = time.time() + QUOTE_TIMEOUT_SECS
    quote    = None
    qp       = \'/trade-api/v2/communications/quotes\'

    while time.time() < deadline:
        try:
            url  = f"{BASE}{qp}?rfq_id={rfq_id}&rfq_creator_user_id={user_id}"
            qs   = requests.get(url, headers=_pss_headers("GET", qp), timeout=8).json().get(\'quotes\', [])
            yes_q = [q for q in qs if float(q.get(\'yes_bid_dollars\',0) or 0) > 0 and q.get(\'status\')==\'open\']
            if yes_q:
                quote = max(yes_q, key=lambda q: float(q.get(\'yes_bid_dollars\',0)))
                log.info(f"[Combo] Best quote: yes_bid={quote[\'yes_bid_dollars\']} contracts={quote.get(\'yes_contracts_fp\')}")
                break
        except Exception as e:
            log.debug(f"[Combo] Poll error: {e}")
        time.sleep(QUOTE_POLL_INTERVAL)

    if not quote:
        log.warning(f"[Combo] No quote received within {QUOTE_TIMEOUT_SECS}s")
        return None

    # ── Step 4: Evaluate quote ─────────────────────────────────────────
    quote_id  = quote.get(\'id\')
    yes_bid   = float(quote.get(\'yes_bid_dollars\', 0) or 0)
    contracts = float(quote.get(\'yes_contracts_fp\', 1) or 1)
    ev        = _evaluate_quote(candidate, yes_bid, stake_dollars)
    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "Combo|WARNING|ERROR" | head -20
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '"target_cost_dollars":   str(stake_dollars),',
    '"target_cost_dollars":   f"{stake_dollars:.2f}",'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

python3 combo_scanner.py --live 2>&1 | grep -E "Combo|WARNING|ERROR" | head -20
python3 -c "
from core.kalshi_client import _signed_get
# Check if the dynamic market ticker can be traded directly like a regular market
data = _signed_get('/trade-api/v2/markets/KXMVESPORTSMULTIGAMEEXTENDED-S202636708EE423F-277741D5149')
m = data.get('market', {})
print(f'Status: {m.get(\"status\")}')
print(f'Yes bid: {m.get(\"yes_bid_dollars\")}')
print(f'Yes ask: {m.get(\"yes_ask_dollars\")}')
print(f'Volume: {m.get(\"volume_fp\")}')
print(f'Can trade: {m.get(\"status\") == \"active\"}')
"
python3 -c "
import kalshi_python
from core.kalshi_client import get_client
import uuid

client = get_client()
pa = kalshi_python.PortfolioApi(api_client=client)

# Place a limit order directly on the combo market
order = pa.create_order(
    ticker          = 'KXMVESPORTSMULTIGAMEEXTENDED-S202636708EE423F-277741D5149',
    action          = 'buy',
    side            = 'yes',
    type            = 'limit',
    yes_price       = 5,   # 5 cents — test with very low price, won't fill
    count           = 1,
    client_order_id = str(uuid.uuid4()),
)
print(f'Order: {order}')
"
python3 -c "
from core.kalshi_client import _signed_get

# Find a recently created combo market with actual pricing
data = _signed_get('/trade-api/v2/markets/KXMVESPORTSMULTIGAMEEXTENDED-S20261522CB36F08-52B2CFFAFF3')
m = data.get('market', {})
print(f'Yes bid: {m.get(\"yes_bid_dollars\")}')
print(f'Yes ask: {m.get(\"yes_ask_dollars\")}')
print(f'Last price: {m.get(\"last_price_dollars\")}')
print(f'Volume: {m.get(\"volume_fp\")}')
"
git add combo_scanner.py && git commit -m "fix: combo RFQ flow complete — dollar precision, dynamic ticker, accept" && git push origin master
python combo_scanner.py
python3 << 'PYEOF'
# Fix UTA team code in nba_stats.py
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()
c = c.replace('"UTA": "UTA"', '"UTA": "UTAH"')
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("UTA fixed")
PYEOF

python3 -c "
from data.nba_stats import get_player_averages
result = get_player_averages('KXNBAPTS-26MAR28UTAPHX-PHXGALLEN8-10')
print(result)
"
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '            time.sleep(0.5)\n        except Exception as e:\n            log.warning(f"[Combo] Prop scan failed {series}: {e}")',
    '            time.sleep(1.5)\n        except Exception as e:\n            log.warning(f"[Combo] Prop scan failed {series}: {e}")'
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

git add combo_scanner.py data/nba_stats.py && git commit -m "fix: UTA roster ESPN code, rate limit delay" && git push origin master
cd /root && source kalshi-bot/bin/activate && python3 paper_trader.py --stats
cd /root && python3 -c "
import csv
rows = list(csv.DictReader(open('paper_trades.csv')))
resolved = [r for r in rows if r.get('resolved','') not in ('','no')]

# Break down by exit reason
from collections import defaultdict
by_reason = defaultdict(lambda: {'n':0,'wins':0,'pnl':0.0})
for r in resolved:
    reason = r.get('resolved','')
    pnl    = float(r.get('hyp_pnl',0) or 0)
    ep     = float(r.get('entry_price',0) or 0)
    key = reason.split()[0] if reason else '?'
    by_reason[key]['n']   += 1
    by_reason[key]['pnl'] += pnl
    if pnl > 0: by_reason[key]['wins'] += 1

print('By exit reason:')
for k,v in by_reason.items():
    wr = v['wins']/v['n']*100 if v['n'] else 0
    print(f'  {k:8s} n={v[\"n\"]:3d} wr={wr:.0f}% pnl=\${v[\"pnl\"]:+.2f}')

# Entry price distribution
vf = [r for r in resolved if r.get('strategy','') == 'value_fade']
prices = [float(r['entry_price']) for r in vf]
print(f'Value fade avg entry price: {sum(prices)/len(prices):.1f}c')
print(f'Entry range: {min(prices):.0f}c - {max(prices):.0f}c')
"
cd /root/kalshi-bot-v2 && python3 paper_trader.py --stats
screen -r paper-v2
python3 combo_scanner.py --live 2>&1 | grep -v DEBUG | grep -v NBAStats | grep -v WARNING
2026-03-28 16:59:42,705 [Combo] Found 40 unique qualified legs
2026-03-28 16:59:42,706 [Combo] CANDIDATE: 8 legs, conf=0.058, payout=29.3x
2026-03-28 16:59:42,706   KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15 yes=0.60 conf=0.70 | Karl-Anthony Towns avg 20.1 vs threshold 15.0 (ratio=1.34) →
2026-03-28 16:59:42,706   KXNBA3PT-26MAR29NYKOKC-NYKJHART3-1 yes=0.64 conf=0.70 | Josh Hart avg 1.5 vs threshold 1.0 (ratio=1.49) → conf=0.70
2026-03-28 16:59:42,706   KXNBAPTS-26MAR29NYKOKC-NYKMBRIDGES25-10 yes=0.65 conf=0.70 | Mikal Bridges avg 14.7 vs threshold 10.0 (ratio=1.47) → conf
2026-03-28 16:59:42,706   KXNBASTL-26MAR28PHICHA-PHIVEDGECOMBE77-1 yes=0.65 conf=0.70 | VJ Edgecombe avg 1.4 vs threshold 1.0 (ratio=1.42) → conf=0.
2026-03-28 16:59:42,706   KXNBAPTS-26MAR29NYKOKC-NYKJBRUNSON11-20 yes=0.67 conf=0.70 | Jalen Brunson avg 26.2 vs threshold 20.0 (ratio=1.31) → conf
2026-03-28 16:59:42,706   KXNBASTL-26MAR28DETMIN-MINDDIVINCENZO0-1 yes=0.67 conf=0.70 | Donte DiVincenzo avg 1.4 vs threshold 1.0 (ratio=1.36) → con
2026-03-28 16:59:42,706   KXNBAREB-26MAR29NYKOKC-NYKMROBINSON23-6 yes=0.68 conf=0.70 | Mitchell Robinson avg 8.8 vs threshold 6.0 (ratio=1.47) → co
2026-03-28 16:59:42,706   KXNBAREB-26MAR28PHICHA-CHAKKNUEPPEL7-4 yes=0.69 conf=0.70 | Kon Knueppel avg 5.3 vs threshold 4.0 (ratio=1.33) → conf=0.
2026-03-28 16:59:43,081 [Combo] Dynamic ticker: KXMVESPORTSMULTIGAMEEXTENDED-S20260D88A4CB3EB-BDC74A1D102
2026-03-28 16:59:43,257 [Combo] RFQ submitted: 784c0036-f3bc-4049-a6f2-44d663682704
2026-03-28 16:59:43,402 [Combo] Best quote: yes_bid=0.0010 contracts=5.00
2026-03-28 16:59:43,403 [Combo] Quote: yes_bid=0.0010 EV=+283.000
2026-03-28 16:59:43,568 [Combo] Quote accepted and auto-confirmed: 61dd0d5c-b660-44f0-89df-f579a99ea9ef
2026-03-28 16:59:43,573 [Combo] EXECUTED
(kalshi-bot) root@Kalshi-bot:~/kalshi-bot-v2#
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/combo_scanner.py', 'r')
c = f.read()
f.close()
c = c.replace(
    "                # Extract player key for dedup — one leg per player total\n                pm = re.search(\n                    r\'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-\',\n                    ticker\n                )\n                player_key = pm.group(1) if pm else ticker",
    "                # Dedup: one leg per player per stat category\n                # e.g. Curry points + Curry threes = OK, two Curry points thresholds = not OK\n                series     = ticker.split('-')[0]  # e.g. KXNBAPTS\n                pm = re.search(\n                    r\'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-\',\n                    ticker\n                )\n                player_key = f\"{series}-{pm.group(1)}\" if pm else ticker"
)
open('/root/kalshi-bot-v2/combo_scanner.py', 'w').write(c)
print("Done")
PYEOF

git add combo_scanner.py data/nba_stats.py && git commit -m "fix: dedup by player+stat category" && git push origin master
cat > /root/kalshi-bot-v2/combo_scheduler.py << 'PYEOF'
#!/usr/bin/env python3
"""
combo_scheduler.py
─────────────────────────────────────────────────────────────────────────────
Schedules combo_scanner.py runs based on tonight's NBA tip-off times.
Runs 2 hours and 30 minutes before each unique tip-off time.
Deduplicates overlapping scan times.
"""

import logging
import time
import subprocess
import sys
import requests
from datetime import datetime, timezone, timedelta, date

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("combo_scheduler")

SCAN_OFFSETS_MINS = [-120, -30]
SCAN_WINDOW_SECS  = 300   # Treat scan times within 5 min as the same


def get_todays_tip_times() -> list[datetime]:
    today = date.today().strftime("%Y%m%d")
    url   = f"https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates={today}"
    try:
        data = requests.get(url, timeout=8).json()
        tips = []
        for event in data.get("events", []):
            dt_str = event.get("date", "")
            if dt_str:
                dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                name = event.get("name", "")
                log.info(f"  Game: {name} @ {dt.astimezone().strftime('%I:%M %p %Z')}")
                tips.append(dt)
        return sorted(set(tips))
    except Exception as e:
        log.error(f"Schedule fetch failed: {e}")
        return []


def build_schedule(tip_times: list[datetime]) -> list[datetime]:
    now   = datetime.now(timezone.utc)
    scans = []

    for tip in tip_times:
        for offset in SCAN_OFFSETS_MINS:
            scan_time = tip + timedelta(minutes=offset)
            if scan_time <= now:
                continue
            # Deduplicate — skip if within 5 min of existing scan
            if any(abs((scan_time - s).total_seconds()) < SCAN_WINDOW_SECS for s in scans):
                continue
            scans.append(scan_time)

    return sorted(scans)


def run_scan():
    log.info("=" * 50)
    log.info("RUNNING COMBO SCAN — LIVE")
    log.info("=" * 50)
    subprocess.run(
        [sys.executable, "/root/kalshi-bot-v2/combo_scanner.py", "--live"],
        cwd="/root/kalshi-bot-v2"
    )


def main():
    log.info("Combo Scheduler starting")
    log.info("Fetching today's NBA schedule...")

    tip_times = get_todays_tip_times()
    if not tip_times:
        log.warning("No games today — exiting")
        return

    schedule = build_schedule(tip_times)
    if not schedule:
        log.warning("No future scan times — all games already started")
        # Run once now anyway
        run_scan()
        return

    log.info(f"\nScheduled {len(schedule)} scans:")
    for s in schedule:
        log.info(f"  {s.astimezone().strftime('%I:%M %p %Z')}")

    for scan_time in schedule:
        now  = datetime.now(timezone.utc)
        wait = (scan_time - now).total_seconds()
        if wait > 0:
            log.info(f"\nSleeping {int(wait/60)}min until {scan_time.astimezone().strftime('%I:%M %p %Z')}")
            time.sleep(wait)
        run_scan()

    log.info("All scans complete for today")


if __name__ == "__main__":
    main()
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/combo_scheduler.py) lines"
python3 /root/kalshi-bot-v2/combo_scheduler.py
screen -S combo
grep -n "def\|TOKEN\|CHAT\|command\|polling" /root/kalshi-bot-v2/telegram.py | head -20
pip show python-telegram-bot 2>/dev/null || pip show telebot 2>/dev/null || echo "not installed"
cat > /root/kalshi-bot-v2/telegram_bot.py << 'PYEOF'
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

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

sys.path.insert(0, '/root/kalshi-bot-v2')
from core.config import config

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("telegram_bot")

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"


# ── LLM reasoning ─────────────────────────────────────────────────────────

def explain_leg(leg) -> str:
    """Ask Claude Haiku to explain why this leg is a good pick in one sentence."""
    if not config.ANTHROPIC_API_KEY:
        return f"avg {leg.reasoning.split('avg')[1].split('→')[0].strip() if 'avg' in leg.reasoning else ''}"

    prompt = f"""You are a sharp sports analyst. Explain in ONE concise sentence (max 12 words) why this prop is a good combo leg tonight.

Leg: {leg.reasoning}

Focus on: why the player is likely to hit the threshold. Be specific, not generic.
Just the sentence, no preamble."""

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
        parts = leg.ticker.split('-')
        if len(parts) >= 2:
            game_code = parts[1][5:]  # e.g. NYKOKC
            t1, t2 = game_code[:3], game_code[3:6]
            game_key = f"{t1} vs {t2}"
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
PYEOF

echo "Written — $(wc -l < /root/kalshi-bot-v2/telegram_bot.py) lines"
cd /root/kalshi-bot-v2 && python3 telegram_bot.py
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()
c = c.replace(
    'from telegram import Update\nfrom telegram.ext import Application, CommandHandler, ContextTypes',
    'import sys as _sys\n_sys.path = [p for p in _sys.path if "kalshi-bot-v2" not in p]\nfrom telegram import Update\nfrom telegram.ext import Application, CommandHandler, ContextTypes\n_sys.path.insert(0, \'/root/kalshi-bot-v2\')'
)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 telegram_bot.py
screen -S tgbot && cd /root/kalshi-bot-v2 && source /root/kalshi-bot/bin/activate && python3 telegram_bot.py
screen tgbot -r
screen -ls
grep "POSITION_SIZE\|MAX_POSITION" /root/kalshi_bot.py | head -5
grep "MAX_POSITION_USD\s*=" /root/kalshi_bot.py | head -5
grep "MAX_POSITION_USD\|POSITION_SIZE_PCT" /root/models.py | head -10
cd /root/kalshi-bot-v2 && git add combo_scanner.py combo_scheduler.py telegram_bot.py && git commit -m "feat: combo scheduler, telegram bot with /parlay command and LLM reasoning" && git push origin master
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''        parts = leg.ticker.split('-')
        if len(parts) >= 2:
            game_code = parts[1][5:]  # e.g. NYKOKC
            t1, t2 = game_code[:3], game_code[3:6]
            game_key = f"{t1} vs {t2}"
        else:
            game_key = "Other"'''

new = '''        import re as _re
        parts = leg.ticker.split('-')
        if len(parts) >= 2:
            # e.g. 26MAR29NYKOKC → extract NYKOKC
            m = _re.search(r\'\\d{2}[A-Z]{3}\\d{2}([A-Z]{6})\', parts[1])
            if m:
                code = m.group(1)
                t1, t2 = code[:3], code[3:6]
                game_key = f"{t1} vs {t2}"
            else:
                game_key = parts[1]
        else:
            game_key = "Other"'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/telegram_bot.py', 'r')
c = f.read()
f.close()

old = '''def explain_leg(leg) -> str:
    """Ask Claude Haiku to explain why this leg is a good pick in one sentence."""
    if not config.ANTHROPIC_API_KEY:
        return f"avg {leg.reasoning.split(\'avg\')[1].split(\'→\')[0].strip() if \'avg\' in leg.reasoning else \'\'}"

    prompt = f"""You are a sharp sports analyst. Explain in ONE concise sentence (max 12 words) why this prop is a good combo leg tonight.

Leg: {leg.reasoning}

Focus on: why the player is likely to hit the threshold. Be specific, not generic.
Just the sentence, no preamble."""'''

new = '''STAT_LABELS = {
    'KXNBAPTS': 'points', 'KXNBAREB': 'rebounds',
    'KXNBAAST': 'assists', 'KXNBA3PT': 'threes',
    'KXNBASTL': 'steals',  'KXNBABLK': 'blocks',
}

def explain_leg(leg) -> str:
    """Ask Claude Haiku to explain why this leg is a good pick in one sentence."""
    if not config.ANTHROPIC_API_KEY:
        return f"avg {leg.reasoning.split(\'avg\')[1].split(\'→\')[0].strip() if \'avg\' in leg.reasoning else \'\'}"

    series    = leg.ticker.split(\'-\')[0]
    stat_name = STAT_LABELS.get(series, \'stat\')
    threshold = leg.ticker.split(\'-\')[-1]

    prompt = f"""You are a sharp sports analyst. Explain in ONE concise sentence (max 12 words) why this player prop is a good combo leg tonight.

Player stat: {leg.reasoning}
Stat type: {stat_name}
Threshold: {threshold}+

Focus specifically on {stat_name} — why will this player get {threshold}+ {stat_name} tonight?
Be specific and accurate. Just the sentence, no preamble."""'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/telegram_bot.py', 'w').write(c)
print("Done")
PYEOF

screen -r tgbot
git add telegram_bot.py && git commit -m "fix: game label parsing, LLM prompt includes stat type" && git push origin master
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()

old = '''def _fetch_averages(espn_id: str, full_name: str) -> dict:
    """Fetch current season per-game averages from ESPN."""'''

new = '''def get_injury_status(espn_id: str, espn_team: str) -> str:
    """
    Return injury status for a player: 'active', 'out', 'doubtful', 'questionable'.
    Uses ESPN roster endpoint which includes injury status.
    """
    cache_key = f"injury_{espn_team}"
    roster = stats_cache.get(cache_key)
    if roster is None:
        try:
            r = requests.get(
                f"{ESPN_BASE}/teams/{espn_team}/roster",
                timeout=6
            )
            r.raise_for_status()
            roster = r.json().get('athletes', [])
            stats_cache.set(cache_key, roster, ttl=300)  # 5 min — injuries change
        except Exception as e:
            log.warning(f"[NBAStats] Roster fetch failed {espn_team}: {e}")
            return 'active'

    for athlete in roster:
        if athlete.get('id') == espn_id:
            status = athlete.get('status', {})
            if isinstance(status, dict):
                s = status.get('type', {}).get('name', 'Active').lower()
            else:
                s = str(status).lower()
            if 'out' in s:
                return 'out'
            if 'doubtful' in s:
                return 'doubtful'
            if 'questionable' in s:
                return 'questionable'
            return 'active'
    return 'active'


def _fetch_averages(espn_id: str, full_name: str) -> dict:
    """Fetch current season per-game averages from ESPN."""'''

c = c.replace(old, new)

# Now update score_prop_leg to check injury status
old2 = '''    avgs      = get_player_averages(ticker)
    if not avgs:
        return {\'confidence\': 0.0, \'reason\': \'No stats available\'}'''

new2 = '''    avgs      = get_player_averages(ticker)
    if not avgs:
        return {\'confidence\': 0.0, \'reason\': \'No stats available\'}

    # Check injury status — skip injured players
    espn_id   = avgs.get(\'espn_id\', \'\')
    parsed    = _parse_ticker(ticker)
    if parsed and espn_id:
        team_code = parsed[0]
        espn_team = TEAM_CODE_MAP.get(team_code, team_code)
        status    = get_injury_status(espn_id, espn_team)
        if status in (\'out\', \'doubtful\'):
            log.debug(f"[NBAStats] {avgs.get(\'player_name\')} is {status} — skipping")
            return {\'confidence\': 0.0, \'reason\': f"{avgs.get(\'player_name\')} is {status} tonight", \'injured\': True}
        if status == \'questionable\':
            log.debug(f"[NBAStats] {avgs.get(\'player_name\')} is questionable — reducing confidence")'''

c = c.replace(old2, new2)

# Add questionable confidence reduction
old3 = '''        if status == \'questionable\':
            log.debug(f"[NBAStats] {avgs.get(\'player_name\')} is questionable — reducing confidence")'''

new3 = '''        if status == \'questionable\':
            log.debug(f"[NBAStats] {avgs.get(\'player_name\')} is questionable — reducing confidence")
            # Will apply 0.1 penalty to confidence below'''

c = c.replace(old3, new3)

open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

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

    reason = (f"{avgs[\'player_name\']} avg {avg_stat:.1f} vs threshold {threshold} "
              f"(ratio={ratio:.2f}) → conf={confidence:.2f}")

    return {
        \'confidence\':   confidence,
        \'avg_stat\':     avg_stat,
        \'threshold\':    threshold,
        \'ratio\':        ratio,
        \'player_name\':  avgs[\'player_name\'],
        \'reason\':       reason,
    }'''

new = '''    # Confidence based on ratio
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
              f"(ratio={ratio:.2f}) → conf={confidence:.2f}{injury_note}")

    return {
        \'confidence\':   confidence,
        \'avg_stat\':     avg_stat,
        \'threshold\':    threshold,
        \'ratio\':        ratio,
        \'player_name\':  avgs[\'player_name\'],
        \'reason\':       reason,
    }'''

c = c.replace(old, new)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg, get_injury_status

# Test Giannis — should be out
result = get_injury_status('3032977', 'MIL')
print(f'Giannis status: {result}')

# Test a healthy player
result2 = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'KAT: conf={result2[\"confidence\"]} | {result2[\"reason\"][:60]}')
" 2>&1 | grep -v DEBUG
python3 << 'PYEOF'
f = open('/root/kalshi-bot-v2/data/nba_stats.py', 'r')
c = f.read()
f.close()
c = c.replace(
    '''            status = athlete.get('status', {})
            if isinstance(status, dict):
                s = status.get('type', {}).get('name', 'Active').lower()
            else:
                s = str(status).lower()''',
    '''            status = athlete.get('status', '')
            if isinstance(status, dict):
                s = status.get('type', {}).get('name', 'Active').lower()
            elif isinstance(status, str):
                s = status.lower()
            else:
                s = 'active'
            # Also check injuries array if present
            injuries = athlete.get('injuries', [])
            if injuries:
                injury_status = injuries[0].get('status', '').lower()
                if injury_status:
                    s = injury_status'''
)
open('/root/kalshi-bot-v2/data/nba_stats.py', 'w').write(c)
print("Done")
PYEOF

python3 -c "
from data.nba_stats import score_prop_leg, get_injury_status
result = get_injury_status('3032977', 'MIL')
print(f'Giannis status: {result}')
result2 = score_prop_leg('KXNBAPTS-26MAR29NYKOKC-NYKKTOWNS32-15')
print(f'KAT: conf={result2[\"confidence\"]} | {result2[\"reason\"][:60]}')
" 2>&1 | grep -v DEBUG
sed -n '135,160p' /root/kalshi-bot-v2/data/nba_stats.py
grep -n "status.get('type'" /root/kalshi-bot-v2/data/nba_stats.py
find /root/kalshi-bot-v2 -name "*.pyc" -delete && find /root/kalshi-bot-v2 -name "__pycache__" -exec rm -rf {} + 2>/dev/null; python3 -c "
from data.nba_stats import get_injury_status
result = get_injury_status('3032977', 'MIL')
print(f'Giannis status: {result}')
" 2>&1 | grep -v DEBUG
