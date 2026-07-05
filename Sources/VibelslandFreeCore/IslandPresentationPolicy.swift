import CoreGraphics
import Foundation

package enum IslandPresentationMode: Equatable {
    case idleMini
    case compactTask
    case expanded
}

package enum IslandPresentationPolicy {
    package static let idleMiniDiameter: CGFloat = 34
    package static let compactTaskSize = CGSize(width: 244, height: 42)

    /// 启动亮相：应用启动后的一段时间内即使空闲也显示浮岛本体（idle-mini），
    /// 让用户确认应用已经正确启动；到期后按常规策略隐藏。
    package static let launchPresenceDuration: TimeInterval = 8

    package static func isLaunchPresenceActive(until deadline: Date?, now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }

    package static func mode(
        sessions: [AgentSession],
        isExpanded: Bool,
        now: Date = Date()
    ) -> IslandPresentationMode {
        if isExpanded {
            return .expanded
        }
        return DashboardSessionPolicy.hasActiveTask(in: sessions, now: now) ? .compactTask : .idleMini
    }

    package static func compactSize(
        sessions: [AgentSession],
        now: Date = Date()
    ) -> CGSize {
        mode(sessions: sessions, isExpanded: false, now: now) == .idleMini
            ? CGSize(width: idleMiniDiameter, height: idleMiniDiameter)
            : compactTaskSize
    }

    package static func isIdleMiniPresentation(
        sessions: [AgentSession],
        isExpanded: Bool,
        now: Date = Date()
    ) -> Bool {
        mode(sessions: sessions, isExpanded: isExpanded, now: now) == .idleMini
    }
}
