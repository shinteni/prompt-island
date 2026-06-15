#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_IDLE_WINDOW_SECONDS:-5}"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"
MAX_VISIBLE_WIDTH="${VIBELSLAND_IDLE_VISIBLE_MAX_WIDTH:-900}"
MAX_VISIBLE_HEIGHT="${VIBELSLAND_IDLE_VISIBLE_MAX_HEIGHT:-600}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-idle-home.XXXXXX")"
APP_PID=""
LOG="$(vibelsland_log_path "$TEMP_HOME")"
BRIDGE="$(vibelsland_bridge_path "$TEMP_HOME")"
SOCKET="$(vibelsland_socket_path "$TEMP_HOME")"

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

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"

if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Idle window verification failed: app process exited early" >&2
    exit 1
fi

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]
SOCKET_MODE="$(/usr/bin/stat -f "%Lp" "$SOCKET")"
[[ "$SOCKET_MODE" == "600" ]]
SOCKET_OWNER="$(/usr/bin/stat -f "%u" "$SOCKET")"
[[ "$SOCKET_OWNER" == "$(/usr/bin/id -u)" ]]

if [[ ! -f "$LOG" ]] || ! /usr/bin/grep -q 'bridge.start' "$LOG"; then
    echo "Idle window verification failed: isolated cold start log is missing bridge.start" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

if /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$LOG" >/dev/null; then
    echo "Idle window verification failed: isolated cold start log contains errors" >&2
    /usr/bin/tail -80 "$LOG" >&2
    exit 1
fi

if /usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_VISIBLE_WIDTH" 0 "$MAX_VISIBLE_HEIGHT" "Idle hidden" >/dev/null 2>&1; then
    echo "Idle window verification failed: idle island should be hidden" >&2
    exit 1
fi

if /usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "Idle mini" >/dev/null 2>&1; then
    echo "Idle window verification failed: small idle circle is visible" >&2
    exit 1
fi

echo "Idle window verification passed"
