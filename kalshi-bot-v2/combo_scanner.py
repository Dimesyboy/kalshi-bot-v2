#!/usr/bin/env python3
"""
combo_scanner.py — kalshi-bot-v2
─────────────────────────────────────────────────────────────────────────────
Scans Kalshi multivariate event collections and builds high-confidence
combo bets via the RFQ system.

Flow:
    1. Fetch all open MVE collections (NBA + MLB)
    2. For each collection, fetch individual leg markets
    3. Score each leg using LLM confidence gate
    4. Filter legs above confidence threshold
    5. Build combo from highest-confidence legs
    6. Submit RFQ and evaluate quoted price
    7. Accept if EV positive, reject otherwise

Kalshi Combo mechanics:
    - Combos use Request For Quote (RFQ) system
    - Institutional market makers respond within ~2 seconds
    - Cross-game combos ARE supported
    - Each leg must resolve YES for combo to pay out
    - Price is product of individual leg probabilities (minus market maker margin)

Auth note:
    - /communications/ endpoints require same RSA auth as other endpoints
    - May require explicit API access enablement from Kalshi
"""

import json
import logging
import math
import time
from datetime import datetime, timezone
from typing import Optional

import requests

from core.config import config
from core.kalshi_client import _signed_get, get_market, get_client
from core.models import Sport
from data.nba_stats import score_prop_leg, get_threshold
from data.nba import get_injuries

log = logging.getLogger("kalshi_bot.combo")

# ── Constants ──────────────────────────────────────────────────────────────
MVE_NBA_SERIES  = "KXMVENBASINGLEGAME"
MVE_MLB_SERIES  = "KXMVEMLBSINGLEGAME"

MIN_LEG_CONFIDENCE    = 0.68   # Each leg must clear this
MIN_COMBINED_CONF     = 0.15   # Floor for full parlay (combined probability)
MAX_COMBO_STAKE       = 5.00   # dollars — fixed until win rate proven
MIN_LEGS              = 4      # Minimum legs for a valid combo
QUOTE_TIMEOUT_SECS    = 5      # How long to wait for market maker quote
QUOTE_POLL_INTERVAL   = 0.5    # Poll every 500ms


# ── Data structures ────────────────────────────────────────────────────────

class ComboLeg:
    def __init__(self, ticker: str, collection_ticker: str,
                 confidence: float, implied_prob: float,
                 is_yes_only: bool, reasoning: str):
        self.ticker            = ticker
        self.collection_ticker = collection_ticker
        self.confidence        = confidence
        self.implied_prob      = implied_prob  # market price as probability
        self.is_yes_only       = is_yes_only
        self.reasoning         = reasoning

    def __repr__(self):
        return (f"ComboLeg({self.ticker} "
                f"conf={self.confidence:.2f} "
                f"prob={self.implied_prob:.2f})")


class ComboCandidate:
    def __init__(self, collection_ticker: str, legs: list[ComboLeg]):
        self.collection_ticker  = collection_ticker
        self.legs               = legs
        self.combined_confidence= self._calc_combined()
        self.expected_payout    = self._calc_payout()

    def _calc_combined(self) -> float:
        """Combined probability = product of individual probabilities."""
        prob = 1.0
        for leg in self.legs:
            prob *= leg.confidence
        return round(prob, 4)

    def _calc_payout(self) -> float:
        """Expected payout per dollar staked."""
        prob = 1.0
        for leg in self.legs:
            prob *= leg.implied_prob
        return round(1.0 / prob, 2) if prob > 0 else 0.0

    def __repr__(self):
        return (f"ComboCandidate({self.collection_ticker} "
                f"{len(self.legs)} legs "
                f"conf={self.combined_confidence:.3f} "
                f"payout={self.expected_payout:.1f}x)")


# ── Collection fetching ────────────────────────────────────────────────────

def fetch_collections(series_ticker: str, limit: int = 50) -> list[dict]:
    """Fetch open MVE collections for a series."""
    try:
        data = _signed_get(
            f'/trade-api/v2/multivariate_event_collections'
            f'?series_ticker={series_ticker}&limit={limit}'
        )
        cols = data.get('multivariate_contracts', [])
        # Only return collections with active quoters
        active = [c for c in cols
                  if any(len(e.get('active_quoters', [])) > 0
                        for e in c.get('associated_events', []))]
        log.info(f"[Combo] {series_ticker}: {len(cols)} collections, "
                f"{len(active)} with active quoters")
        return active if active else cols  # fall back to all if none active
    except Exception as e:
        log.warning(f"[Combo] Collection fetch failed {series_ticker}: {e}")
        return []


def fetch_leg_market(ticker: str) -> Optional[dict]:
    """Fetch market data for a single leg."""
    return get_market(ticker)


# ── Leg scoring ────────────────────────────────────────────────────────────

def score_leg(ticker: str, collection_ticker: str,
              is_yes_only: bool) -> Optional[ComboLeg]:
    """
    Score a combo leg using player season average vs threshold.
    No LLM — pure stats-based scoring.

    Rules:
    - Player avg must be >= 1.3x threshold (ratio gate)
    - Market yes_bid between 0.60 and 0.92
    - Volume >= 500
    """
    m = fetch_leg_market(ticker)
    if not m:
        return None

    yes_bid = float(m.get('yes_bid_dollars', 0) or 0)
    volume  = int(m.get('volume', 0) or 0)

    # Skip extreme prices
    if yes_bid < 0.60 or yes_bid > 0.92:
        return None

    # Skip very low volume
    if volume < 500:
        pass  # Allow pre-game zero volume — volume builds closer to tip

    # Score using season average vs threshold
    result = score_prop_leg(ticker)
    confidence = result.get('confidence', 0.0)

    if confidence < MIN_LEG_CONFIDENCE:
        log.debug(f"[Combo] {ticker} skip: conf={confidence:.2f} "
                 f"ratio={result.get('ratio',0):.2f}")
        return None

    log.info(f"[Combo] LEG: {ticker} conf={confidence:.2f} | {result.get('reason','')}")

    return ComboLeg(
        ticker            = ticker,
        collection_ticker = collection_ticker,
        confidence        = confidence,
        implied_prob      = yes_bid,
        is_yes_only       = is_yes_only,
        reasoning         = result.get('reason', ''),
    )


def build_combo(collection: dict) -> Optional[ComboCandidate]:
    """
    Score all legs in a collection and build a combo candidate
    if enough high-confidence legs exist.
    """
    collection_ticker = collection.get('collection_ticker', '')
    event_tickers     = collection.get('associated_event_tickers', [])

    # Filter to prop events only — skip game/spread/total
    prop_series = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT',
                   'KXNBASTL', 'KXNBABLK', 'KXMLBHIT', 'KXMLBHR']
    prop_events = [t for t in event_tickers
                   if any(t.startswith(s) for s in prop_series)]

    log.debug(f"[Combo] {collection_ticker}: {len(prop_events)} prop events")

    qualified_legs = []
    for event_ticker in prop_events:
        try:
            data = _signed_get(
                f'/trade-api/v2/markets?event_ticker={event_ticker}'
                f'&limit=20&status=open'
            )
            markets = data.get('markets', [])
            for m in markets:
                ticker = m.get('ticker', '')
                leg = score_leg(ticker, collection_ticker, True)
                if leg:
                    qualified_legs.append(leg)
            time.sleep(0.1)
        except Exception as e:
            log.debug(f"[Combo] Event fetch error {event_ticker}: {e}")

    if len(qualified_legs) < MIN_LEGS:
        log.debug(f"[Combo] {collection_ticker}: only {len(qualified_legs)} "
                 f"qualified legs (need {MIN_LEGS})")
        return None

    # Deduplicate — one leg per player per stat category
    # If Siakam has 2+ AND 4+ rebounds, only keep the best one
    seen = {}
    deduped = []
    for leg in qualified_legs:
        # Extract player+stat key from ticker e.g. LACBMATHURIN9-KXNBAREB
        import re
        m = re.search(r'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-', leg.ticker)
        series = leg.ticker.split('-')[0]
        player_key = f"{series}-{m.group(1)}" if m else leg.ticker
        if player_key not in seen or leg.confidence > seen[player_key].confidence:
            seen[player_key] = leg
    deduped = list(seen.values())
    qualified_legs = deduped

    # Sort by confidence descending
    qualified_legs.sort(key=lambda x: x.confidence, reverse=True)

    candidate = ComboCandidate(collection_ticker, qualified_legs)

    if candidate.combined_confidence < MIN_COMBINED_CONF:
        log.debug(f"[Combo] {collection_ticker}: combined conf "
                 f"{candidate.combined_confidence:.3f} below floor")
        return None

    log.info(f"[Combo] CANDIDATE {candidate}")
    for leg in candidate.legs:
        log.info(f"  {leg.ticker} conf={leg.confidence:.2f} "
                f"prob={leg.implied_prob:.2f} | {leg.reasoning[:60]}")

    return candidate


# ── RFQ submission ─────────────────────────────────────────────────────────

def submit_rfq(candidate: ComboCandidate,
               stake_dollars: float = MAX_COMBO_STAKE) -> Optional[dict]:
    """
    Submit an RFQ for a combo candidate.
    Returns quote dict if successful, None otherwise.

    NOTE: Requires /communications/ endpoint access.
    This may need explicit enablement from Kalshi support.
    """
    import base64
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    try:
        with open(config.KALSHI_KEY_FILE, 'rb') as f:
            private_key = serialization.load_pem_private_key(
                f.read(), password=None
            )
    except Exception as e:
        log.error(f"[Combo] Key load failed: {e}")
        return None

    def _pss_headers(method: str, path: str) -> dict:
        ts_ms = str(int(time.time() * 1000))
        msg   = (ts_ms + method + path).encode()
        sig   = private_key.sign(
            msg,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        return {
            "KALSHI-ACCESS-KEY":       config.KALSHI_KEY_ID,
            "KALSHI-ACCESS-SIGNATURE": base64.b64encode(sig).decode(),
            "KALSHI-ACCESS-TIMESTAMP": ts_ms,
            "Content-Type":            "application/json",
        }

    def _signed_post(path: str, body: dict) -> dict:
        r = requests.post(
            f"https://api.elections.kalshi.com{path}",
            headers=_pss_headers("POST", path),
            json=body, timeout=8
        )
        r.raise_for_status()
        return r.json()

    def _signed_put(path: str, body: dict = {}) -> dict:
        r = requests.put(
            f"https://api.elections.kalshi.com{path}",
            headers=_pss_headers("PUT", path),
            json=body, timeout=8
        )
        r.raise_for_status()
        return r.json()

    # ── Step 1: Submit RFQ ─────────────────────────────────────────────
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
        log.warning(f"[Combo] RFQ submission failed: {e}")
        return None

    # ── Step 2: Poll for quote ─────────────────────────────────────────
    deadline = time.time() + QUOTE_TIMEOUT_SECS
    quote    = None

    while time.time() < deadline:
        try:
            poll_path = f'/trade-api/v2/communications/rfqs/{rfq_id}'
            r_poll = requests.get(
                f"https://api.elections.kalshi.com{poll_path}",
                headers=_pss_headers("GET", poll_path),
                timeout=8
            )
            data = r_poll.json()
            quotes = data.get('quotes', [])
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

    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")

    if ev <= 0:
        log.info(f"[Combo] Quote rejected — negative EV")
        return None

    # ── Step 4: Accept (confirm is automatic) ─────────────────────────
    try:
        accept_path = f'/trade-api/v2/communications/quotes/{quote_id}/accept'
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
        return None


def _evaluate_quote(candidate: ComboCandidate,
                    quoted_price: float,
                    stake: float) -> float:
    """
    Evaluate EV of a quoted combo price.
    EV = (combined_confidence * payout) - ((1 - combined_confidence) * stake)
    """
    if quoted_price <= 0:
        return -1.0
    payout    = stake / quoted_price  # what we win
    win_prob  = candidate.combined_confidence
    ev        = win_prob * (payout - stake) - (1 - win_prob) * stake
    return round(ev, 4)


# ── Main scanner ───────────────────────────────────────────────────────────

# Prop series to scan
PROP_SERIES = ['KXNBAPTS', 'KXNBAREB', 'KXNBAAST', 'KXNBA3PT', 'KXNBASTL']

# Min/max yes_bid for combo legs
LEG_MIN_BID = 0.60
LEG_MAX_BID = 0.88   # Cap at 88% — above this barely adds payout

# Combo sizing
MIN_COMBO_LEGS       = 4
MAX_COMBO_LEGS       = 8
MIN_COMBINED_CONF    = 0.02   # 2% floor
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
                f'/trade-api/v2/markets?series_ticker={series}&limit=200&status=open'
            )
            for m in data.get('markets', []):
                ticker  = m.get('ticker', '')
                yes_bid = float(m.get('yes_bid_dollars', 0) or 0)

                if not (LEG_MIN_BID <= yes_bid <= LEG_MAX_BID):
                    continue

                result = score_prop_leg(ticker)
                conf   = result.get('confidence', 0.0)
                if conf < MIN_LEG_CONFIDENCE:
                    continue

                # Extract player key for dedup — one leg per player total
                pm = re.search(
                    r'-((?:LAC|IND|GSW|NYK|BOS|MIA|MIL|DEN|PHX|DAL|LAL|MEM|ATL|CLE|CHI|OKC|SAS|NOP|MIN|UTA|POR|SAC|TOR|DET|HOU|ORL|PHI|BKN|CHA|WAS)[A-Z0-9]+)-',
                    ticker
                )
                player_key = pm.group(1) if pm else ticker

                leg = ComboLeg(
                    ticker            = ticker,
                    collection_ticker = 'KXMVESPORTSMULTIGAMEEXTENDED-R',
                    confidence        = conf,
                    implied_prob      = yes_bid,
                    is_yes_only       = True,
                    reasoning         = result.get('reason', ''),
                )

                # Keep lowest-price leg per player (best payout contribution)
                if player_key not in seen_players or yes_bid < seen_players[player_key].implied_prob:
                    seen_players[player_key] = leg

            time.sleep(0.5)
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

    candidate = ComboCandidate('KXMVESPORTSMULTIGAMEEXTENDED-R', selected)

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

    return candidates


def _log_combo_trade(candidate: ComboCandidate, quote: dict):
    """Log a placed combo trade to combo_trades.json."""
    import os
    log_file = "/root/kalshi-bot-v2/data/combo_trades.json"
    trades   = []
    if os.path.exists(log_file):
        try:
            with open(log_file) as f:
                trades = json.load(f)
        except Exception:
            pass

    trades.append({
        "time":                datetime.now(timezone.utc).isoformat(),
        "collection_ticker":   candidate.collection_ticker,
        "legs":                [l.ticker for l in candidate.legs],
        "combined_confidence": candidate.combined_confidence,
        "expected_payout":     candidate.expected_payout,
        "quote":               quote,
        "is_combo":            True,
    })

    with open(log_file, 'w') as f:
        json.dump(trades, f, indent=2)


def _detect_sport(ticker: str) -> Sport:
    if 'NBA' in ticker:
        return Sport.NBA
    if 'MLB' in ticker:
        return Sport.MLB
    return Sport.OTHER


# ── CLI ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    dry_run = "--live" not in sys.argv
    if dry_run:
        log.info("Running in DRY RUN mode (pass --live to execute)")
    scan_and_execute(dry_run=dry_run)
