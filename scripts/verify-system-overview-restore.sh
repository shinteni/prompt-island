#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_SYSTEM_OVERVIEW_SECONDS:-5}"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-overview-home.XXXXXX")"
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

/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "Initial idle" >/dev/null

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
        if output="$(/usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "Restored idle" 2>&1)"; then
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
