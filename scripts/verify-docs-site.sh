#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"

python3 - "$ROOT" "$SITE_URL" <<'PY'
import json
import os
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
docs = root / "docs"
site_url = sys.argv[2].rstrip("/") + "/"
site_host = urlparse(site_url).netloc
errors = []

required = [
    docs / ".nojekyll",
    docs / "404.html",
    docs / "index.html",
    docs / "download.html",
    docs / "advantages.html",
    docs / "privacy.html",
    docs / "site.webmanifest",
    docs / "sitemap.xml",
    docs / "robots.txt",
]
for path in required:
    if not path.exists():
        errors.append(f"Missing required docs file: {path.relative_to(root)}")

blocked_copy = [
    "状态层",
    "status layer",
    "Status layer",
    "ステータスレイヤー",
    "不是新的工作台",
    "new workspace",
    "新しい作業台",
    "而不是改变你的工作流",
    "without changing your workflow",
    "作業流れは変えず",
    "它补的是",
]


class RefParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.absolute_site_urls = []
        self.active_nav_without_current = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {"a", "link"} and attrs.get("href"):
            self.refs.append(("href", attrs["href"]))
        if tag in {"img", "script", "source"} and attrs.get("src"):
            self.refs.append(("src", attrs["src"]))
        if tag == "meta" and attrs.get("content"):
            key = attrs.get("property") or attrs.get("name") or ""
            if key in {"og:url", "og:image", "twitter:image"}:
                self.absolute_site_urls.append(attrs["content"])
        if tag == "link" and attrs.get("rel") in {"canonical", "alternate"} and attrs.get("href"):
            self.absolute_site_urls.append(attrs["href"])
        if (
            tag == "a"
            and attrs.get("class")
            and "active" in attrs["class"].split()
            and attrs.get("data-i18n", "").startswith("shared.nav.")
        ):
            if attrs.get("aria-current") != "page":
                self.active_nav_without_current.append(attrs.get("href", "<missing href>"))


def is_external(value):
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https", "mailto", "tel"} or value.startswith("#")


html_files = sorted(docs.glob("**/*.html"))
for path in html_files:
    text = path.read_text(encoding="utf-8")
    rel = path.relative_to(root)
    for phrase in blocked_copy:
        if phrase in text:
            errors.append(f"Blocked copy remains in {rel}: {phrase}")

    parser = RefParser()
    parser.feed(text)
    for current in parser.active_nav_without_current:
        errors.append(f"Active navigation missing aria-current in {rel}: {current}")

    for kind, value in parser.refs:
        if not value or is_external(value):
            continue
        clean = value.split("#", 1)[0].split("?", 1)[0]
        if not clean:
            continue
        target = (path.parent / clean).resolve()
        try:
            target.relative_to(root.resolve())
        except ValueError:
            errors.append(f"Local {kind} escapes repository in {rel}: {value}")
            continue
        if not target.exists():
            errors.append(f"Missing local {kind} target in {rel}: {value}")

    for value in parser.absolute_site_urls:
        parsed = urlparse(value)
        if not parsed.scheme:
            continue
        if parsed.netloc == site_host and not value.startswith(site_url):
            errors.append(f"Site URL should start with {site_url} in {rel}: {value}")
        if "shinteni.github.io/prompt-island/" in value and not site_url.startswith("https://shinteni.github.io/prompt-island/"):
            errors.append(f"GitHub Pages URL remains after custom site URL in {rel}: {value}")

manifest_path = docs / "site.webmanifest"
if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for icon in manifest.get("icons", []):
        src = icon.get("src")
        if src and not (docs / src).exists():
            errors.append(f"Manifest icon is missing: {src}")

sitemap_path = docs / "sitemap.xml"
if sitemap_path.exists():
    tree = ET.parse(sitemap_path)
    namespace = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    locs = [node.text or "" for node in tree.findall(".//sm:loc", namespace)]
    if not locs:
        errors.append("Sitemap has no loc entries.")
    for loc in locs:
        if not loc.startswith(site_url):
            errors.append(f"Sitemap loc does not match site URL {site_url}: {loc}")

robots_path = docs / "robots.txt"
if robots_path.exists():
    robots = robots_path.read_text(encoding="utf-8")
    expected_sitemap = f"Sitemap: {site_url}sitemap.xml"
    if expected_sitemap not in robots:
        errors.append(f"robots.txt missing expected sitemap line: {expected_sitemap}")

checksum_path = root / "dist" / "Vibelsland-Free-0.1.0-macos.zip.sha256"
if checksum_path.exists():
    checksum = checksum_path.read_text(encoding="utf-8").strip()
    parts = checksum.split()
    if len(parts) != 2:
        errors.append("Release checksum should contain exactly a hash and a filename.")
    elif "/" in parts[1] or "\\" in parts[1]:
        errors.append(f"Release checksum should use a filename, not a path: {parts[1]}")
    else:
        for path in [docs / "download.html", docs / "en" / "download.html", docs / "ja" / "download.html"]:
            if path.exists() and parts[0] not in path.read_text(encoding="utf-8"):
                errors.append(f"Download page checksum does not match dist checksum: {path.relative_to(root)}")

if errors:
    print("Docs site verification failed:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(f"Docs site verification passed for {site_url}")
PY
