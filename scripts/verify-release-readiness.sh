#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
ARCHIVE="$ROOT/dist/Vibelsland-Free-0.1.0-macos.zip"
CHECKSUM="$ARCHIVE.sha256"
CHECKLIST="$ROOT/RELEASE_CHECKLIST.md"

MODE="${VIBELSLAND_RELEASE_MODE:-github}"
RUN_AUTOMATION=1
ALLOW_PENDING=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            MODE="local"
            shift
            ;;
        --public)
            MODE="github"
            shift
            ;;
        --github)
            MODE="github"
            shift
            ;;
        --notarized)
            MODE="notarized"
            shift
            ;;
        --no-run)
            RUN_AUTOMATION=0
            shift
            ;;
        --allow-pending-manual)
            ALLOW_PENDING=1
            shift
            ;;
        --allow-visible-test-windows)
            export VIBELSLAND_ALLOW_VISIBLE_TEST_WINDOWS=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 64
            ;;
    esac
done

case "$MODE" in
    local|github|notarized) ;;
    *)
        echo "VIBELSLAND_RELEASE_MODE must be local, github, or notarized" >&2
        exit 64
        ;;
esac

if [[ "$RUN_AUTOMATION" == "1" ]]; then
    . "$ROOT/scripts/visible-test-window-guard.sh"
    zsh "$ROOT/scripts/package-release.sh"
    zsh "$ROOT/scripts/verify-idle-window.sh"
    zsh "$ROOT/scripts/verify-single-instance.sh"
    zsh "$ROOT/scripts/verify-menu-settings.sh"
    zsh "$ROOT/scripts/verify-menu-open-logs.sh"
    zsh "$ROOT/scripts/verify-restart-recovery.sh"
    zsh "$ROOT/scripts/verify-app-internal-restart.sh"
    zsh "$ROOT/scripts/verify-menu-restart.sh"
    zsh "$ROOT/scripts/verify-system-overview-restore.sh"
    zsh "$ROOT/scripts/verify-menu-open-panel-restore.sh"
    zsh "$ROOT/scripts/verify-stale-events-idle-window.sh"
    zsh "$ROOT/scripts/verify-long-task-window.sh"
    zsh "$ROOT/scripts/verify-expand-collapse-visibility.sh"
    zsh "$ROOT/scripts/verify-visual-snapshots.sh"
    zsh "$ROOT/scripts/verify-session-card-click.sh"
    zsh "$ROOT/scripts/verify-approval-window.sh"
    zsh "$ROOT/scripts/verify-approval-response.sh"
    zsh "$ROOT/scripts/verify-codex-cli-approval-response.sh"
    zsh "$ROOT/scripts/verify-codex-desktop-approval-response.sh"
    zsh "$ROOT/scripts/verify-approval-timeout.sh"
    zsh "$ROOT/scripts/verify-runtime.sh"
    zsh "$ROOT/scripts/verify-bridge-events.sh"
fi

[[ -d "$APP_DIR" ]]
[[ -f "$ARCHIVE" ]]
[[ -f "$CHECKSUM" ]]
(
    cd "$ROOT/dist"
    /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM")" >/dev/null
)

zsh "$ROOT/scripts/verify-docs-site.sh"
zsh "$ROOT/scripts/verify-docs-live.sh"

SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
SIGNING_BLOCKER=""
if [[ "$MODE" == "notarized" && "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]; then
    SIGNING_BLOCKER="- [ ] Notarized 分发签名：当前仍是 ad-hoc；若走 Developer ID/notarization 分发线，必须完成正式签名、notarization 和下载后首次启动验证。"
elif [[ "$MODE" == "local" && "$SIGNATURE_INFO" != *"Signature=adhoc"* ]]; then
    SIGNING_BLOCKER="- [ ] 本机构建签名：当前不再是 ad-hoc，请确认打包脚本是否被改成正式分发模式。"
fi

PENDING_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vibelsland-release-pending.XXXXXX")"
trap 'rm -f "$PENDING_FILE"' EXIT

pending_section() {
    local section="$1"
    /usr/bin/awk -v section="$section" '
        $0 == "## " section { inside = 1; next }
        inside && /^## / { inside = 0 }
        inside && /^- \[ \]/ { print }
    ' "$CHECKLIST"
}

{
    pending_section "人工回归"
    pending_section "发布阻塞"
} > "$PENDING_FILE"

if [[ "$MODE" == "local" ]]; then
    /usr/bin/sed -i '' '/若不是本机自用/d' "$PENDING_FILE"
    /usr/bin/sed -i '' '/若走 notarized/d' "$PENDING_FILE"
elif [[ "$MODE" == "github" ]]; then
    /usr/bin/sed -i '' '/若走 notarized/d' "$PENDING_FILE"
fi

if [[ -n "$SIGNING_BLOCKER" ]]; then
    printf '%s\n' "$SIGNING_BLOCKER" >> "$PENDING_FILE"
fi

if [[ -s "$PENDING_FILE" ]]; then
    echo "Release readiness blocked for $MODE mode:"
    /bin/cat "$PENDING_FILE"
    if [[ "$ALLOW_PENDING" == "1" ]]; then
        echo "Pending manual items acknowledged."
        exit 0
    fi
    exit 2
fi

echo "Release readiness passed for $MODE mode."
