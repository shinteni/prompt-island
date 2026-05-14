import Foundation

package enum SessionOpenAction: Equatable {
    case selectOnly
    case openCodexThread(threadID: String, logNamespace: String, errorMessage: String)
    case focusClaudeCodeTerminal(sessionID: String?)
    case focusApplication(AgentSource)
}

package enum SessionOpenPolicy {
    package static func action(for session: AgentSession) -> SessionOpenAction {
        switch session.source {
        case .unknown:
            return .selectOnly
        case .codexDesktop:
            if let threadID = CodexThreadLinkPolicy.threadID(for: session) {
                return .openCodexThread(
                    threadID: threadID,
                    logNamespace: "codex.desktop",
                    errorMessage: "无法跳转到 Codex 对话"
                )
            }
            return .focusApplication(.codexDesktop)
        case .codexCli:
            if let threadID = CodexThreadLinkPolicy.threadID(for: session) {
                return .openCodexThread(
                    threadID: threadID,
                    logNamespace: "codex.cli",
                    errorMessage: "无法跳转到 Codex CLI 会话"
                )
            }
            return .focusApplication(.codexCli)
        case .claudeCode:
            return .focusClaudeCodeTerminal(sessionID: claudeCodeSessionID(for: session))
        }
    }

    package static func claudeCodeSessionID(for session: AgentSession) -> String? {
        UUID(uuidString: session.id) == nil ? nil : session.id
    }
}
