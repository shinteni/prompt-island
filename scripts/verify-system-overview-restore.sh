#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_SYSTEM_OVERVIEW_SECONDS:-5}"
MIN_EXPANDED_WIDTH="${VIBELSLAND_EXPANDED_MIN_WIDTH:-500}"
MAX_EXPANDED_WIDTH="${VIBELSLAND_EXPANDED_MAX_WIDTH:-700}"
MIN_EXPANDED_HEIGHT="${VIBELSLAND_EXPANDED_MIN_HEIGHT:-110}"
MAX_EXPANDED_HEIGHT="${VIBELSLAND_EXPANDED_MAX_HEIGHT:-380}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-overview-home.XXXXXX")"
APP_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"

cleanup() {
    vibelsland_cleanup_temp_home "$TEMP_HOME" "$APP_PID"
}
trap cleanup EXIT

vibelsland_write_test_config "$TEMP_HOME" \
    enableClaude=false \
    enableCodexCLI=false \
    enableCodexDesktop=false \
    enableSounds=false \
    soundTheme=soft \
    doNotDisturb=true \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

wait_for_expanded_window() {
    local label="$1"
    local output=""
    for _ in {1..40}; do
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_EXPANDED_WIDTH" "$MAX_EXPANDED_WIDTH" "$MIN_EXPANDED_HEIGHT" "$MAX_EXPANDED_HEIGHT" "$label" 2>&1)"; then
            return 0
        fi
        sleep 0.2
    done
    echo "System overview restore verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
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
    echo "System overview restore verification failed: app process exited early" >&2
    exit 1
fi

if ! click_menu_open_panel; then
    echo "System overview restore verification failed: could not click status bar Open Panel menu item" >&2
    exit 1
fi

wait_for_expanded_window "Initial overview panel"

/usr/bin/swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.apple.expose.awake"), object: nil, userInfo: nil, deliverImmediately: true)'

hidden_seen=0
restored_seen=0
output=""
for _ in {1..45}; do
    if [[ -f "$LOG" ]] && /usr/bin/grep -q 'island.system-overview.hidden' "$LOG"; then
        hidden_seen=1
    fi
    if [[ "$hidden_seen" == "1" ]] && [[ -f "$LOG" ]] && /usr/bin/grep -q 'island.system-overview.restored' "$LOG"; then
        restored_seen=1
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" "$MIN_EXPANDED_WIDTH" "$MAX_EXPANDED_WIDTH" "$MIN_EXPANDED_HEIGHT" "$MAX_EXPANDED_HEIGHT" "Restored overview panel" 2>&1)"; then
            echo "$output"
            exit 0
        fi
    fi
    sleep 0.2
done

echo "System overview restore verification failed: hidden_seen=$hidden_seen restored_seen=$restored_seen" >&2
echo "$output" >&2
if [[ -f "$LOG" ]]; then
    /usr/bin/tail -80 "$LOG" >&2
fi
exit 1
