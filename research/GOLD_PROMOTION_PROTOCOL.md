# AUREON Ω PRIME — Gold Promotion Protocol

BTC is paused. Gold is the only active research target.

## Immutable control

The control is the exact historical `FVG_Scalper_V2_12_Research` configuration that produced:

- XAUUSD M1
- 2026-09-01 through 2026-09-24
- ZAR 800 initial deposit
- 1:100 leverage
- ZAR 942,349.65 net profit
- ZAR 943,149.65 ending balance
- Profit factor 2.58
- 1,135 trades
- 64.41% win rate
- 21.55% relative equity drawdown

The Strategy Tester report is authoritative when it differs from source defaults.

## Research rules

1. Preserve the control source and preset unchanged.
2. Change one strategy dimension at a time during decomposition.
3. Reject variants that improve headline balance only by materially increasing drawdown, reducing sample size, or exploiting unrealistic sizing.
4. Keep BUY and SELL attribution separate.
5. Retain trade-frequency information; a low-trade result cannot replace a 1,135-trade control without stronger out-of-sample evidence.
6. Prefer broker real ticks for final validation.
7. Do not optimize and validate on the same data.
8. Never enable real-money trading from CI.

## Promotion stages

### Gate 0 — Control reproduction
Identify the MT5 modelling mode that most closely reproduces the historical control. Record any unavoidable difference caused by current broker history/build changes.

### Gate 1 — Edge decomposition
Measure independently:
- BUY only / SELL only / BOTH
- one-trade-per-FVG on/off
- M1/M5/M15 execution
- bias off vs selected EMA bias
- FVG/body thresholds
- midpoint/rejection behavior
- session attribution
- profit lock/trailing/fixed-R exits

### Gate 2 — Candidate selection
A candidate must show positive expectancy with a meaningful sample and must not rely on a single outlier trade. Same-period results are research evidence only, not proof.

### Gate 3 — Out-of-sample
Use untouched historical blocks. Target:
- positive net expectancy
- PF >= 1.30
- >= 300 trades across the aggregate validation set where broker history permits
- max equity DD <= 25%
- positive result in at least 70% of evaluated monthly blocks

### Gate 4 — Walk-forward / stability
Across sequential train/test windows:
- positive test result in at least 4 of 6 windows
- median test PF >= 1.20
- no isolated parameter spike; neighboring parameter values must remain viable

### Gate 5 — Execution stress
Re-test with realistic adverse assumptions:
- real ticks where available
- random execution delay
- wider spread / degraded fills where supported
- broker lot/margin limits

Target:
- aggregate PF > 1.10 under stress
- max equity DD < 30%
- no margin-call / invalid-volume dependency

### Gate 6 — PrimeXBT demo forward
Run only on the approved demo account. Require at least 30 calendar days and 100 closed trades unless trade frequency materially changes. Compare live-forward slippage, spread, effective risk and realized-R distributions against backtest expectations.

### Gate 7 — Live-ready decision
AUREON may be described as live-ready only after Gates 0–6 pass. Production code remains demo-safe until a final explicit live deployment decision is made. Backtests never guarantee future profitability.
