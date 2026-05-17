#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"
SITE_URL="${SITE_URL%/}/"
VERIFY_DIST="${VIBELSLAND_VERIFY_DIST:-0}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fetch_status() {
  local url="$1"
  local output="$2"
  local curl_args=(-L -s -o "$output" -w "%{http_code}")
  if [[ -n "${GITHUB_TOKEN:-}" && "$url" == https://api.github.com/* ]]; then
    curl_args=(-L -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" -o "$output" -w "%{http_code}")
  fi
  /usr/bin/curl "${curl_args[@]}" "$url"
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
  "404.html"
  "download.html"
  "install.html"
  "release-notes.html"
  "support.html"
  "en/support.html"
  "ja/support.html"
  ".well-known/security.txt"
  "llms.txt"
  "release.json"
  "sitemap.xml"
  "site.webmanifest"
)

for page in "${pages[@]}"; do
  safe_name="${page//\//_}"
  [[ -z "$safe_name" ]] && safe_name="index.html"
  require_status "${SITE_URL}${page}" "$TMP_DIR/$safe_name"
done

missing_pages=(
  "not-found-${RANDOM}.html"
  "en/not-found-${RANDOM}.html"
  "ja/not-found-${RANDOM}.html"
)
for missing_page in "${missing_pages[@]}"; do
  safe_missing_name="not-found-${missing_page//\//_}"
  missing_status="$(fetch_status "${SITE_URL}${missing_page}" "$TMP_DIR/$safe_missing_name")"
  if [[ "$missing_status" != "404" ]]; then
    echo "Live check failed: missing URL should return 404, got $missing_status for $missing_page" >&2
    exit 1
  fi
  if ! grep -q 'data-page="404"' "$TMP_DIR/$safe_missing_name"; then
    echo "Live check failed: missing URL did not serve the site 404 page: $missing_page" >&2
    exit 1
  fi
  if ! grep -q "Page not found" "$TMP_DIR/$safe_missing_name" || ! grep -q "ページが見つかりません" "$TMP_DIR/$safe_missing_name"; then
    echo "Live check failed: 404 static fallback is not multilingual for $missing_page" >&2
    exit 1
  fi
  if ! grep -q "styles.css?v=" "$TMP_DIR/$safe_missing_name" || ! grep -q "lang.js?v=" "$TMP_DIR/$safe_missing_name"; then
    echo "Live check failed: 404 page is missing versioned assets for $missing_page" >&2
    exit 1
  fi
done

python3 - "$TMP_DIR/release.json" > "$TMP_DIR/release-vars.txt" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = [
    ("version", metadata.get("version")),
    ("tag", metadata.get("tag")),
    ("release_url", metadata.get("release_url")),
    ("release_api_url", metadata.get("release_api_url")),
    ("repository", metadata.get("repository")),
    ("source.ref", metadata.get("source", {}).get("ref")),
    ("source.sha", metadata.get("source", {}).get("sha")),
    ("archive.name", metadata.get("archive", {}).get("name")),
    ("archive.sha256", metadata.get("archive", {}).get("sha256")),
    ("archive.download_url", metadata.get("archive", {}).get("download_url")),
    ("checksum_file.name", metadata.get("checksum_file", {}).get("name")),
    ("checksum_file.sha256", metadata.get("checksum_file", {}).get("sha256")),
    ("checksum_file.download_url", metadata.get("checksum_file", {}).get("download_url")),
    ("app.bundle_name", metadata.get("app", {}).get("bundle_name")),
    ("app.binary_name", metadata.get("app", {}).get("binary_name")),
    ("app.bundle_identifier", metadata.get("app", {}).get("bundle_identifier")),
    ("app.bundle_version", metadata.get("app", {}).get("bundle_version")),
]
for label, value in required:
    if not value:
        raise SystemExit(f"Live check failed: release.json missing {label}")
if metadata["tag"] != f"v{metadata['version']}":
    raise SystemExit("Live check failed: release.json tag does not match version.")
print(metadata["archive"]["name"])
print(metadata["checksum_file"]["name"])
print(metadata["archive"]["sha256"])
print(metadata["archive"]["download_url"])
print(metadata["checksum_file"]["download_url"])
print(metadata["release_api_url"])
print(metadata["tag"])
print(str(metadata["archive"]["size_bytes"]))
print(str(metadata["checksum_file"]["size_bytes"]))
print(metadata["checksum_file"]["sha256"])
print(metadata["app"]["bundle_name"])
print(metadata["app"]["binary_name"])
print(metadata["app"]["bundle_identifier"])
print(metadata["version"])
print(metadata["app"]["bundle_version"])
print(metadata["repository"])
print(metadata["source"]["ref"])
print(metadata["source"]["sha"])
print(metadata.get("platform", {}).get("architecture", ""))
PY

{
  read -r ARCHIVE
  read -r CHECKSUM
  read -r EXPECTED_ARCHIVE_HASH
  read -r ARCHIVE_URL
  read -r CHECKSUM_URL
  read -r RELEASE_API_URL
  read -r RELEASE_TAG
  read -r EXPECTED_ARCHIVE_SIZE
  read -r EXPECTED_CHECKSUM_SIZE
  read -r EXPECTED_CHECKSUM_HASH
  read -r APP_BUNDLE_NAME
  read -r APP_BINARY_NAME
  read -r APP_BUNDLE_ID
  read -r APP_VERSION
  read -r APP_BUILD_NUMBER
  read -r REPOSITORY_URL
  read -r SOURCE_REF
  read -r SOURCE_SHA
  read -r PLATFORM_ARCH
} < "$TMP_DIR/release-vars.txt"

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

python3 - "$TMP_DIR" > "$TMP_DIR/external-links.txt" <<'PY'
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

tmp_dir = Path(sys.argv[1])

class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ("href", "src", "content"):
            value = attrs.get(key, "")
            if value.startswith(("http://", "https://")):
                self.urls.add(value.split("#", 1)[0])

def collect_json_urls(value, urls):
    if isinstance(value, str):
        if value.startswith(("http://", "https://")):
            urls.add(value.split("#", 1)[0])
    elif isinstance(value, list):
        for item in value:
            collect_json_urls(item, urls)
    elif isinstance(value, dict):
        for item in value.values():
            collect_json_urls(item, urls)

urls = set()
for path in tmp_dir.glob("*.html"):
    parser = LinkParser()
    parser.feed(path.read_text(encoding="utf-8", errors="ignore"))
    urls.update(parser.urls)

for path in [tmp_dir / "llms.txt", tmp_dir / ".well-known_security.txt"]:
    if path.exists():
        urls.update(re.findall(r"https?://[^\\s)<>\"']+", path.read_text(encoding="utf-8", errors="ignore")))

release_path = tmp_dir / "release.json"
if release_path.exists():
    collect_json_urls(json.loads(release_path.read_text(encoding="utf-8")), urls)

for url in sorted(urls):
    print(url)
PY

while IFS= read -r external_url; do
  [[ -z "$external_url" ]] && continue
  external_status="$(fetch_status "$external_url" /dev/null || true)"
  [[ -n "$external_status" ]] || external_status="000"
  case "$external_status" in
    200|201|202|203|204|206|301|302|303|307|308) ;;
    *)
      echo "Live check failed: external link returned $external_status: $external_url" >&2
      exit 1
      ;;
  esac
done < "$TMP_DIR/external-links.txt"

require_status "$RELEASE_API_URL" "$TMP_DIR/release-api.json"
REPOSITORY_PATH="${REPOSITORY_URL#https://github.com/}"
TAG_REF_API="https://api.github.com/repos/$REPOSITORY_PATH/git/ref/${SOURCE_REF#refs/}"
require_status "$TAG_REF_API" "$TMP_DIR/release-tag-ref.json"
python3 - "$TMP_DIR/release.json" "$TMP_DIR/release-api.json" "$TMP_DIR/release-tag-ref.json" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
tag_ref = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
if release.get("tag_name") != metadata["tag"]:
    raise SystemExit(f"Live check failed: release tag mismatch: {release.get('tag_name')}")
if release.get("draft") or release.get("prerelease"):
    raise SystemExit("Live check failed: release should not be draft or prerelease.")
if tag_ref.get("ref") != metadata["source"]["ref"]:
    raise SystemExit(f"Live check failed: tag ref mismatch: {tag_ref.get('ref')}")
tag_object = tag_ref.get("object", {})
if tag_object.get("type") != "commit":
    raise SystemExit(f"Live check failed: release tag should resolve directly to a commit: {tag_object.get('type')}")
if tag_object.get("sha") != metadata["source"]["sha"]:
    raise SystemExit(f"Live check failed: release tag commit mismatch: {tag_object.get('sha')}")
assets = {asset.get("name"): asset for asset in release.get("assets", [])}
expected_names = {metadata["archive"]["name"], metadata["checksum_file"]["name"]}
actual_names = set(assets)
if actual_names != expected_names:
    raise SystemExit(f"Live check failed: release assets mismatch: {sorted(actual_names)}")
for key, section in [("archive", metadata["archive"]), ("checksum_file", metadata["checksum_file"])]:
    asset = assets.get(section["name"])
    if not asset:
        raise SystemExit(f"Live check failed: missing release asset {section['name']}")
    expected_digest = f"sha256:{section['sha256']}"
    if asset.get("digest") != expected_digest:
        raise SystemExit(f"Live check failed: {section['name']} digest mismatch: {asset.get('digest')}")
    if asset.get("size") != section["size_bytes"]:
        raise SystemExit(f"Live check failed: {section['name']} size mismatch: {asset.get('size')}")
    if asset.get("browser_download_url") != section["download_url"]:
        raise SystemExit(f"Live check failed: {section['name']} download URL mismatch.")
PY

require_status "$CHECKSUM_URL" "$TMP_DIR/$CHECKSUM"
require_status "$ARCHIVE_URL" "$TMP_DIR/$ARCHIVE"
actual_checksum_size="$(/usr/bin/stat -f %z "$TMP_DIR/$CHECKSUM")"
if [[ "$actual_checksum_size" != "$EXPECTED_CHECKSUM_SIZE" ]]; then
  echo "Live check failed: checksum file size mismatch: $actual_checksum_size" >&2
  exit 1
fi
actual_checksum_hash="$(/usr/bin/shasum -a 256 "$TMP_DIR/$CHECKSUM" | awk '{print $1}')"
if [[ "$actual_checksum_hash" != "$EXPECTED_CHECKSUM_HASH" ]]; then
  echo "Live check failed: checksum file digest mismatch: $actual_checksum_hash" >&2
  exit 1
fi
live_hash="$(awk '{print $1}' "$TMP_DIR/$CHECKSUM")"
if [[ "$live_hash" != "$EXPECTED_ARCHIVE_HASH" ]]; then
  echo "Live check failed: release checksum does not match release.json." >&2
  echo "expected: $EXPECTED_ARCHIVE_HASH" >&2
  echo "live:     $live_hash" >&2
  exit 1
fi
actual_archive_size="$(/usr/bin/stat -f %z "$TMP_DIR/$ARCHIVE")"
if [[ "$actual_archive_size" != "$EXPECTED_ARCHIVE_SIZE" ]]; then
  echo "Live check failed: release archive size mismatch: $actual_archive_size" >&2
  exit 1
fi
local_checksum_path="$ROOT/dist/$CHECKSUM"
if [[ "$VERIFY_DIST" == "1" && -f "$local_checksum_path" ]]; then
  local_hash="$(awk '{print $1}' "$local_checksum_path")"
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

UNZIP_DIR="$TMP_DIR/unpacked"
mkdir -p "$UNZIP_DIR"
/usr/bin/ditto -x -k "$TMP_DIR/$ARCHIVE" "$UNZIP_DIR"
app_count="$(find "$UNZIP_DIR" -maxdepth 1 -name "*.app" -type d | wc -l | tr -d ' ')"
if [[ "$app_count" != "1" ]]; then
  echo "Live check failed: release archive should contain exactly one .app, found $app_count" >&2
  exit 1
fi
APP_PATH="$UNZIP_DIR/$APP_BUNDLE_NAME"
INFO="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_BINARY_NAME"
if [[ ! -d "$APP_PATH" || ! -f "$INFO" || ! -x "$EXECUTABLE" ]]; then
  echo "Live check failed: release archive app layout is incomplete." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO")" == "$APP_BUNDLE_ID" ]]
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO")" == "$APP_VERSION" ]]
[[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO")" == "$APP_BUILD_NUMBER" ]]
[[ "$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO")" == "$APP_BINARY_NAME" ]]
if [[ -n "$PLATFORM_ARCH" ]] && ! /usr/bin/lipo -archs "$EXECUTABLE" | tr ' ' '\n' | grep -qx "$PLATFORM_ARCH"; then
  echo "Live check failed: release executable missing architecture $PLATFORM_ARCH" >&2
  /usr/bin/lipo -archs "$EXECUTABLE" >&2
  exit 1
fi

echo "Live docs verification passed for $SITE_URL"
