#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_MENU_LOGS_SECONDS:-5}"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-menu-logs-home.XXXXXX")"
APP_PID=""
LOG="$TEMP_HOME/Library/Logs/VibelslandFree/app.log"
BRIDGE="$TEMP_HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$TEMP_HOME/.vibelsland-free/run/vibelsland.sock"

cleanup() {
    /usr/bin/osascript >/dev/null 2>&1 <<APPLESCRIPT || true
set tempRoot to "$TEMP_HOME"
tell application "Finder"
  repeat with finderWindow in windows
    try
      set targetPath to POSIX path of (target of finderWindow as alias)
      if targetPath starts with tempRoot then close finderWindow
    end try
  end repeat
end tell
APPLESCRIPT
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

is_active_process() {
    local pid="$1"
    local state
    state="$(/bin/ps -p "$pid" -o stat= 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    [[ -n "$state" && "$state" != Z* ]]
}

wait_for_window() {
    local label="$1"
    shift
    local output=""
    for _ in {1..40}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$@" "$label" 2>&1)"; then
            return
        fi
        sleep 0.2
    done
    echo "Menu open logs verification failed: $label did not appear" >&2
    echo "$output" >&2
    exit 1
}

open_logs_from_menu() {
    /usr/bin/osascript >/dev/null <<'APPLESCRIPT'
tell application "System Events"
  tell process "VibelslandFree"
    click menu bar item 1 of menu bar 2
    delay 0.2
    click menu item "打开日志" of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
APPLESCRIPT
}

finder_log_selection() {
    /usr/bin/osascript 2>/dev/null <<'APPLESCRIPT'
tell application "Finder"
  if not (exists window 1) then return ""
  set targetPath to POSIX path of (target of front window as alias)
  set selectionPaths to {}
  repeat with selectedItem in selection
    try
      set end of selectionPaths to POSIX path of (selectedItem as alias)
    end try
  end repeat
  return targetPath & linefeed & selectionPaths
end tell
APPLESCRIPT
}

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"
if ! is_active_process "$APP_PID"; then
    echo "Menu open logs verification failed: app process exited early" >&2
    exit 1
fi

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]
wait_for_window "Initial menu open logs idle" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT"

if [[ ! -f "$LOG" ]] || ! /usr/bin/grep -q 'bridge.start' "$LOG"; then
    echo "Menu open logs verification failed: isolated log is missing bridge.start" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

if ! open_logs_from_menu; then
    echo "Menu open logs verification failed: could not click status bar Open Logs menu item" >&2
    exit 1
fi

EXPECTED_DIR="$TEMP_HOME/Library/Logs/VibelslandFree/"
for _ in {1..50}; do
    FINDER_OUTPUT="$(finder_log_selection || true)"
    if [[ "$FINDER_OUTPUT" == *"$EXPECTED_DIR"* ]]; then
        echo "Menu open logs verification passed"
        exit 0
    fi
    sleep 0.2
done

echo "Menu open logs verification failed: Finder did not open the isolated logs directory" >&2
echo "$FINDER_OUTPUT" >&2
exit 1
