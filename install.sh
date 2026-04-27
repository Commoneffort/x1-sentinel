#!/usr/bin/env bash
# =============================================================================
#  x1-sentinel installer
#  https://github.com/Commoneffort/x1-sentinel
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/Commoneffort/x1-sentinel/main/install.sh | bash
#    -- or, after cloning --
#    ./install.sh
#
#  Environment overrides (skip prompts, useful for automation):
#    NONINTERACTIVE=1     answer yes to all prompts
#    INSTALL_PREFIX=/opt/x1-sentinel    install location (default: ~/.local/share/x1-sentinel)
#    SERVICE_USER=$USER   user that runs the daemon
#    SKIP_DEPS=1          don't install system dependencies
#    SKIP_SYSTEMD=1       don't install systemd unit
# =============================================================================

set -euo pipefail
shopt -s extglob

# -------- colors --------
if [[ -t 1 ]]; then
    C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YEL=$'\033[1;33m'
    C_CYN=$'\033[1;36m'; C_BLD=$'\033[1m';   C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_BLD=""; C_DIM=""; C_RST=""
fi

step()  { printf '%b▸%b %s\n' "$C_CYN" "$C_RST" "$*"; }
ok()    { printf '  %b✓%b %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '  %b!%b %s\n' "$C_YEL" "$C_RST" "$*"; }
fail()  { printf '  %b✗%b %s\n' "$C_RED" "$C_RST" "$*"; }
die()   { fail "$*"; exit 1; }

confirm() {
    local prompt="$1" default="${2:-y}"
    [[ "${NONINTERACTIVE:-0}" == "1" ]] && return 0
    local p
    [[ "$default" == "y" ]] && p="[Y/n]" || p="[y/N]"
    read -r -p "  ${prompt} ${p} " ans
    ans="${ans:-$default}"
    [[ "${ans,,}" =~ ^y ]]
}

prompt() {
    local question="$1" default="${2:-}"
    [[ "${NONINTERACTIVE:-0}" == "1" ]] && { echo "$default"; return; }
    local ans
    if [[ -n "$default" ]]; then
        read -r -p "  ${question} [${default}]: " ans
        echo "${ans:-$default}"
    else
        read -r -p "  ${question}: " ans
        echo "$ans"
    fi
}

# -------- environment defaults --------
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local/share/x1-sentinel}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/x1-sentinel}"
SERVICE_USER="${SERVICE_USER:-$USER}"
REPO_URL="${REPO_URL:-https://github.com/Commoneffort/x1-sentinel}"

# -------- banner --------
cat <<EOF
${C_BLD}${C_CYN}
═══════════════════════════════════════════════════════════════════════
                          CAPYBARA installer
            precognitive validator monitoring for X1 mainnet
═══════════════════════════════════════════════════════════════════════
${C_RST}

${C_BLD}WHAT THIS INSTALLER DOES${C_RST}

  CAPYBARA is a ${C_BLD}read-only${C_RST} monitoring tool. It does NOT modify your
  validator, its config, its keypair, or its systemd service. It does
  NOT restart your validator. Your validator keeps running while
  CAPYBARA is being installed.

  Specifically, this installer will:

    1. ${C_GRN}[safe]${C_RST}  Check for required tools (bash, awk, curl, journalctl…).
    2. ${C_GRN}[safe]${C_RST}  Run auto-detection by READING:
                  • systemd validator service (read-only)
                  • /proc, /sys for CPU/RAM/disk facts
                  • your local RPC (if exposed)
                  • the cluster RPC for slot-drift comparison
                Detection writes nothing.
    3. ${C_GRN}[safe]${C_RST}  Show you what was detected. Nothing is committed yet.
    4. ${C_YEL}[writes]${C_RST} Copy CAPYBARA files to:
                  • ${INSTALL_PREFIX}
                  • ${HOME}/.local/bin/x1-sentinel  (symlink)
    5. ${C_YEL}[writes]${C_RST} Write config to ${CONFIG_DIR}/sentinel.conf
                with the values you confirmed.
    6. ${C_YEL}[opt-in]${C_RST} If you choose: install a systemd ${C_BLD}user${C_RST} service that
                runs CAPYBARA as your user — NOT a system service, NOT
                touching your validator's service file.
    7. ${C_YEL}[opt-in]${C_RST} If you choose: send a single test message to the
                Telegram bot or Discord webhook you provide.
    8. ${C_YEL}[opt-in]${C_RST} If you choose: open these firewall ports via ufw:
                  • 8000-8020/tcp+udp (TPU dynamic range)
                  • 8001/tcp (gossip)
                  • 8899/tcp (RPC, only if you're exposing it)
                Run only if your validator NEEDS these ports open and
                they currently aren't.

${C_BLD}WHAT THIS INSTALLER WILL NEVER DO${C_RST}

    ${C_RED}✗${C_RST}  Stop, restart, or modify your validator service
    ${C_RED}✗${C_RST}  Touch your identity keypair or vote keypair
    ${C_RED}✗${C_RST}  Change your validator's startup arguments
    ${C_RED}✗${C_RST}  Modify /etc/systemd/system/* or any system file
    ${C_RED}✗${C_RST}  Send any data anywhere except (optionally) the alert
        endpoints you configure

${C_BLD}IF YOU DO WANT TO CHANGE VALIDATOR SETTINGS LATER${C_RST}

  CAPYBARA is monitoring only. If its risk score later tells you to
  change validator config (e.g. snapshots to tmpfs, CPU pinning),
  ${C_BLD}you${C_RST} make that change manually. The recommended workflow:

    # 1. Wait for a safe restart window
    tachyon-validator --ledger ~/ledger wait-for-restart-window \\
        --min-idle-time 10

    # 2. Apply your edits to /etc/systemd/system/<your-validator>.service
    sudo systemctl daemon-reload

    # 3. Restart only when --wait-for-restart-window says it's safe
    sudo systemctl restart <your-validator>.service

  CAPYBARA never does any of this for you.

${C_BLD}NOTHING WILL BE INSTALLED WITHOUT YOUR CONFIRMATION.${C_RST}
You will be asked Y/n at every step that writes files.

EOF

confirm "Continue?" y || exit 0

# -------- step 1: check deps --------
step "Checking dependencies"
MISSING=()
for dep in bash awk grep sed curl jq systemctl journalctl; do
    if command -v "$dep" >/dev/null 2>&1; then
        ok "$dep"
    else
        fail "$dep (missing)"
        MISSING+=("$dep")
    fi
done

# Optional but recommended
for opt in iostat lsblk nvme cpupower; do
    if command -v "$opt" >/dev/null 2>&1; then
        ok "$opt (optional)"
    else
        warn "$opt (optional, recommended)"
    fi
done

if (( ${#MISSING[@]} > 0 )); then
    if [[ "${SKIP_DEPS:-0}" != "1" ]] && command -v apt-get >/dev/null 2>&1; then
        warn "Missing required tools: ${MISSING[*]}"
        if confirm "Install via apt?" y; then
            sudo apt-get update -qq
            sudo apt-get install -y "${MISSING[@]}" sysstat nvme-cli linux-tools-common
            ok "Dependencies installed"
        else
            die "Cannot continue without dependencies"
        fi
    else
        die "Missing required tools: ${MISSING[*]} (install them and re-run)"
    fi
fi

# -------- step 2: auto-detection --------
step "Auto-detecting validator setup"

# Source the detect library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/detect.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/detect.sh"
elif [[ -f "$INSTALL_PREFIX/lib/detect.sh" ]]; then
    # shellcheck disable=SC1091
    source "$INSTALL_PREFIX/lib/detect.sh"
else
    die "lib/detect.sh not found. Are you running install.sh from the repo directory?"
fi

run_all_detection
print_detection_summary

# -------- step 3: confirm or override --------
step "Configuration"
echo "  You can override any auto-detected value below:"
echo

DETECTED_SERVICE="${DETECTED_SERVICE:-}"
DETECTED_IDENTITY_PUBKEY="${DETECTED_IDENTITY_PUBKEY:-}"
DETECTED_RPC_URL="${DETECTED_RPC_URL:-http://localhost:8899}"
DETECTED_CLUSTER_RPC="${DETECTED_CLUSTER_RPC:-https://rpc.mainnet.x1.xyz}"
DETECTED_LEDGER="${DETECTED_LEDGER:-}"
DETECTED_ACCOUNTS="${DETECTED_ACCOUNTS:-}"
DETECTED_NVME_DEV="${DETECTED_NVME_DEV:-}"
DETECTED_BUDGET_MS="${DETECTED_BUDGET_MS:-400}"

CFG_SERVICE=$(prompt    "Validator systemd service" "$DETECTED_SERVICE")
CFG_PUBKEY=$(prompt     "Validator identity pubkey" "$DETECTED_IDENTITY_PUBKEY")
CFG_RPC_URL=$(prompt    "Local RPC URL"             "$DETECTED_RPC_URL")
CFG_CLUSTER=$(prompt    "Cluster RPC URL"           "$DETECTED_CLUSTER_RPC")
CFG_NVME=$(prompt       "Primary NVMe device"       "$DETECTED_NVME_DEV")
CFG_BUDGET=$(prompt     "Slot budget (ms)"          "$DETECTED_BUDGET_MS")

# -------- step 4: alerts --------
step "Alert configuration (optional)"
ALERT_TG_TOKEN=""
ALERT_TG_CHAT=""
ALERT_DISCORD_WEBHOOK=""

if confirm "Configure Telegram alerts?" n; then
    ALERT_TG_TOKEN=$(prompt "Telegram bot token (from @BotFather)" "")
    ALERT_TG_CHAT=$(prompt  "Telegram chat ID" "")
    if [[ -n "$ALERT_TG_TOKEN" && -n "$ALERT_TG_CHAT" ]]; then
        # test it
        if curl -fsS "https://api.telegram.org/bot${ALERT_TG_TOKEN}/sendMessage" \
            -d "chat_id=${ALERT_TG_CHAT}" \
            -d "text=✅ x1-sentinel installed on $(hostname)" >/dev/null 2>&1; then
            ok "Telegram test message sent"
        else
            warn "Telegram test failed (will save config anyway)"
        fi
    fi
fi

if confirm "Configure Discord alerts?" n; then
    ALERT_DISCORD_WEBHOOK=$(prompt "Discord webhook URL" "")
    if [[ -n "$ALERT_DISCORD_WEBHOOK" ]]; then
        if curl -fsS -H "Content-Type: application/json" \
            -d "{\"content\":\"✅ x1-sentinel installed on $(hostname)\"}" \
            "$ALERT_DISCORD_WEBHOOK" >/dev/null 2>&1; then
            ok "Discord test message sent"
        else
            warn "Discord test failed (will save config anyway)"
        fi
    fi
fi

# -------- step 5: install files --------
step "Installing to $INSTALL_PREFIX"
mkdir -p "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/docs" "$CONFIG_DIR"

cp "$SCRIPT_DIR/x1-sentinel" "$INSTALL_PREFIX/x1-sentinel"
cp "$SCRIPT_DIR/lib/"*.sh    "$INSTALL_PREFIX/lib/"
[[ -f "$SCRIPT_DIR/lib/splash.txt" ]] && cp "$SCRIPT_DIR/lib/splash.txt" "$INSTALL_PREFIX/lib/"
[[ -d "$SCRIPT_DIR/docs" ]]          && cp -r "$SCRIPT_DIR/docs/"* "$INSTALL_PREFIX/docs/" 2>/dev/null || true
chmod +x "$INSTALL_PREFIX/x1-sentinel"

# Symlink to /usr/local/bin if root, else ~/.local/bin
if [[ $EUID -eq 0 ]]; then
    BIN_PATH=/usr/local/bin/x1-sentinel
else
    mkdir -p "$HOME/.local/bin"
    BIN_PATH="$HOME/.local/bin/x1-sentinel"
fi
ln -sf "$INSTALL_PREFIX/x1-sentinel" "$BIN_PATH"
ok "Linked $BIN_PATH"

# Write config
CONFIG_FILE="$CONFIG_DIR/sentinel.conf"
cat > "$CONFIG_FILE" <<EOF
# x1-sentinel configuration
# Generated by installer on $(date)
# Edit any value and restart the daemon (systemctl --user restart x1-sentinel)

# --- Validator identity ---
PUBKEY=${CFG_PUBKEY}
SERVICE=${CFG_SERVICE}

# --- RPC endpoints ---
RPC_URL=${CFG_RPC_URL}
CLUSTER_RPC=${CFG_CLUSTER}

# --- Hardware ---
NVME_DEV=${CFG_NVME}

# --- Tuning ---
BUDGET_MS=${CFG_BUDGET}
REFRESH=1

# --- Alerts ---
TG_TOKEN=${ALERT_TG_TOKEN}
TG_CHAT=${ALERT_TG_CHAT}
DISCORD_WEBHOOK=${ALERT_DISCORD_WEBHOOK}

# --- Daemon settings ---
HISTORY_DIR=${HOME}/.local/share/x1-sentinel/history
HISTORY_RETENTION_DAYS=30
EOF
ok "Wrote $CONFIG_FILE"

# -------- step 6: systemd --------
if [[ "${SKIP_SYSTEMD:-0}" != "1" ]] && confirm "Install systemd user service for daemon mode?" y; then
    mkdir -p "$HOME/.config/systemd/user"
    sed -e "s|@BIN@|$BIN_PATH|g" \
        -e "s|@CONFIG@|$CONFIG_FILE|g" \
        "$SCRIPT_DIR/systemd/x1-sentinel.service" \
        > "$HOME/.config/systemd/user/x1-sentinel.service"
    systemctl --user daemon-reload
    if confirm "Enable and start the service now?" y; then
        systemctl --user enable --now x1-sentinel
        ok "Service running. Check with: journalctl --user -u x1-sentinel -f"
    else
        ok "Service installed but not started"
        echo "    Start later: systemctl --user start x1-sentinel"
    fi
fi

# -------- step 7: firewall --------
if command -v ufw >/dev/null 2>&1 && confirm "Open validator firewall ports via ufw? (8000-8020 tcp+udp, 8001 tcp gossip)" n; then
    sudo ufw allow 8000:8020/tcp comment 'Solana TPU/dynamic'
    sudo ufw allow 8000:8020/udp comment 'Solana TPU/dynamic'
    sudo ufw allow 8001/tcp      comment 'Solana gossip'
    sudo ufw allow 8899/tcp      comment 'Solana RPC (only if exposing)'
    ok "Ports opened"
fi

# -------- done --------
cat <<EOF

${C_GRN}${C_BLD}═══════════════════════════════════════════════════════════════
                  CAPYBARA — install complete
═══════════════════════════════════════════════════════════════${C_RST}

  Run interactive dashboard:
    ${C_CYN}x1-sentinel${C_RST}

  Run as background daemon (alerts + history):
    ${C_CYN}x1-sentinel --daemon${C_RST}

  View metric history (after daemon has run):
    ${C_CYN}x1-sentinel --history${C_RST}      # last 24h
    ${C_CYN}x1-sentinel --history 168${C_RST}  # last week

  Open the docs:
    ${C_CYN}x1-sentinel --docs${C_RST}

  Inside the dashboard:
    ${C_CYN}h${C_RST}  toggle inline help next to each metric
    ${C_CYN}?${C_RST}  full help overlay
    ${C_CYN}d${C_RST}  open metric reference
    ${C_CYN}q${C_RST}  quit

  Edit config:
    ${C_CYN}\$EDITOR ${CONFIG_FILE}${C_RST}

  Documentation:
    ${C_CYN}${REPO_URL}${C_RST}

EOF
