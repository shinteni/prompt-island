#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="${VIBELSLAND_DOCS_DIR:-$ROOT/docs}"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"
CUSTOM_DOMAIN="${VIBELSLAND_CUSTOM_DOMAIN:-}"

python3 - "$ROOT" "$DOCS_DIR" "$SITE_URL" "$CUSTOM_DOMAIN" <<'PY'
import json
import html
import hashlib
import datetime as dt
import os
import re
import struct
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

root = Path(sys.argv[1]).resolve()
docs = Path(sys.argv[2]).resolve()
site_url = sys.argv[3].rstrip("/") + "/"
custom_domain = sys.argv[4].strip()
require_custom_domain = os.environ.get("VIBELSLAND_REQUIRE_CUSTOM_DOMAIN") == "1"
default_site_url = "https://shinteni.github.io/prompt-island/"
site_parts = urlparse(site_url)
site_host = site_parts.netloc
docs_root = docs.resolve()
verify_dist = os.environ.get("VIBELSLAND_VERIFY_DIST") == "1"
errors = []

if custom_domain:
    if (site_parts.hostname or "").lower() != custom_domain.lower():
        errors.append(
            "VIBELSLAND_SITE_URL host must match VIBELSLAND_CUSTOM_DOMAIN: "
            f"{site_parts.hostname} != {custom_domain}"
        )
if require_custom_domain:
    if site_url == default_site_url:
        errors.append("VIBELSLAND_REQUIRE_CUSTOM_DOMAIN=1 requires a non-default VIBELSLAND_SITE_URL.")
    if not custom_domain:
        errors.append("VIBELSLAND_REQUIRE_CUSTOM_DOMAIN=1 requires VIBELSLAND_CUSTOM_DOMAIN.")


def display(path):
    path = Path(path).resolve()
    for base in [root, docs_root]:
        try:
            return str(path.relative_to(base))
        except ValueError:
            continue
    return str(path)

required = [
    docs / ".nojekyll",
    docs / ".well-known" / "security.txt",
    docs / "404.html",
    docs / "site.webmanifest",
    docs / "sitemap.xml",
    docs / "llms.txt",
    docs / "release.json",
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
        errors.append(f"Missing required docs file: {display(path)}")

release_path = docs / "release.json"
release = {}
if release_path.exists():
    try:
        release = json.loads(release_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"Invalid release.json: {exc}")


def release_value(keys, expected_type=str):
    current = release
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            errors.append(f"release.json missing {'.'.join(keys)}")
            return "" if expected_type is str else 0
        current = current[key]
    if expected_type is not None and not isinstance(current, expected_type):
        errors.append(f"release.json {'.'.join(keys)} should be {expected_type.__name__}")
        return "" if expected_type is str else 0
    return current


release_version = release_value(["version"])
release_tag = release_value(["tag"])
release_label = f"v{release_version}" if release_version else ""
release_repository = release_value(["repository"])
release_url = release_value(["release_url"])
release_api_url = release_value(["release_api_url"])
release_notes_url = release_value(["release_notes_url"])
release_source_ref = release_value(["source", "ref"])
release_source_sha = release_value(["source", "sha"])
release_platform_arch = release_value(["platform", "architecture"])
release_platform_processor = release_value(["platform", "processor"])
release_app_name = release_value(["app", "bundle_name"])
release_binary_name = release_value(["app", "binary_name"])
release_bundle_id = release_value(["app", "bundle_identifier"])
release_bundle_version = release_value(["app", "bundle_version"])
release_archive_name = release_value(["archive", "name"])
release_archive_size = release_value(["archive", "size_bytes"], int)
release_archive_hash = release_value(["archive", "sha256"])
release_archive_url = release_value(["archive", "download_url"])
release_checksum_name = release_value(["checksum_file", "name"])
release_checksum_size = release_value(["checksum_file", "size_bytes"], int)
release_checksum_hash = release_value(["checksum_file", "sha256"])
release_checksum_url = release_value(["checksum_file", "download_url"])

if release:
    if release_tag != release_label:
        errors.append(f"release.json tag should match version: {release_tag} vs {release_label}")
    for value, label in [
        (release_repository, "repository"),
        (release_url, "release_url"),
        (release_api_url, "release_api_url"),
        (release_notes_url, "release_notes_url"),
        (release_archive_url, "archive.download_url"),
        (release_checksum_url, "checksum_file.download_url"),
    ]:
        validate_target = value if isinstance(value, str) else ""
        if validate_target:
            parsed = urlparse(validate_target)
            if parsed.scheme != "https":
                errors.append(f"release.json {label} should use https: {validate_target}")
    for value, label in [
        (release_archive_hash, "archive.sha256"),
        (release_checksum_hash, "checksum_file.sha256"),
        (release_source_sha, "source.sha"),
    ]:
        if value and not re.fullmatch(r"[0-9a-f]{64}|[0-9a-f]{40}", value):
            errors.append(f"release.json {label} has an unexpected hash format: {value}")

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
    return parsed.scheme in {"http", "https", "mailto", "tel"}


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


def collect_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from collect_strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from collect_strings(item)


def image_dimensions(path):
    data = path.read_bytes()
    if data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24:
        width, height = struct.unpack(">II", data[16:24])
        return width, height
    if data.startswith(b"\xff\xd8"):
        index = 2
        while index + 9 < len(data):
            while index < len(data) and data[index] == 0xFF:
                index += 1
            if index >= len(data):
                break
            marker = data[index]
            index += 1
            if marker in {0xD8, 0xD9}:
                continue
            if index + 2 > len(data):
                break
            length = int.from_bytes(data[index:index + 2], "big")
            if length < 2 or index + length > len(data):
                break
            if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
                height = int.from_bytes(data[index + 3:index + 5], "big")
                width = int.from_bytes(data[index + 5:index + 7], "big")
                return width, height
            index += length
    return None


def parse_declared_size(value):
    match = re.fullmatch(r"(\d+)x(\d+)", value or "")
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def html_has_anchor(path, fragment):
    if not fragment:
        return True
    target_id = unquote(fragment)
    if not target_id:
        return True
    text = path.read_text(encoding="utf-8")
    escaped = re.escape(target_id)
    return (
        re.search(rf'\bid=["\']{escaped}["\']', text) is not None
        or re.search(rf'\bname=["\']{escaped}["\']', text) is not None
    )


def validate_absolute_site_url(value, rel, context):
    parsed = urlparse(value)
    if not parsed.scheme:
        return
    if parsed.netloc == site_host and not value.startswith(site_url):
        errors.append(f"{context} should start with {site_url} in {rel}: {value}")
    if default_site_url in value and not site_url.startswith(default_site_url):
        errors.append(f"GitHub Pages URL remains after custom site URL in {rel}: {value}")


expected_routes = {}
expected_url_alternates = {}
for filename in localized_files:
    expected_alternates = {
        "zh-CN": page_url("zh-CN", filename),
        "en": page_url("en", filename),
        "ja": page_url("ja", filename),
        "x-default": page_url("zh-CN", filename),
    }
    for expected_url in expected_alternates.values():
        expected_url_alternates[expected_url] = expected_alternates
    for language in ["zh-CN", "en", "ja"]:
        expected_routes[page_file(language, filename)] = {
            "canonical": page_url(language, filename),
            "alternates": expected_alternates,
        }


html_files = sorted(docs.glob("**/*.html"))
versioned_assets = {"styles.css", "lang.js", "effects.js"}
asset_versions = {}
for asset_name in versioned_assets:
    asset_path = docs / asset_name
    if not asset_path.exists():
        errors.append(f"Missing versioned asset: {display(asset_path)}")
        continue
    asset_versions[asset_name] = hashlib.sha256(asset_path.read_bytes()).hexdigest()[:12]

for path in html_files:
    text = path.read_text(encoding="utf-8")
    rel = display(path)
    if site_url != default_site_url and default_site_url in text:
        errors.append(f"Default GitHub Pages URL remains in {rel}")
    for phrase in blocked_copy:
        if phrase in text:
            errors.append(f"Blocked copy remains in {rel}: {phrase}")
    nav_match = re.search(r'<nav class="nav-links"[^>]*>(.*?)</nav>', text, re.S)
    if not nav_match:
        errors.append(f"Missing primary navigation in {rel}")
    else:
        nav_block = nav_match.group(1)
        required_nav_keys = [
            "shared.nav.home",
            "shared.nav.download",
            "shared.nav.support",
        ]
        for key in required_nav_keys:
            if f'data-i18n="{key}"' not in nav_block:
                errors.append(f"Primary navigation missing {key} in {rel}")
                continue
            anchor_match = re.search(rf'<a\b(?=[^>]*data-i18n="{re.escape(key)}")[^>]*>', nav_block)
            if not anchor_match or "data-mobile-label=" not in anchor_match.group(0):
                errors.append(f"Primary navigation missing mobile label for {key} in {rel}")

    footer_match = re.search(r'<footer class="site-footer"[^>]*>.*?<nav\b[^>]*>(.*?)</nav>', text, re.S)
    if not footer_match:
        errors.append(f"Missing footer navigation in {rel}")
    else:
        footer_block = footer_match.group(1)
        required_footer_keys = [
            "shared.nav.home",
            "shared.nav.advantages",
            "shared.nav.download",
            "shared.nav.install",
            "shared.nav.release",
            "shared.nav.privacy",
            "shared.nav.faq",
            "shared.nav.support",
        ]
        for key in required_footer_keys:
            if f'data-i18n="{key}"' not in footer_block:
                errors.append(f"Footer navigation missing {key} in {rel}")

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
            payload = json.loads(block)
        except json.JSONDecodeError as exc:
            errors.append(f"Invalid JSON-LD in {rel}: {exc}")
            continue
        for value in collect_strings(payload):
            validate_absolute_site_url(value, rel, "JSON-LD URL")

    for kind, value in parser.refs:
        if value.startswith("http://"):
            errors.append(f"External {kind} should use https in {rel}: {value}")
        if not value or is_external(value):
            continue
        before_hash, _, fragment = value.partition("#")
        clean = before_hash.split("?", 1)[0]
        if not clean:
            target = path
        else:
            target = (path.parent / clean).resolve()
        try:
            target.relative_to(docs_root)
        except ValueError:
            errors.append(f"Local {kind} escapes repository in {rel}: {value}")
            continue
        if not target.exists():
            errors.append(f"Missing local {kind} target in {rel}: {value}")
        elif fragment and target.suffix == ".html" and not html_has_anchor(target, fragment):
            errors.append(f"Missing local anchor target in {rel}: {value}")
        if target.name in versioned_assets:
            query = urlparse(value).query
            match = re.search(r"(?:^|&)v=([^&]+)", query)
            expected_version = asset_versions.get(target.name)
            if not match:
                errors.append(f"Version query missing for local asset in {rel}: {value}")
            elif expected_version and match.group(1) != expected_version:
                errors.append(
                    f"Version query for {target.name} in {rel} should be {expected_version}: {value}"
                )

    for value in parser.absolute_site_urls:
        validate_absolute_site_url(value, rel, "Site URL")

manifest_path = docs / "site.webmanifest"
if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_manifest_values = {
        "id": "./",
        "start_url": "./index.html",
        "scope": "./",
    }
    required_manifest_fields = [
        "name",
        "short_name",
        "description",
        "id",
        "start_url",
        "scope",
        "display",
        "background_color",
        "theme_color",
        "icons",
        "screenshots",
        "shortcuts",
    ]
    for key in required_manifest_fields:
        if not manifest.get(key):
            errors.append(f"Manifest missing required field: {key}")
    if manifest.get("short_name") == manifest.get("name"):
        errors.append("Manifest short_name should be shorter than name.")
    if isinstance(manifest.get("short_name"), str) and len(manifest["short_name"]) > 12:
        errors.append(f"Manifest short_name is too long for install surfaces: {manifest['short_name']}")
    for key, expected_value in expected_manifest_values.items():
        actual_value = manifest.get(key)
        if actual_value != expected_value:
            errors.append(f"Manifest {key} should be {expected_value}: {actual_value}")
    for value in collect_strings(manifest):
        validate_absolute_site_url(value, "site.webmanifest", "Manifest URL")
    has_maskable_icon = False
    for icon in manifest.get("icons", []):
        src = icon.get("src")
        icon_path = docs / src if src else None
        if not src:
            errors.append("Manifest icon is missing src.")
            continue
        if not icon_path.exists():
            errors.append(f"Manifest icon is missing: {src}")
            continue
        if icon.get("type") != "image/png":
            errors.append(f"Manifest icon should be image/png: {src}")
        declared_size = parse_declared_size(icon.get("sizes"))
        actual_size = image_dimensions(icon_path)
        if not declared_size:
            errors.append(f"Manifest icon has invalid sizes value: {src}")
        elif actual_size != declared_size:
            errors.append(f"Manifest icon size mismatch for {src}: declared {declared_size}, actual {actual_size}")
        purpose_tokens = set((icon.get("purpose") or "").split())
        if "maskable" in purpose_tokens:
            has_maskable_icon = True
        if "any" not in purpose_tokens:
            errors.append(f"Manifest icon should include purpose any: {src}")
    if manifest.get("icons") and not has_maskable_icon:
        errors.append("Manifest should include at least one maskable icon.")
    for screenshot in manifest.get("screenshots", []):
        src = screenshot.get("src")
        screenshot_path = docs / src if src else None
        if not src:
            errors.append("Manifest screenshot is missing src.")
            continue
        if not screenshot_path.exists():
            errors.append(f"Manifest screenshot is missing: {src}")
            continue
        declared_size = parse_declared_size(screenshot.get("sizes"))
        actual_size = image_dimensions(screenshot_path)
        if not declared_size:
            errors.append(f"Manifest screenshot has invalid sizes value: {src}")
        elif actual_size != declared_size:
            errors.append(f"Manifest screenshot size mismatch for {src}: declared {declared_size}, actual {actual_size}")
        expected_type = "image/jpeg" if screenshot_path.suffix.lower() in {".jpg", ".jpeg"} else "image/png"
        if screenshot.get("type") != expected_type:
            errors.append(f"Manifest screenshot type mismatch for {src}: {screenshot.get('type')}")
    for shortcut in manifest.get("shortcuts", []):
        url = shortcut.get("url", "")
        if not shortcut.get("name") or not shortcut.get("description") or not url:
            errors.append(f"Manifest shortcut is incomplete: {shortcut}")
            continue
        if url.startswith(("http://", "https://")):
            errors.append(f"Manifest shortcut should stay local: {url}")
            continue
        clean = url.split("#", 1)[0].split("?", 1)[0]
        if clean.startswith("./"):
            clean = clean[2:]
        target = (docs / clean).resolve()
        try:
            target.relative_to(docs_root)
        except ValueError:
            errors.append(f"Manifest shortcut escapes docs root: {url}")
            continue
        if not target.exists():
            errors.append(f"Manifest shortcut target is missing: {url}")

not_found_path = docs / "404.html"
if not_found_path.exists():
    not_found_text = not_found_path.read_text(encoding="utf-8")
    for phrase in [
        'data-page="404"',
        "Page not found",
        "ページが見つかりません",
        '404.html?lang=en',
        '404.html?lang=ja',
        f'<noscript><link rel="stylesheet" href="{site_url}styles.css?v={asset_versions.get("styles.css", "")}"></noscript>',
        'base.href = window.location.hostname.endsWith("github.io") ? "/prompt-island/" : "/"',
    ]:
        if phrase not in not_found_text:
            errors.append(f"404 page missing static fallback value: {phrase}")

if site_url != default_site_url:
    text_suffixes = {".html", ".xml", ".txt", ".json", ".webmanifest"}
    for path in docs.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in text_suffixes and path.name != "security.txt":
            continue
        if default_site_url in path.read_text(encoding="utf-8"):
            errors.append(f"Default GitHub Pages URL remains in {display(path)}")

for path in [docs / "download.html", docs / "en" / "download.html", docs / "ja" / "download.html"]:
    if path.exists():
        parser = RefParser()
        page_text = path.read_text(encoding="utf-8")
        parser.feed(page_text)
        json_ld_types = []
        for block in parser.json_ld:
            if not block:
                continue
            try:
                payload = json.loads(block)
            except json.JSONDecodeError:
                continue
            json_ld_types.append(payload.get("@type"))
            if payload.get("@type") == "SoftwareApplication":
                expected_payload = {
                    "softwareVersion": release_version,
                    "downloadUrl": release_archive_url,
                    "sha256": release_archive_hash,
                    "processorRequirements": release_platform_processor,
                }
                for key, expected_value in expected_payload.items():
                    if expected_value and payload.get(key) != expected_value:
                        errors.append(f"Download JSON-LD {key} does not match release.json in {display(path)}: {payload.get(key)}")
        if "SoftwareApplication" not in json_ld_types:
            errors.append(f"Download page missing SoftwareApplication JSON-LD: {display(path)}")
        for phrase in [release_label, release_archive_name, release_archive_hash, release_archive_url, release_checksum_url, release_app_name, release_source_sha[:7], release_platform_arch, release_platform_processor]:
            escaped_phrase = html.escape(phrase) if phrase else ""
            if phrase and phrase not in page_text and escaped_phrase not in page_text:
                errors.append(f"Download page missing release metadata value in {display(path)}: {phrase}")

for path in [docs / "support.html", docs / "en" / "support.html", docs / "ja" / "support.html"]:
    if path.exists():
        support_text = path.read_text(encoding="utf-8")
        for phrase in ["MIT License", "https://github.com/shinteni/prompt-island/blob/main/LICENSE"]:
            if phrase not in support_text:
                errors.append(f"Support page missing license/disclaimer value in {display(path)}: {phrase}")

for path in [docs / "index.html", docs / "en" / "index.html", docs / "ja" / "index.html"]:
    if path.exists():
        home_text = path.read_text(encoding="utf-8")
        for phrase in [
            'class="home-entry"',
            'class="start-hero"',
            'class="start-logo"',
            'start-download',
            'class="start-steps"',
            'class="start-card"',
            'class="start-card-image"',
            'class="start-caption"',
            'start-welcome.svg',
            'start-project.svg',
            'start-build.svg',
            'data-i18n="home.hero.title"',
            'data-i18n="home.step1.title"',
            'data-i18n="home.step2.title"',
            'data-i18n="home.step3.title"',
            'data-i18n-aria-label="aria.homeSteps"',
        ]:
            if phrase not in home_text:
                errors.append(f"Home page missing start layout in {display(path)}: {phrase}")

sitemap_path = docs / "sitemap.xml"
if sitemap_path.exists():
    tree = ET.parse(sitemap_path)
    namespace = {
        "sm": "http://www.sitemaps.org/schemas/sitemap/0.9",
        "xhtml": "http://www.w3.org/1999/xhtml",
    }
    url_nodes = tree.findall(".//sm:url", namespace)
    locs = [node.findtext("sm:loc", default="", namespaces=namespace) for node in url_nodes]
    if not locs:
        errors.append("Sitemap has no loc entries.")
    for url_node, loc in zip(url_nodes, locs):
        if not loc.startswith(site_url):
            errors.append(f"Sitemap loc does not match site URL {site_url}: {loc}")
            continue
        expected_alternates = expected_url_alternates.get(loc)
        if not expected_alternates:
            errors.append(f"Sitemap loc is not in expected localized route matrix: {loc}")
        else:
            actual_alternates = {}
            for link in url_node.findall("xhtml:link", namespace):
                if link.attrib.get("rel") == "alternate" and link.attrib.get("hreflang"):
                    actual_alternates[link.attrib["hreflang"]] = link.attrib.get("href", "")
            for hreflang, expected_href in expected_alternates.items():
                actual_href = actual_alternates.get(hreflang)
                if actual_href != expected_href:
                    errors.append(f"Unexpected sitemap hreflang {hreflang} for {loc}: {actual_href or '<missing>'}")
            extra_hreflangs = sorted(set(actual_alternates) - set(expected_alternates))
            for hreflang in extra_hreflangs:
                errors.append(f"Unexpected extra sitemap hreflang {hreflang} for {loc}: {actual_alternates[hreflang]}")
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
        release_label,
        release_archive_name,
        release_archive_hash,
        release_archive_url,
        f"{site_url}release.json",
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
        "Contact: https://github.com/shinteni/prompt-island/security/advisories/new",
        "Preferred-Languages: zh, en, ja",
        f"Canonical: {site_url}.well-known/security.txt",
        f"Policy: {site_url}support.html#report-title",
    ]
    for line in expected_security_lines:
        if line not in security:
            errors.append(f"security.txt missing expected line: {line}")
    security_fields = {}
    for raw_line in security.splitlines():
        if ":" not in raw_line:
            continue
        name, value = raw_line.split(":", 1)
        security_fields[name.strip().lower()] = value.strip()
    expires_value = security_fields.get("expires")
    if not expires_value:
        errors.append("security.txt missing Expires line")
    else:
        try:
            expires_at = dt.datetime.fromisoformat(expires_value.replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"security.txt Expires is not valid ISO-8601: {expires_value}")
        else:
            now = dt.datetime.now(dt.timezone.utc)
            if expires_at <= now:
                errors.append(f"security.txt Expires is not in the future: {expires_value}")

if custom_domain:
    cname_path = docs / "CNAME"
    if not cname_path.exists():
        errors.append(f"CNAME is required when VIBELSLAND_CUSTOM_DOMAIN={custom_domain}")
    else:
        actual_domain = cname_path.read_text(encoding="utf-8").strip()
        if actual_domain != custom_domain:
            errors.append(f"CNAME should be {custom_domain}: {actual_domain}")

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
            target.relative_to(root)
        except ValueError:
            errors.append(f"Markdown reference escapes repository in {md_path.name}: {value}")
            continue
        if not target.exists():
            errors.append(f"Missing markdown reference target in {md_path.name}: {value}")

for script_path, expected_values in {
    root / "scripts" / "build-app.sh": [release_app_name, release_bundle_id, release_version, release_bundle_version],
    root / "scripts" / "package-release.sh": [release_app_name, release_version, release_archive_name, release_checksum_name],
}.items():
    if script_path.exists():
        script_text = script_path.read_text(encoding="utf-8")
        if "release.json" not in script_text:
            errors.append(f"{script_path.name} should read docs/release.json")
        for value in expected_values:
            if value and value not in script_text and "release.json" not in script_text:
                errors.append(f"{script_path.name} missing expected release metadata value: {value}")

for path in [root / "README.md", root / "README.en.md"]:
    if path.exists():
        text = path.read_text(encoding="utf-8")
        for phrase in [release_label, release_archive_name, release_archive_hash, release_archive_url, release_checksum_url, "docs/release.json"]:
            if phrase and phrase not in text:
                errors.append(f"{path.name} missing release metadata value: {phrase}")

checksum_path = root / "dist" / release_checksum_name
if verify_dist and checksum_path.exists():
    checksum = checksum_path.read_text(encoding="utf-8").strip()
    parts = checksum.split()
    if len(parts) != 2:
        errors.append("Release checksum should contain exactly a hash and a filename.")
    elif "/" in parts[1] or "\\" in parts[1]:
        errors.append(f"Release checksum should use a filename, not a path: {parts[1]}")
    else:
        if parts[0] != release_archive_hash:
            errors.append(f"Release checksum file hash does not match release.json: {parts[0]}")
        if parts[1] != release_archive_name:
            errors.append(f"Release checksum file archive does not match release.json: {parts[1]}")
        checksum_file_hash = subprocess.run(
            ["/usr/bin/shasum", "-a", "256", checksum_path.name],
            cwd=checksum_path.parent,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if checksum_file_hash.returncode != 0:
            errors.append(f"Could not hash release checksum file: {checksum_file_hash.stderr.strip()}")
        elif checksum_file_hash.stdout.split()[0] != release_checksum_hash:
            errors.append(f"Release checksum file digest does not match release.json: {checksum_file_hash.stdout.split()[0]}")
        if checksum_path.stat().st_size != release_checksum_size:
            errors.append(f"Release checksum file size does not match release.json: {checksum_path.stat().st_size}")
        for path in [
            docs / "download.html",
            docs / "en" / "download.html",
            docs / "ja" / "download.html",
            root / "README.md",
            root / "README.en.md",
        ]:
            if path.exists() and parts[0] not in path.read_text(encoding="utf-8"):
                errors.append(f"Download page checksum does not match dist checksum: {display(path)}")
        archive_path = checksum_path.with_suffix("")
        if archive_path.exists():
            if archive_path.stat().st_size != release_archive_size:
                errors.append(f"Release archive size does not match release.json: {archive_path.stat().st_size}")
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
