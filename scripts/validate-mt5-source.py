import pathlib
import re
import sys

target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "mt5/AUREON_PRIME_MT5_V4_MULTI_ASSET.mq5")
text = target.read_text(encoding="utf-8")

def number(pattern: str) -> float:
    m = re.search(pattern, text)
    if not m:
        raise SystemExit(f"Missing required numeric input: {pattern}")
    return float(m.group(1))

checks = {
    "strict mode": "#property strict" in text,
    "demo-only default": re.search(r"InpDemoOnly\s*=\s*true\s*;", text) is not None,
    "execution disarmed default": re.search(r"InpExecutionArmed\s*=\s*false\s*;", text) is not None,
    "daily loss <= 2%": number(r"InpPortfolioDailyLossPct\s*=\s*([0-9.]+)") <= 2.0,
    "hard drawdown <= 8%": number(r"InpPortfolioHardStopDDPct\s*=\s*([0-9.]+)") <= 8.0,
    "one-position guard": "InpOnePositionPerSymbol = true" in text,
    "portfolio position cap": "InpPortfolioMaxOpenPositions" in text and "CountOpenPositionsAll" in text,
    "margin guard": "InpMinProjectedMarginLevelPct" in text and "MarginPreflight" in text,
    "stale tick guard": "InpMaxTickAgeSeconds" in text,
    "spread-to-ATR guard": "InpMaxSpreadATRRatio" in text,
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

print(f"\nAUREON MT5 source safety validation PASSED: {target}")
