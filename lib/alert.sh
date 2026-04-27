#!/usr/bin/env bash
# =============================================================================
# x1-sentinel alert dispatch library
# Sourced by x1-sentinel main script.
#
# Functions:
#   alert_send <level> <title> <body>
#       Sends to all configured destinations with rate limiting.
#       Levels: INFO, WARN, HIGH, CRIT
# =============================================================================

ALERT_RATE_LIMIT_SEC="${ALERT_RATE_LIMIT_SEC:-300}"   # 5 min default
ALERT_STATE_DIR="${ALERT_STATE_DIR:-/tmp/x1-sentinel-alerts}"
mkdir -p "$ALERT_STATE_DIR" 2>/dev/null || true

_alert_should_send() {
    local key="$1"
    local now last
    now=$(date +%s)
    last=$(cat "$ALERT_STATE_DIR/last_${key}" 2>/dev/null || echo 0)
    if (( now - last < ALERT_RATE_LIMIT_SEC )); then
        return 1
    fi
    echo "$now" > "$ALERT_STATE_DIR/last_${key}"
    return 0
}

_alert_telegram() {
    local level="$1" title="$2" body="$3"
    [[ -z "${TG_TOKEN:-}" || -z "${TG_CHAT:-}" ]] && return 0
    local emoji
    case "$level" in
        INFO) emoji="ℹ️" ;;
        WARN) emoji="⚠️" ;;
        HIGH) emoji="🟠" ;;
        CRIT) emoji="🚨" ;;
        *)    emoji="📊" ;;
    esac
    local text="${emoji} *${title}*
\`$(hostname -s)\`
${body}"
    curl -fsS -m 5 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT}" \
        -d "text=${text}" \
        -d "parse_mode=Markdown" >/dev/null 2>&1 || return 1
}

_alert_discord() {
    local level="$1" title="$2" body="$3"
    [[ -z "${DISCORD_WEBHOOK:-}" ]] && return 0
    local color
    case "$level" in
        INFO) color=3447003  ;;  # blue
        WARN) color=16776960 ;;  # yellow
        HIGH) color=15105570 ;;  # orange
        CRIT) color=15158332 ;;  # red
        *)    color=10070709 ;;
    esac
    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "${title}",
    "description": "${body}",
    "color": ${color},
    "footer": {"text": "$(hostname -s)"},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }]
}
EOF
    )
    curl -fsS -m 5 -H "Content-Type: application/json" \
        -d "$payload" "$DISCORD_WEBHOOK" >/dev/null 2>&1 || return 1
}

_alert_webhook() {
    local level="$1" title="$2" body="$3"
    [[ -z "${WEBHOOK_URL:-}" ]] && return 0
    local payload
    payload=$(cat <<EOF
{
  "host": "$(hostname -s)",
  "level": "${level}",
  "title": "${title}",
  "body": "${body}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    )
    curl -fsS -m 5 -H "Content-Type: application/json" \
        -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1 || return 1
}

# Public API: alert_send <level> <title> <body>
# Rate-limited per (level + first 32 chars of title) to prevent spam.
alert_send() {
    local level="$1" title="$2" body="$3"
    local key
    key=$(echo "${level}_${title:0:32}" | tr -c 'a-zA-Z0-9_' '_')
    _alert_should_send "$key" || return 0
    _alert_telegram "$level" "$title" "$body" &
    _alert_discord  "$level" "$title" "$body" &
    _alert_webhook  "$level" "$title" "$body" &
    wait
}
