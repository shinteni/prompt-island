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
