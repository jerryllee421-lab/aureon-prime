# AUREON Ω PRIME — Zero-cost runtime path

AUREON V4 is designed to run **Gold and Bitcoin from one MT5 terminal**. The EA is timer-driven, so it does not depend on Gold ticks in order to monitor Bitcoin.

## Recommended free-infrastructure route

The runtime needs an x86_64 Linux VM because the MT5 desktop terminal is the process that actually hosts Expert Advisors.

Current practical options include:

- Oracle Cloud Always Free AMD `VM.Standard.E2.1.Micro` when capacity is available.
- Google Cloud Free Tier `e2-micro` in an eligible US region, provided usage stays inside the published Free Tier limits.

AUREON's bootstrap adds a 2 GB swap file because these free micro instances typically have only 1 GB RAM.

## Why one terminal matters

V3 required a separate EA attachment per symbol. V4 performs both markets from one process:

```text
MT5 terminal
    |
    +-- AUREON PRIME V4
            |
            +-- Gold engine: M1 / M5 / M15 / H1
            |
            +-- Bitcoin engine: M5 / M15 / H1 / H4
            |
            +-- Shared portfolio governor
```

This is substantially lighter and also removes cross-terminal risk-governor race conditions.

## Bootstrap

On a new **Ubuntu 24.04 x86_64** VM:

```bash
curl -fsSL https://raw.githubusercontent.com/jerryllee421-lab/aureon-prime/main/deploy/bootstrap-ubuntu-mt5.sh -o /tmp/aureon.sh
chmod +x /tmp/aureon.sh
/tmp/aureon.sh
```

The script prompts locally for the demo MT5 login, trading password and server. They are never sent to GitHub.

It then:

1. adds a swap safety buffer;
2. installs Wine and Xvfb;
3. installs the PrimeXBT-branded MT5 desktop terminal;
4. performs an initial demo login;
5. downloads the public AUREON V4 source;
6. compiles the EA with MetaEditor;
7. compiles and runs the read-only broker probe;
8. discovers the broker's actual Gold/BTC symbol names;
9. creates a demo-only startup preset;
10. enables MT5 automated trading;
11. starts a systemd service;
12. automatically restarts the terminal after crashes/reboots.

## Security

- Source defaults remain `InpExecutionArmed=false` and `InpDemoOnly=true`.
- The deployment preset arms execution only for the demo host.
- The demo password is stored only on the VM in the MT5 custom configuration file, with restrictive file permissions.
- No DLL imports or WebRequest dependency are required by the EA.
- GitHub never receives the trading password.
- The public repository contains no broker credentials.

## Runtime limits

MT5 mobile/WebTrader can monitor the account, but the EA itself requires the desktop terminal to remain running. The Linux VM is therefore the execution host; the phone remains the control/monitoring device.

Always-free cloud offerings have provider-specific capacity, billing-account, usage and reclamation rules. Verify the selected VM is marked free-tier eligible before creating it.
