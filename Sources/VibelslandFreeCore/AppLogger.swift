import Foundation

package final class AppLogger: @unchecked Sendable {
    package static let shared = AppLogger()

    private let queue = DispatchQueue(label: "free.vibelsland.logger")
    private let fileURL: URL
    private let formatter: ISO8601DateFormatter
    private let homePath: String
    private let maxLogBytes: Int

    init(
        fileURL: URL = AppPaths.logURL,
        homePath: String = AppPaths.home.path,
        maxLogBytes: Int = 5 * 1024 * 1024
    ) {
        self.fileURL = fileURL
        self.homePath = homePath
        self.maxLogBytes = maxLogBytes
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    package func info(_ event: String, detail: String = "") {
        write(level: "info", event: event, detail: detail)
    }

    package func error(_ event: String, detail: String = "") {
        write(level: "error", event: event, detail: detail)
    }

    /// Blocks until every previously enqueued write has been flushed to disk.
    /// Intended for tests and shutdown; production logging stays asynchronous.
    package func flush() {
        queue.sync {}
    }

    /// Replaces the user's home directory prefix with `~` so that shared logs do
    /// not leak the macOS account name or absolute private project paths.
    /// The prefix is only collapsed at a path boundary, so `/Users/ann` never
    /// corrupts a longer sibling path such as `/Users/annette`.
    package static func redactHome(_ text: String, home: String) -> String {
        guard !home.isEmpty, text.contains(home) else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: home)
        let pattern = escaped + "(?=/|$|[\\s\"':,);\\]])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.replacingOccurrences(of: home + "/", with: "~/")
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "~")
    }

    private func write(level: String, event: String, detail: String) {
        let redactedDetail = Self.redactHome(detail, home: homePath)
        let line = "\(formatter.string(from: Date())) [\(level)] \(event) \(redactedDetail)\n"
        queue.async {
            do {
                try AppPaths.ensureRuntimeDirectories()
                self.rotateIfNeeded()
                try self.append(line)
            } catch {
                NSLog("VibelslandFree log failed: \(error.localizedDescription)")
            }
        }
    }

    /// When the active log reaches the size cap, move it aside to a single `.1`
    /// backup. Disk use therefore stays bounded at roughly twice the cap.
    private func rotateIfNeeded() {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size >= maxLogBytes else {
            return
        }
        let rotatedURL = fileURL.appendingPathExtension("1")
        try? manager.removeItem(at: rotatedURL)
        try? manager.moveItem(at: fileURL, to: rotatedURL)
    }

    private func append(_ line: String) throws {
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
