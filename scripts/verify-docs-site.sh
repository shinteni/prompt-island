#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"

python3 - "$ROOT" "$SITE_URL" <<'PY'
import json
import os
import re
import subprocess
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
    docs / ".well-known" / "security.txt",
    docs / "404.html",
    docs / "site.webmanifest",
    docs / "sitemap.xml",
    docs / "llms.txt",
    docs / "robots.txt",
]
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
for filename in localized_files:
    required.extend([
        docs / filename,
        docs / "en" / filename,
        docs / "ja" / filename,
    ])
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
    "尚未完成 Developer ID",
    "not yet Developer ID",
    "にはまだ対応",
    "安装被 macOS 拦截",
    "macOS blocks installation",
    "起動をブロック",
]


class RefParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.absolute_site_urls = []
        self.active_nav_without_current = []
        self.script_type = ""
        self.script_text = []
        self.json_ld = []
        self.html_lang = ""
        self.h1_count = 0
        self.images_missing_alt = []
        self.meta = {}
        self.canonical = ""
        self.alternates = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "html":
            self.html_lang = attrs.get("lang", "")
        if tag == "h1":
            self.h1_count += 1
        if tag == "script":
            self.script_type = attrs.get("type", "")
            self.script_text = []
        if tag in {"a", "link"} and attrs.get("href"):
            self.refs.append(("href", attrs["href"]))
        if tag in {"img", "script", "source"} and attrs.get("src"):
            self.refs.append(("src", attrs["src"]))
        if tag == "img" and "alt" not in attrs:
            self.images_missing_alt.append(attrs.get("src", "<missing src>"))
        if tag == "meta" and attrs.get("content"):
            key = attrs.get("property") or attrs.get("name") or ""
            if key:
                self.meta[key] = attrs["content"]
            if key in {"og:url", "og:image", "twitter:image"}:
                self.absolute_site_urls.append(attrs["content"])
        if tag == "link" and attrs.get("rel") in {"canonical", "alternate"} and attrs.get("href"):
            self.absolute_site_urls.append(attrs["href"])
            if attrs.get("rel") == "canonical":
                self.canonical = attrs["href"]
            elif attrs.get("rel") == "alternate" and attrs.get("hreflang"):
                self.alternates[attrs["hreflang"]] = attrs["href"]
        if (
            tag == "a"
            and attrs.get("class")
            and "active" in attrs["class"].split()
            and attrs.get("data-i18n", "").startswith("shared.nav.")
        ):
            if attrs.get("aria-current") != "page":
                self.active_nav_without_current.append(attrs.get("href", "<missing href>"))

    def handle_data(self, data):
        if self.script_type == "application/ld+json":
            self.script_text.append(data)

    def handle_endtag(self, tag):
        if tag == "script":
            if self.script_type == "application/ld+json":
                self.json_ld.append("".join(self.script_text).strip())
            self.script_type = ""
            self.script_text = []


def is_external(value):
    parsed = urlparse(value)
    return parsed.scheme in {"http", "https", "mailto", "tel"} or value.startswith("#")


def page_file(language, filename):
    if language == "zh-CN":
        return docs / filename
    prefix = "en" if language == "en" else "ja"
    return docs / prefix / filename


def page_url(language, filename):
    if filename == "index.html":
        if language == "zh-CN":
            return site_url
        return f"{site_url}{language}/" if language in {"en", "ja"} else site_url
    if language == "zh-CN":
        return f"{site_url}{filename}"
    return f"{site_url}{language}/{filename}"


expected_routes = {}
for filename in localized_files:
    expected_alternates = {
        "zh-CN": page_url("zh-CN", filename),
        "en": page_url("en", filename),
        "ja": page_url("ja", filename),
        "x-default": page_url("zh-CN", filename),
    }
    for language in ["zh-CN", "en", "ja"]:
        expected_routes[page_file(language, filename)] = {
            "canonical": page_url(language, filename),
            "alternates": expected_alternates,
        }


html_files = sorted(docs.glob("**/*.html"))
versioned_assets = {"styles.css", "lang.js", "effects.js"}
for path in html_files:
    text = path.read_text(encoding="utf-8")
    rel = path.relative_to(root)
    for phrase in blocked_copy:
        if phrase in text:
            errors.append(f"Blocked copy remains in {rel}: {phrase}")

    parser = RefParser()
    parser.feed(text)
    if not parser.html_lang:
        errors.append(f"Missing html lang in {rel}")
    if parser.h1_count != 1:
        errors.append(f"Expected exactly one h1 in {rel}, found {parser.h1_count}")
    for src in parser.images_missing_alt:
        errors.append(f"Image missing alt attribute in {rel}: {src}")
    expected_route = expected_routes.get(path)
    if expected_route:
        expected_canonical = expected_route["canonical"]
        if parser.canonical != expected_canonical:
            errors.append(f"Unexpected canonical in {rel}: {parser.canonical or '<missing>'}")
        if parser.meta.get("og:url") != expected_canonical:
            errors.append(f"og:url should match canonical in {rel}: {parser.meta.get('og:url')}")
        for hreflang, expected_href in expected_route["alternates"].items():
            actual_href = parser.alternates.get(hreflang)
            if actual_href != expected_href:
                errors.append(f"Unexpected hreflang {hreflang} in {rel}: {actual_href or '<missing>'}")
        extra_hreflangs = sorted(set(parser.alternates) - set(expected_route["alternates"]))
        for hreflang in extra_hreflangs:
            errors.append(f"Unexpected extra hreflang {hreflang} in {rel}: {parser.alternates[hreflang]}")
    expected_locale = {"zh-CN": "zh_CN", "en": "en_US", "ja": "ja_JP"}.get(parser.html_lang)
    expected_social = {
        "og:site_name": "Vibelsland Free",
        "og:locale": expected_locale,
        "og:image:alt": None,
        "twitter:image:alt": None,
    }
    for key, expected_value in expected_social.items():
        value = parser.meta.get(key, "")
        if not value:
            errors.append(f"Missing social meta {key} in {rel}")
        elif expected_value and value != expected_value:
            errors.append(f"Unexpected social meta {key} in {rel}: {value}")
    og_image = parser.meta.get("og:image", "")
    expected_dimensions = None
    if og_image.endswith("/hero-island-light.jpg"):
        expected_dimensions = ("1672", "941")
    elif og_image.endswith("/ui-island-light.jpg"):
        expected_dimensions = ("1040", "860")
    if expected_dimensions:
        width, height = expected_dimensions
        if parser.meta.get("og:image:width") != width:
            errors.append(f"Unexpected og:image:width in {rel}: {parser.meta.get('og:image:width')}")
        if parser.meta.get("og:image:height") != height:
            errors.append(f"Unexpected og:image:height in {rel}: {parser.meta.get('og:image:height')}")
    for current in parser.active_nav_without_current:
        errors.append(f"Active navigation missing aria-current in {rel}: {current}")

    for block in parser.json_ld:
        if not block:
            continue
        try:
            json.loads(block)
        except json.JSONDecodeError as exc:
            errors.append(f"Invalid JSON-LD in {rel}: {exc}")

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
        if target.name in versioned_assets and "?v=" not in value:
            errors.append(f"Version query missing for local asset in {rel}: {value}")

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
    for screenshot in manifest.get("screenshots", []):
        src = screenshot.get("src")
        if src and not (docs / src).exists():
            errors.append(f"Manifest screenshot is missing: {src}")

for path in [docs / "download.html", docs / "en" / "download.html", docs / "ja" / "download.html"]:
    if path.exists():
        parser = RefParser()
        parser.feed(path.read_text(encoding="utf-8"))
        json_ld_types = []
        for block in parser.json_ld:
            if not block:
                continue
            try:
                payload = json.loads(block)
            except json.JSONDecodeError:
                continue
            json_ld_types.append(payload.get("@type"))
        if "SoftwareApplication" not in json_ld_types:
            errors.append(f"Download page missing SoftwareApplication JSON-LD: {path.relative_to(root)}")

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
            continue
        parsed = urlparse(loc)
        rel_url = loc[len(site_url):].split("#", 1)[0].split("?", 1)[0]
        if not rel_url:
            target = docs / "index.html"
        elif rel_url.endswith("/"):
            target = docs / rel_url / "index.html"
        else:
            target = docs / rel_url
        if not target.exists():
            errors.append(f"Sitemap loc has no local target: {loc}")

robots_path = docs / "robots.txt"
if robots_path.exists():
    robots = robots_path.read_text(encoding="utf-8")
    expected_sitemap = f"Sitemap: {site_url}sitemap.xml"
    if expected_sitemap not in robots:
        errors.append(f"robots.txt missing expected sitemap line: {expected_sitemap}")

llms_path = docs / "llms.txt"
if llms_path.exists():
    llms = llms_path.read_text(encoding="utf-8")
    for phrase in [
        "Vibelsland Free",
        "v0.1.0",
        "Vibelsland-Free-0.1.0-macos.zip",
        "64c7c0a4eae81042bbc3896e24a07ab5d5573aeaafa846eada2e982f887ecf81",
        f"{site_url}install.html",
        f"{site_url}privacy.html",
        f"{site_url}.well-known/security.txt",
    ]:
        if phrase not in llms:
            errors.append(f"llms.txt missing expected product fact: {phrase}")

security_path = docs / ".well-known" / "security.txt"
if security_path.exists():
    security = security_path.read_text(encoding="utf-8")
    expected_security_lines = [
        "Contact: https://github.com/shinteni/prompt-island/issues",
        f"Canonical: {site_url}.well-known/security.txt",
        f"Policy: {site_url}support.html",
    ]
    for line in expected_security_lines:
        if line not in security:
            errors.append(f"security.txt missing expected line: {line}")

markdown_ref_pattern = re.compile(r"!\[[^\]]*\]\(([^)]+)\)|\[[^\]]+\]\(([^)]+)\)|<img[^>]+src=\"([^\"]+)\"", re.I)
for md_path in [root / "README.md", root / "README.en.md", root / "PRIVACY.md"]:
    if not md_path.exists():
        continue
    markdown = md_path.read_text(encoding="utf-8")
    for match in markdown_ref_pattern.finditer(markdown):
        value = next((group for group in match.groups() if group), "")
        if not value or is_external(value):
            continue
        clean = value.split("#", 1)[0].split("?", 1)[0]
        if not clean:
            continue
        target = (md_path.parent / clean).resolve()
        try:
            target.relative_to(root.resolve())
        except ValueError:
            errors.append(f"Markdown reference escapes repository in {md_path.name}: {value}")
            continue
        if not target.exists():
            errors.append(f"Missing markdown reference target in {md_path.name}: {value}")

checksum_path = root / "dist" / "Vibelsland-Free-0.1.0-macos.zip.sha256"
if checksum_path.exists():
    checksum = checksum_path.read_text(encoding="utf-8").strip()
    parts = checksum.split()
    if len(parts) != 2:
        errors.append("Release checksum should contain exactly a hash and a filename.")
    elif "/" in parts[1] or "\\" in parts[1]:
        errors.append(f"Release checksum should use a filename, not a path: {parts[1]}")
    else:
        for path in [
            docs / "download.html",
            docs / "en" / "download.html",
            docs / "ja" / "download.html",
            root / "README.md",
            root / "README.en.md",
        ]:
            if path.exists() and parts[0] not in path.read_text(encoding="utf-8"):
                errors.append(f"Download page checksum does not match dist checksum: {path.relative_to(root)}")
        archive_path = checksum_path.with_suffix("")
        if archive_path.exists():
            result = subprocess.run(
                ["/usr/bin/shasum", "-a", "256", "-c", checksum_path.name],
                cwd=checksum_path.parent,
                text=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            if result.returncode != 0:
                errors.append(f"Release checksum verification failed: {result.stderr.strip()}")

if errors:
    print("Docs site verification failed:")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(f"Docs site verification passed for {site_url}")
PY
