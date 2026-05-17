#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/docs"
SITE_URL="${VIBELSLAND_SITE_URL:-https://shinteni.github.io/prompt-island/}"
SITE_URL="${SITE_URL%/}/"
OUTPUT_DIR="${1:-${TMPDIR:-/tmp}/vibelsland-docs-site}"
CUSTOM_DOMAIN="${VIBELSLAND_CUSTOM_DOMAIN:-}"

python3 - "$SOURCE_DIR" "$OUTPUT_DIR" "$SITE_URL" "$CUSTOM_DOMAIN" <<'PY'
import json
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).expanduser().resolve()
site_url = sys.argv[3].rstrip("/") + "/"
custom_domain = sys.argv[4].strip()
default_url = "https://shinteni.github.io/prompt-island/"

parsed = urlparse(site_url)
if parsed.scheme not in {"http", "https"} or not parsed.netloc:
    raise SystemExit(f"VIBELSLAND_SITE_URL must be an absolute http(s) URL: {site_url}")
if custom_domain:
    if "/" in custom_domain or ":" in custom_domain or custom_domain != custom_domain.strip("."):
        raise SystemExit(f"VIBELSLAND_CUSTOM_DOMAIN should be a bare host name: {custom_domain}")
    if (parsed.hostname or "").lower() != custom_domain.lower():
        raise SystemExit(
            "VIBELSLAND_SITE_URL host must match VIBELSLAND_CUSTOM_DOMAIN: "
            f"{parsed.hostname} != {custom_domain}"
        )

if not source.is_dir():
    raise SystemExit(f"Source docs directory does not exist: {source}")

dangerous_outputs = {
    Path("/").resolve(),
    Path.home().resolve(),
    source,
    source.parent,
}
if output in dangerous_outputs:
    raise SystemExit(f"Refusing to replace unsafe output directory: {output}")

if output.exists():
    shutil.rmtree(output)
shutil.copytree(source, output, ignore=shutil.ignore_patterns(".DS_Store"))

rewrite_suffixes = {".html", ".xml", ".txt", ".json", ".webmanifest"}
for path in output.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix not in rewrite_suffixes and path.name != "security.txt":
        continue
    text = path.read_text(encoding="utf-8")
    rewritten = text.replace(default_url, site_url)
    if rewritten != text:
        path.write_text(rewritten, encoding="utf-8")

manifest_path = output / "site.webmanifest"
if manifest_path.exists():
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["id"] = "./"
    manifest["start_url"] = "./index.html"
    manifest["scope"] = "./"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

if custom_domain:
    (output / "CNAME").write_text(custom_domain + "\n", encoding="utf-8")

print(f"Built docs site for {site_url} at {output}")
PY

VIBELSLAND_DOCS_DIR="$OUTPUT_DIR" VIBELSLAND_SITE_URL="$SITE_URL" VIBELSLAND_CUSTOM_DOMAIN="$CUSTOM_DOMAIN" zsh "$ROOT/scripts/verify-docs-site.sh"
