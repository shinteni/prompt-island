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

    package init(session: AgentSession) {
        let project = Self.projectTitle(for: session)
        title = "\(project) · \(session.source.displayName)"
        confidence = Self.confidence(for: session)
        statusText = Self.statusText(for: session, confidence: confidence)
        signals = Self.signals(for: session)

        if let approval = session.approval, !approval.isExpired {
            primaryLine = "审批：\(Self.clean(approval.detail.isEmpty ? approval.tool : approval.detail, limit: 86))"
            secondaryLine = session.lastUserMessage.map { "你：\(Self.clean($0, limit: 86))" }
            return
        }

        if session.status == .runningTool,
           let tool = Self.latestTool(from: session) {
            primaryLine = "工具：\(tool)"
            secondaryLine = Self.conversationLine(for: session, preferAssistant: true)
            return
        }

        if session.status == .failed {
            primaryLine = "出错：\(Self.latestActivityText(from: session) ?? "任务未正常完成")"
            secondaryLine = Self.conversationLine(for: session, preferAssistant: true)
            return
        }

        if let message = session.lastAssistantMessage, !message.isEmpty {
            primaryLine = "AI：\(Self.clean(message, limit: 110))"
            secondaryLine = session.lastUserMessage.map { "你：\(Self.clean($0, limit: 92))" }
            return
        }

        if let message = session.lastUserMessage, !message.isEmpty {
            primaryLine = "你：\(Self.clean(message, limit: 110))"
            secondaryLine = Self.latestActivityText(from: session).map { "活动：\($0)" }
            return
        }

        if let activity = Self.latestActivityText(from: session) {
            primaryLine = "活动：\(activity)"
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

    private static func statusText(for session: AgentSession, confidence: DisplayConfidence) -> String {
        if let approval = session.approval {
            if approval.resolutionState != .pending {
                return approval.resolutionState.title
            }
            if approval.isResolving {
                return "正在返回审批"
            }
            if approval.isExpired {
                return "审批已回退"
            }
            return "等待审批"
        }
        if confidence == .inferred {
            switch session.status {
            case .done:
                return "可能已完成"
            case .thinking, .runningTool:
                return "最近有活动"
            case .failed:
                return "可能异常"
            default:
                break
            }
        }
        if session.status == .failed,
           let latest = latestActivityText(from: session) {
            if latest.contains("拒绝") {
                return "已拒绝"
            }
            if latest.contains("回退") || latest.contains("超时") {
                return "已回退"
            }
        }
        return session.status.displayName
    }

    private static func signals(for session: AgentSession) -> [Signal] {
        var result: [Signal] = []
        if let tool = latestTool(from: session) {
            result.append(Signal(symbol: "wrench.and.screwdriver", text: tool))
        }
        let activeSubagentCount = session.subagents.filter { $0.status.isActiveVisual }.count
        if activeSubagentCount > 0 {
            let text = activeSubagentCount == session.subagents.count
                ? "\(activeSubagentCount) 子智能体"
                : "\(activeSubagentCount)/\(session.subagents.count) 子智能体"
            result.append(Signal(symbol: "person.2", text: text))
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

    private static func conversationLine(for session: AgentSession, preferAssistant: Bool) -> String? {
        if preferAssistant,
           let message = session.lastAssistantMessage,
           !message.isEmpty {
            return "AI：\(clean(message, limit: 92))"
        }
        if let message = session.lastUserMessage, !message.isEmpty {
            return "你：\(clean(message, limit: 92))"
        }
        if let message = session.lastAssistantMessage, !message.isEmpty {
            return "AI：\(clean(message, limit: 92))"
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
}
