# AUREON Ω PRIME

Autonomous cTrader execution engine and deterministic research stack.

## Current milestone

**V0.1 — Execution & Safety Kernel**

V0.1 deliberately does **not** place trades. Its purpose is to prove the build
pipeline and hard safety invariants before any strategy is allowed to execute.

### Included

- .NET 8 deterministic core
- cTrader cBot shell
- hard risk gate
- emergency halt
- daily-loss and drawdown blocks
- open-position and loss-streak limits
- minimum reward-to-risk validation
- zero-dependency smoke tests
- reproducible Docker build
- lightweight GitHub CI

## Architecture

```text
Broker data
    ↓
Deterministic market state
    ↓
Strategy intent
    ↓
HARD RISK GATE
    ↓
Execution gate
    ↓
cTrader order
```

The production trading engine must not depend on an LLM, AppDeploy, Google AI
Studio, Supabase, Vercel or an external market-data API.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Safety status

**NO LIVE EXECUTION IN V0.1.**

The next milestone is to compile and validate the kernel, then introduce the
first strategy module behind the existing risk gate.
