import Foundation

/// 多审批并存时的队列策略：排序、主审批选取、可见行数与队列卡片高度。
/// 队列卡片高度放在这里，是为了让 SwiftUI 布局和 IslandWindow 的窗口高度
/// 计算共用同一套数字，避免两处失同步。
package enum ApprovalQueuePolicy {
    package static let maximumVisibleRows = 3

    /// 队列卡片布局常量（与 ApprovalQueueCard 的实际布局一一对应）。
    package static let cardVerticalPadding: CGFloat = 10
    package static let headerHeight: CGFloat = 20
    package static let rowHeight: CGFloat = 44
    package static let elementSpacing: CGFloat = 6
    package static let overflowFooterHeight: CGFloat = 14

    /// 按发起时间从早到晚排序的待审批会话（未过期）。
    package static func queue(in sessions: [AgentSession]) -> [AgentSession] {
        sessions
            .filter { session in
                guard let approval = session.approval else { return false }
                return !approval.isExpired
            }
            .sorted { lhs, rhs in
                (lhs.approval?.createdAt ?? .distantFuture) < (rhs.approval?.createdAt ?? .distantFuture)
            }
    }

    package static func count(in sessions: [AgentSession]) -> Int {
        queue(in: sessions).count
    }

    /// 主审批 = 等待最久的那一个。
    package static func primarySession(in sessions: [AgentSession]) -> AgentSession? {
        queue(in: sessions).first
    }

    package static func visibleRows(in sessions: [AgentSession]) -> [AgentSession] {
        Array(queue(in: sessions).prefix(maximumVisibleRows))
    }

    package static func overflowCount(in sessions: [AgentSession]) -> Int {
        max(0, count(in: sessions) - maximumVisibleRows)
    }

    package static func cardHeight(rowCount: Int, overflowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let hasOverflow = overflowCount > 0
        let elementGaps = CGFloat(rowCount + (hasOverflow ? 1 : 0)) * elementSpacing
        var height = cardVerticalPadding * 2
        height += headerHeight
        height += CGFloat(rowCount) * rowHeight
        height += hasOverflow ? overflowFooterHeight : 0
        height += elementGaps
        return height
    }

    package static func cardHeight(in sessions: [AgentSession]) -> CGFloat {
        cardHeight(
            rowCount: visibleRows(in: sessions).count,
            overflowCount: overflowCount(in: sessions)
        )
    }
}
