#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WINDOW_FRAME="$ROOT/scripts/window-frame.swift"
WINDOW_FRAME_SAMPLES="$ROOT/scripts/window-frame-samples.swift"
WAIT_SECONDS="${VIBELSLAND_EXPAND_COLLAPSE_SECONDS:-5}"
MIN_TASK_WIDTH="${VIBELSLAND_TASK_MIN_WIDTH:-180}"
MAX_TASK_WIDTH="${VIBELSLAND_TASK_MAX_WIDTH:-320}"
MIN_TASK_HEIGHT="${VIBELSLAND_TASK_MIN_HEIGHT:-32}"
MAX_TASK_HEIGHT="${VIBELSLAND_TASK_MAX_HEIGHT:-70}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
[[ -f "$WINDOW_FRAME" ]]
[[ -f "$WINDOW_FRAME_SAMPLES" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-expand-collapse-home.XXXXXX")"
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
    doNotDisturb=true \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

visible_process_count() {
    { /usr/bin/pgrep -x VibelslandFree 2>/dev/null || true; } | /usr/bin/wc -l | /usr/bin/tr -d ' '
}

assert_single_process() {
    local count
    count="$(visible_process_count)"
    if [[ "$count" != "1" ]]; then
        echo "Expand/collapse verification failed: expected one VibelslandFree process, got $count" >&2
        /usr/bin/pgrep -fl VibelslandFree >&2 || true
        exit 1
    fi
}

wait_for_window() {
    local label="$1"
    shift
    local output=""
    for _ in {1..30}; do
        assert_single_process
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$@" "$label" 2>&1)"; then
            return 0
        fi
        sleep 0.2
    done
    echo "Expand/collapse verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
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
    echo "Expand/collapse verification failed: app process exited early" >&2
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

SMOKE_ID="vibelsland-expand-collapse-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"
(
    export HOME="$TEMP_HOME"
    printf '%s\n' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Verify collapse remains visible\"}" |
        "$BRIDGE" --source codex >/dev/null
)

wait_for_window "Task before expand" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT"

post_expanded_state true
wait_for_window "Expanded" 380 560 90 310
EXPANDED_FRAME="$(/usr/bin/swift "$WINDOW_FRAME" "$APP_PID" 380 560 90 310 "Expanded frame")"
EXPANDED_WIDTH="$(printf '%s\n' "$EXPANDED_FRAME" | /usr/bin/awk '{print $3}')"

COLLAPSE_SAMPLES="$TEMP_HOME/collapse-frames.txt"
: > "$COLLAPSE_SAMPLES"
/usr/bin/swift "$WINDOW_FRAME_SAMPLES" "$APP_PID" 1.0 0.016 "Collapse frames" > "$COLLAPSE_SAMPLES" &
SAMPLE_PID="$!"
(
    sleep 0.08
    post_expanded_state false
) &
POST_COLLAPSE_PID="$!"
wait "$POST_COLLAPSE_PID"
wait "$SAMPLE_PID"
INTERMEDIATE_FRAME_COUNT="$(/usr/bin/awk -v compactMax="$MAX_TASK_WIDTH" -v expanded="$EXPANDED_WIDTH" '
    $4 > compactMax + 4 && $4 < expanded - 4 { count += 1 }
    END { print count + 0 }
' "$COLLAPSE_SAMPLES")"
UNIQUE_FRAME_COUNT="$(/usr/bin/awk '
    { key = int($4) "x" int($5); if (!seen[key]++) { count += 1 } }
    END { print count + 0 }
' "$COLLAPSE_SAMPLES")"
if (( INTERMEDIATE_FRAME_COUNT < 2 || UNIQUE_FRAME_COUNT < 4 )); then
    echo "Expand/collapse verification failed: collapse did not expose enough intermediate frames" >&2
    echo "expanded=$EXPANDED_FRAME intermediate=$INTERMEDIATE_FRAME_COUNT unique=$UNIQUE_FRAME_COUNT" >&2
    /bin/cat "$COLLAPSE_SAMPLES" >&2
    exit 1
fi

wait_for_window "Task after collapse" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT"

if [[ -f "$LOG" ]] && /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Expand/collapse verification failed: isolated log contains errors" >&2
    /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

echo "Expand/collapse visibility verification passed"
