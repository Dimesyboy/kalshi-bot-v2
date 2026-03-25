# Bot Performance Analysis

**Generated:** 2026-03-19
**Status:** LIVE TRADING SUSPENDED - no validated edge

## Trade Log Summary (94 trades)

| Strategy | N | Win% | Total PNL | Avg PNL | Verdict |
|---|---|---|---|---|---|
| exit_trail_value_fade | 14 | 100% | +$0.68 | +$0.049 | EXIT WORKING |
| watcher_value_fade | 6 | 16.7% | -$2.85 | -$0.475 | WATCHER MISFIRING |
| exit_sl_tennis_underdog | 9 | 0% | -$3.16 | -$0.351 | DEAD |
| watcher_tennis_underdog | 39 | 15.4% | -$4.74 | -$0.122 | DEAD z=-4.32 |
| watcher_manual | 12 | 8.3% | -$23.82 | -$1.985 | DEAD |
| watcher_reconciled | 4 | 0% | -$36.27 | -$9.068 | BUG - $34 data error |
| TOTAL | 94 | - | -$73.26 | - | |

Fee drag: $8.17 (11.2% of gross losses)

## Value Fade Deep Dive

- Win rate: 75% (looks good, is misleading)
- Avg win: $0.094
- Avg loss: $0.716
- Payoff ratio: 0.13x (need >0.33x to break even at 75% win rate)
- Kelly fraction: -115.4% - CONFIRMED NEGATIVE EV

Entry price breakdown:
- NO at 6-8c (YES 92-94c): 16 trades, avg -$0.05 - wrong price zone
- NO at 9-12c: 2 trades, avg -$0.82 - large losses
- NO at 21c+: 1 trade, avg +$0.73 - only real winner, 1 data point

Root cause: Fading 92-94c favorites gives tiny upside (6-8c win)
but full downside (position goes to 0). Asymmetry is inverted.

## Bugs Fixed

1. Reconcile Guard: NO entries above 20c now skipped.
   Was reconstructing positions at 92c NO entry = instant $17 loss each.

2. Tennis Underdog Disabled: z=-4.32, p<0.001, 56 total trades.
   Not a sample size problem. Confirmed losing strategy.

## Code Weaknesses Found

1.  No backtested edge - strategies built on intuition not data
2.  REST polling 45s - not HFT, misses intraday moves
3.  NO position stop-loss missing - holds to 0 with no protection
4.  Duplicate exits - watcher + main loop both close same position
5.  Fee model wrong - assumes maker, likely paying taker on stops
6.  ESPN context silently degrades - falls back to blind entry
7.  urllib3 monkey-patch - thread-unsafe fills fetch
8.  Hit rate model invalid - NBA stats not normally distributed
9.  Spring training records - near-zero predictive value
10. Hardcoded injury stars - breaks silently on trades/retirements
11. Settings dont reach PriceWatcher - Telegram panel misleading
12. Hard close sells 20c below entry - guaranteed bad fill
13. Edge confirmation at n=5 - statistically meaningless

## Roadmap

Phase 1 (NOW): Run paper_trader.py for 2-3 weeks. 200+ signals per strategy.
Phase 2: Fix value_fade entry zone. Target YES 75-88c not 95c+.
Phase 3: Fix payoff ratio. Need 1.5x minimum. Tighter stops, better entries.
Phase 4: Replace NBA hit rate model with nba_api real game logs.
Phase 5: Re-enable live at $0.50 max once paper shows positive Kelly.

## What Edge Actually Looks Like

Target: 52% win rate WITH 1.5x payoff ratio (not 65% win rate alone).
Current: 75% win rate with 0.13x payoff = losing money.

Value fade correct zone:
- YES bid 80-88c (not 95c+)
- NO price >= 12c
- Spread <= 3c, Volume >= 15000
- ESPN confirms close game, Q1/Q2 only, lead < 6pts
- Stop loss: -8c from entry
- Take profit: +12c from entry
