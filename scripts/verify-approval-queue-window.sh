#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_APPROVAL_WINDOW_SECONDS:-5}"
# 队列卡片（2 行 = 140pt）比单审批卡（88pt）高 52pt：
# 单审批窗口约 236pt，两个审批的队列窗口必须明显更高才算通过。
MIN_WIDTH="${VIBELSLAND_APPROVAL_QUEUE_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_QUEUE_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_QUEUE_MIN_HEIGHT:-250}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_QUEUE_MAX_HEIGHT:-400}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-approval-queue-home.XXXXXX")"
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
    echo "Approval queue verification failed: app process exited early" >&2
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

SMOKE_ID="vibelsland-approval-queue-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="/tmp/$SMOKE_ID"

send_approval() {
    local session_suffix="$1"
    local command="$2"
    (
        export HOME="$TEMP_HOME"
        export VIBELSLAND_BRIDGE_TIMEOUT=1
        printf '%s\n' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SMOKE_ID-$session_suffix\",\"cwd\":\"$SMOKE_WORKSPACE-$session_suffix\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$command\"},\"permission_suggestions\":[{\"type\":\"session\",\"pattern\":\"Bash($command)\"}]}" | "$BRIDGE" --source claude >/dev/null
    ) || true
}

send_approval "first" "echo first approval"
send_approval "second" "echo second approval"

output=""
for _ in {1..25}; do
    if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_WIDTH" "$MAX_WIDTH" "$MIN_HEIGHT" "$MAX_HEIGHT" "Approval queue" 2>&1)"; then
        if [[ -f "$LOG" ]] && [[ "$(/usr/bin/grep -c 'event.ingest claudeCode approval' "$LOG")" -ge 2 ]]; then
            echo "Approval queue verification passed: $output"
            exit 0
        fi
    fi
    sleep 0.2
done

echo "Approval queue verification failed: queue window size was not reached" >&2
echo "$output" >&2
if [[ -f "$LOG" ]]; then
    /usr/bin/tail -80 "$LOG" >&2
fi
exit 1
