#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WINDOW_FRAME="$ROOT/scripts/window-frame.swift"
CLICK_POINT="$ROOT/scripts/click-point.swift"
WAIT_SECONDS="${VIBELSLAND_SESSION_CARD_CLICK_SECONDS:-5}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
[[ -f "$WINDOW_FRAME" ]]
[[ -f "$CLICK_POINT" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-card-click-home.XXXXXX")"
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
    echo "Session card click verification failed: $label did not appear" >&2
    echo "$output" >&2
    [[ -f "$LOG" ]] && /usr/bin/tail -80 "$LOG" >&2
    exit 1
}

post_expanded_state() {
    local expanded="$1"
    /usr/bin/swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"free.vibelsland.verify.setExpanded\"), object: nil, userInfo: [\"expanded\": \"$expanded\"], deliverImmediately: true)"
}

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
    "$EXECUTABLE" >/dev/null 2>&1
) &
APP_PID="$!"

sleep "$WAIT_SECONDS"
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Session card click verification failed: app process exited early" >&2
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

SMOKE_ID="vibelsland-card-click-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"
(
    export HOME="$TEMP_HOME"
    printf '%s\n' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-unknown\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Verify task card click opens session\"}" |
        "$BRIDGE" --source unknown >/dev/null
)

wait_for_window "Task before card click" 180 320 32 70

post_expanded_state true
wait_for_window "Expanded before card click" 500 700 110 380

FRAME="$(
    /usr/bin/swift "$WINDOW_FRAME" "$APP_PID" 500 700 110 380 "Expanded card click"
)"
read -r X Y W H <<< "$FRAME"
CLICK_X="$(/usr/bin/awk -v x="$X" -v w="$W" 'BEGIN { printf "%.0f", x + (w * 0.45) }')"
CLICK_Y="$(/usr/bin/awk -v y="$Y" 'BEGIN { printf "%.0f", y + 72 }')"

/usr/bin/swift "$CLICK_POINT" "$CLICK_X" "$CLICK_Y"

for _ in {1..40}; do
    if [[ -f "$LOG" ]] && /usr/bin/grep -q "session.open.request.*$SMOKE_ID-unknown unknown" "$LOG"; then
        echo "Session card click verification passed"
        exit 0
    fi
    sleep 0.15
done

echo "Session card click verification failed: card click did not trigger session.open.request" >&2
[[ -f "$LOG" ]] && /usr/bin/tail -120 "$LOG" >&2
exit 1
