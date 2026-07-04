#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
ARCHIVE="$ROOT/dist/$(python3 -c "import json;print(json.load(open('$ROOT/docs/release.json'))['archive']['name'])")"
CHECKSUM="$ARCHIVE.sha256"
CHECKLIST="$ROOT/MAINTAINER_RELEASE_CHECKLIST.md"

MODE="${VIBELSLAND_RELEASE_MODE:-github}"
RUN_AUTOMATION=1
ALLOW_PENDING=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: zsh scripts/verify-release-readiness.sh [--local|--github|--notarized] [--no-run] [--allow-pending-manual]

Modes:
  --local      Verify the local dist package against docs/release.json.
  --github     Verify the GitHub Release, website metadata, and local dist package all describe the same public artifact.
  --notarized  Same as --github, and require non-ad-hoc distribution signing.

The release package, docs/release.json, download pages, and GitHub Release assets must stay in lockstep. For an unpublished candidate, run package-release.sh, upload the matching Release assets, update metadata, then run this readiness gate.
EOF
            exit 0
            ;;
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

require_path() {
    local path="$1"
    local label="$2"
    if [[ -e "$path" ]]; then
        return
    fi
    echo "Release readiness missing $label: $path" >&2
    if [[ "$RUN_AUTOMATION" == "0" ]]; then
        echo "Run without --no-run to rebuild local verification artifacts, or restore the matching public Release assets into dist/ before checking $MODE mode." >&2
    fi
    exit 1
}

restore_public_release_assets() {
    local metadata
    metadata=("${(@f)$(python3 - "$ROOT/docs/release.json" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(metadata["archive"]["name"])
print(metadata["archive"]["download_url"])
print(metadata["checksum_file"]["name"])
print(metadata["checksum_file"]["download_url"])
PY
)}")
    local archive_name="$metadata[1]"
    local archive_url="$metadata[2]"
    local checksum_name="$metadata[3]"
    local checksum_url="$metadata[4]"

    /bin/mkdir -p "$ROOT/dist"
    /usr/bin/curl -L -sS -o "$ROOT/dist/$archive_name" "$archive_url"
    /usr/bin/curl -L -sS -o "$ROOT/dist/$checksum_name" "$checksum_url"
}

if [[ "$RUN_AUTOMATION" == "1" ]]; then
    . "$ROOT/scripts/verify-support.sh"
    if [[ "$MODE" == "local" ]]; then
        zsh "$ROOT/scripts/package-release.sh"
    else
        zsh "$ROOT/scripts/verify-app.sh"
        restore_public_release_assets
    fi
    VIBELSLAND_VERIFY_DIST=1 zsh "$ROOT/scripts/verify-docs-site.sh"
    zsh "$ROOT/scripts/verify-cask.sh"
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

require_path "$APP_DIR" "app bundle"
require_path "$ARCHIVE" "release archive"
require_path "$CHECKSUM" "release checksum"
if ! (
    cd "$ROOT/dist"
    /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM")" >/dev/null
); then
    echo "Release readiness checksum validation failed: $CHECKSUM" >&2
    exit 1
fi

VIBELSLAND_VERIFY_DIST=1 zsh "$ROOT/scripts/verify-docs-site.sh"
VIBELSLAND_VERIFY_DIST=1 zsh "$ROOT/scripts/verify-docs-live.sh"

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
