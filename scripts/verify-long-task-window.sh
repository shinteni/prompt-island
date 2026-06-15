#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_LONG_TASK_SECONDS:-5}"
MIN_TASK_WIDTH="${VIBELSLAND_TASK_MIN_WIDTH:-180}"
MAX_TASK_WIDTH="${VIBELSLAND_TASK_MAX_WIDTH:-320}"
MIN_TASK_HEIGHT="${VIBELSLAND_TASK_MIN_HEIGHT:-32}"
MAX_TASK_HEIGHT="${VIBELSLAND_TASK_MAX_HEIGHT:-70}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-task-home.XXXXXX")"
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

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"

if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Long task verification failed: app process exited early" >&2
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

SMOKE_ID="vibelsland-long-task-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"

send_bridge_event() {
    local source="$1"
    local stage="$2"
    local payload="$3"
    (
        export HOME="$TEMP_HOME"
        printf '%s\n' "$payload" | "$BRIDGE" --source "$source" >/dev/null
    )
    wait_for_task_window "$stage"
}

wait_for_task_window() {
    local stage="$1"
    local output=""
    for _ in {1..20}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT" "Task" 2>&1)"; then
            return 0
        fi
        sleep 0.2
    done
    echo "Long task verification failed at stage: $stage" >&2
    echo "$output" >&2
    if [[ -f "$LOG" ]]; then
        echo "Recent isolated app log:" >&2
        /usr/bin/tail -80 "$LOG" >&2
    fi
    exit 1
}

send_bridge_event claude "claude-prompt" "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Verify subagent stop stays active\"}"
send_bridge_event claude "subagent-start" "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"agent_name\":\"worker\"}"
send_bridge_event claude "subagent-stop" "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"agent_name\":\"worker\"}"
send_bridge_event codex "codex-prompt" "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Verify tool end stays active\"}"
send_bridge_event codex "tool-start" "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sleep 30\"}}"
send_bridge_event codex "tool-end" "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sleep 30\"}}"

/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_TASK_WIDTH" "$MAX_TASK_WIDTH" "$MIN_TASK_HEIGHT" "$MAX_TASK_HEIGHT" "Task"
