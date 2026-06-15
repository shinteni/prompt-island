#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_INTERNAL_RESTART_SECONDS:-5}"
MAX_VISIBLE_WIDTH="${VIBELSLAND_IDLE_VISIBLE_MAX_WIDTH:-900}"
MAX_VISIBLE_HEIGHT="${VIBELSLAND_IDLE_VISIBLE_MAX_HEIGHT:-600}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-internal-restart-home.XXXXXX")"
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

visible_process_count() {
    { /usr/bin/pgrep -x VibelslandFree 2>/dev/null || true; } | /usr/bin/wc -l | /usr/bin/tr -d ' '
}

assert_no_duplicate_instances() {
    local count
    count="$(visible_process_count)"
    if (( count > 1 )); then
        echo "Internal restart verification failed: duplicate VibelslandFree instances are visible during restart" >&2
        /usr/bin/pgrep -fl VibelslandFree >&2 || true
        exit 1
    fi
}

is_active_process() {
    local pid="$1"
    local state
    state="$(/bin/ps -p "$pid" -o stat= 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    [[ -n "$state" && "$state" != Z* ]]
}

wait_for_ready() {
    local pid="$1"
    local label="$2"
    for _ in {1..60}; do
        assert_no_duplicate_instances
        if is_active_process "$pid" && [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
            if ! /usr/bin/swift "$WINDOW_CHECKER" "$pid" 0 "$MAX_VISIBLE_WIDTH" 0 "$MAX_VISIBLE_HEIGHT" "$label" >/dev/null 2>&1; then
                return
            fi
        fi
        sleep 0.2
    done
    echo "Internal restart verification failed: $label did not become ready" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
    exit 1
}

start_app() {
    (
        export VIBELSLAND_HOME="$TEMP_HOME"
        export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
        "$EXECUTABLE" >/dev/null 2>&1
    ) &
    APP_PID="$!"
}

start_app
wait_for_ready "$APP_PID" "Initial internal restart"

FIRST_PID="$APP_PID"
FIRST_SOCKET_INODE="$(/usr/bin/stat -f "%i" "$SOCKET")"

/usr/bin/swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("free.vibelsland.verify.restart"), object: nil, userInfo: nil, deliverImmediately: true)'

OLD_EXITED=0
for _ in {1..120}; do
    assert_no_duplicate_instances
    if ! is_active_process "$FIRST_PID"; then
        wait "$FIRST_PID" >/dev/null 2>&1 || true
        APP_PID=""
        OLD_EXITED=1
        break
    fi
    sleep 0.05
done

if [[ "$OLD_EXITED" != "1" ]]; then
    echo "Internal restart verification failed: old app instance did not exit after internal restart action" >&2
    exit 1
fi

NEW_PID=""
for _ in {1..100}; do
    assert_no_duplicate_instances
    NEW_PID="$(/usr/bin/pgrep -x VibelslandFree 2>/dev/null | /usr/bin/grep -v "^$FIRST_PID$" | /usr/bin/head -1 || true)"
    if [[ -n "$NEW_PID" ]]; then
        APP_PID="$NEW_PID"
        break
    fi
    sleep 0.1
done

if [[ -z "$NEW_PID" ]]; then
    echo "Internal restart verification failed: app did not relaunch after internal restart action" >&2
    exit 1
fi

wait_for_ready "$APP_PID" "Relaunched internal restart"

SECOND_SOCKET_INODE="$(/usr/bin/stat -f "%i" "$SOCKET")"
if [[ "$FIRST_SOCKET_INODE" == "$SECOND_SOCKET_INODE" ]]; then
    echo "Internal restart verification failed: socket was not refreshed" >&2
    exit 1
fi

if [[ ! -f "$LOG" ]] || [[ "$(/usr/bin/grep -c 'bridge.start' "$LOG")" -lt 2 ]]; then
    echo "Internal restart verification failed: expected two bridge.start log entries" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

if /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Internal restart verification failed: isolated restart log contains errors" >&2
    /usr/bin/tail -100 "$LOG" >&2
    exit 1
fi

echo "Internal restart verification passed: $FIRST_PID -> $APP_PID"
