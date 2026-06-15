#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_CODEX_APPROVAL_RESPONSE_SECONDS:-5}"
MIN_WIDTH="${VIBELSLAND_APPROVAL_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_MIN_HEIGHT:-110}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_MAX_HEIGHT:-240}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-codex-approval-response-home.XXXXXX")"
APP_PID=""
BRIDGE_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"
BRIDGE="$(vibelsland_bridge_path "$TEMP_HOME")"
SOCKET="$(vibelsland_socket_path "$TEMP_HOME")"

cleanup() {
    vibelsland_cleanup_temp_home "$TEMP_HOME" "$BRIDGE_PID" "$APP_PID"
}
trap cleanup EXIT

vibelsland_write_test_config "$TEMP_HOME" \
    enableClaude=false \
    enableCodexCLI=true \
    enableCodexDesktop=false \
    enableSounds=false \
    soundTheme=soft \
    doNotDisturb=false \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

start_app() {
    /bin/rm -f "$SOCKET"
    (
        export VIBELSLAND_HOME="$TEMP_HOME"
        export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
        "$EXECUTABLE" >/dev/null 2>&1
    ) &
    APP_PID="$!"

    sleep "$WAIT_SECONDS"

    if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
        echo "Codex CLI approval response verification failed: app process exited early" >&2
        exit 1
    fi

    for _ in {1..60}; do
        if [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
            break
        fi
        sleep 0.2
    done

    [[ -x "$BRIDGE" ]]
    [[ -S "$SOCKET" ]]
}

stop_app() {
    if [[ -n "$APP_PID" ]]; then
        /bin/kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
        APP_PID=""
    fi
}

run_decision() {
    local decision="$1"
    local expected="$2"
    local smoke_id="vibelsland-codex-approval-response-$decision-$(/bin/date +%s)-$$"
    local smoke_workspace="/tmp/$smoke_id"
    local payload_file="$TEMP_HOME/codex-$decision-request.json"
    local output_file="$TEMP_HOME/codex-$decision-output.json"
    local status_file="$TEMP_HOME/codex-$decision-status.txt"
    local ingest_count_before=0

    start_app
    if [[ -f "$LOG" ]]; then
        ingest_count_before="$(/usr/bin/grep -c 'event.ingest codexCli approval' "$LOG" || true)"
    fi

    /bin/rm -f "$payload_file" "$output_file" "$status_file"
    /bin/cat > "$payload_file" <<JSON
{"hook_event_name":"PermissionRequest","session_id":"$smoke_id-codex","thread_id":"$smoke_id-thread","cwd":"$smoke_workspace","tool_name":"Bash","tool_input":{"command":"echo codex-approval-response-$decision"}}
JSON

    (
        export HOME="$TEMP_HOME"
        export VIBELSLAND_BRIDGE_TIMEOUT=8
        "$BRIDGE" --source codex < "$payload_file" > "$output_file"
        echo "$?" > "$status_file"
    ) &
    BRIDGE_PID="$!"

    local output=""
    for _ in {1..35}; do
        local ingest_count_after=0
        if [[ -f "$LOG" ]]; then
            ingest_count_after="$(/usr/bin/grep -c 'event.ingest codexCli approval' "$LOG" || true)"
        fi
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_WIDTH" "$MAX_WIDTH" "$MIN_HEIGHT" "$MAX_HEIGHT" "Codex CLI Approval" 2>&1)" &&
            [[ "$ingest_count_after" -gt "$ingest_count_before" ]]; then
            break
        fi
        sleep 0.2
    done

    local final_ingest_count=0
    if [[ -f "$LOG" ]]; then
        final_ingest_count="$(/usr/bin/grep -c 'event.ingest codexCli approval' "$LOG" || true)"
    fi
    if [[ "$final_ingest_count" -le "$ingest_count_before" ]]; then
        echo "Codex CLI approval response verification failed: approval event was not visible for $decision" >&2
        echo "$output" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
        exit 1
    fi

    sleep 0.3
    /usr/bin/swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"free.vibelsland.verify.resolveApproval\"), object: nil, userInfo: [\"decision\": \"$decision\"], deliverImmediately: true)"

    for _ in {1..60}; do
        if [[ -f "$status_file" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ ! -f "$status_file" ]]; then
        echo "Codex CLI approval response verification failed: bridge did not return after $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
        exit 1
    fi

    local bridge_status bridge_output
    bridge_status="$(/bin/cat "$status_file")"
    bridge_output="$(/bin/cat "$output_file")"
    BRIDGE_PID=""

    if [[ "$bridge_status" != "0" ]]; then
        echo "Codex CLI approval response verification failed: bridge exited with $bridge_status for $decision" >&2
        exit 1
    fi

    if [[ "$bridge_output" != *"$expected"* ]]; then
        echo "Codex CLI approval response verification failed: unexpected bridge response for $decision: $bridge_output" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -140 "$LOG" >&2
        exit 1
    fi

    if [[ ! -f "$LOG" ]] ||
        ! /usr/bin/grep -q "approval.resolved codexCli $decision" "$LOG"; then
        echo "Codex CLI approval response verification failed: app did not record resolved approval for $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
        exit 1
    fi
    stop_app
}

run_decision "accept" '"behavior":"allow"'
run_decision "decline" '"behavior":"deny"'

if /usr/bin/grep -q 'approval.timedOut' "$LOG"; then
    echo "Codex CLI approval response verification failed: app logged timeout during resolved approval" >&2
    /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

echo "Codex CLI approval response verification passed: accept decline"
