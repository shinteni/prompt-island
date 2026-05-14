import Foundation

package enum DashboardSessionPolicy {
    package static let minimumConfiguredVisibleSessions = 3
    package static let maximumVisibleSessions = 5
    package static let completedHideAfter: TimeInterval = 2 * 60
    package static let failedHideAfter: TimeInterval = 10 * 60
    package static let idleHideAfter: TimeInterval = 45
    package static let activeHideAfter: TimeInterval = 2 * 60 * 60

    package static func visibleSessions(
        from sessions: [AgentSession],
        excluding excludedID: AgentSession.ID? = nil,
        limit: Int = maximumVisibleSessions,
        now: Date = Date()
    ) -> [AgentSession] {
        let boundedLimit = max(0, min(limit, maximumVisibleSessions))
        guard boundedLimit > 0 else { return [] }

        let candidates = sessions
            .filter { session in
                session.id != excludedID && isVisible(session, now: now)
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        var result: [AgentSession] = []
        var usedSources = Set<AgentSource>()

        for session in candidates where !usedSources.contains(session.source) {
            result.append(session)
            usedSources.insert(session.source)
            if result.count == boundedLimit {
                return result
            }
        }

        for session in candidates where !result.contains(where: { $0.id == session.id }) {
            result.append(session)
            if result.count == boundedLimit {
                return result
            }
        }

        return result
    }

    package static func configuredVisibleSessionLimit(_ value: Int) -> Int {
        min(max(value, minimumConfiguredVisibleSessions), maximumVisibleSessions)
    }

    package static func isVisible(_ session: AgentSession, now: Date = Date()) -> Bool {
        if let approval = session.approval, !approval.isExpired {
            return true
        }

        let age = now.timeIntervalSince(session.updatedAt)
        if session.status.isActiveVisual {
            return age < activeHideAfter
        }
        switch session.status {
        case .done:
            return age < completedHideAfter
        case .failed:
            return age < failedHideAfter
        case .idle:
            return age < idleHideAfter
        case .thinking, .runningTool, .waitingApproval, .waitingQuestion:
            return age < activeHideAfter
        }
    }

    package static func hasActiveTask(in sessions: [AgentSession], now: Date = Date()) -> Bool {
        sessions.contains { session in
            guard isVisible(session, now: now) else { return false }
            if let approval = session.approval, !approval.isExpired {
                return true
            }
            return session.status.isActiveVisual
        }
    }

    package static func pendingApprovalSession(in sessions: [AgentSession]) -> AgentSession? {
        sessions.first { session in
            guard let approval = session.approval else { return false }
            return !approval.isExpired
        }
    }
}
