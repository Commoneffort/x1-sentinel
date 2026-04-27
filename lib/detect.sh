#!/usr/bin/env bash
# =============================================================================
# x1-sentinel auto-detection library
# Sourced by install.sh; sets DETECTED_* variables.
# Functions: detect_service, detect_validator_args, detect_identity,
#            detect_paths, detect_disk, detect_rpc, detect_cluster,
#            run_all_detection, print_detection_summary
# =============================================================================

# All detection functions populate DETECTED_* globals and never fail (best-effort).

detect_service() {
    DETECTED_SERVICE=""
    local svc
    svc=$(systemctl list-units --type=service --state=running 2>/dev/null \
        | awk '/(solana|tachyon|agave|x1).*-validator\.service/ {print $1; exit}')
    [[ -z "$svc" ]] && svc=$(systemctl list-units --type=service --state=running 2>/dev/null \
        | awk '/(solana|tachyon|agave|x1)\.service/ {print $1; exit}')
    DETECTED_SERVICE="${svc:-solana-validator.service}"
}

detect_validator_args() {
    DETECTED_VALIDATOR_BIN=""
    DETECTED_VALIDATOR_ARGS=""
    [[ -z "${DETECTED_SERVICE:-}" ]] && return

    # Get ExecStart line from systemd
    local execstart
    execstart=$(systemctl cat "$DETECTED_SERVICE" 2>/dev/null \
        | awk '/^ExecStart=/{sub(/^ExecStart=/,""); flag=1; print; next}
               flag && /^[[:space:]]/{print; next}
               flag{flag=0}' \
        | tr -d '\\\n' | tr -s ' ')

    if [[ -n "$execstart" ]]; then
        # First non-flag token after the binary path is the binary
        DETECTED_VALIDATOR_BIN=$(awk '{print $1}' <<<"$execstart")
        DETECTED_VALIDATOR_ARGS="$execstart"
    fi
}

# Extract --foo value or --foo=value from validator args
_arg_value() {
    local key="$1"
    [[ -z "${DETECTED_VALIDATOR_ARGS:-}" ]] && return
    # Try --key value form
    local v
    v=$(awk -v k="--$key" '
        { for(i=1;i<=NF;i++) if($i==k) { print $(i+1); exit } }
    ' <<<"$DETECTED_VALIDATOR_ARGS")
    [[ -n "$v" && "$v" != --* ]] && { echo "$v"; return; }
    # Try --key=value form
    awk -v k="--$key=" '
        { for(i=1;i<=NF;i++) if(index($i,k)==1) { sub(k,"",$i); print $i; exit } }
    ' <<<"$DETECTED_VALIDATOR_ARGS"
}

detect_identity() {
    DETECTED_IDENTITY_PATH=""
    DETECTED_IDENTITY_PUBKEY=""

    # 1. Try --identity from validator args (most authoritative)
    local id
    id=$(_arg_value identity)

    # 2. Fall back to common default locations
    if [[ -z "$id" || ! -r "$id" ]]; then
        local candidates=(
            "$HOME/.config/solana/identity.json"
            "/root/.config/solana/identity.json"
            "/home/sol/.config/solana/identity.json"
            "/home/solana/.config/solana/identity.json"
            "$HOME/solana/identity.json"
            "$HOME/validator-keypair.json"
            "$HOME/.solana/identity.json"
        )
        # Also probe other users' home dirs (common on shared validator hosts)
        if [[ -d /home ]]; then
            for d in /home/*/.config/solana/identity.json; do
                [[ -r "$d" ]] && candidates+=("$d")
            done
        fi
        for c in "${candidates[@]}"; do
            if [[ -r "$c" ]]; then
                id="$c"
                break
            fi
        done
    fi

    [[ -z "$id" ]] && return
    DETECTED_IDENTITY_PATH="$id"

    # Extract pubkey: prefer solana-keygen, fall back to parsing the file
    if [[ -r "$id" ]]; then
        if command -v solana-keygen >/dev/null 2>&1; then
            DETECTED_IDENTITY_PUBKEY=$(solana-keygen pubkey "$id" 2>/dev/null || echo "")
        fi
        # If solana-keygen unavailable or failed, derive pubkey from the
        # JSON keypair file (last 32 bytes are the pubkey, base58-encoded)
        if [[ -z "$DETECTED_IDENTITY_PUBKEY" ]] && command -v python3 >/dev/null 2>&1; then
            DETECTED_IDENTITY_PUBKEY=$(python3 -c "
import json, sys
try:
    with open('$id') as f:
        kp = json.load(f)
    if isinstance(kp, list) and len(kp) == 64:
        # last 32 bytes are the pubkey; base58 encode them
        b = bytes(kp[32:])
        alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
        n = int.from_bytes(b, 'big')
        out = ''
        while n > 0:
            n, r = divmod(n, 58)
            out = alphabet[r] + out
        # Leading zero bytes
        for byte in b:
            if byte == 0: out = '1' + out
            else: break
        print(out)
except Exception:
    pass
" 2>/dev/null)
        fi
    fi
}

detect_paths() {
    DETECTED_LEDGER=$(_arg_value ledger)
    DETECTED_ACCOUNTS=$(_arg_value accounts)
    DETECTED_SNAPSHOTS=$(_arg_value snapshots)
    DETECTED_LOG=$(_arg_value log)
    DETECTED_RPC_PORT=$(_arg_value rpc-port)
    DETECTED_GOSSIP_PORT=$(_arg_value gossip-port)
    DETECTED_VOTE_ACCOUNT=$(_arg_value vote-account)

    # Sizes (best-effort)
    DETECTED_LEDGER_SIZE=""
    DETECTED_ACCOUNTS_SIZE=""
    [[ -d "$DETECTED_LEDGER"   ]] && DETECTED_LEDGER_SIZE=$(du -sh "$DETECTED_LEDGER"   2>/dev/null | awk '{print $1}')
    [[ -d "$DETECTED_ACCOUNTS" ]] && DETECTED_ACCOUNTS_SIZE=$(du -sh "$DETECTED_ACCOUNTS" 2>/dev/null | awk '{print $1}')
}

detect_disk() {
    DETECTED_NVME_DEV=""
    DETECTED_DISK_LAYOUT=""
    DETECTED_RAID=""

    # Find what device backs root
    DETECTED_NVME_DEV=$(findmnt -no SOURCE / 2>/dev/null | sed 's|^/dev/||' | head -1)

    # If it's md*, it's RAID — get the layout
    if [[ "$DETECTED_NVME_DEV" =~ ^md ]]; then
        DETECTED_RAID="yes"
        local detail
        detail=$(cat /proc/mdstat 2>/dev/null | grep "^${DETECTED_NVME_DEV}" || true)
        DETECTED_DISK_LAYOUT="$detail"
    fi

    # Count physical NVMe drives
    DETECTED_NVME_COUNT=$(lsblk -ndo NAME,TYPE 2>/dev/null \
        | awk '$2=="disk" && $1 ~ /^nvme[0-9]+n[0-9]+$/' | wc -l)

    # CPU/RAM info for the report
    DETECTED_NCPU=$(nproc 2>/dev/null || echo "?")
    DETECTED_CPU_MODEL=$(awk -F: '/^model name/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    DETECTED_RAM_GB=$(awk '/^MemTotal:/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null)
}

detect_rpc() {
    DETECTED_RPC_URL="http://localhost:${DETECTED_RPC_PORT:-8899}"
    DETECTED_RPC_OK="no"
    DETECTED_RPC_SLOT=""
    local r
    r=$(timeout 3 curl -fsS -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' "$DETECTED_RPC_URL" 2>/dev/null \
        | grep -oE '"result":[0-9]+' | cut -d: -f2)
    if [[ -n "$r" ]]; then
        DETECTED_RPC_OK="yes"
        DETECTED_RPC_SLOT="$r"
    fi
}

detect_cluster() {
    DETECTED_CLUSTER_RPC=""
    DETECTED_CLUSTER_OK="no"
    DETECTED_CLUSTER_SLOT=""
    DETECTED_DRIFT=""

    # Try to detect cluster from --entrypoint args
    local ep
    ep=$(awk '{ for(i=1;i<=NF;i++) if($i=="--entrypoint") { print $(i+1); exit } }' \
        <<<"${DETECTED_VALIDATOR_ARGS:-}")

    # Map entrypoint host to a cluster RPC guess
    if [[ "$ep" == *mainnet.x1.xyz* ]]; then
        DETECTED_CLUSTER_RPC="https://rpc.mainnet.x1.xyz"
    elif [[ "$ep" == *testnet.x1.xyz* ]]; then
        DETECTED_CLUSTER_RPC="https://rpc.testnet.x1.xyz"
    elif [[ "$ep" == *mainnet-beta.solana.com* ]]; then
        DETECTED_CLUSTER_RPC="https://api.mainnet-beta.solana.com"
    elif [[ "$ep" == *testnet.solana.com* ]]; then
        DETECTED_CLUSTER_RPC="https://api.testnet.solana.com"
    elif [[ "$ep" == *devnet.solana.com* ]]; then
        DETECTED_CLUSTER_RPC="https://api.devnet.solana.com"
    fi

    [[ -z "$DETECTED_CLUSTER_RPC" ]] && return

    local r
    r=$(timeout 3 curl -fsS -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' "$DETECTED_CLUSTER_RPC" 2>/dev/null \
        | grep -oE '"result":[0-9]+' | cut -d: -f2)
    if [[ -n "$r" ]]; then
        DETECTED_CLUSTER_OK="yes"
        DETECTED_CLUSTER_SLOT="$r"
        if [[ -n "$DETECTED_RPC_SLOT" ]]; then
            DETECTED_DRIFT=$(( r - DETECTED_RPC_SLOT ))
        fi
    fi
}

detect_budget() {
    DETECTED_BUDGET_MS=400
    # Heuristic: if entrypoint is X1 it's 400ms. (Solana also 400ms.)
    # Future: read from cluster getEpochSchedule.
}

run_all_detection() {
    detect_service
    detect_validator_args
    detect_identity
    detect_paths
    detect_disk
    detect_rpc
    detect_cluster
    detect_budget
}

print_detection_summary() {
    local fmt="  %-20s %s\n"
    printf "$fmt" "Service:"        "${DETECTED_SERVICE:-not found}"
    printf "$fmt" "Binary:"         "${DETECTED_VALIDATOR_BIN:-?}"
    if [[ -n "${DETECTED_IDENTITY_PUBKEY:-}" ]]; then
        printf "$fmt" "Identity:"   "${DETECTED_IDENTITY_PUBKEY:0:8}…${DETECTED_IDENTITY_PUBKEY: -4}  (${DETECTED_IDENTITY_PATH})"
    else
        printf "$fmt" "Identity:"   "${DETECTED_IDENTITY_PATH:-not detected}"
    fi
    printf "$fmt" "Vote account:"   "${DETECTED_VOTE_ACCOUNT:-?}"
    printf "$fmt" "Ledger:"         "${DETECTED_LEDGER:-?} (${DETECTED_LEDGER_SIZE:-?})"
    printf "$fmt" "Accounts:"       "${DETECTED_ACCOUNTS:-?} (${DETECTED_ACCOUNTS_SIZE:-?})"
    printf "$fmt" "Snapshots:"      "${DETECTED_SNAPSHOTS:-?}"
    printf "$fmt" "RPC port:"       "${DETECTED_RPC_PORT:-?}"
    printf "$fmt" "Gossip port:"    "${DETECTED_GOSSIP_PORT:-?}"
    printf "$fmt" "CPU:"            "${DETECTED_NCPU} cores  ${DETECTED_CPU_MODEL:-?}"
    printf "$fmt" "RAM:"            "${DETECTED_RAM_GB}GB"
    printf "$fmt" "Root device:"    "${DETECTED_NVME_DEV:-?}"
    printf "$fmt" "RAID:"           "${DETECTED_RAID:-no} (${DETECTED_NVME_COUNT:-0} physical NVMe drives)"
    [[ -n "${DETECTED_DISK_LAYOUT:-}" ]] && printf "$fmt" "" "$DETECTED_DISK_LAYOUT"
    printf "$fmt" "Local RPC:"      "${DETECTED_RPC_URL} (${DETECTED_RPC_OK}, slot ${DETECTED_RPC_SLOT:-?})"
    printf "$fmt" "Cluster RPC:"    "${DETECTED_CLUSTER_RPC:-?} (${DETECTED_CLUSTER_OK}, slot ${DETECTED_CLUSTER_SLOT:-?})"
    [[ -n "${DETECTED_DRIFT:-}" ]] && printf "$fmt" "Drift:"   "${DETECTED_DRIFT} slots"
    echo
}
