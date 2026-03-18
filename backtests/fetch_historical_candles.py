"""Historical backtester for Kalshi — tests Value Fade on REAL past prices
Usage: python backtests/fetch_historical_candles.py YOUR_MARKET_TICKER
Example: python backtests/fetch_historical_candles.py NBA_2025_PLAYOFFS_GAME123

Find past tickers in the Kalshi app (Past Games → copy the ticker like NBA_... or MLB_...)
Only works on SETTLED historical markets (most old NBA/Tennis/MLB games)."""
import requests
import sys
import time

BASE = "https://api.elections.kalshi.com/trade-api/v2"
HEADERS = {"User-Agent": "KalshiBot-Backtester"}

def fetch_candles(ticker: str):
    print(f"Fetching 1-minute candles for {ticker} (historical only)...")
    
    # Required params per official docs
    params = {
        "start_ts": int(time.time() - 86400*90),   # last 90 days (seconds)
        "end_ts": int(time.time()),
        "period_interval": 1                       # 1-minute candles = HFT perfect
    }
    
    url = f"{BASE}/historical/markets/{ticker}/candlesticks"
    
    r = requests.get(url, params=params, headers=HEADERS, timeout=15)
    
    if r.status_code == 404:
        print("❌ Ticker not found in historical data.")
        print("   → Use a fully SETTLED past game from Kalshi app (older than ~1 week)")
        print("   → Example tickers: search 'NBA' in Kalshi Past section")
        return None
    r.raise_for_status()
    data = r.json()
    
    candles = data.get("candlesticks", [])
    print(f"✅ Got {len(candles)} candles")
    
    # Simulate your exact Value Fade strategy
    signals = 0
    wins = 0
    total_pnl = 0.0
    
    for c in candles:
        yes_bid_close = float(c["yes_bid"]["close"])
        if yes_bid_close >= 0.95:          # your main trigger
            signals += 1
            # Conservative simulation: buying NO on heavy favorite usually wins ~25-30¢
            pnl_per_contract = 0.25 if yes_bid_close >= 0.97 else 0.12
            total_pnl += pnl_per_contract
            if pnl_per_contract > 0:
                wins += 1
    
    if signals == 0:
        print("No 95%+ favorites found — try a different ticker or longer range.")
        return
    
    print("\n=== HISTORICAL BACKTEST RESULTS ===")
    print(f"Market: {ticker}")
    print(f"Signals fired: {signals}")
    print(f"Win rate: {wins/signals*100:.1f}%")
    print(f"Est. PNL per contract: ${total_pnl:.2f}")
    print("✅ Strategy edge looks strong!" if (wins/signals > 0.55) else "📉 Needs more data or tuning")
    print("\nTip: Run on 10+ past games and average the results!")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python backtests/fetch_historical_candles.py TICKER")
        print("Example: python backtests/fetch_historical_candles.py NBA_EXAMPLE_2025")
        sys.exit(1)
    fetch_candles(sys.argv[1])
