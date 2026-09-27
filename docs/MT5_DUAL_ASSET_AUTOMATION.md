# AUREON Ω PRIME — MT5 Dual-Asset Automation

## Scope

This build targets two independent EA instances on the same MT5 demo account:

- Gold: attach the EA to the broker's XAU/GOLD symbol. AUTO mode detects names containing `XAU` or `GOLD`. Trading is permitted whenever the broker's Gold market is open; weekends are blocked.
- Bitcoin: attach the same EA to the broker's BTC symbol. AUTO mode detects names containing `BTC`. Weekend trading is permitted when the broker continues to provide tradable BTC quotes.

No account credentials are stored in this repository.

## Default safety state

The compiled EA defaults to:

- `InpExecutionArmed=false`
- `InpDemoOnly=true`
- Portfolio daily loss stop: 2%
- Portfolio peak-to-equity hard stop: 8%
- Maximum open positions across the account: 2
- One AUREON position per symbol
- Margin preflight required
- Stale-tick guard
- Fixed + relative spread protection
- Persistent account and FVG state
- No martingale
- No grid
- No DLLs
- No WebRequest dependency

The EA will not place an order until `InpExecutionArmed=true` is explicitly selected.

## Gold profile

- Entry timeframe: M1
- Regime timeframe: M15
- Context: M5 / M15 / H1
- Base risk: 0.50%
- Long risk scale: 0.75
- Short risk scale: 1.00
- Long minimum quality: 58
- Short minimum quality: 48
- Maximum attempts per FVG: 2
- Maximum entries per day: 12
- Far target: 30R with profit locks and adaptive ATR trail

These asymmetric defaults preserve the research direction of V2.30 rather than forcing symmetrical long/short behaviour.

## Bitcoin profile

- Entry timeframe: M5
- Regime timeframe: H1
- Context: M15 / H1 / H4
- Base risk: 0.35%
- Long risk scale: 1.00
- Short risk scale: 0.90
- Minimum quality: 55 both directions
- Maximum attempts per FVG: 2
- Maximum entries per day: 18
- Far target: 15R with profit locks and adaptive ATR trail
- Weekend trading allowed when the broker market is tradable

BTC parameters are research defaults and require broker-specific backtest/forward validation before any real-money use.

## Signal path

```text
closed candles
  -> FVG + displacement qualification
  -> zone validation
  -> MTF trend votes
  -> regime EMA / slope / ADX context
  -> volatility + shock filter
  -> spread quality
  -> directional quality threshold
  -> controlled re-entry gate
  -> shared portfolio drawdown gate
  -> margin preflight
  -> broker-normalized volume
  -> order
  -> profit lock / smart ATR trail
```

## Shared portfolio governor

Both chart instances use terminal Global Variables keyed by the trading account.

That means Gold and BTC share:

- start-of-day equity
- peak equity
- daily-loss stop
- drawdown risk scaling
- hard drawdown stop

This prevents the two independent symbol engines from treating the account as if each owns the full risk budget.

## 24/5 and 24/7 runtime

An MT5 EA requires a continuously running MetaTrader terminal or MetaTrader virtual hosting. MT5 mobile/WebTrader can monitor and trade manually, but they are not the always-on EA runtime.

For demo forward validation, the final deployment target must therefore be one of:

1. a continuously running desktop/hosted MT5 terminal; or
2. MetaTrader Virtual Hosting / broker-sponsored hosting when available.

The GitHub workflow is used for deterministic compilation and testing, not as a production trading server.
