import Foundation

/// Codex Desktop 状态刷新的节奏。旧实现用 1 秒固定定时器撞节流墙（大部分
/// 唤醒直接空转），这里让定时器本身按同一套间隔自排程：刷新频率不变，
/// 进程唤醒次数在空闲时降到原来的 1/8。
package enum CodexRefreshCadencePolicy {
    package static let expandedInterval: TimeInterval = 2.0
    package static let recentActivityInterval: TimeInterval = 2.5
    package static let idleInterval: TimeInterval = 8.0
    package static let recentActivityWindow: TimeInterval = 45

    package static func interval(
        sessions: [AgentSession],
        isExpanded: Bool,
        now: Date = Date()
    ) -> TimeInterval {
        if isExpanded {
            return expandedInterval
        }
        let hasRecentOrActiveDesktop = sessions.contains { session in
            session.source == .codexDesktop &&
                (session.status.isActiveVisual || now.timeIntervalSince(session.updatedAt) < recentActivityWindow)
        }
        return hasRecentOrActiveDesktop ? recentActivityInterval : idleInterval
    }
}

/// 会话老化刷新的按需调度。旧实现每 15 秒固定唤醒；实际上只有两类时刻需要
/// 唤醒：面板展开时刷新相对时间文本（保持 15 秒），以及某个会话跨过
/// 可见性边界（完成 2 分钟、失败 10 分钟、空闲 45 秒、活跃 2 小时）的精确
/// 时刻。折叠且没有会话临近边界时完全不唤醒。
package enum SessionAgingSchedulePolicy {
    package static let expandedRefreshInterval: TimeInterval = 15
    package static let minimumDelay: TimeInterval = 1

    package static func nextRefreshDelay(
        sessions: [AgentSession],
        isExpanded: Bool,
        now: Date = Date()
    ) -> TimeInterval? {
        guard !sessions.isEmpty else { return nil }
        var delays: [TimeInterval] = []
        if isExpanded {
            delays.append(expandedRefreshInterval)
        }
        for session in sessions {
            if let remaining = hideDelay(for: session, now: now) {
                delays.append(remaining)
            }
        }
        guard let next = delays.min() else { return nil }
        return max(minimumDelay, next)
    }

    /// 该会话距离「从面板消失」还剩多久；nil 表示没有时间驱动的转换点
    /// （已经不可见，或有待审批——审批的消失由解决事件驱动）。
    package static func hideDelay(for session: AgentSession, now: Date = Date()) -> TimeInterval? {
        guard DashboardSessionPolicy.isVisible(session, now: now) else { return nil }
        if let approval = session.approval, !approval.isExpired {
            return nil
        }
        let age = now.timeIntervalSince(session.updatedAt)
        let hideAfter: TimeInterval
        switch session.status {
        case .done:
            hideAfter = DashboardSessionPolicy.completedHideAfter
        case .failed:
            hideAfter = DashboardSessionPolicy.failedHideAfter
        case .idle:
            hideAfter = DashboardSessionPolicy.idleHideAfter
        case .thinking, .runningTool, .waitingApproval, .waitingQuestion:
            hideAfter = DashboardSessionPolicy.activeHideAfter
        }
        return hideAfter - age
    }
}

/// 展开面板离开鼠标后自动收起。旧实现 0.22 秒轮询鼠标位置 30 tick；
/// 事件驱动版由 NSTrackingArea 进出事件触发，宽限时长保持一致。
package enum IslandAutoCollapsePolicy {
    package static let graceDuration: TimeInterval = 6.6
}
