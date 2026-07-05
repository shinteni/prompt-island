#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WINDOW_ID="$ROOT/scripts/window-id.swift"
IMAGE_CHECK="$ROOT/scripts/image-content-check.swift"
WAIT_SECONDS="${VIBELSLAND_VISUAL_SNAPSHOT_SECONDS:-5}"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"
MIN_TASK_WIDTH="${VIBELSLAND_TASK_MIN_WIDTH:-180}"
MAX_TASK_WIDTH="${VIBELSLAND_TASK_MAX_WIDTH:-320}"
MIN_TASK_HEIGHT="${VIBELSLAND_TASK_MIN_HEIGHT:-32}"
MAX_TASK_HEIGHT="${VIBELSLAND_TASK_MAX_HEIGHT:-70}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
[[ -f "$WINDOW_ID" ]]
[[ -f "$IMAGE_CHECK" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-visual-home.XXXXXX")"
APP_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"

cleanup() {
    if [[ -n "$APP_PID" ]]; then
        /bin/kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
    fi
    if [[ "${VIBELSLAND_KEEP_VISUAL_SNAPSHOTS:-0}" != "1" ]]; then
        /bin/rm -rf "$TEMP_HOME"
    else
        echo "Visual snapshots kept at $TEMP_HOME"
    fi
}
trap cleanup EXIT

vibelsland_write_test_config "$TEMP_HOME" \
    enableClaude=true \
    enableCodexCLI=true \
    enableCodexDesktop=false \
    enableSounds=false \
    soundTheme=soft \
    doNotDisturb=true \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

wait_for_window() {
    local label="$1"
    shift
    local output=""
    for _ in {1..40}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$@" "$label" 2>&1)"; then
            return 0
        fi
        sleep 0.2
    done
    echo "Visual snapshot verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
}

ensure_no_window() {
    local label="$1"
    shift
    local output=""
    for _ in {1..10}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$@" "$label" 2>&1)"; then
            echo "Visual snapshot verification failed: $label should be hidden" >&2
            echo "$output" >&2
            [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
            exit 1
        fi
        sleep 0.1
    done
}

capture_window() {
    local label="$1"
    local output="$2"
    shift 2
    local window_id
    window_id="$(/usr/bin/swift "$WINDOW_ID" "$APP_PID" "$@" "$label")"
    /usr/sbin/screencapture -x -o -l "$window_id" "$output"
    /usr/bin/swift "$IMAGE_CHECK" "$output" "$label"
}

post_expanded_state() {
    local expanded="$1"
    /usr/bin/swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"free.vibelsland.verify.setExpanded\"), object: nil, userInfo: [\"expanded\": \"$expanded\"], deliverImmediately: true)"
}

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Visual snapshot verification failed: app process exited early" >&2
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

ensure_no_window "Idle hidden" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT"

SMOKE_ID="vibelsland-visual-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"
(
    export HOME="$TEMP_HOME"
    printf '%s\n' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Verify visual snapshots\"}" |
        "$BRIDGE" --source codex >/dev/null
)

wait_for_window "Task visual" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT"
capture_window "Task visual" "$TEMP_HOME/task.png" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT"

post_expanded_state true
wait_for_window "Expanded visual" 380 560 90 310
capture_window "Expanded visual" "$TEMP_HOME/expanded.png" 380 560 90 310

if [[ -f "$LOG" ]] && /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Visual snapshot verification failed: isolated log contains errors" >&2
    /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

echo "Visual snapshot verification passed"
