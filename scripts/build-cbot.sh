#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="${AUREON_CTRADER_STAGE:-/tmp/aureon-calgo}"
IMAGE="${CTRADER_CLI_IMAGE:-ghcr.io/spotware/ctrader-console:latest}"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Sources/Robots/AUREON_PRIME/AUREON_PRIME"
mkdir -p "$STAGE_DIR/Sources/Robots/AUREON_PRIME/Aureon.Core"
mkdir -p "$ROOT_DIR/artifacts"

cp -R "$ROOT_DIR/src/Aureon.Prime/." "$STAGE_DIR/Sources/Robots/AUREON_PRIME/AUREON_PRIME/"
cp -R "$ROOT_DIR/src/Aureon.Core/." "$STAGE_DIR/Sources/Robots/AUREON_PRIME/Aureon.Core/"

docker pull "$IMAGE" >/dev/null

docker run --rm \
  -v "$STAGE_DIR:/root/cAlgo" \
  "$IMAGE" \
  build /root/cAlgo/Sources/Robots/AUREON_PRIME/AUREON_PRIME/Aureon.Prime.csproj

ALGO_FILE="$(find "$STAGE_DIR" -type f -name '*.algo' -print -quit)"
if [[ -z "$ALGO_FILE" ]]; then
  echo "ERROR: cTrader build completed without producing an .algo package." >&2
  exit 1
fi

cp "$ALGO_FILE" "$ROOT_DIR/artifacts/AUREON_PRIME.algo"
echo "$ROOT_DIR/artifacts/AUREON_PRIME.algo"
