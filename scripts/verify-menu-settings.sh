#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WINDOW_ID="$ROOT/scripts/window-id.swift"
IMAGE_CHECK="$ROOT/scripts/image-content-check.swift"
WAIT_SECONDS="${VIBELSLAND_MENU_SETTINGS_SECONDS:-5}"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
[[ -f "$WINDOW_ID" ]]
[[ -f "$IMAGE_CHECK" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-menu-settings-home.XXXXXX")"
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
    echo "Menu settings verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
}

open_settings_from_menu() {
    /usr/bin/osascript >/dev/null <<'APPLESCRIPT'
tell application "System Events"
  tell process "VibelslandFree"
    click menu bar item 1 of menu bar 2
    delay 0.2
    click menu item "设置..." of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
APPLESCRIPT
}

wait_for_settings_accessibility() {
    for _ in {1..30}; do
        if /usr/bin/osascript -e 'tell application "System Events" to tell process "VibelslandFree" to exists window "设置"' 2>/dev/null | /usr/bin/grep -q true; then
            return 0
        fi
        sleep 0.2
    done
    echo "Menu settings verification failed: settings window was not exposed to accessibility" >&2
    exit 1
}

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Menu settings verification failed: app process exited early" >&2
    exit 1
fi

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]
wait_for_window "Initial menu settings idle" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT"

if ! open_settings_from_menu; then
    echo "Menu settings verification failed: could not click status bar Settings menu item" >&2
    exit 1
fi

wait_for_settings_accessibility
wait_for_window "Settings window" 850 1000 650 850
SETTINGS_WINDOW_ID="$(/usr/bin/swift "$WINDOW_ID" "$APP_PID" 850 1000 650 850 "Settings window")"
/usr/sbin/screencapture -x -o -l "$SETTINGS_WINDOW_ID" "$TEMP_HOME/settings.png"
/usr/bin/swift "$IMAGE_CHECK" "$TEMP_HOME/settings.png" "Settings window"

SOCKET_MODE="$(/usr/bin/stat -f "%Lp" "$SOCKET")"
[[ "$SOCKET_MODE" == "600" ]]
SOCKET_OWNER="$(/usr/bin/stat -f "%u" "$SOCKET")"
[[ "$SOCKET_OWNER" == "$(/usr/bin/id -u)" ]]

if [[ ! -f "$LOG" ]] || ! /usr/bin/grep -q 'bridge.start' "$LOG"; then
    echo "Menu settings verification failed: isolated log is missing bridge.start" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

if /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Menu settings verification failed: isolated log contains errors" >&2
    /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

echo "Menu settings verification passed"
