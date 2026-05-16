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
  "llms.txt"
  "sitemap.xml"
  "site.webmanifest"
)

for page in "${pages[@]}"; do
  safe_name="${page//\//_}"
  [[ -z "$safe_name" ]] && safe_name="index.html"
  require_status "${SITE_URL}${page}" "$TMP_DIR/$safe_name"
done

python3 - "$TMP_DIR/sitemap.xml" "$SITE_URL" > "$TMP_DIR/sitemap-urls.txt" <<'PY'
import sys
from xml.etree import ElementTree as ET

sitemap_path = sys.argv[1]
site_url = sys.argv[2]
namespace = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}
tree = ET.parse(sitemap_path)
locs = [node.text or "" for node in tree.findall(".//sm:loc", namespace)]
if not locs:
    raise SystemExit("Live check failed: sitemap has no loc entries.")
for loc in locs:
    if not loc.startswith(site_url):
        raise SystemExit(f"Live check failed: sitemap loc does not start with {site_url}: {loc}")
    print(loc)
PY

sitemap_index=0
while IFS= read -r sitemap_url; do
  sitemap_index=$((sitemap_index + 1))
  require_status "$sitemap_url" "$TMP_DIR/sitemap-page-$sitemap_index.html"
done < "$TMP_DIR/sitemap-urls.txt"

python3 - "$TMP_DIR" "$SITE_URL" <<'PY'
import sys
from html.parser import HTMLParser
from pathlib import Path

tmp_dir = Path(sys.argv[1])
site_url = sys.argv[2]

class HeadParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.canonical = ""
        self.og_url = ""
        self.og_site_name = ""
        self.og_locale = ""
        self.alternates = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href", "")
        elif tag == "link" and attrs.get("rel") == "alternate" and attrs.get("hreflang"):
            self.alternates[attrs["hreflang"]] = attrs.get("href", "")
        elif tag == "meta":
            key = attrs.get("property") or attrs.get("name") or ""
            if key == "og:url":
                self.og_url = attrs.get("content", "")
            elif key == "og:site_name":
                self.og_site_name = attrs.get("content", "")
            elif key == "og:locale":
                self.og_locale = attrs.get("content", "")

urls = [line.strip() for line in (tmp_dir / "sitemap-urls.txt").read_text(encoding="utf-8").splitlines() if line.strip()]
for index, url in enumerate(urls, start=1):
    text = (tmp_dir / f"sitemap-page-{index}.html").read_text(encoding="utf-8")
    parser = HeadParser()
    parser.feed(text)
    expected_locale = "zh_CN"
    if url.startswith(site_url + "en/"):
        expected_locale = "en_US"
    elif url.startswith(site_url + "ja/"):
        expected_locale = "ja_JP"
    if parser.canonical != url:
        raise SystemExit(f"Live check failed: canonical mismatch for {url}: {parser.canonical}")
    if parser.og_url != url:
        raise SystemExit(f"Live check failed: og:url mismatch for {url}: {parser.og_url}")
    if parser.og_site_name != "Vibelsland Free":
        raise SystemExit(f"Live check failed: og:site_name missing for {url}")
    if parser.og_locale != expected_locale:
        raise SystemExit(f"Live check failed: og:locale mismatch for {url}: {parser.og_locale}")
    for hreflang in ["zh-CN", "en", "ja", "x-default"]:
        if hreflang not in parser.alternates:
            raise SystemExit(f"Live check failed: hreflang {hreflang} missing for {url}")
PY

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
require_status "$RELEASE_BASE/$ARCHIVE" "$TMP_DIR/$ARCHIVE"
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
(
  cd "$TMP_DIR"
  /usr/bin/shasum -a 256 -c "$CHECKSUM" >/dev/null
)

echo "Live docs verification passed for $SITE_URL"
