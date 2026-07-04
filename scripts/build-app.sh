#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_METADATA="$ROOT/docs/release.json"
metadata=("${(@f)$(python3 - "$RELEASE_METADATA" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(metadata["app"]["bundle_name"])
print(metadata["app"]["bundle_identifier"])
print(metadata["version"])
print(metadata["app"]["bundle_version"])
PY
)}")
APP_BUNDLE_NAME="$metadata[1]"
APP_NAME="${APP_BUNDLE_NAME%.app}"
BUNDLE_ID="$metadata[2]"
APP_VERSION="$metadata[3]"
BUILD_NUMBER="$metadata[4]"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_BUNDLE_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# 发布包默认构建 Universal Binary（Apple Silicon + Intel）。
# 本地想加速可用 VIBELSLAND_BUILD_ARCHS=arm64 只出单架构。
# 注意：一次传多个 --arch 需要完整 Xcode 的 xcbuild，CommandLineTools
# 环境不可用，所以逐架构编译后用 lipo 合并。
BUILD_ARCHS="${VIBELSLAND_BUILD_ARCHS:-arm64 x86_64}"

cd "$ROOT"
ARCH_BINARIES=()
for arch in ${=BUILD_ARCHS}; do
    swift build -c release --arch "$arch"
    ARCH_BINARIES+=("$(swift build -c release --arch "$arch" --show-bin-path)/VibelslandFree")
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
if (( ${#ARCH_BINARIES[@]} == 1 )); then
    cp "${ARCH_BINARIES[1]}" "$MACOS/VibelslandFree"
else
    /usr/bin/lipo -create "${ARCH_BINARIES[@]}" -output "$MACOS/VibelslandFree"
fi

# 断言二进制包含请求的所有架构，防止发布包悄悄退化成单架构。
BINARY_ARCHS="$(/usr/bin/lipo -archs "$MACOS/VibelslandFree")"
for arch in ${=BUILD_ARCHS}; do
    if [[ " $BINARY_ARCHS " != *" $arch "* ]]; then
        echo "build-app: missing architecture $arch (got: $BINARY_ARCHS)" >&2
        exit 1
    fi
done

ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vibelsland-icon.XXXXXX")"
trap 'rm -rf "$ICON_TMP"' EXIT
ICONSET="$ICON_TMP/AppIcon.iconset"
ICON_SWIFT="$ICON_TMP/generate-icon.swift"
mkdir -p "$ICONSET"
cat > "$ICON_SWIFT" <<'SWIFT'
import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "VibelslandIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let outer = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let outerRadius = size * 0.22
    let outerPath = NSBezierPath(roundedRect: outer, xRadius: outerRadius, yRadius: outerRadius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.78, green: 0.93, blue: 1.0, alpha: 0.64),
        NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.34)
    ])?.draw(in: outerPath, angle: 315)
    NSColor.white.withAlphaComponent(0.78).setStroke()
    outerPath.lineWidth = max(1.0, size * 0.018)
    outerPath.stroke()

    let highlight = NSBezierPath(roundedRect: outer.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: size * 0.17, yRadius: size * 0.17)
    NSColor.white.withAlphaComponent(0.28).setStroke()
    highlight.lineWidth = max(1.0, size * 0.010)
    highlight.stroke()

    let mark = NSBezierPath()
    mark.lineWidth = max(1.6, size * 0.072)
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: size * 0.34, y: size * 0.66))
    mark.line(to: NSPoint(x: size * 0.49, y: size * 0.50))
    mark.line(to: NSPoint(x: size * 0.34, y: size * 0.34))
    mark.move(to: NSPoint(x: size * 0.57, y: size * 0.39))
    mark.line(to: NSPoint(x: size * 0.66, y: size * 0.39))
    mark.move(to: NSPoint(x: size * 0.72, y: size * 0.39))
    mark.line(to: NSPoint(x: size * 0.78, y: size * 0.39))
    NSColor.black.withAlphaComponent(0.78).setStroke()
    mark.stroke()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VibelslandIcon", code: 2)
    }
    return png
}

for (name, pixels) in specs {
    let data = try drawIcon(pixels: pixels)
    try data.write(to: outputURL.appendingPathComponent(name))
}
SWIFT
/usr/bin/swift "$ICON_SWIFT" "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>VibelslandFree</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 >_ - island. All rights reserved.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null
[[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$CONTENTS/Info.plist")" == "true" ]]

echo "$APP_DIR"
