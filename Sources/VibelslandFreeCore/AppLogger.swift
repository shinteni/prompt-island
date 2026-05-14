import Foundation

package final class AppLogger: @unchecked Sendable {
    package static let shared = AppLogger()

    private let queue = DispatchQueue(label: "free.vibelsland.logger")
    private let fileURL: URL
    private let formatter: ISO8601DateFormatter

    init(fileURL: URL = AppPaths.logURL) {
        self.fileURL = fileURL
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    package func info(_ event: String, detail: String = "") {
        write(level: "info", event: event, detail: detail)
    }

    package func error(_ event: String, detail: String = "") {
        write(level: "error", event: event, detail: detail)
    }

    private func write(level: String, event: String, detail: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(event) \(detail)\n"
        queue.async {
            do {
                try AppPaths.ensureRuntimeDirectories()
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    let handle = try FileHandle(forWritingTo: self.fileURL)
                    try handle.seekToEnd()
                    if let data = line.data(using: .utf8) {
                        try handle.write(contentsOf: data)
                    }
                    try handle.close()
                } else {
                    try line.write(to: self.fileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                NSLog("VibelslandFree log failed: \(error.localizedDescription)")
            }
        }
    }
}
