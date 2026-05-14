#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_MENU_OPEN_PANEL_SECONDS:-5}"
MIN_EXPANDED_WIDTH="${VIBELSLAND_EXPANDED_MIN_WIDTH:-500}"
MAX_EXPANDED_WIDTH="${VIBELSLAND_EXPANDED_MAX_WIDTH:-700}"
MIN_EXPANDED_HEIGHT="${VIBELSLAND_EXPANDED_MIN_HEIGHT:-110}"
MAX_EXPANDED_HEIGHT="${VIBELSLAND_EXPANDED_MAX_HEIGHT:-380}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-menu-open-panel-home.XXXXXX")"
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

wait_for_expanded_window() {
    local label="$1"
    local output=""
    for _ in {1..40}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_EXPANDED_WIDTH" "$MAX_EXPANDED_WIDTH" "$MIN_EXPANDED_HEIGHT" "$MAX_EXPANDED_HEIGHT" "$label" 2>&1)"; then
            return 0
        fi
        sleep 0.2
    done
    echo "Menu open panel verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
}

ensure_hidden_window() {
    local label="$1"
    for _ in {1..20}; do
        if ! /usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 900 0 600 "Hidden check" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    echo "Menu open panel verification failed: $label remained visible" >&2
    exit 1
}

click_menu_open_panel() {
    /usr/bin/osascript >/dev/null <<'APPLESCRIPT'
tell application "System Events"
  tell process "VibelslandFree"
    click menu bar item 1 of menu bar 2
    delay 0.2
    click menu item "打开面板" of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
APPLESCRIPT
}

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Menu open panel verification failed: app process exited early" >&2
    exit 1
fi

ensure_hidden_window "Initial idle island"

if ! click_menu_open_panel; then
    echo "Menu open panel verification failed: could not click status bar Open Panel menu item" >&2
    exit 1
fi

wait_for_expanded_window "Restored by menu open panel"

if [[ -f "$LOG" ]] && /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Menu open panel verification failed: isolated log contains errors" >&2
    /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

echo "Menu open panel restore verification passed"
