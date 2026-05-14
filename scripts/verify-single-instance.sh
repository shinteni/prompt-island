#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WINDOW_ID="$ROOT/scripts/window-id.swift"
MAX_IDLE_WIDTH="${VIBELSLAND_IDLE_MAX_WIDTH:-80}"
MAX_IDLE_HEIGHT="${VIBELSLAND_IDLE_MAX_HEIGHT:-80}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
[[ -f "$WINDOW_ID" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-single-instance-home.XXXXXX")"
APP_PID=""
BASELINE_PIDS=""
BRIDGE="$TEMP_HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$TEMP_HOME/.vibelsland-free/run/vibelsland.sock"

cleanup() {
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        if [[ " $BASELINE_PIDS " == *" $pid "* ]]; then
            continue
        fi
        /bin/kill "$pid" >/dev/null 2>&1 || true
    done < <({ /usr/bin/pgrep -x VibelslandFree 2>/dev/null || true; })
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

visible_processes() {
    { /usr/bin/pgrep -x VibelslandFree 2>/dev/null || true; }
}

tracked_processes() {
    while read -r pid; do
        [[ -z "$pid" ]] && continue
        if [[ " $BASELINE_PIDS " == *" $pid "* ]]; then
            continue
        fi
        print "$pid"
    done < <(visible_processes)
}

visible_process_count() {
    tracked_processes | /usr/bin/wc -l | /usr/bin/tr -d ' '
}

launch_app_bundle() {
    /usr/bin/open --env "VIBELSLAND_HOME=$TEMP_HOME" -n "$APP_DIR"
}

wait_for_first_pid() {
    for _ in {1..80}; do
        while read -r pid; do
            [[ -z "$pid" ]] && continue
            if [[ " $BASELINE_PIDS " == *" $pid "* ]]; then
                continue
            fi
            if is_active_process "$pid"; then
                APP_PID="$pid"
                return
            fi
        done < <(tracked_processes)
        sleep 0.1
    done
    echo "Single-instance verification failed: app bundle launch did not create a process" >&2
    exit 1
}

wait_for_ready() {
    local pid="$1"
    local label="$2"
    for _ in {1..60}; do
        if is_active_process "$pid" && [[ -x "$BRIDGE" && -S "$SOCKET" ]] &&
            /usr/bin/swift "$WINDOW_CHECKER" "$pid" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "$label" >/dev/null 2>&1; then
            return
        fi
        sleep 0.2
    done
    echo "Single-instance verification failed: $label did not become ready" >&2
    exit 1
}

BASELINE_PIDS="$(visible_processes | /usr/bin/xargs || true)"
launch_app_bundle
wait_for_first_pid
wait_for_ready "$APP_PID" "Initial single-instance app"
FIRST_WINDOW_ID="$(/usr/bin/swift "$WINDOW_ID" "$APP_PID" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "Initial single-instance app")"

launch_app_bundle
RETURNED_TO_ONE=0
for _ in {1..80}; do
    if [[ "$(visible_process_count)" == "1" ]]; then
        RETURNED_TO_ONE=1
        break
    fi
    sleep 0.05
done

if [[ "$RETURNED_TO_ONE" != "1" ]]; then
    echo "Single-instance verification failed: second app-bundle launch did not hand off and exit" >&2
    /usr/bin/pgrep -fl VibelslandFree >&2 || true
    exit 1
fi

if ! is_active_process "$APP_PID"; then
    echo "Single-instance verification failed: first app exited after second launch" >&2
    exit 1
fi

PROCESS_COUNT="$(visible_process_count)"
if [[ "$PROCESS_COUNT" != "1" ]]; then
    echo "Single-instance verification failed: expected one VibelslandFree process, got $PROCESS_COUNT" >&2
    /usr/bin/pgrep -fl VibelslandFree >&2 || true
    exit 1
fi

wait_for_ready "$APP_PID" "Single-instance survivor"
SECOND_WINDOW_ID="$(/usr/bin/swift "$WINDOW_ID" "$APP_PID" 0 "$MAX_IDLE_WIDTH" 0 "$MAX_IDLE_HEIGHT" "Single-instance survivor")"
if [[ "$SECOND_WINDOW_ID" != "$FIRST_WINDOW_ID" ]]; then
    echo "Single-instance verification failed: second launch replaced the survivor window instead of reusing it" >&2
    exit 1
fi

echo "Single-instance verification passed: survivor pid=$APP_PID via app bundle launch"
