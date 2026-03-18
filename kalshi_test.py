# Save as test_kalshi.py and run: python test_kalshi.py
from kalshi_python import Configuration, KalshiClient

config = Configuration(host="https://demo-api.kalshi.co/trade-api/v2")
config.api_key_id = "a4f8b14f-7f2a-4b79-adbf-d45147498a3e"  # ← paste yours
with open("/path/to/your/PRIVATE_KEY_PATH.pem", "r") as f:  # ← your PRIVATE_KEY_PATH
    config.private_key_pem = f.read()

client = KalshiClient(config)

try:
    markets_resp = client.get_markets(status="open", limit=10)
    print(f"Success! Found {len(markets_resp.markets)} open markets on first page.")
    for m in markets_resp.markets[:3]:
        print(f" - {m.ticker:>18} | {m.title[:70]}... | Vol: {m.volume:,} | OI: {m.open_interest:,}")
except Exception as e:
    print("Failed:", type(e).__name__, str(e))
