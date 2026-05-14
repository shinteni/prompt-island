#!/bin/zsh

# Source this before launching an isolated, visible VibelslandFree instance.
if [[ "${VIBELSLAND_ALLOW_VISIBLE_TEST_WINDOWS:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

EXISTING_PIDS="$(/usr/bin/pgrep -x VibelslandFree 2>/dev/null | /usr/bin/xargs || true)"
if [[ -n "$EXISTING_PIDS" ]]; then
    echo "This verification launches a visible isolated Vibelsland Free window." >&2
    echo "Existing VibelslandFree process(es) are already running: $EXISTING_PIDS" >&2
    echo "Quit the app first, or set VIBELSLAND_ALLOW_VISIBLE_TEST_WINDOWS=1 if a temporary duplicate UI is intentional." >&2
    exit 3
fi

return 0 2>/dev/null || exit 0
