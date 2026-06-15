#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_APPROVAL_RESPONSE_SECONDS:-5}"
MIN_WIDTH="${VIBELSLAND_APPROVAL_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_MIN_HEIGHT:-110}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_MAX_HEIGHT:-240}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-approval-response-home.XXXXXX")"
APP_PID=""
BRIDGE_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"

cleanup() {
    if [[ -n "$BRIDGE_PID" ]]; then
        /bin/kill "$BRIDGE_PID" >/dev/null 2>&1 || true
        wait "$BRIDGE_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$APP_PID" ]]; then
        /bin/kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
    fi
    if [[ "${VIBELSLAND_KEEP_FAILED_APPROVAL_RESPONSE_HOME:-0}" != "1" || "${APPROVAL_RESPONSE_FAILED:-0}" != "1" ]]; then
        /bin/rm -rf "$TEMP_HOME"
    else
        echo "Preserving failed approval response home: $TEMP_HOME" >&2
    fi
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

BRIDGE="$(vibelsland_bridge_path "$TEMP_HOME")"
SOCKET="$(vibelsland_socket_path "$TEMP_HOME")"

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
        echo "Approval response verification failed: app process exited early" >&2
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
    local extra_expected="${3:-}"
    local smoke_id="vibelsland-approval-response-$decision-$(/bin/date +%s)-$$"
    local smoke_workspace="/tmp/$smoke_id"
    local payload_file="$TEMP_HOME/$decision-request.json"
    local output_file="$TEMP_HOME/$decision-output.json"
    local status_file="$TEMP_HOME/$decision-status.txt"
    local ingest_count_before=0
    start_app
    if [[ -f "$LOG" ]]; then
        ingest_count_before="$(/usr/bin/grep -c 'event.ingest claudeCode approval' "$LOG" || true)"
    fi

    /bin/rm -f "$payload_file" "$output_file" "$status_file"
    /bin/cat > "$payload_file" <<JSON
{"hook_event_name":"PermissionRequest","session_id":"$smoke_id-claude","cwd":"$smoke_workspace","tool_name":"Bash","tool_input":{"command":"echo approval-response-$decision"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}
JSON

    (
        export HOME="$TEMP_HOME"
        export VIBELSLAND_BRIDGE_TIMEOUT=8
        "$BRIDGE" --source claude < "$payload_file" > "$output_file"
        echo "$?" > "$status_file"
    ) &
    BRIDGE_PID="$!"

    local output=""
    for _ in {1..35}; do
        local ingest_count_after=0
        if [[ -f "$LOG" ]]; then
            ingest_count_after="$(/usr/bin/grep -c 'event.ingest claudeCode approval' "$LOG" || true)"
        fi
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_WIDTH" "$MAX_WIDTH" "$MIN_HEIGHT" "$MAX_HEIGHT" "Approval" 2>&1)" &&
            [[ "$ingest_count_after" -gt "$ingest_count_before" ]]; then
            break
        fi
        sleep 0.2
    done

    local final_ingest_count=0
    if [[ -f "$LOG" ]]; then
        final_ingest_count="$(/usr/bin/grep -c 'event.ingest claudeCode approval' "$LOG" || true)"
    fi
    if [[ "$final_ingest_count" -le "$ingest_count_before" ]]; then
        echo "Approval response verification failed: approval event was not visible for $decision" >&2
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
        echo "Approval response verification failed: bridge did not return after $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
        exit 1
    fi

    local bridge_status bridge_output
    bridge_status="$(/bin/cat "$status_file")"
    bridge_output="$(/bin/cat "$output_file")"
    BRIDGE_PID=""

    if [[ "$bridge_status" != "0" ]]; then
        echo "Approval response verification failed: bridge exited with $bridge_status for $decision" >&2
        exit 1
    fi

    if [[ "$bridge_output" != *"$expected"* ]]; then
        APPROVAL_RESPONSE_FAILED=1
        echo "Approval response verification failed: unexpected bridge response for $decision: $bridge_output" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -140 "$LOG" >&2
        exit 1
    fi

    if [[ -n "$extra_expected" && "$bridge_output" != *"$extra_expected"* ]]; then
        APPROVAL_RESPONSE_FAILED=1
        echo "Approval response verification failed: missing expected response field for $decision: $bridge_output" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -140 "$LOG" >&2
        exit 1
    fi

    if [[ ! -f "$LOG" ]] ||
        ! /usr/bin/grep -q "approval.resolved claudeCode $decision" "$LOG"; then
        echo "Approval response verification failed: app did not record resolved approval for $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
        exit 1
    fi
    stop_app
}

run_decision "accept" '"behavior":"allow"'
run_decision "decline" '"behavior":"deny"' 'Permission denied in >_ - island.'
run_decision "cancel" '"interrupt":true' 'Permission cancelled in >_ - island.'
run_decision "acceptForSession" '"behavior":"allow"' '"updatedPermissions"'

if /usr/bin/grep -q 'approval.timedOut' "$LOG"; then
    echo "Approval response verification failed: app logged timeout during resolved approval" >&2
    /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

echo "Approval response verification passed: accept decline cancel acceptForSession"
