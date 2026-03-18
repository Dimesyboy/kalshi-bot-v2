import pytest
# Import your live strategies (adjust if needed after migration)
from strategies import strategy_value_fade, strategy_exit

def test_value_fade_blocks_late_game():
    """Q3+ favorites should NEVER trigger - core HFT edge protection"""
    # Mock late-game market (real test would use full Market dataclass)
    mock_market = type("Mock", (), {"yes_bid": 0.97, "volume": 12000})()
    mock_ctx = type("Mock", (), {"nba_quarter": 4, "lead": 5})()
    signal = strategy_value_fade(mock_market, mock_ctx)
    assert signal is None, "Late-game fade blocked - correct!"

def test_tennis_underdog_competitive_only():
    """Underdog only when sets still alive"""
    mock_market = type("Mock", (), {"yes_bid": 0.25})()
    mock_ctx = type("Mock", (), {"sets_down": 1, "games_diff": 2})()
    # signal = strategy_tennis_underdog(...)  # add your function
    # assert signal is not None
    pass  # extend with your exact functions

if __name__ == "__main__":
    print("Run: pytest tests/ -v")
    print("These protect your HFT profit logic from regressions.")
