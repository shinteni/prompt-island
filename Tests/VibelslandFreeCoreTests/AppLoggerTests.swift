import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct AppLoggerTests {
    @Test func testRedactHomeCollapsesPrefixAtPathBoundaries() {
        let home = "/Users/ann"
        XCTAssertEqual(
            AppLogger.redactHome("/Users/ann/.claude/settings.json", home: home),
            "~/.claude/settings.json"
        )
        // Path embedded in a larger message with a trailing space.
        XCTAssertEqual(
            AppLogger.redactHome("open /Users/ann/code/proj failed", home: home),
            "open ~/code/proj failed"
        )
        // Path that ends exactly at the home directory.
        XCTAssertEqual(AppLogger.redactHome("cwd=/Users/ann", home: home), "cwd=~")
        // Multiple occurrences are all collapsed.
        XCTAssertEqual(
            AppLogger.redactHome("/Users/ann/a -> /Users/ann/b", home: home),
            "~/a -> ~/b"
        )
    }

    @Test func testRedactHomeDoesNotCorruptSimilarSiblingPaths() {
        let home = "/Users/ann"
        // A longer account name must stay intact (no boundary after `ann`).
        XCTAssertEqual(
            AppLogger.redactHome("/Users/annette/secret", home: home),
            "/Users/annette/secret"
        )
    }

    @Test func testRedactHomeIsNoOpWhenAbsentOrHomeEmpty() {
        XCTAssertEqual(AppLogger.redactHome("no path here", home: "/Users/ann"), "no path here")
        XCTAssertEqual(AppLogger.redactHome("/Users/ann/x", home: ""), "/Users/ann/x")
    }

    @Test func testLogRotationBoundsSizeAndKeepsOneBackup() throws {
        let manager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibelsland-logger-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("app.log")
        let cap = 512
        let logger = AppLogger(fileURL: logURL, homePath: "/Users/ann", maxLogBytes: cap)

        for index in 0..<300 {
            logger.info("event.\(index)", detail: "/Users/ann/path/component/\(index)")
        }
        logger.flush()

        // Rotation must have produced exactly one backup file.
        let rotatedURL = logURL.appendingPathExtension("1")
        XCTAssertTrue(manager.fileExists(atPath: rotatedURL.path))

        // The active log stays bounded near the cap (cap + at most one line).
        let activeSize = ((try? manager.attributesOfItem(atPath: logURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertTrue(activeSize < cap * 2)

        // Home paths are redacted in the persisted log content.
        let content = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(content.contains("/Users/ann"))
        XCTAssertTrue(content.contains("~/path/component"))
    }
}
