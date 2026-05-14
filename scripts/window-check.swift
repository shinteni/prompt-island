import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 7,
      let pid = Int32(CommandLine.arguments[1]),
      let minWidth = Double(CommandLine.arguments[2]),
      let maxWidth = Double(CommandLine.arguments[3]),
      let minHeight = Double(CommandLine.arguments[4]),
      let maxHeight = Double(CommandLine.arguments[5]) else {
    fputs("usage: window-check.swift <pid> <minWidth> <maxWidth> <minHeight> <maxHeight> <label>\n", stderr)
    exit(64)
}

let label = CommandLine.arguments[6]
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.compactMap { item -> (Double, Double, Double, Int)? in
    guard (item[kCGWindowOwnerPID as String] as? Int32) == pid,
          let bounds = item[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return nil
    }
    let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
    let layer = item[kCGWindowLayer as String] as? Int ?? 0
    guard alpha > 0.01, width > 4, height > 4 else {
        return nil
    }
    return (width, height, alpha, layer)
}

if windows.contains(where: { window in
    window.0 >= minWidth && window.0 <= maxWidth && window.1 >= minHeight && window.1 <= maxHeight
}) {
    print("\(label) window verification passed: \(windows)")
    exit(0)
}

fputs("\(label) window verification failed: visible windows for pid \(pid): \(windows)\n", stderr)
exit(1)
