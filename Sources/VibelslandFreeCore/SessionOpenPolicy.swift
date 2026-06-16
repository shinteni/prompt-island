import Foundation

package enum SessionOpenAction: Equatable {
    case selectOnly
    case openCodexThread(threadID: String, logNamespace: String, errorMessage: String)
    case focusClaudeCodeTerminal(sessionID: String?)
    case focusApplication(AgentSource)
}

package enum SessionOpenPolicy {
    package static func action(for session: AgentSession, language: AppLanguage = .chinese) -> SessionOpenAction {
        switch session.source {
        case .unknown:
            return .selectOnly
        case .codexDesktop:
            if let threadID = CodexThreadLinkPolicy.threadID(for: session) {
                return .openCodexThread(
                    threadID: threadID,
                    logNamespace: "codex.desktop",
                    errorMessage: codexDesktopOpenError(language)
                )
            }
            return .focusApplication(.codexDesktop)
        case .codexCli:
            if let threadID = CodexThreadLinkPolicy.threadID(for: session) {
                return .openCodexThread(
                    threadID: threadID,
                    logNamespace: "codex.cli",
                    errorMessage: codexCliOpenError(language)
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

    private static func codexDesktopOpenError(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Could not jump to the Codex conversation"
        case .japanese: "Codex の会話へ移動できません"
        case .chinese: "无法跳转到 Codex 对话"
        }
    }

    private static func codexCliOpenError(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Could not jump to the Codex CLI session"
        case .japanese: "Codex CLI セッションへ移動できません"
        case .chinese: "无法跳转到 Codex CLI 会话"
        }
    }
}
