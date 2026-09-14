import Foundation
import Testing
@testable import VibelslandFreeCore

struct ClaudeDesktopSessionLinkTests {
    @Test func resolvesTheDesktopIDInsteadOfUsingTheCLIID() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("claude-link-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions/\(UUID())/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cliID = UUID().uuidString.lowercased()
        let desktopID = "local_\(UUID().uuidString.lowercased())"
        let metadata = directory.appendingPathComponent("\(desktopID).json")
        try JSONSerialization.data(withJSONObject: ["sessionId": desktopID, "cliSessionId": cliID])
            .write(to: metadata)
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: cliID, homeURL: home) == "claude://claude.ai/epitaxy/\(desktopID)")
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: cliID.uppercased(), homeURL: home) == "claude://claude.ai/epitaxy/\(desktopID)")
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: UUID().uuidString, homeURL: home) == nil)
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: "claude-/tmp/work", homeURL: home) == nil)
        try JSONSerialization.data(withJSONObject: ["sessionId": "local_invalid?prompt=bad", "cliSessionId": cliID]).write(to: metadata)
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: cliID, homeURL: home) == nil)
    }

    @Test func missingDesktopHistoryLeavesCLIAvailable() {
        #expect(ClaudeDesktopSessionLink.deepLink(forCLISessionID: UUID().uuidString,
            homeURL: URL(fileURLWithPath: "/nonexistent-claude-history")) == nil)
    }
}
