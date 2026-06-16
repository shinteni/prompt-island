#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if /usr/bin/xcrun --find xctest >/dev/null 2>&1; then
    swift test --enable-swift-testing --no-parallel --num-workers 1
else
    echo "warning: xctest runner not found; compiling and discovering tests only." >&2
    if [[ "${VIBELSLAND_REQUIRE_TEST_EXECUTION:-0}" == "1" ]]; then
        echo "error: VIBELSLAND_REQUIRE_TEST_EXECUTION=1 requires a full Xcode toolchain with xctest." >&2
        exit 1
    fi
    swift test list
fi
