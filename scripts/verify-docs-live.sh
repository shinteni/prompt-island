#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"
SITE_URL="${SITE_URL%/}/"
RELEASE_BASE="${VIBELSLAND_RELEASE_BASE:-https://github.com/shinteni/prompt-island/releases/download/v0.1.0}"
ARCHIVE="Vibelsland-Free-0.1.0-macos.zip"
CHECKSUM="$ARCHIVE.sha256"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fetch_status() {
  local url="$1"
  local output="$2"
  /usr/bin/curl -L -s -o "$output" -w "%{http_code}" "$url"
}

require_status() {
  local url="$1"
  local output="$2"
  local http_status
  http_status="$(fetch_status "$url" "$output")"
  if [[ "$http_status" != "200" ]]; then
    echo "Live check failed: $url returned $http_status" >&2
    return 1
  fi
}

pages=(
  ""
  "download.html"
  "install.html"
  "release-notes.html"
  "support.html"
  "en/support.html"
  "ja/support.html"
  ".well-known/security.txt"
  "sitemap.xml"
  "site.webmanifest"
)

for page in "${pages[@]}"; do
  safe_name="${page//\//_}"
  [[ -z "$safe_name" ]] && safe_name="index.html"
  require_status "${SITE_URL}${page}" "$TMP_DIR/$safe_name"
done

if ! grep -q "styles.css?v=" "$TMP_DIR/support.html"; then
  echo "Live check failed: support.html is missing versioned stylesheet." >&2
  exit 1
fi
if ! grep -q "effects.js?v=" "$TMP_DIR/support.html"; then
  echo "Live check failed: support.html is missing versioned effects script." >&2
  exit 1
fi
if ! grep -q "security.txt" "$TMP_DIR/support.html"; then
  echo "Live check failed: support.html is missing security.txt link." >&2
  exit 1
fi

require_status "$RELEASE_BASE/$CHECKSUM" "$TMP_DIR/$CHECKSUM"
local_checksum_path="$ROOT/dist/$CHECKSUM"
if [[ -f "$local_checksum_path" ]]; then
  local_hash="$(awk '{print $1}' "$local_checksum_path")"
  live_hash="$(awk '{print $1}' "$TMP_DIR/$CHECKSUM")"
  if [[ "$local_hash" != "$live_hash" ]]; then
    echo "Live check failed: release checksum mismatch." >&2
    echo "local: $local_hash" >&2
    echo "live:  $live_hash" >&2
    exit 1
  fi
fi

echo "Live docs verification passed for $SITE_URL"
