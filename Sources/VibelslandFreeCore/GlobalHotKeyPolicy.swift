import Foundation

package enum GlobalHotKeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleIsland
    case jumpToApproval

    package var id: String { rawValue }

    /// Carbon RegisterEventHotKey 使用的稳定 ID，注册与回调之间靠它对应。
    package var carbonHotKeyID: UInt32 {
        switch self {
        case .toggleIsland: 1
        case .jumpToApproval: 2
        }
    }

    /// Carbon 虚拟键码（kVK_ANSI_*）。
    package var keyCode: UInt32 {
        switch self {
        case .toggleIsland: 34 // kVK_ANSI_I
        case .jumpToApproval: 0 // kVK_ANSI_A
        }
    }

    /// Carbon 修饰键掩码：controlKey(0x1000) + optionKey(0x0800)。
    /// 选 ⌃⌥ 组合是因为它极少与系统或常见应用快捷键冲突。
    package var carbonModifiers: UInt32 {
        0x1000 | 0x0800
    }

    package var displayShortcut: String {
        switch self {
        case .toggleIsland: "⌃⌥I"
        case .jumpToApproval: "⌃⌥A"
        }
    }
}

package enum GlobalHotKeyPolicy {
    package static func actions(enabled: Bool) -> [GlobalHotKeyAction] {
        enabled ? GlobalHotKeyAction.allCases : []
    }

    package static func action(forHotKeyID id: UInt32) -> GlobalHotKeyAction? {
        GlobalHotKeyAction.allCases.first { $0.carbonHotKeyID == id }
    }

    /// 跳转目标：最早发起且仍未过期的审批所在会话。
    package static func approvalTargetSessionID(in sessions: [AgentSession]) -> AgentSession.ID? {
        sessions
            .filter { session in
                guard let approval = session.approval else { return false }
                return !approval.isExpired
            }
            .min { lhs, rhs in
                (lhs.approval?.createdAt ?? .distantFuture) < (rhs.approval?.createdAt ?? .distantFuture)
            }?
            .id
    }
}
