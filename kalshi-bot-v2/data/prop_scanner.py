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
