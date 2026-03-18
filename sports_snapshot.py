import requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from collections import defaultdict

BASE = "https://api.elections.kalshi.com/trade-api/v2"

# ── Series definitions ────────────────────────────────────────────────────────

SERIES = {
    "NBA": [
        ("KXNBAGAME",      "Moneyline"),
        ("KXNBASPREAD",    "Spread"),
        ("KXNBATOTAL",     "Total"),
        ("KXNBATEAMTOTAL", "Team Total"),
        ("KXNBA1HWINNER",  "1H Winner"),
        ("KXNBA1HTOTAL",   "1H Total"),
        ("KXNBA2HWINNER",  "2H Winner"),
        ("KXNBA1QWINNER",  "Q1 Winner"),
        ("KXNBA2QWINNER",  "Q2 Winner"),
        ("KXNBA3QWINNER",  "Q3 Winner"),
        ("KXNBA4QWINNER",  "Q4 Winner"),
        ("KXNBAPTS",       "Player Points"),
        ("KXNBAREB",       "Player Rebounds"),
        ("KXNBAAST",       "Player Assists"),
        ("KXNBA3PT",       "Player 3PT"),
        ("KXNBAPRA",       "Pts+Reb+Ast"),
        ("KXNBASTL",       "Player Steals"),
        ("KXNBABLK",       "Player Blocks"),
    ],
    "Tennis": [
        ("KXATPGAME",         "ATP Winner"),
        ("KXWTAGAME",         "WTA Winner"),
        ("KXATPMATCH",        "ATP Match"),
        ("KXWTAMATCH",        "WTA Match"),
        ("KXATPDOUBLES",      "ATP Doubles"),
        ("KXWTADOUBLES",      "WTA Doubles"),
        ("KXTENNISEXHIBITION","Exhibition"),
        ("KXEXHIBITIONMEN",   "Exhibition Men"),
        ("KXEXHIBITIONWOMEN", "Exhibition Women"),
    ],
    "MLB": [
        ("KXMLBGAME",    "Moneyline"),
        ("KXMLBSPREAD",  "Run Line"),
        ("KXMLBTOTAL",   "Total Runs"),
        ("KXMLBRFI",     "Run 1st Inning"),
        ("KXMLBHIT",     "Player Hits"),
        ("KXMLBSTGAME",  "Spring Training"),
    ],
}

# ── Fetch one series ──────────────────────────────────────────────────────────

def fetch_series(series_ticker, label):
    try:
        r = requests.get(f"{BASE}/events", params={
            "series_ticker": series_ticker,
            "status": "open",
            "limit": 50,
            "with_nested_markets": "true",
        }, timeout=8)
        r.raise_for_status()
        return label, r.json().get("events", [])
    except Exception as e:
        return label, []

# ── Build snapshot ────────────────────────────────────────────────────────────

def get_live_sports_snapshot():
    snapshot = {}

    for sport, series_list in SERIES.items():
        games = defaultdict(lambda: {"info": None, "markets": defaultdict(list)})

        with ThreadPoolExecutor(max_workers=10) as pool:
            futures = {
                pool.submit(fetch_series, ticker, label): (ticker, label)
                for ticker, label in series_list
            }
            for future in as_completed(futures):
                label, events = future.result()
                for e in events:
                    key = e.get("event_ticker", "")
                    if not key:
                        continue
                    if games[key]["info"] is None:
                        games[key]["info"] = e
                    for m in e.get("markets", []):
                        games[key]["markets"][label].append(m)

        snapshot[sport] = games

    return snapshot

# ── Formatting helpers ────────────────────────────────────────────────────────

def fmt_price(val):
    try:
        cents = round(float(val) * 100)
        return f"{cents}¢"
    except:
        return "N/A"

def fmt_vol(val):
    try:
        v = float(val)
        if v >= 1_000_000:
            return f"{v/1_000_000:.1f}M"
        if v >= 1_000:
            return f"{v/1_000:.1f}k"
        return str(int(v))
    except:
        return "0"

def fmt_close(ts):
    if not ts:
        return "Live"
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = dt - now
        mins = int(diff.total_seconds() / 60)
        if mins < 0:
            return "Closing soon"
        if mins < 60:
            return f"~{mins}m"
        return f"~{mins//60}h {mins%60}m"
    except:
        return ts

# ── Print snapshot ────────────────────────────────────────────────────────────

SPORT_EMOJI = {"NBA": "🏀", "Tennis": "🎾", "MLB": "⚾"}

def print_snapshot(snapshot):
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n{'━'*65}")
    print(f"  KALSHI LIVE SPORTS SNAPSHOT  —  {now_str}")
    print(f"{'━'*65}")

    for sport, games in snapshot.items():
        emoji = SPORT_EMOJI.get(sport, "🏟")
        active = {k: v for k, v in games.items() if v["info"] is not None}

        print(f"\n{emoji}  {sport}  —  {len(active)} live event(s)")
        print(f"{'─'*65}")

        if not active:
            print("  No live markets right now.")
            continue

        for event_key, game in active.items():
            e = game["info"]
            title = e.get("title", event_key)
            close = fmt_close(e.get("close_time"))

            print(f"\n  📌 {title}")
            print(f"     Ticker: {event_key}  |  Closes: {close}")

            markets_by_label = game["markets"]

            # ── Game-level lines first ──
            GAME_LABELS = [
                "Moneyline", "Run Line", "Spread",
                "Total", "Total Runs", "Team Total",
                "Run 1st Inning",
                "1H Winner", "1H Total", "2H Winner",
                "Q1 Winner", "Q2 Winner", "Q3 Winner", "Q4 Winner",
                "ATP Winner", "WTA Winner", "ATP Match", "WTA Match",
                "ATP Doubles", "WTA Doubles",
                "Exhibition", "Exhibition Men", "Exhibition Women",
                "Spring Training",
            ]

            PROP_LABELS = [
                "Player Points", "Player Rebounds", "Player Assists",
                "Player 3PT", "Pts+Reb+Ast", "Player Steals",
                "Player Blocks", "Player Hits",
            ]

            for label in GAME_LABELS:
                mkts = markets_by_label.get(label, [])
                if not mkts:
                    continue
                print(f"\n     [{label}]")
                for m in mkts:
                    title_m = m.get("title", "")
                    yes_bid = fmt_price(m.get("yes_bid_dollars"))
                    yes_ask = fmt_price(m.get("yes_ask_dollars"))
                    vol     = fmt_vol(m.get("volume_fp"))
                    liq     = fmt_vol(m.get("liquidity_dollars"))
                    print(f"       {title_m}")
                    print(f"         Yes: {yes_bid}/{yes_ask}  |  Vol: {vol}  |  Liq: {liq}")

            # ── Player props collapsed ──
            prop_count = sum(len(markets_by_label.get(l, [])) for l in PROP_LABELS)
            if prop_count > 0:
                print(f"\n     [Player Props]  ({prop_count} markets)")
                for label in PROP_LABELS:
                    mkts = markets_by_label.get(label, [])
                    if not mkts:
                        continue
                    print(f"       {label}:")
                    for m in mkts:
                        title_m = m.get("title", "")
                        yes_bid = fmt_price(m.get("yes_bid_dollars"))
                        yes_ask = fmt_price(m.get("yes_ask_dollars"))
                        vol     = fmt_vol(m.get("volume_fp"))
                        print(f"         {title_m}")
                        print(f"           Yes: {yes_bid}/{yes_ask}  |  Vol: {vol}")

    print(f"\n{'━'*65}\n")

# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Fetching live sports data...")
    snapshot = get_live_sports_snapshot()
    print_snapshot(snapshot)
