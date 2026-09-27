import pathlib, re, sys

p = pathlib.Path("mt5/AUREON_PRIME_MT5_V3_00_DUAL_ASSET.mq5")
text = p.read_text(encoding="utf-8")

checks = {
    "strict mode": "#property strict" in text,
    "demo-only default": re.search(r"InpDemoOnly\s*=\s*true\s*;", text) is not None,
    "execution disarmed default": re.search(r"InpExecutionArmed\s*=\s*false\s*;", text) is not None,
    "daily loss <= 2%": float(re.search(r"InpPortfolioDailyLossPct\s*=\s*([0-9.]+)", text).group(1)) <= 2.0,
    "hard drawdown <= 8%": float(re.search(r"InpPortfolioHardStopDDPct\s*=\s*([0-9.]+)", text).group(1)) <= 8.0,
    "one-position guard": "InpOnePositionPerSymbol = true" in text,
    "margin guard": "InpMinProjectedMarginLevelPct" in text and "MarginPreflight" in text,
    "no WebRequest": "WebRequest(" not in text,
    "no DLL imports": "#import" not in text,
    "no martingale": "martingale" not in text.lower(),
    "no grid execution": "grid" not in text.lower(),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")

if failed:
    print("\nSafety validation failed:", ", ".join(failed), file=sys.stderr)
    raise SystemExit(1)

print("\nAUREON MT5 source safety validation PASSED")
