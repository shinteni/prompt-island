#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
LOG="$HOME/Library/Logs/VibelslandFree/app.log"
BRIDGE="$HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$HOME/.vibelsland-free/run/vibelsland.sock"
SMOKE_ID="vibelsland-smoke-$(/bin/date +%s)-$$"
SMOKE_WORKSPACE="${TMPDIR:-/tmp}/$SMOKE_ID"
OLD_TIMESTAMP=1

[[ -d "$APP_DIR" ]]

if ! /usr/bin/pgrep -x VibelslandFree >/dev/null 2>&1; then
    /usr/bin/open "$APP_DIR"
fi

for _ in {1..60}; do
    if [[ -x "$BRIDGE" && -S "$SOCKET" ]]; then
        break
    fi
    sleep 0.2
done

[[ -x "$BRIDGE" ]]
[[ -S "$SOCKET" ]]

if [[ -f "$LOG" ]]; then
    LOG_START_LINES="$(/usr/bin/wc -l < "$LOG" | tr -d ' ')"
else
    LOG_START_LINES=0
fi

RECENT_LOG="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vibelsland-bridge-log.XXXXXX")"
trap 'rm -f "$RECENT_LOG"' EXIT

send_bridge_event() {
    local source="$1"
    local payload="$2"
    printf '%s\n' "$payload" | "$BRIDGE" --source "$source" >/dev/null
}

refresh_recent_log() {
    if [[ -f "$LOG" ]]; then
        /usr/bin/tail -n +"$((LOG_START_LINES + 1))" "$LOG" > "$RECENT_LOG"
    else
        : > "$RECENT_LOG"
    fi
}

wait_for_log() {
    local pattern="$1"
    for _ in {1..40}; do
        refresh_recent_log
        if /usr/bin/grep -q "$pattern" "$RECENT_LOG"; then
            return 0
        fi
        sleep 0.15
    done
    echo "Bridge event verification failed: missing log pattern: $pattern" >&2
    /usr/bin/tail -40 "$RECENT_LOG" >&2
    return 1
}

send_bridge_event claude "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"prompt\":\"Vibelsland bridge smoke prompt\"}"
send_bridge_event codex "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SMOKE_ID-codex\",\"thread_id\":\"$SMOKE_ID-thread\",\"cwd\":\"$SMOKE_WORKSPACE\",\"codex_session_start_source\":\"codex_desktop_subagent\"}"
send_bridge_event claude "{\"timestamp\":$OLD_TIMESTAMP,\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$SMOKE_ID-claude\",\"cwd\":\"$SMOKE_WORKSPACE\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo vibelsland-smoke\"}}"

wait_for_log 'event.ingest claudeCode prompt'
wait_for_log 'event.ingest codexCli session'
wait_for_log 'event.ingest claudeCode tool'

refresh_recent_log
if /usr/bin/grep -E '\[error\]|bridge\.parse\.failed|bridge\.token\.rejected' "$RECENT_LOG" >/dev/null; then
    echo "Bridge event verification failed: recent app log contains errors" >&2
    /usr/bin/tail -40 "$RECENT_LOG" >&2
    exit 1
fi

echo "Bridge event verification passed: $SMOKE_ID"
