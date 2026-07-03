import Foundation

/// 审批系统通知的纯逻辑：什么时候发、通知/动作标识符怎么编、动作怎么映射回审批决定。
/// UserNotifications 框架的调用留在界面层，这里保持可单测。
package enum ApprovalNotificationPolicy {
    package static let categoryIdentifier = "free.vibelsland.approval"
    package static let acceptActionIdentifier = "free.vibelsland.approval.accept"
    package static let declineActionIdentifier = "free.vibelsland.approval.decline"

    private static let notificationIdentifierPrefix = "free.vibelsland.approval.request."

    package static func notificationIdentifier(approvalID: String) -> String {
        notificationIdentifierPrefix + approvalID
    }

    package static func approvalID(fromNotificationIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(notificationIdentifierPrefix) else { return nil }
        let id = String(identifier.dropFirst(notificationIdentifierPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// 勿扰优先：用户开了勿扰就不打扰；已过期或已进入回传流程的审批不再通知。
    package static func shouldNotify(
        enabled: Bool,
        doNotDisturb: Bool,
        approval: ApprovalRequest
    ) -> Bool {
        guard enabled, !doNotDisturb else { return false }
        guard !approval.isExpired else { return false }
        return approval.resolutionState == .pending
    }

    /// 把通知动作映射回审批决定；只映射该审批实际支持的决定。
    package static func decision(
        forActionIdentifier identifier: String,
        approval: ApprovalRequest
    ) -> ApprovalDecision? {
        let decision: ApprovalDecision
        switch identifier {
        case acceptActionIdentifier:
            decision = .accept
        case declineActionIdentifier:
            decision = .decline
        default:
            return nil
        }
        return approval.supports(decision) ? decision : nil
    }

    /// 通知正文：优先命令详情，为空退回工具名，截断避免超长横幅。
    package static func body(for approval: ApprovalRequest, limit: Int = 140) -> String {
        let raw = approval.detail.isEmpty ? approval.tool : approval.detail
        let flattened = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }
}
