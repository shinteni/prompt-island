import Foundation

package enum CodexThreadLinkPolicy {
    package static func threadID(for session: AgentSession) -> String? {
        switch session.source {
        case .codexDesktop:
            return explicitThreadID(session) ?? desktopThreadID(from: session.id)
        case .codexCli:
            return explicitThreadID(session) ?? uuidThreadID(from: session.id)
        case .claudeCode, .unknown:
            return nil
        }
    }

    package static func deepLink(for threadID: String) -> String {
        let encodedThreadID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID
        return "codex://threads/\(encodedThreadID)"
    }

    private static func explicitThreadID(_ session: AgentSession) -> String? {
        guard let threadID = session.threadID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !threadID.isEmpty else {
            return nil
        }
        return threadID
    }

    private static func desktopThreadID(from sessionID: String) -> String? {
        let prefix = "codex-desktop-"
        guard sessionID.hasPrefix(prefix) else { return nil }
        let threadID = String(sessionID.dropFirst(prefix.count))
        return threadID.isEmpty ? nil : threadID
    }

    private static func uuidThreadID(from sessionID: String) -> String? {
        UUID(uuidString: sessionID) == nil ? nil : sessionID
    }
}
