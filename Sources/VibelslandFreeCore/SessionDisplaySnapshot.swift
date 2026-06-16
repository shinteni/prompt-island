import Foundation

package struct SessionDisplaySnapshot: Equatable {
    package struct Signal: Equatable, Identifiable {
        package var id: String { "\(symbol)-\(text)" }
        package var symbol: String
        package var text: String

        package init(symbol: String, text: String) {
            self.symbol = symbol
            self.text = text
        }
    }

    package var title: String
    package var primaryLine: String
    package var secondaryLine: String?
    package var statusText: String
    package var confidence: DisplayConfidence
    package var signals: [Signal]

    package init(session: AgentSession, language: AppLanguage = .chinese) {
        let project = Self.projectTitle(for: session)
        title = "\(project) · \(session.source.displayName)"
        confidence = Self.confidence(for: session)
        statusText = Self.statusText(for: session, confidence: confidence, language: language)
        signals = Self.signals(for: session, language: language)

        if let approval = session.approval, !approval.isExpired {
            primaryLine = "\(Self.approvalLabel(language))\(Self.separator(language))\(Self.clean(approval.detail.isEmpty ? approval.tool : approval.detail, limit: 86))"
            secondaryLine = session.lastUserMessage.map { "\(Self.youLabel(language))\(Self.separator(language))\(Self.clean($0, limit: 86))" }
            return
        }

        if session.status == .runningTool,
           let tool = Self.latestTool(from: session) {
            primaryLine = "\(Self.toolLabel(language))\(Self.separator(language))\(tool)"
            secondaryLine = Self.conversationLine(for: session, preferAssistant: true, language: language)
            return
        }

        if session.status == .failed {
            primaryLine = "\(Self.errorLabel(language))\(Self.separator(language))\(Self.latestActivityText(from: session) ?? Self.taskFailedFallback(language))"
            secondaryLine = Self.conversationLine(for: session, preferAssistant: true, language: language)
            return
        }

        if let message = session.lastAssistantMessage, !message.isEmpty {
            primaryLine = "AI\(Self.separator(language))\(Self.clean(message, limit: 110))"
            secondaryLine = session.lastUserMessage.map { "\(Self.youLabel(language))\(Self.separator(language))\(Self.clean($0, limit: 92))" }
            return
        }

        if let message = session.lastUserMessage, !message.isEmpty {
            primaryLine = "\(Self.youLabel(language))\(Self.separator(language))\(Self.clean(message, limit: 110))"
            secondaryLine = Self.latestActivityText(from: session).map { "\(Self.activityLabel(language))\(Self.separator(language))\($0)" }
            return
        }

        if let activity = Self.latestActivityText(from: session) {
            primaryLine = "\(Self.activityLabel(language))\(Self.separator(language))\(activity)"
            secondaryLine = Self.workspaceLine(for: session)
            return
        }

        primaryLine = statusText
        secondaryLine = Self.workspaceLine(for: session)
    }

    private static func confidence(for session: AgentSession) -> DisplayConfidence {
        if let approval = session.approval, !approval.isExpired {
            return .realtime
        }
        if session.source == .codexDesktop,
           session.activity.contains(where: { $0.title == "审批已返回" || $0.title == "审批已处理" }) {
            return .realtime
        }
        if session.lastAssistantMessage != nil || session.lastUserMessage != nil || session.usage != nil {
            return .transcript
        }
        if !session.activity.isEmpty {
            return .event
        }
        return .inferred
    }

    private static func statusText(for session: AgentSession, confidence: DisplayConfidence, language: AppLanguage) -> String {
        if let approval = session.approval {
            if approval.resolutionState != .pending {
                return approval.resolutionState.title(language: language)
            }
            if approval.isResolving {
                return returningApprovalText(language)
            }
            if approval.isExpired {
                return approvalFallbackText(language)
            }
            return ApprovalResolutionState.pending.title(language: language)
        }
        if confidence == .inferred {
            switch session.status {
            case .done:
                return maybeDoneText(language)
            case .thinking, .runningTool:
                return recentActivityText(language)
            case .failed:
                return maybeErrorText(language)
            default:
                break
            }
        }
        if session.status == .failed,
           let latest = latestActivityText(from: session) {
            if latest.contains("拒绝") {
                return ApprovalResolutionState.declined.title(language: language)
            }
            if latest.contains("超时") {
                return ApprovalResolutionState.timedOut.title(language: language)
            }
            if latest.contains("回退") {
                return approvalFallbackText(language)
            }
        }
        return session.status.displayName(language: language)
    }

    private static func signals(for session: AgentSession, language: AppLanguage) -> [Signal] {
        var result: [Signal] = []
        if let tool = latestTool(from: session) {
            result.append(Signal(symbol: "wrench.and.screwdriver", text: tool))
        }
        let activeSubagentCount = session.subagents.filter { $0.status.isActiveVisual }.count
        if activeSubagentCount > 0 {
            result.append(Signal(symbol: "person.2", text: subagentSignal(active: activeSubagentCount, total: session.subagents.count, language: language)))
        }
        if let usage = session.usage {
            result.append(Signal(symbol: "chart.line.uptrend.xyaxis", text: usage.shortText))
        }
        if result.isEmpty,
           let workspace = workspaceLine(for: session) {
            result.append(Signal(symbol: "folder", text: workspace))
        }
        return Array(result.prefix(3))
    }

    private static func projectTitle(for session: AgentSession) -> String {
        let candidates = [
            URL(fileURLWithPath: session.workspace).lastPathComponent,
            session.title,
            session.prompt,
            session.lastUserMessage ?? ""
        ]

        for candidate in candidates {
            let cleaned = clean(candidate, limit: 34)
            guard isMeaningfulTitle(cleaned, source: session.source) else { continue }
            return cleaned
        }
        return session.source.displayName
    }

    private static func isMeaningfulTitle(_ value: String, source: AgentSource) -> Bool {
        let lowercased = value.lowercased()
        guard !value.isEmpty else { return false }
        guard lowercased != source.displayName.lowercased(),
              lowercased != source.shortName.lowercased(),
              lowercased != ".claude",
              lowercased != ".codex",
              lowercased != "claude",
              lowercased != "codex",
              lowercased != "default",
              lowercased != NSUserName().lowercased(),
              !lowercased.hasPrefix("gpt-") else {
            return false
        }
        return true
    }

    private static func conversationLine(for session: AgentSession, preferAssistant: Bool, language: AppLanguage) -> String? {
        if preferAssistant,
           let message = session.lastAssistantMessage,
           !message.isEmpty {
            return "AI\(separator(language))\(clean(message, limit: 92))"
        }
        if let message = session.lastUserMessage, !message.isEmpty {
            return "\(youLabel(language))\(separator(language))\(clean(message, limit: 92))"
        }
        if let message = session.lastAssistantMessage, !message.isEmpty {
            return "AI\(separator(language))\(clean(message, limit: 92))"
        }
        return nil
    }

    private static func latestTool(from session: AgentSession) -> String? {
        session.activity.reversed().compactMap { item -> String? in
            let title = item.title
            guard title.contains("工具") || title.contains("修改") else { return nil }
            let raw = item.detail.isEmpty ? item.title : item.detail
            let text = clean(raw, limit: 36)
            return text.isEmpty ? nil : text
        }.first
    }

    private static func latestActivityText(from session: AgentSession) -> String? {
        session.activity.reversed().compactMap { item -> String? in
            guard !["token_count", "reasoning"].contains(item.title) else { return nil }
            let raw = item.detail.isEmpty ? item.title : "\(item.title) · \(item.detail)"
            let text = clean(raw, limit: 92)
            return text.isEmpty ? nil : text
        }.first
    }

    private static func workspaceLine(for session: AgentSession) -> String? {
        let workspace = session.workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else { return nil }
        let last = URL(fileURLWithPath: workspace).lastPathComponent
        guard isMeaningfulTitle(last, source: session.source) else { return nil }
        return clean(last, limit: 46)
    }

    private static func clean(_ value: String, limit: Int) -> String {
        let sanitized = DisplayTextSanitizer.sanitize(value)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sanitized.prefix(limit))
    }

    private static func approvalLabel(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Approval"
        case .japanese: "承認"
        case .chinese: "审批"
        }
    }

    private static func toolLabel(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Tool"
        case .japanese: "ツール"
        case .chinese: "工具"
        }
    }

    private static func errorLabel(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Error"
        case .japanese: "エラー"
        case .chinese: "出错"
        }
    }

    private static func activityLabel(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Activity"
        case .japanese: "アクティビティ"
        case .chinese: "活动"
        }
    }

    private static func youLabel(_ language: AppLanguage) -> String {
        switch language {
        case .english: "You"
        case .japanese: "あなた"
        case .chinese: "你"
        }
    }

    private static func separator(_ language: AppLanguage) -> String {
        switch language {
        case .english: ": "
        case .japanese, .chinese: "："
        }
    }

    private static func taskFailedFallback(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Task did not complete normally"
        case .japanese: "タスクは正常に完了しませんでした"
        case .chinese: "任务未正常完成"
        }
    }

    private static func returningApprovalText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Returning approval"
        case .japanese: "承認を返送中"
        case .chinese: "正在返回审批"
        }
    }

    private static func approvalFallbackText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Approval fell back"
        case .japanese: "承認はフォールバック済み"
        case .chinese: "审批已回退"
        }
    }

    private static func maybeDoneText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Maybe done"
        case .japanese: "完了の可能性"
        case .chinese: "可能已完成"
        }
    }

    private static func recentActivityText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Recent activity"
        case .japanese: "最近のアクティビティ"
        case .chinese: "最近有活动"
        }
    }

    private static func maybeErrorText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Possible issue"
        case .japanese: "異常の可能性"
        case .chinese: "可能异常"
        }
    }

    private static func subagentSignal(active: Int, total: Int, language: AppLanguage) -> String {
        let value = active == total ? "\(active)" : "\(active)/\(total)"
        switch language {
        case .english:
            return active == 1 && total == 1 ? "1 subagent" : "\(value) subagents"
        case .japanese:
            return "\(value) サブエージェント"
        case .chinese:
            return "\(value) 子智能体"
        }
    }
}
