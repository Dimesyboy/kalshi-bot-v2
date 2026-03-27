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
from core.models import Sport, Market
from confidence.model import extract_nba_features, extract_mlb_features
from confidence.llm_gate import evaluate as llm_evaluate

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
    Score a single combo leg using the LLM confidence gate.
    Returns ComboLeg if confidence >= threshold, None otherwise.
    """
    m = fetch_leg_market(ticker)
    if not m:
        return None

    yes_bid = float(m.get('yes_bid_dollars', 0) or 0)
    volume  = int(m.get('volume', 0) or 0)

    if yes_bid <= 0 or yes_bid >= 1.0:
        return None

    # Build a minimal Market object for feature extraction
    market = Market(
        ticker       = ticker,
        event_ticker = collection_ticker,
        sport        = _detect_sport(ticker),
        yes_bid      = yes_bid,
        no_bid       = 1.0 - yes_bid,
        volume       = volume,
        spread       = 1.0,
        status       = 'open',
        close_time   = None,
        is_live      = False,
    )

    # Extract features and evaluate
    sport = market.sport
    if sport == Sport.NBA:
        features = extract_nba_features(market, None, [])
    elif sport == Sport.MLB:
        features = extract_mlb_features(market, None, [])
    else:
        return None

    # Add prop-specific context
    features['is_prop_market'] = True
    features['prop_ticker']    = ticker
    features['yes_bid_pct']    = round(yes_bid * 100, 1)

    conf_result = llm_evaluate(sport, ticker, features)

    if conf_result.score < MIN_LEG_CONFIDENCE:
        log.debug(f"[Combo] {ticker} below threshold: {conf_result.score:.2f}")
        return None

    return ComboLeg(
        ticker            = ticker,
        collection_ticker = collection_ticker,
        confidence        = conf_result.score,
        implied_prob      = yes_bid,
        is_yes_only       = is_yes_only,
        reasoning         = conf_result.reasoning,
    )


# ── Combo building ─────────────────────────────────────────────────────────

def build_combo(collection: dict) -> Optional[ComboCandidate]:
    """
    Score all legs in a collection and build a combo candidate
    if enough high-confidence legs exist.
    """
    collection_ticker = collection.get('collection_ticker', '')
    events            = collection.get('associated_events', [])

    log.debug(f"[Combo] Scoring {len(events)} legs in {collection_ticker}")

    qualified_legs = []
    for event in events:
        ticker      = event.get('ticker', '')
        is_yes_only = event.get('is_yes_only', True)

        leg = score_leg(ticker, collection_ticker, is_yes_only)
        if leg:
            qualified_legs.append(leg)
        time.sleep(0.1)  # Rate limit protection

    if len(qualified_legs) < MIN_LEGS:
        log.debug(f"[Combo] {collection_ticker}: only {len(qualified_legs)} "
                 f"qualified legs (need {MIN_LEGS})")
        return None

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

    def _signed_post(path: str, body: dict) -> dict:
        ts_ms   = str(int(time.time() * 1000))
        msg     = (ts_ms + "POST" + path).encode()
        sig     = private_key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.b64encode(sig).decode()
        headers = {
            "KALSHI-ACCESS-KEY":       config.KALSHI_KEY_ID,
            "KALSHI-ACCESS-SIGNATURE": sig_b64,
            "KALSHI-ACCESS-TIMESTAMP": ts_ms,
            "Content-Type":            "application/json",
        }
        r = requests.post(
            f"https://api.elections.kalshi.com{path}",
            headers=headers, json=body, timeout=8
        )
        r.raise_for_status()
        return r.json()

    def _signed_put(path: str, body: dict = {}) -> dict:
        ts_ms   = str(int(time.time() * 1000))
        msg     = (ts_ms + "PUT" + path).encode()
        sig     = private_key.sign(msg, padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.b64encode(sig).decode()
        headers = {
            "KALSHI-ACCESS-KEY":       config.KALSHI_KEY_ID,
            "KALSHI-ACCESS-SIGNATURE": sig_b64,
            "KALSHI-ACCESS-TIMESTAMP": ts_ms,
            "Content-Type":            "application/json",
        }
        r = requests.put(
            f"https://api.elections.kalshi.com{path}",
            headers=headers, json=body, timeout=8
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
            data   = _signed_get(f'/trade-api/v2/communications/rfqs/{rfq_id}')
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
    ev         = _evaluate_quote(candidate, yes_bid, stake_dollars)

    log.info(f"[Combo] Quote: yes_bid={yes_bid:.4f} EV={ev:+.3f}")

    if ev <= 0:
        log.info(f"[Combo] Quote rejected — negative EV")
        return None

    # ── Step 4: Accept and confirm ─────────────────────────────────────
    try:
        _signed_put(f'/trade-api/v2/communications/quotes/{quote_id}/accept')
        log.info(f"[Combo] Quote accepted: {quote_id}")
        _signed_put(f'/trade-api/v2/communications/quotes/{quote_id}/confirm')
        log.info(f"[Combo] Quote confirmed — combo placed!")
        return quote
    except Exception as e:
        log.error(f"[Combo] Accept/confirm failed: {e}")
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

def scan_and_execute(dry_run: bool = True) -> list[ComboCandidate]:
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
