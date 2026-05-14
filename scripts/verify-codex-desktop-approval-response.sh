#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_DESKTOP_APPROVAL_RESPONSE_SECONDS:-5}"
MIN_WIDTH="${VIBELSLAND_APPROVAL_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_MIN_HEIGHT:-110}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_MAX_HEIGHT:-240}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-desktop-approval-response-home.XXXXXX")"
APP_PID=""
LOG="$TEMP_HOME/Library/Logs/VibelslandFree/app.log"
FAKE_CODEX="$TEMP_HOME/fake-codex"
FAKE_SOCKET="$TEMP_HOME/fake-codex-ipc.sock"

cleanup() {
    if [[ -n "$APP_PID" ]]; then
        /bin/kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$TEMP_HOME"
}
trap cleanup EXIT

CONFIG_DIR="$TEMP_HOME/Library/Application Support/VibelslandFree"
/bin/mkdir -p "$CONFIG_DIR"
/bin/cat > "$CONFIG_DIR/config.json" <<'JSON'
{
  "enableClaude": false,
  "enableCodexCLI": false,
  "enableCodexDesktop": true,
  "enableSounds": false,
  "soundTheme": "soft",
  "doNotDisturb": false,
  "launchAtLogin": false,
  "islandPosition": "topCenter",
  "approvalTimeoutSeconds": 7200,
  "maxVisibleSessions": 5
}
JSON

/bin/cat > "$FAKE_CODEX" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
import time

request_id = os.environ["VIBELSLAND_FAKE_CODEX_REQUEST_ID"]
decision_output = os.environ["VIBELSLAND_FAKE_CODEX_OUTPUT"]
decision = os.environ["VIBELSLAND_FAKE_CODEX_DECISION"]

def write(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()

sent = False
for line in sys.stdin:
    try:
        message = json.loads(line)
    except Exception:
        continue

    if message.get("method") == "initialize":
        write({"id": message.get("id"), "result": {"codexHome": os.environ.get("HOME", ""), "userAgent": "fake-codex"}})

    if message.get("method") == "initialized" and not sent:
        write({
            "id": request_id,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "threadId": "desktop-thread-" + decision,
                "turnId": "turn-" + decision,
                "itemId": "item-" + decision,
                "cwd": "/tmp/vibelsland-desktop-approval-" + decision,
                "command": "echo desktop-approval-" + decision,
                "availableDecisions": ["accept", "acceptForSession", "decline", "cancel"]
            }
        })
        sent = True
        continue

    if message.get("id") == request_id and "result" in message:
        with open(decision_output, "w", encoding="utf-8") as handle:
            json.dump(message, handle, sort_keys=True, separators=(",", ":"))
        write({"method": "serverRequest/resolved", "params": {"requestId": request_id}})
        time.sleep(0.4)
        break
PY
/bin/chmod +x "$FAKE_CODEX"

start_app() {
    local decision="$1"
    local output_file="$2"
    /bin/rm -f "$FAKE_SOCKET"
    /usr/bin/touch "$FAKE_SOCKET"
    (
        export VIBELSLAND_HOME="$TEMP_HOME"
        export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
        export VIBELSLAND_CODEX_EXECUTABLE="$FAKE_CODEX"
        export VIBELSLAND_CODEX_IPC_SOCKET="$FAKE_SOCKET"
        export VIBELSLAND_FAKE_CODEX_DECISION="$decision"
        export VIBELSLAND_FAKE_CODEX_REQUEST_ID="desktop-request-$decision"
        export VIBELSLAND_FAKE_CODEX_OUTPUT="$output_file"
        "$EXECUTABLE" >/dev/null 2>&1
    ) &
    APP_PID="$!"

    sleep "$WAIT_SECONDS"

    if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
        echo "Codex Desktop approval response verification failed: app process exited early for $decision" >&2
        exit 1
    fi
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
    local output_file="$TEMP_HOME/desktop-$decision-output.json"
    local request_key="desktop-request-$decision"
    local focused_count_before=0
    if [[ -f "$LOG" ]]; then
        focused_count_before="$(/usr/bin/grep -c 'approval.focused' "$LOG" || true)"
    fi

    /bin/rm -f "$output_file"
    start_app "$decision" "$output_file"

    local output=""
    for _ in {1..40}; do
        local focused_count_after=0
        if [[ -f "$LOG" ]]; then
            focused_count_after="$(/usr/bin/grep -c 'approval.focused' "$LOG" || true)"
        fi
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_WIDTH" "$MAX_WIDTH" "$MIN_HEIGHT" "$MAX_HEIGHT" "Codex Desktop Approval" 2>&1)" &&
            [[ "$focused_count_after" -gt "$focused_count_before" ]]; then
            break
        fi
        sleep 0.2
    done

    local focused_count_final=0
    if [[ -f "$LOG" ]]; then
        focused_count_final="$(/usr/bin/grep -c 'approval.focused' "$LOG" || true)"
    fi
    if [[ "$focused_count_final" -le "$focused_count_before" ]]; then
        echo "Codex Desktop approval response verification failed: approval was not visible for $decision" >&2
        echo "$output" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -120 "$LOG" >&2
        exit 1
    fi

    sleep 0.3
    /usr/bin/swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"free.vibelsland.verify.resolveApproval\"), object: nil, userInfo: [\"decision\": \"$decision\"], deliverImmediately: true)"

    for _ in {1..60}; do
        if [[ -f "$output_file" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ ! -f "$output_file" ]]; then
        echo "Codex Desktop approval response verification failed: fake app-server did not receive response for $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -160 "$LOG" >&2
        exit 1
    fi

    local response
    response="$(/bin/cat "$output_file")"
    if [[ "$response" != *"$expected"* ]]; then
        echo "Codex Desktop approval response verification failed: unexpected response for $decision: $response" >&2
        exit 1
    fi

    for _ in {1..30}; do
        if [[ -f "$LOG" ]] && /usr/bin/grep -q "codex.desktop.approval.resolved $request_key" "$LOG"; then
            break
        fi
        sleep 0.1
    done

    if [[ ! -f "$LOG" ]] ||
        ! /usr/bin/grep -q "codex.desktop.approval.resolved $request_key" "$LOG"; then
        echo "Codex Desktop approval response verification failed: app did not mark Desktop approval resolved for $decision" >&2
        [[ -f "$LOG" ]] && /usr/bin/tail -160 "$LOG" >&2
        exit 1
    fi

    stop_app
}

run_decision "accept" '"decision":"accept"'
run_decision "acceptForSession" '"decision":"acceptForSession"'
run_decision "decline" '"decision":"decline"'
run_decision "cancel" '"decision":"cancel"'

if /usr/bin/grep -q 'Codex Desktop 未确认结果' "$LOG"; then
    echo "Codex Desktop approval response verification failed: Desktop resolve timeout was logged" >&2
    /usr/bin/tail -160 "$LOG" >&2
    exit 1
fi

echo "Codex Desktop approval response verification passed: accept acceptForSession decline cancel"
