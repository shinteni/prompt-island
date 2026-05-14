import Foundation

package struct IslandLayoutSignature: Equatable {
    package var isExpanded: Bool
    package var position: IslandPosition
    package var presentationMode: IslandPresentationMode
    package var hasHealthWarning: Bool
    package var pendingApprovalID: AgentSession.ID?
    package var visibleSessionCount: Int
    package var isShowingApprovalDetail: Bool

    package init(
        sessions: [AgentSession],
        healthChecks: [HealthCheckItem],
        isExpanded: Bool,
        isApprovalDetailVisible: Bool,
        maxVisibleSessions: Int,
        position: IslandPosition,
        now: Date = Date()
    ) {
        let pendingApproval = DashboardSessionPolicy.pendingApprovalSession(in: sessions)
        let configuredLimit = DashboardSessionPolicy.configuredVisibleSessionLimit(maxVisibleSessions)
        self.isExpanded = isExpanded
        self.position = position
        self.presentationMode = IslandPresentationPolicy.mode(
            sessions: sessions,
            isExpanded: isExpanded,
            now: now
        )
        self.hasHealthWarning = healthChecks.contains { $0.status == .needsAction }
        self.pendingApprovalID = pendingApproval?.id
        self.visibleSessionCount = DashboardSessionPolicy.visibleSessions(
            from: sessions,
            excluding: pendingApproval?.id,
            limit: pendingApproval == nil ? configuredLimit : max(0, configuredLimit - 1),
            now: now
        ).count
        self.isShowingApprovalDetail = isApprovalDetailVisible && pendingApproval != nil
    }
}
