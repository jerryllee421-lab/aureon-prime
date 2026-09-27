#!/usr/bin/env bash
set -euo pipefail

# AUREON Ω PRIME V4 - Ubuntu x86_64 MT5/Wine bootstrap.
# Intended for a small always-on VM used ONLY with a demo MT5 account first.
# Credentials are prompted locally and are never written to the Git repository.

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: AUREON MT5/Wine bootstrap requires an x86_64 VM." >&2
  exit 1
fi

if [[ "$(id -u)" == "0" ]]; then
  echo "ERROR: Run this script as a normal sudo-enabled user, not root." >&2
  exit 1
fi

AUREON_REPO_RAW="${AUREON_REPO_RAW:-https://raw.githubusercontent.com/jerryllee421-lab/aureon-prime/main}"
MT5_INSTALLER_URL="${MT5_INSTALLER_URL:-https://download.terminal.free/cdn/web/pxbt.trading.ltd/mt5/pxbttrading5setup.exe}"
WINEPREFIX="${WINEPREFIX:-$HOME/.aureon-mt5}"
export WINEPREFIX
export WINEARCH=win64
export WINEDEBUG=-all

INSTALL_WIN='C:\AUREON_MT5'
INSTALL_DIR="$WINEPREFIX/drive_c/AUREON_MT5"
WORK_DIR="$HOME/.local/share/aureon-prime"
BIN_DIR="$HOME/.local/bin"
LOG_DIR="$HOME/.local/state/aureon-prime"
mkdir -p "$WORK_DIR" "$BIN_DIR" "$LOG_DIR"
chmod 700 "$WORK_DIR" "$LOG_DIR"

echo "=== AUREON Ω PRIME V4 BOOTSTRAP ==="
echo "This setup is DEMO-ONLY. It will not remove the EA's internal demo-account guard."

read -r -p "MT5 demo login: " MT5_LOGIN
read -r -p "MT5 server name: " MT5_SERVER
read -r -s -p "MT5 demo TRADING password: " MT5_PASSWORD
echo

if [[ -z "$MT5_LOGIN" || -z "$MT5_SERVER" || -z "$MT5_PASSWORD" ]]; then
  echo "ERROR: login, server and password are required." >&2
  exit 1
fi

echo "== Create swap safety buffer when needed =="
if [[ "$(swapon --show --noheadings | wc -l)" -eq 0 ]]; then
  if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile >/dev/null
  fi
  sudo swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "== Install Wine + headless runtime =="
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
  | sudo tee /etc/apt/keyrings/winehq-archive.key >/dev/null
curl -fsSL https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
  | sudo tee /etc/apt/sources.list.d/winehq-noble.sources >/dev/null
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends \
  winehq-stable xvfb xauth x11-utils cabextract winbind curl ca-certificates p7zip-full python3

wine --version
python3 --version

echo "== Initialise isolated Wine prefix =="
mkdir -p "$WINEPREFIX"
xvfb-run -a timeout 300s wineboot -u >/dev/null 2>&1 || true
wineserver -w >/dev/null 2>&1 || true

echo "== Install PrimeXBT-branded MetaTrader 5 =="
INSTALLER="$WORK_DIR/pxbttrading5setup.exe"
curl --fail --location --retry 5 --retry-delay 3 "$MT5_INSTALLER_URL" -o "$INSTALLER"
test "$(stat -c %s "$INSTALLER")" -gt 100000

xvfb-run -a timeout 900s wine "$INSTALLER" /auto /path:"$INSTALL_WIN" \
  >"$LOG_DIR/installer.log" 2>&1 || true
sleep 5
wineserver -k >/dev/null 2>&1 || true

TERMINAL="$(find "$WINEPREFIX/drive_c" -type f -iname 'terminal64.exe' -path '*AUREON_MT5*' -print -quit)"
METAEDITOR="$(find "$WINEPREFIX/drive_c" -type f -iname 'metaeditor64.exe' -path '*AUREON_MT5*' -print -quit)"

if [[ -z "$TERMINAL" || -z "$METAEDITOR" ]]; then
  echo "ERROR: MT5 terminal/metaeditor not found. See $LOG_DIR/installer.log" >&2
  exit 1
fi

MQL5_DIR="$INSTALL_DIR/MQL5"
EXPERT_DIR="$MQL5_DIR/Experts/AUREON"
SCRIPT_DIR="$MQL5_DIR/Scripts/AUREON"
PRESET_DIR="$MQL5_DIR/Presets"
FILES_DIR="$MQL5_DIR/Files"
mkdir -p "$EXPERT_DIR" "$SCRIPT_DIR" "$PRESET_DIR" "$FILES_DIR"

echo "== First launch: initialise PrimeXBT server catalogue =="
LOGIN_CFG="$INSTALL_DIR/aureon-login-init.ini"
cat >"$LOGIN_CFG" <<EOF
[Common]
Login=$MT5_LOGIN
Password=$MT5_PASSWORD
Server=$MT5_SERVER
KeepPrivate=0
NewsEnable=0
CertInstall=0

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0
EOF
chmod 600 "$LOGIN_CFG"

LOGIN_CFG_WIN='C:\AUREON_MT5\aureon-login-init.ini'
set +e
xvfb-run -a timeout 40s wine "$TERMINAL" /portable "/config:$LOGIN_CFG_WIN" \
  >"$LOG_DIR/first-login.log" 2>&1
set -e
wineserver -k >/dev/null 2>&1 || true
sleep 3

echo "== Download version-pinned public AUREON sources =="
curl -fsSL "$AUREON_REPO_RAW/mt5/AUREON_PRIME_MT5_V4_MULTI_ASSET.mq5" \
  -o "$EXPERT_DIR/AUREON_PRIME_MT5_V4_MULTI_ASSET.mq5"
curl -fsSL "$AUREON_REPO_RAW/mt5/AUREON_BrokerProbe.mq5" \
  -o "$SCRIPT_DIR/AUREON_BrokerProbe.mq5"

echo "== Compile EA and read-only broker probe with MetaEditor =="
compile_mq5() {
  local src="$1"
  local log="${src%.mq5}.log"
  local ex5="${src%.mq5}.ex5"
  local win_src
  local win_mql5
  win_src="$(winepath -w "$src")"
  win_mql5="$(winepath -w "$MQL5_DIR")"

  xvfb-run -a timeout 240s wine "$METAEDITOR" \
    "/compile:$win_src" "/include:$win_mql5" /log \
    >"$LOG_DIR/metaeditor-process.log" 2>&1 || true
  sleep 2
  wineserver -k >/dev/null 2>&1 || true

  [[ -s "$ex5" ]] || { echo "ERROR: compile did not produce $ex5" >&2; exit 1; }

  if [[ -f "$log" ]]; then
    iconv -f UTF-16LE -t UTF-8 "$log" > "$LOG_DIR/$(basename "${log%.log}")-compile.log" 2>/dev/null || true
    grep -aEiq '(^|[^0-9])0 errors([^0-9]|$)' "$LOG_DIR/$(basename "${log%.log}")-compile.log" || {
      cat "$LOG_DIR/$(basename "${log%.log}")-compile.log" >&2 || true
      echo "ERROR: MetaEditor did not confirm zero errors." >&2
      exit 1
    }
  fi
}

compile_mq5 "$EXPERT_DIR/AUREON_PRIME_MT5_V4_MULTI_ASSET.mq5"
compile_mq5 "$SCRIPT_DIR/AUREON_BrokerProbe.mq5"

echo "== Probe broker symbol names/specifications without sending orders =="
PROBE_CFG="$INSTALL_DIR/aureon-probe.ini"
cat >"$PROBE_CFG" <<EOF
[Common]
Login=$MT5_LOGIN
Password=$MT5_PASSWORD
Server=$MT5_SERVER
KeepPrivate=0
NewsEnable=0
CertInstall=0

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Script=AUREON\AUREON_BrokerProbe
ShutdownTerminal=1
EOF
chmod 600 "$PROBE_CFG"

PROBE_CFG_WIN='C:\AUREON_MT5\aureon-probe.ini'
rm -f "$FILES_DIR/AUREON_BROKER_PROBE.csv"
set +e
xvfb-run -a timeout 180s wine "$TERMINAL" /portable "/config:$PROBE_CFG_WIN" \
  >"$LOG_DIR/broker-probe.log" 2>&1
PROBE_RC=$?
set -e
wineserver -k >/dev/null 2>&1 || true
sleep 3

PROBE_CSV="$FILES_DIR/AUREON_BROKER_PROBE.csv"
if [[ ! -s "$PROBE_CSV" ]]; then
  echo "ERROR: broker probe did not produce symbol data. Probe exit=$PROBE_RC" >&2
  echo "See $LOG_DIR/broker-probe.log" >&2
  exit 1
fi

readarray -t DISCOVERED < <(python3 - "$PROBE_CSV" <<'PY'
import csv, sys
p=sys.argv[1]
rows=list(csv.DictReader(open(p, newline='', encoding='utf-8-sig')))

def pick(kind):
    best=None
    best_score=-1
    for r in rows:
        s=(r.get("symbol") or "").upper()
        if kind=="gold":
            if "XAU" not in s and "GOLD" not in s:
                continue
            score=100 if s=="XAUUSD" else 95 if s=="GOLD" else 90 if "XAUUSD" in s else 80
        else:
            if "BTC" not in s:
                continue
            score=100 if s=="BTCUSD" else 95 if s=="BTCUSDT" else 90 if "BTCUSD" in s else 80
        try:
            if int(r.get("trade_mode") or 0) > 0:
                score += 5
        except ValueError:
            pass
        if score>best_score:
            best_score=score
            best=r.get("symbol") or ""
    return best or ""

print(pick("gold"))
print(pick("btc"))
PY
)

GOLD_SYMBOL="${DISCOVERED[0]:-}"
BTC_SYMBOL="${DISCOVERED[1]:-}"

if [[ -z "$GOLD_SYMBOL" || -z "$BTC_SYMBOL" ]]; then
  echo "ERROR: could not discover both Gold and Bitcoin symbols." >&2
  echo "Broker probe saved at: $PROBE_CSV" >&2
  exit 1
fi

echo "Discovered Gold: $GOLD_SYMBOL"
echo "Discovered Bitcoin: $BTC_SYMBOL"

echo "== Create demo-forward EA preset =="
PRESET="$PRESET_DIR/AUREON_PRIME_MT5_V4_DEMO.set"
cat >"$PRESET" <<EOF
InpExecutionArmed=true||false||0||true||N
InpDemoOnly=true||false||0||true||N
InpEnableGold=true||false||0||true||N
InpEnableBitcoin=true||false||0||true||N
InpGoldSymbol=$GOLD_SYMBOL
InpBitcoinSymbol=$BTC_SYMBOL
EOF
chmod 600 "$PRESET"

echo "== Create secure persistent MT5 startup config =="
LIVE_CFG="$INSTALL_DIR/aureon-live.ini"
cat >"$LIVE_CFG" <<EOF
[Common]
Login=$MT5_LOGIN
Password=$MT5_PASSWORD
Server=$MT5_SERVER
KeepPrivate=0
NewsEnable=0
CertInstall=0

[Charts]
MaxBars=100000

[Experts]
AllowLiveTrading=1
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[StartUp]
Expert=AUREON\AUREON_PRIME_MT5_V4_MULTI_ASSET
ExpertParameters=AUREON_PRIME_MT5_V4_DEMO.set
Symbol=$GOLD_SYMBOL
Period=M1
EOF
chmod 600 "$LIVE_CFG"

# Remove sensitive shell variables as soon as the config is written.
unset MT5_PASSWORD

echo "== Install watchdog-style systemd service =="
RUNNER="$BIN_DIR/aureon-mt5-run"
cat >"$RUNNER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export WINEPREFIX="$WINEPREFIX"
export WINEARCH=win64
export WINEDEBUG=-all
exec /usr/bin/xvfb-run -a -s "-screen 0 1280x720x24" /usr/bin/wine "$TERMINAL" /portable "/config:C:\\AUREON_MT5\\aureon-live.ini"
EOF
chmod 700 "$RUNNER"

SERVICE="/etc/systemd/system/aureon-mt5.service"
sudo tee "$SERVICE" >/dev/null <<EOF
[Unit]
Description=AUREON PRIME MT5 demo-forward engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
ExecStart=$RUNNER
Restart=always
RestartSec=15
TimeoutStopSec=20
KillMode=control-group
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now aureon-mt5.service

echo
echo "=== AUREON Ω PRIME V4 DEPLOYED ==="
echo "Gold symbol: $GOLD_SYMBOL"
echo "Bitcoin symbol: $BTC_SYMBOL"
echo "Runtime: one MT5 terminal, timer-driven dual-asset EA"
echo "Mode: DEMO ONLY"
echo
echo "Status:"
sudo systemctl --no-pager --full status aureon-mt5.service || true
echo
echo "Useful commands:"
echo "  sudo systemctl status aureon-mt5"
echo "  sudo journalctl -u aureon-mt5 -f"
echo "  sudo systemctl restart aureon-mt5"
echo "  sudo systemctl stop aureon-mt5"
