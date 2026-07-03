#!/bin/zsh
set -euo pipefail

# 从 docs/release.json 生成 Homebrew Cask，保证版本号、下载地址与 SHA-256
# 始终和发布元数据一致。发布新版本后重新运行本脚本并提交生成结果。
# 输出路径可用第一个参数覆盖（verify-cask.sh 用它生成到临时目录做 diff）。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_METADATA="$ROOT/docs/release.json"
OUTPUT="${1:-$ROOT/Casks/vibelsland-free.rb}"

mkdir -p "$(dirname "$OUTPUT")"

python3 - "$RELEASE_METADATA" "$OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
output = Path(sys.argv[2])

version = metadata["version"]
sha256 = metadata["archive"]["sha256"]
archive_name = metadata["archive"]["name"]
bundle_name = metadata["app"]["bundle_name"]
bundle_id = metadata["app"]["bundle_identifier"]
architecture = metadata["platform"]["architecture"]
signing = metadata["distribution"]["signing"]

url_template = (
    "https://github.com/shinteni/prompt-island/releases/download/"
    f"v#{{version}}/{archive_name.replace(version, '#{version}')}"
)

lines = [
    'cask "vibelsland-free" do',
    f'  version "{version}"',
    f'  sha256 "{sha256}"',
    "",
    f'  url "{url_template}"',
    '  name "Vibelsland Free"',
    '  desc "Local-first floating island showing Claude Code and Codex session status"',
    '  homepage "https://shinteni.github.io/prompt-island/"',
    "",
    "  depends_on macos: :sonoma",
]

if architecture == "arm64":
    lines.append("  depends_on arch: :arm64")

lines += [
    "",
    f'  app "{bundle_name}"',
    "",
    f'  uninstall quit: "{bundle_id}"',
    "",
    "  zap trash: [",
    '    "~/.vibelsland-free",',
    '    "~/Library/Application Support/VibelslandFree",',
    '    "~/Library/Logs/VibelslandFree",',
    "  ]",
]

if signing == "ad-hoc":
    lines += [
        "",
        "  caveats <<~EOS",
        f"    Vibelsland Free {version} is ad-hoc signed and not notarized, so macOS",
        "    Gatekeeper asks for manual confirmation on first launch. Steps:",
        "    https://shinteni.github.io/prompt-island/install.html",
        "  EOS",
    ]

lines += ["end", ""]

output.write_text("\n".join(lines), encoding="utf-8")
print(output)
PY
