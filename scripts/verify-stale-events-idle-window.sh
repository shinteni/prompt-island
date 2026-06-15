#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
WINDOW_CHECKER="$ROOT/scripts/window-check.swift"
WAIT_SECONDS="${VIBELSLAND_STALE_EVENTS_SECONDS:-5}"
MAX_VISIBLE_WIDTH="${VIBELSLAND_IDLE_VISIBLE_MAX_WIDTH:-900}"
MAX_VISIBLE_HEIGHT="${VIBELSLAND_IDLE_VISIBLE_MAX_HEIGHT:-600}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]
[[ -f "$WINDOW_CHECKER" ]]
. "$ROOT/scripts/visible-test-window-guard.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-stale-home.XXXXXX")"
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
  "enableClaude": true,
  "enableCodexCLI": true,
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
    echo "Stale event verification failed: app process exited early" >&2
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

SMOKE_ID="vibelsland-stale-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"
OLD_TIMESTAMP="$(/bin/date -v-1d +%s)"

send_bridge_event() {
    local source="$1"
    local payload="$2"
    (
        export HOME="$TEMP_HOME"
        printf '%s\n' "$payload" | "$BRIDGE" --source "$source" >/dev/null
    )
}

send_bridge_event claude "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"stale claude prompt\"}"
send_bridge_event claude "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"Stop\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"message\":\"stale claude done\"}"
send_bridge_event codex "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"stale codex prompt\"}"
send_bridge_event codex "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo stale\"}}"

for _ in {1..30}; do
    if [[ -f "$LOG" ]] &&
        /usr/bin/grep -q 'event.ingest claudeCode prompt' "$LOG" &&
        /usr/bin/grep -q 'event.ingest codexCli session' "$LOG"; then
        if /usr/bin/swift "$WINDOW_CHECKER" "$APP_PID" 0 "$MAX_VISIBLE_WIDTH" 0 "$MAX_VISIBLE_HEIGHT" "Stale idle" >/dev/null 2>&1; then
            echo "Stale event verification failed: stale events should not show an idle window" >&2
            exit 1
        fi
        exit 0
    fi
    sleep 0.2
done

echo "Stale event verification failed: events were not ingested while staying idle" >&2
if [[ -f "$LOG" ]]; then
    /usr/bin/tail -80 "$LOG" >&2
fi
exit 1
