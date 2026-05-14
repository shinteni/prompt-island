#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibelsland Free.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/VibelslandFree"
LOG="$HOME/Library/Logs/VibelslandFree/app.log"
BRIDGE="$HOME/.vibelsland-free/bin/vibelsland-bridge"
SOCKET="$HOME/.vibelsland-free/run/vibelsland.sock"
RUNTIME_SECONDS="${VIBELSLAND_RUNTIME_SECONDS:-25}"
CPU_MAX="${VIBELSLAND_CPU_MAX:-8.0}"
RSS_MAX_KB="${VIBELSLAND_RSS_MAX_KB:-300000}"
SHOULD_RESTART="${VIBELSLAND_RUNTIME_RESTART:-1}"

[[ -d "$APP_DIR" ]]
[[ -x "$EXECUTABLE" ]]

if [[ -f "$LOG" ]]; then
    LOG_START_LINES="$(/usr/bin/wc -l < "$LOG" | tr -d ' ')"
else
    LOG_START_LINES=0
fi

if [[ "$SHOULD_RESTART" != "0" ]]; then
    /usr/bin/pkill -x VibelslandFree >/dev/null 2>&1 || true
    sleep 0.4
    EXPECT_BRIDGE_START=1
else
    EXPECT_BRIDGE_START=0
fi

/usr/bin/open "$APP_DIR"
sleep "$RUNTIME_SECONDS"

PID="$(/usr/bin/pgrep -x VibelslandFree | head -1)"
[[ -n "$PID" ]]

CPU="$(/bin/ps -o %cpu= -p "$PID" | tr -d ' ')"
[[ -n "$CPU" ]]
/usr/bin/awk -v cpu="$CPU" -v max="$CPU_MAX" 'BEGIN { exit !((cpu + 0) <= (max + 0)) }'

RSS_KB="$(/bin/ps -o rss= -p "$PID" | tr -d ' ')"
[[ -n "$RSS_KB" ]]
/usr/bin/awk -v rss="$RSS_KB" -v max="$RSS_MAX_KB" 'BEGIN { exit !((rss + 0) <= (max + 0)) }'

[[ -x "$BRIDGE" ]]
/usr/bin/grep -q '"thread_id"' "$BRIDGE"
/usr/bin/grep -q '"threadId"' "$BRIDGE"
/usr/bin/grep -q '"codex_session_start_source"' "$BRIDGE"
[[ -S "$SOCKET" ]]
SOCKET_MODE="$(/usr/bin/stat -f "%Lp" "$SOCKET")"
[[ "$SOCKET_MODE" == "600" ]]
SOCKET_OWNER="$(/usr/bin/stat -f "%u" "$SOCKET")"
[[ "$SOCKET_OWNER" == "$(/usr/bin/id -u)" ]]

RECENT_LOG="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vibelsland-runtime-log.XXXXXX")"
trap 'rm -f "$RECENT_LOG"' EXIT

if [[ -f "$LOG" ]]; then
    /usr/bin/tail -n +"$((LOG_START_LINES + 1))" "$LOG" > "$RECENT_LOG"
fi

if [[ "$EXPECT_BRIDGE_START" == "1" ]]; then
    /usr/bin/grep -q 'bridge.start' "$RECENT_LOG"
fi
if /usr/bin/grep -E '\[error\]|codex\.sqlite\.read\.failed' "$RECENT_LOG" >/dev/null; then
    echo "Runtime verification failed: recent app log contains errors" >&2
    /usr/bin/tail -40 "$RECENT_LOG" >&2
    exit 1
fi

echo "Runtime verification passed: pid=$PID cpu=$CPU% rss=${RSS_KB}KB"
