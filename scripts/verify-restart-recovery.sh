#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_RESTART_RECOVERY_SECONDS:-5}"
MAX_VISIBLE_WIDTH="${VIBELSLAND_IDLE_VISIBLE_MAX_WIDTH:-900}"
MAX_VISIBLE_HEIGHT="${VIBELSLAND_IDLE_VISIBLE_MAX_HEIGHT:-600}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-restart-home.XXXXXX")"
APP_PID=""
LOG="$TEMP_HOME/Library/Logs/VibelslandFree/app.log"
BRIDGE="$TEMP_HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$TEMP_HOME/.vibelsland-free/run/vibelsland.sock"

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
  "enableCodexDesktop": false,
  "enableSounds": false,
  "soundTheme": "soft",
  "doNotDisturb": true,
  "launchAtLogin": false,
  "islandPosition": "topCenter",
  "approvalTimeoutSeconds": 7200,
  "maxVisibleSessions": 5
}
JSON

start_app() {
    (
        export VIBELSLAND_HOME="$TEMP_HOME"
        "$EXECUTABLE" >/dev/null 2>&1
    ) &
    APP_PID="$!"
    sleep "$WAIT_SECONDS"
    if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
        echo "Restart recovery verification failed: app process exited early" >&2
        exit 1
    fi
}

stop_app() {
    /bin/kill "$APP_PID" >/dev/null 2>&1 || true
    for _ in {1..30}; do
        if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
            wait "$APP_PID" >/dev/null 2>&1 || true
            APP_PID=""
            return
        fi
        sleep 0.1
    done
    echo "Restart recovery verification failed: app did not stop" >&2
    exit 1
}

verify_ready() {
    local label="$1"
    [[ -x "$BRIDGE" ]]
    [[ -S "$SOCKET" ]]
    local socket_mode socket_owner
    socket_mode="$(/usr/bin/stat -f "%Lp" "$SOCKET")"
    [[ "$socket_mode" == "600" ]]
    socket_owner="$(/usr/bin/stat -f "%u" "$SOCKET")"
    [[ "$socket_owner" == "$(/usr/bin/id -u)" ]]
    if /usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_VISIBLE_WIDTH" 0 "$MAX_VISIBLE_HEIGHT" "$label" >/dev/null 2>&1; then
        echo "Restart recovery verification failed: $label should be hidden while idle" >&2
        exit 1
    fi
}

start_app
verify_ready "First idle"
FIRST_PID="$APP_PID"
FIRST_SOCKET_INODE="$(/usr/bin/stat -f "%i" "$SOCKET")"

stop_app

start_app
verify_ready "Restarted idle"
SECOND_PID="$APP_PID"
SECOND_SOCKET_INODE="$(/usr/bin/stat -f "%i" "$SOCKET")"

if [[ "$FIRST_PID" == "$SECOND_PID" ]]; then
    echo "Restart recovery verification failed: pid did not change" >&2
    exit 1
fi

if [[ "$FIRST_SOCKET_INODE" == "$SECOND_SOCKET_INODE" ]]; then
    echo "Restart recovery verification failed: socket was not refreshed" >&2
    exit 1
fi

if [[ ! -f "$LOG" ]] || [[ "$(/usr/bin/grep -c 'bridge.start' "$LOG")" -lt 2 ]]; then
    echo "Restart recovery verification failed: expected two bridge.start log entries" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

if /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Restart recovery verification failed: isolated restart log contains errors" >&2
    /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

echo "Restart recovery verification passed: $FIRST_PID -> $SECOND_PID"
