#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
MIN_PANEL_WIDTH="${VIBELSLAND_PANEL_MIN_WIDTH:-120}"
MAX_PANEL_WIDTH="${VIBELSLAND_PANEL_MAX_WIDTH:-900}"
MIN_PANEL_HEIGHT="${VIBELSLAND_PANEL_MIN_HEIGHT:-80}"
MAX_PANEL_HEIGHT="${VIBELSLAND_PANEL_MAX_HEIGHT:-700}"
MAX_HIDDEN_WIDTH="${VIBELSLAND_IDLE_VISIBLE_MAX_WIDTH:-900}"
MAX_HIDDEN_HEIGHT="${VIBELSLAND_IDLE_VISIBLE_MAX_HEIGHT:-700}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-single-instance-home.XXXXXX")"
APP_PID=""
BASELINE_PIDS=""
BRIDGE="$(vibelsland_bridge_path "$TEMP_HOME")"
SOCKET="$(vibelsland_socket_path "$TEMP_HOME")"

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

wait_for_runtime_ready() {
    local pid="$1"
    local label="$2"
    for _ in {1..60}; do
        if is_active_process "$pid" && [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
            return
        fi
        sleep 0.2
    done
    echo "Single-instance verification failed: $label did not create bridge runtime" >&2
    exit 1
}

assert_idle_hidden() {
    local pid="$1"
    if /usr/bin/swift "$WINDOW_CHECKER" "$pid" 0 "$MAX_HIDDEN_WIDTH" 0 "$MAX_HIDDEN_HEIGHT" "Initial idle hidden" >/dev/null 2>&1; then
        echo "Single-instance verification failed: initial idle launch should stay hidden" >&2
        exit 1
    fi
}

wait_for_panel_visible() {
    local pid="$1"
    for _ in {1..60}; do
        if is_active_process "$pid" &&
            /usr/bin/swift "$WINDOW_CHECKER" "$pid" "$MIN_PANEL_WIDTH" "$MAX_PANEL_WIDTH" "$MIN_PANEL_HEIGHT" "$MAX_PANEL_HEIGHT" "Single-instance survivor panel" >/dev/null 2>&1; then
            return
        fi
        sleep 0.2
    done
    echo "Single-instance verification failed: second launch did not open the survivor panel" >&2
    /usr/bin/swift "$WINDOW_CHECKER" "$pid" 0 "$MAX_HIDDEN_WIDTH" 0 "$MAX_HIDDEN_HEIGHT" "Single-instance survivor windows" >&2 || true
    exit 1
}

BASELINE_PIDS="$(visible_processes | /usr/bin/xargs || true)"
launch_app_bundle
wait_for_first_pid
wait_for_runtime_ready "$APP_PID" "Initial single-instance app"
assert_idle_hidden "$APP_PID"

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

wait_for_runtime_ready "$APP_PID" "Single-instance survivor"
wait_for_panel_visible "$APP_PID"

echo "Single-instance verification passed: survivor pid=$APP_PID via app bundle launch"
