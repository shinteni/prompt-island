import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count >= 5,
      let pid = Int32(CommandLine.arguments[1]),
      let duration = Double(CommandLine.arguments[2]),
      let interval = Double(CommandLine.arguments[3]) else {
    fputs("usage: window-frame-samples.swift <pid> <durationSeconds> <intervalSeconds> <label>\n", stderr)
    exit(64)
}

let label = CommandLine.arguments[4]
let startedAt = CFAbsoluteTimeGetCurrent()

func currentFrame() -> (x: Double, y: Double, width: Double, height: Double)? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { item -> (x: Double, y: Double, width: Double, height: Double, alpha: Double, layer: Int)? in
        guard (item[kCGWindowOwnerPID as String] as? Int32) == pid,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double,
              let y = bounds["Y"] as? Double,
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else {
            return nil
        }
        let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
        let layer = item[kCGWindowLayer as String] as? Int ?? 0
        guard alpha > 0.01, width > 4, height > 4 else {
            return nil
        }
        return (x, y, width, height, alpha, layer)
    }
    .sorted { left, right in
        if left.layer != right.layer { return left.layer < right.layer }
        return left.width * left.height > right.width * right.height
    }
    .first
    .map { ($0.x, $0.y, $0.width, $0.height) }
}

var sawFrame = false
while CFAbsoluteTimeGetCurrent() - startedAt <= duration {
    let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
    if let frame = currentFrame() {
        sawFrame = true
        print(String(format: "%.4f %.1f %.1f %.1f %.1f", elapsed, frame.x, frame.y, frame.width, frame.height))
        fflush(stdout)
    }
    Thread.sleep(forTimeInterval: max(0.001, interval))
}

if !sawFrame {
    fputs("\(label) frame sampling failed: no visible windows for pid \(pid)\n", stderr)
    exit(1)
}
