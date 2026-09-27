# AUREON Ω PRIME architecture

## Production principle

The production trading engine must remain independent of ChatGPT, AppDeploy,
Google AI Studio, Vercel, Supabase and any external LLM API.

The live path is:

```text
Broker data
  -> deterministic market state
  -> strategy intent
  -> hard risk gate
  -> execution gate
  -> cTrader order
  -> position management
```

## Planes

### Production plane

- `Aureon.Core`: deterministic domain logic.
- `Aureon.Prime`: cTrader adapter and cBot lifecycle.
- cTrader Cloud: intended 24/7 runtime.

### Research plane

- Docker: reproducible build/research environment.
- GitHub Actions: compile and lightweight verification.
- Heavy backtests/optimisation: manual or release-triggered only.

### Control plane

A future ASTRA CONTROL mobile application may display state, research reports
and journal data. It must never be required for an open position to be managed.

## Safety invariants

1. Emergency halt overrides every strategy.
2. Daily loss and drawdown limits are hard blocks.
3. Position-count limit is a hard block.
4. Consecutive-loss limit is a hard block.
5. Invalid entry/stop/target geometry is rejected.
6. Minimum reward-to-risk is enforced before execution.
7. No martingale, grid or loss-recovery multiplier.
8. V0.1 does not create orders. Execution is introduced only after the safety
   kernel compiles and passes deterministic tests.
