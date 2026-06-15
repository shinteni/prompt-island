#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_APPROVAL_WINDOW_SECONDS:-5}"
MIN_WIDTH="${VIBELSLAND_APPROVAL_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_MIN_HEIGHT:-110}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_MAX_HEIGHT:-240}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-approval-home.XXXXXX")"
APP_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"

cleanup() {
    vibelsland_cleanup_temp_home "$TEMP_HOME" "$APP_PID"
}
trap cleanup EXIT

vibelsland_write_test_config "$TEMP_HOME" \
    enableClaude=true \
    enableCodexCLI=true \
    enableCodexDesktop=false \
    enableSounds=false \
    soundTheme=soft \
    doNotDisturb=false \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"

if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Approval window verification failed: app process exited early" >&2
    exit 1
fi

BRIDGE="$(vibelsland_bridge_path "$TEMP_HOME")"
SOCKET="$(vibelsland_socket_path "$TEMP_HOME")"
for _ in {1..60}; do
    if [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
        break
    fi
    sleep 0.2
done

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]

SMOKE_ID="vibelsland-approval-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="/tmp/$SMOKE_ID"

(
    export HOME="$TEMP_HOME"
    export VIBELSLAND_BRIDGE_TIMEOUT=1
    printf '%s\n' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo approval\"},\"permission_suggestions\":[{\"type\":\"session\",\"pattern\":\"Bash(echo approval)\"}]}" | "$BRIDGE" --source claude >/dev/null
) || true

output=""
for _ in {1..25}; do
    if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_WIDTH" "$MAX_WIDTH" "$MIN_HEIGHT" "$MAX_HEIGHT" "Approval" 2>&1)"; then
        if [[ -f "$LOG" ]] && /usr/bin/grep -q 'event.ingest claudeCode approval' "$LOG"; then
            echo "$output"
            exit 0
        fi
    fi
    sleep 0.2
done

echo "Approval window verification failed: approval event was not visible" >&2
echo "$output" >&2
if [[ -f "$LOG" ]]; then
    /usr/bin/tail -80 "$LOG" >&2
fi
exit 1
