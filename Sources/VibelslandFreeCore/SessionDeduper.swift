import Foundation

package enum SessionDeduper {
    package static func compact(
        _ sessions: [AgentSession],
        selectedSessionID: AgentSession.ID?
    ) -> (sessions: [AgentSession], selectedSessionID: AgentSession.ID?) {
        var compacted = sessions
        var selected = selectedSessionID

        for desktopID in sessions.filter({ $0.source == .codexDesktop }).map(\.id) {
            guard let desktop = compacted.first(where: { $0.id == desktopID }) else {
                continue
            }

            let shadows = compacted.filter { candidate in
                candidate.id != desktopID && isCodexShadow(candidate, of: desktop)
            }
            guard !shadows.isEmpty else { continue }

            var merged = desktop
            for shadow in shadows where isDuplicateCodexShadow(shadow, of: desktop) {
                merged = merge(desktop: merged, shadow: shadow)
            }

            let shadowIDs = Set(shadows.map(\.id))
            compacted.removeAll { shadowIDs.contains($0.id) }
            if let index = compacted.firstIndex(where: { $0.id == desktopID }) {
                compacted[index] = merged
            }
            if let selectedID = selected, shadowIDs.contains(selectedID) {
                selected = desktopID
            }
        }

        return (compacted, selected)
    }

    private static func isCodexShadow(_ candidate: AgentSession, of desktop: AgentSession) -> Bool {
        guard candidate.source == .codexCli,
              desktop.source == .codexDesktop,
              sameWorkspace(candidate.workspace, desktop.workspace) else {
            return false
        }

        let interval = abs(candidate.updatedAt.timeIntervalSince(desktop.updatedAt))
        if interval > 1_800 {
            return isDesktopDerivedCodexStartSource(candidate.codexSessionStartSource)
                && isNestedCodexCLIShadow(candidate, of: desktop)
        }

        if isDuplicateCodexShadow(candidate, of: desktop) {
            return true
        }

        return isNestedCodexCLIShadow(candidate, of: desktop)
    }

    private static func isDuplicateCodexShadow(_ candidate: AgentSession, of desktop: AgentSession) -> Bool {
        sameNonEmpty(candidate.lastUserMessage, desktop.lastUserMessage)
            || sameNonEmpty(candidate.lastAssistantMessage, desktop.lastAssistantMessage)
            || sameNonEmpty(latestToolText(candidate), latestToolText(desktop))
            || sameDisplayLine(candidate, desktop)
    }

    private static func isNestedCodexCLIShadow(_ candidate: AgentSession, of desktop: AgentSession) -> Bool {
        guard candidate.source == .codexCli,
              desktop.source == .codexDesktop,
              candidate.approval == nil,
              candidate.status != .waitingApproval else {
            return false
        }

        return desktop.status != .idle && looksLikeNestedCodexInvocation(candidate)
    }

    private static func merge(desktop: AgentSession, shadow: AgentSession) -> AgentSession {
        var result = desktop
        result.updatedAt = max(desktop.updatedAt, shadow.updatedAt)
        result.status = mergedStatus(desktop.status, shadow.status, desktopUpdatedAt: desktop.updatedAt, shadowUpdatedAt: shadow.updatedAt)
        result.lastUserMessage = nonEmpty(desktop.lastUserMessage) ?? nonEmpty(shadow.lastUserMessage)
        result.lastAssistantMessage = nonEmpty(desktop.lastAssistantMessage) ?? nonEmpty(shadow.lastAssistantMessage)
        result.usage = desktop.usage ?? shadow.usage
        result.approval = desktop.approval ?? shadow.approval
        result.question = desktop.question ?? shadow.question
        result.activity = mergedActivities(desktop.activity + shadow.activity)
        return result
    }

    private static func mergedStatus(
        _ desktop: SessionStatus,
        _ shadow: SessionStatus,
        desktopUpdatedAt: Date,
        shadowUpdatedAt: Date
    ) -> SessionStatus {
        if desktop == .waitingApproval || shadow == .waitingApproval {
            return .waitingApproval
        }
        if desktop == .failed || shadow == .failed {
            return .failed
        }
        if shadowUpdatedAt > desktopUpdatedAt,
           shadow == .runningTool || shadow == .thinking {
            return shadow
        }
        if desktop == .runningTool || desktop == .thinking {
            return desktop
        }
        if desktop == .done || shadow == .done {
            return .done
        }
        return desktop
    }

    private static func mergedActivities(_ activities: [ActivityItem]) -> [ActivityItem] {
        var seen = Set<String>()
        let filtered = activities
            .sorted { $0.date < $1.date }
            .filter { item in
                let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = "\(item.symbol)|\(item.title)|\(detail)"
                return seen.insert(key).inserted
            }
        return Array(filtered.suffix(8))
    }

    package static func sameWorkspace(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedPath(lhs)
        let right = normalizedPath(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return false
        }
        return left == right ||
            isDescendant(left, of: right) ||
            isDescendant(right, of: left)
    }

    private static func sameDisplayLine(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let left = SessionDisplaySnapshot(session: lhs)
        let right = SessionDisplaySnapshot(session: rhs)
        return sameNonEmpty(left.primaryLine, right.primaryLine)
            || sameNonEmpty(left.title, right.title)
    }

    private static func latestToolText(_ session: AgentSession) -> String? {
        session.activity.reversed().compactMap { item -> String? in
            guard item.title.contains("工具") || item.title.contains("修改") else { return nil }
            return item.detail.isEmpty ? item.title : item.detail
        }.first
    }

    private static func looksLikeNestedCodexInvocation(_ session: AgentSession) -> Bool {
        if isDesktopDerivedCodexStartSource(session.codexSessionStartSource) {
            return true
        }

        return session.activity.contains { item in
            let title = normalizeText(item.title)
            let detail = normalizeText(item.detail)
            return title.hasPrefix("call_") ||
                title.contains("subagent") ||
                detail.contains("内部 cli") ||
                detail.contains("internal cli") ||
                detail.contains("subagent")
        }
    }

    private static func isDesktopDerivedCodexStartSource(_ value: String?) -> Bool {
        guard let value = nonEmpty(value) else {
            return false
        }
        let token = normalizeText(value)
        return token.contains("desktop") ||
            token.contains("subagent") ||
            token.contains("internal") ||
            token.contains("nested") ||
            token.contains("thread_spawn")
    }

    private static func sameNonEmpty(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = nonEmpty(lhs),
              let rhs = nonEmpty(rhs) else {
            return false
        }
        return normalizeText(lhs) == normalizeText(rhs)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedPath(_ path: String) -> String {
        NSString(string: path)
            .expandingTildeInPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDescendant(_ child: String, of parent: String) -> Bool {
        let normalizedParent = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        guard !normalizedParent.isEmpty else { return false }
        return child.hasPrefix(normalizedParent + "/")
    }
}
