"""ESPN Cache Helper - reduces scraping hits for HFT (30s TTL)
Replace any requests.get in espn_data.py / nba_context.py / tennis_context.py etc.
with: from espn_cache import get_cached
data = get_cached(url, params=...)
"""
import requests
import json
import os
from datetime import datetime, timedelta

CACHE_FILE = "espn_cache.json"
CACHE_TTL_SECONDS = 30  # live scores change fast - perfect for 45s polling

def get_cached(url: str, params: dict = None):
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE) as f:
                cache = json.load(f)
            if url in cache:
                entry = cache[url]
                if datetime.fromisoformat(entry["timestamp"]) + timedelta(seconds=CACHE_TTL_SECONDS) > datetime.now():
                    return entry["data"]
        except:
            pass  # corrupt cache → refetch

    # Fetch fresh
    r = requests.get(url, params=params or {}, timeout=10)
    r.raise_for_status()
    data = r.json() if "application/json" in r.headers.get("content-type", "") else r.text

    # Save
    cache = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE) as f:
                cache = json.load(f)
        except:
            pass
    cache[url] = {"data": data, "timestamp": datetime.now().isoformat()}
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)

    return data
