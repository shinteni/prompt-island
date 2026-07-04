#!/bin/zsh
set -euo pipefail

# Cask 一致性校验：
# 1. 提交的 Casks/vibelsland-free.rb 必须与 docs/release.json 重新生成的结果逐字一致；
# 2. Ruby 语法有效；
# 3. sha256 与发布元数据一致（由 1 隐含，这里再显式核对一次防御生成器缺陷）。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK="$ROOT/Casks/vibelsland-free.rb"
RELEASE_METADATA="$ROOT/docs/release.json"

[[ -f "$CASK" ]]

TMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vibelsland-cask.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

zsh "$ROOT/scripts/generate-cask.sh" "$TMP_DIR/vibelsland-free.rb" >/dev/null
if ! /usr/bin/diff -u "$CASK" "$TMP_DIR/vibelsland-free.rb"; then
    echo "verify-cask: Casks/vibelsland-free.rb is out of sync with docs/release.json; run scripts/generate-cask.sh" >&2
    exit 1
fi

/usr/bin/ruby -c "$CASK" >/dev/null

EXPECTED_SHA="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['archive']['sha256'])" "$RELEASE_METADATA")"
if ! /usr/bin/grep -q "sha256 \"$EXPECTED_SHA\"" "$CASK"; then
    echo "verify-cask: sha256 in cask does not match docs/release.json" >&2
    exit 1
fi

echo "Cask verification passed"
