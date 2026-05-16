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
namespace = {
    "sm": "http://www.sitemaps.org/schemas/sitemap/0.9",
    "xhtml": "http://www.w3.org/1999/xhtml",
}

localized_files = [
    "index.html",
    "advantages.html",
    "download.html",
    "install.html",
    "privacy.html",
    "faq.html",
    "support.html",
    "release-notes.html",
]

def page_url(language, filename):
    if filename == "index.html":
        if language == "zh-CN":
            return site_url
        return f"{site_url}{language}/"
    if language == "zh-CN":
        return f"{site_url}{filename}"
    return f"{site_url}{language}/{filename}"

expected_url_alternates = {}
for filename in localized_files:
    expected = {
        "zh-CN": page_url("zh-CN", filename),
        "en": page_url("en", filename),
        "ja": page_url("ja", filename),
        "x-default": page_url("zh-CN", filename),
    }
    for url in expected.values():
        expected_url_alternates[url] = expected

tree = ET.parse(sitemap_path)
url_nodes = tree.findall(".//sm:url", namespace)
locs = [node.findtext("sm:loc", default="", namespaces=namespace) for node in url_nodes]
if not locs:
    raise SystemExit("Live check failed: sitemap has no loc entries.")
for url_node, loc in zip(url_nodes, locs):
    if not loc.startswith(site_url):
        raise SystemExit(f"Live check failed: sitemap loc does not start with {site_url}: {loc}")
    expected = expected_url_alternates.get(loc)
    if not expected:
        raise SystemExit(f"Live check failed: unexpected sitemap loc: {loc}")
    actual = {}
    for link in url_node.findall("xhtml:link", namespace):
        if link.attrib.get("rel") == "alternate" and link.attrib.get("hreflang"):
            actual[link.attrib["hreflang"]] = link.attrib.get("href", "")
    for hreflang, expected_href in expected.items():
        if actual.get(hreflang) != expected_href:
            raise SystemExit(f"Live check failed: sitemap hreflang {hreflang} mismatch for {loc}: {actual.get(hreflang)}")
    extra = sorted(set(actual) - set(expected))
    if extra:
        raise SystemExit(f"Live check failed: sitemap has extra hreflang values for {loc}: {', '.join(extra)}")
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
localized_files = [
    "index.html",
    "advantages.html",
    "download.html",
    "install.html",
    "privacy.html",
    "faq.html",
    "support.html",
    "release-notes.html",
]

def filename_for_url(url):
    if url == site_url or url in {site_url + "en/", site_url + "ja/"}:
        return "index.html"
    return url.rstrip("/").rsplit("/", 1)[-1]

def page_url(language, filename):
    if filename == "index.html":
        if language == "zh-CN":
            return site_url
        return f"{site_url}{language}/"
    if language == "zh-CN":
        return f"{site_url}{filename}"
    return f"{site_url}{language}/{filename}"

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
    filename = filename_for_url(url)
    if filename not in localized_files:
        raise SystemExit(f"Live check failed: unexpected localized page in sitemap: {url}")
    expected_alternates = {
        "zh-CN": page_url("zh-CN", filename),
        "en": page_url("en", filename),
        "ja": page_url("ja", filename),
        "x-default": page_url("zh-CN", filename),
    }
    for hreflang, expected_href in expected_alternates.items():
        actual_href = parser.alternates.get(hreflang)
        if actual_href != expected_href:
            raise SystemExit(f"Live check failed: hreflang {hreflang} mismatch for {url}: {actual_href}")
    extra = sorted(set(parser.alternates) - set(expected_alternates))
    if extra:
        raise SystemExit(f"Live check failed: extra hreflang values for {url}: {', '.join(extra)}")
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
