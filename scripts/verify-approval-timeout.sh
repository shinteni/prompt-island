#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_APPROVAL_TIMEOUT_WAIT_SECONDS:-5}"
MIN_WIDTH="${VIBELSLAND_APPROVAL_MIN_WIDTH:-500}"
MAX_WIDTH="${VIBELSLAND_APPROVAL_MAX_WIDTH:-700}"
MIN_HEIGHT="${VIBELSLAND_APPROVAL_MIN_HEIGHT:-110}"
MAX_HEIGHT="${VIBELSLAND_APPROVAL_MAX_HEIGHT:-240}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-approval-timeout-home.XXXXXX")"
APP_PID=""
LOG="$TEMP_HOME/Library/Logs/VibelslandFree/app.log"

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
  "enableClaude": true,
  "enableCodexCLI": true,
  "enableCodexDesktop": false,
  "enableSounds": false,
  "soundTheme": "soft",
  "doNotDisturb": false,
  "launchAtLogin": false,
  "islandPosition": "topCenter",
  "approvalTimeoutSeconds": 7200,
  "maxVisibleSessions": 5
}
JSON

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    export VIBELSLAND_APPROVAL_TIMEOUT_SECONDS=1
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"

if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Approval timeout verification failed: app process exited early" >&2
    exit 1
fi

BRIDGE="$TEMP_HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$TEMP_HOME/.vibelsland-free/run/vibelsland.sock"
for _ in {1..60}; do
    if [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
        break
    fi
    sleep 0.2
done

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]

SMOKE_ID="vibelsland-approval-timeout-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="/tmp/$SMOKE_ID"
PAYLOAD="{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo timeout\"},\"permission_suggestions\":[{\"type\":\"session\",\"pattern\":\"Bash(echo timeout)\"}]}"

set +e
BRIDGE_OUTPUT="$(
    export HOME="$TEMP_HOME"
    export VIBELSLAND_BRIDGE_TIMEOUT=5
    printf '%s\n' "$PAYLOAD" | "$BRIDGE" --source claude
)"
BRIDGE_STATUS=$?
set -e

if [[ "$BRIDGE_STATUS" -ne 0 ]]; then
    echo "Approval timeout verification failed: bridge exited with $BRIDGE_STATUS" >&2
    exit 1
fi

if [[ -n "$BRIDGE_OUTPUT" ]]; then
    echo "Approval timeout verification failed: bridge returned an approval response: $BRIDGE_OUTPUT" >&2
    exit 1
fi

if [[ ! -f "$LOG" ]] ||
    ! /usr/bin/grep -q 'event.ingest claudeCode approval' "$LOG" ||
    ! /usr/bin/grep -q 'approval.timedOut' "$LOG"; then
    echo "Approval timeout verification failed: timeout was not recorded by the app" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

if /usr/bin/grep -q 'approval.resolved' "$LOG"; then
    echo "Approval timeout verification failed: app resolved approval instead of timing out" >&2
    /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

echo "Approval timeout verification passed"
