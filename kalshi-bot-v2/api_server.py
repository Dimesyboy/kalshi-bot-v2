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
