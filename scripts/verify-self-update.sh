#!/bin/zsh
set -euo pipefail

# 应用内自更新端到端验证：
# 1. 把构建好的 app 复制到临时目录当作"已安装"版本；
# 2. 用同一 app 制作版本号 9.9.9 的假发布（改 Info.plist → 重签 → zip → shasum）；
# 3. 启动已安装版本，通过验证动作注入指向 file:// 资产的合成 Release；
# 4. 断言：安装路径上的 Info.plist 已变成 9.9.9、旧版本保留在暂存区、
#    应用已用新版本重启（进程存活且来自同一路径）。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/>_ - island.app"
FAKE_VERSION="9.9.9"

[[ -d "$APP_DIR" ]]
. "$ROOT/scripts/verify-support.sh"

TEMP_HOME="$(/usr/bin/mktemp -d "/tmp/vibelsland-selfupdate-home.XXXXXX")"
WORK="$(/usr/bin/mktemp -d "/tmp/vibelsland-selfupdate-work.XXXXXX")"
APP_PID=""

cleanup() {
    /usr/bin/pkill -f "$WORK/Applications" >/dev/null 2>&1 || true
    vibelsland_cleanup_temp_home "$TEMP_HOME" "$APP_PID"
    /bin/rm -rf "$WORK"
}
trap cleanup EXIT

APP_NAME="$(basename "$APP_DIR")"
INSTALL_DIR="$WORK/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
/bin/mkdir -p "$INSTALL_DIR"
/usr/bin/ditto "$APP_DIR" "$INSTALLED_APP"

# 制作假发布：同一 app 提升版本号并重签
RELEASE_DIR="$WORK/release"
/bin/mkdir -p "$RELEASE_DIR"
STAGE_APP="$RELEASE_DIR/$APP_NAME"
/usr/bin/ditto "$APP_DIR" "$STAGE_APP"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$FAKE_VERSION" "$STAGE_APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$STAGE_APP" >/dev/null 2>&1

ARCHIVE_NAME="Vibelsland-Free-$FAKE_VERSION-macos.zip"
(
    cd "$RELEASE_DIR"
    /usr/bin/ditto -c -k --norsrc --keepParent "$APP_NAME" "$ARCHIVE_NAME"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)

vibelsland_write_test_config "$TEMP_HOME" \
    enableClaude=true \
    enableCodexCLI=true \
    enableCodexDesktop=false \
    enableSounds=false \
    soundTheme=soft \
    doNotDisturb=true \
    launchAtLogin=false \
    islandPosition=topCenter \
    approvalTimeoutSeconds=7200 \
    maxVisibleSessions=5

(
    export VIBELSLAND_HOME="$TEMP_HOME"
    export VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1
    "$INSTALLED_APP/Contents/MacOS/VibelslandFree" >/dev/null 2>&1
) &
APP_PID="$!"

sleep 4
if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "Self-update verification failed: app exited early" >&2
    exit 1
fi

/usr/bin/swift - "$FAKE_VERSION" "$ARCHIVE_NAME" "$RELEASE_DIR" <<'SWIFT'
import Foundation
let version = CommandLine.arguments[1]
let archiveName = CommandLine.arguments[2]
let releaseDir = CommandLine.arguments[3]
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("free.vibelsland.verify.selfUpdate"),
    object: nil,
    userInfo: [
        "version": version,
        "archiveName": archiveName,
        "archiveURL": URL(fileURLWithPath: "\(releaseDir)/\(archiveName)").absoluteString,
        "checksumURL": URL(fileURLWithPath: "\(releaseDir)/\(archiveName).sha256").absoluteString,
    ],
    deliverImmediately: true
)
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
SWIFT

# 等待：下载(file://) → 校验 → 替换 → 重启
INSTALLED_VERSION=""
for _ in {1..60}; do
    INSTALLED_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$INSTALLED_VERSION" == "$FAKE_VERSION" ]]; then
        break
    fi
    sleep 0.5
done

if [[ "$INSTALLED_VERSION" != "$FAKE_VERSION" ]]; then
    echo "Self-update verification failed: installed bundle version is '$INSTALLED_VERSION', expected $FAKE_VERSION" >&2
    /usr/bin/tail -30 "$(vibelsland_log_path "$TEMP_HOME")" >&2 || true
    exit 1
fi

BACKUP="$TEMP_HOME/Library/Application Support/VibelslandFree/updates/$FAKE_VERSION/previous-$APP_NAME"
if [[ ! -d "$BACKUP" ]]; then
    echo "Self-update verification failed: previous bundle was not kept at $BACKUP" >&2
    exit 1
fi

# 重启后的新进程应来自同一安装路径
RESTARTED=0
for _ in {1..40}; do
    if /usr/bin/pgrep -f "$INSTALLED_APP/Contents/MacOS/VibelslandFree" >/dev/null 2>&1; then
        RESTARTED=1
        break
    fi
    sleep 0.5
done

if [[ "$RESTARTED" != "1" ]]; then
    echo "Self-update verification failed: updated app did not relaunch" >&2
    /usr/bin/tail -30 "$(vibelsland_log_path "$TEMP_HOME")" >&2 || true
    exit 1
fi

echo "Self-update verification passed: bundle now $INSTALLED_VERSION, previous kept, app relaunched"
