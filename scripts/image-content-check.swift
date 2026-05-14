import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: image-content-check.swift <image> [label]\n", stderr)
    exit(64)
}

let path = CommandLine.arguments[1]
let label = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : path
guard let image = NSImage(contentsOfFile: path),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    fputs("\(label) image check failed: cannot read \(path)\n", stderr)
    exit(1)
}

let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh
guard width >= 24, height >= 24 else {
    fputs("\(label) image check failed: image too small \(width)x\(height)\n", stderr)
    exit(1)
}

let sampleStep = max(1, min(width, height) / 80)
var sampled = 0
var visible = 0
var bright = 0
var dark = 0
var minLuminance = 1.0
var maxLuminance = 0.0
var uniqueBuckets = Set<Int>()

for y in stride(from: 0, to: height, by: sampleStep) {
    for x in stride(from: 0, to: width, by: sampleStep) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            continue
        }
        sampled += 1
        let alpha = Double(color.alphaComponent)
        guard alpha > 0.04 else {
            continue
        }
        visible += 1
        let red = Double(color.redComponent)
        let green = Double(color.greenComponent)
        let blue = Double(color.blueComponent)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        minLuminance = min(minLuminance, luminance)
        maxLuminance = max(maxLuminance, luminance)
        if luminance > 0.72 { bright += 1 }
        if luminance < 0.28 { dark += 1 }
        let redBucket = min(7, max(0, Int(red * 8)))
        let greenBucket = min(7, max(0, Int(green * 8)))
        let blueBucket = min(7, max(0, Int(blue * 8)))
        uniqueBuckets.insert((redBucket << 6) | (greenBucket << 3) | blueBucket)
    }
}

let visibleRatio = sampled == 0 ? 0 : Double(visible) / Double(sampled)
let luminanceRange = maxLuminance - minLuminance
let hasVisibleContent = visibleRatio > 0.18
let hasContrast = luminanceRange > 0.08 || (bright > 0 && dark > 0)
let hasColorVariety = uniqueBuckets.count >= 4

guard hasVisibleContent, hasContrast, hasColorVariety else {
    fputs(
        "\(label) image check failed: visibleRatio=\(visibleRatio) luminanceRange=\(luminanceRange) colors=\(uniqueBuckets.count) size=\(width)x\(height)\n",
        stderr
    )
    exit(1)
}

print("\(label) image check passed: \(width)x\(height), visible=\(String(format: "%.2f", visibleRatio)), contrast=\(String(format: "%.2f", luminanceRange)), colors=\(uniqueBuckets.count)")
