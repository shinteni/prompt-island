import Foundation

package enum ClaudeDesktopSessionLink {
    private struct Record: Decodable {
        var sessionId: String
        var cliSessionId: String?
    }

    /// Desktop IDs differ from the CLI IDs supplied by hooks. Read only on a card click.
    package static func deepLink(forCLISessionID sessionID: String, homeURL: URL = AppPaths.home) -> String? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        let root = homeURL.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let manager = FileManager.default
        guard let accounts = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for account in accounts where UUID(uuidString: account.lastPathComponent) != nil {
            let organizations = (try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? []
            for organization in organizations where UUID(uuidString: organization.lastPathComponent) != nil {
                let files = (try? manager.contentsOfDirectory(at: organization, includingPropertiesForKeys: nil)) ?? []
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file),
                          let record = try? JSONDecoder().decode(Record.self, from: data),
                          record.cliSessionId?.lowercased() == sessionID.lowercased(),
                          record.sessionId == file.deletingPathExtension().lastPathComponent,
                          UUID(uuidString: String(record.sessionId.dropFirst(6))) != nil else { continue }
                    return "claude://claude.ai/epitaxy/\(record.sessionId)"
                }
            }
        }
        return nil
    }
}
