import Foundation
import SwiftUI

package enum AgentSource: String, Codable, CaseIterable, Identifiable {
    case claudeCode
    case codexCli
    case codexDesktop
    case unknown

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codexCli: "Codex CLI"
        case .codexDesktop: "Codex Desktop"
        case .unknown: "Unknown"
        }
    }

    package var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codexCli: "Codex"
        case .codexDesktop: "Codex App"
        case .unknown: "Agent"
        }
    }

    package var color: Color {
        switch self {
        case .claudeCode: Color(red: 0.86, green: 0.42, blue: 0.24)
        case .codexCli: Color(red: 0.20, green: 0.72, blue: 0.42)
        case .codexDesktop: Color(red: 0.34, green: 0.60, blue: 0.92)
        case .unknown: Color.gray
        }
    }

    package var applicationBundleIdentifier: String? {
        switch self {
        case .claudeCode: "com.anthropic.claudefordesktop"
        case .codexCli, .codexDesktop: "com.openai.codex"
        case .unknown: nil
        }
    }

    package var fallbackApplicationPath: String? {
        switch self {
        case .claudeCode: "/Applications/Claude.app"
        case .codexCli, .codexDesktop: "/Applications/Codex.app"
        case .unknown: nil
        }
    }

    package init(hookSource: String?) {
        switch hookSource?.lowercased() {
        case "claude", "claudecode", "claude_code", "claude-code":
            self = .claudeCode
        case "codex":
            self = .codexCli
        case "codex-desktop", "codexdesktop", "codex_app", "codex-app":
            self = .codexDesktop
        default:
            self = .unknown
        }
    }
}

package enum AgentEventKind: String, Codable, CaseIterable {
    case session
    case prompt
    case tool
    case approval
    case notification
    case subagent
    case status
}

package enum SessionStatus: String, Codable, CaseIterable {
    case idle
    case thinking
    case runningTool
    case waitingApproval
    case waitingQuestion
    case done
    case failed

    package var displayName: String {
        switch self {
        case .idle: "空闲"
        case .thinking: "思考中"
        case .runningTool: "执行工具"
        case .waitingApproval: "等待审批"
        case .waitingQuestion: "等待输入"
        case .done: "已完成"
        case .failed: "出错"
        }
    }

    package var symbolName: String {
        switch self {
        case .idle: "moon"
        case .thinking: "sparkles"
        case .runningTool: "terminal"
        case .waitingApproval: "hand.raised"
        case .waitingQuestion: "questionmark.bubble"
        case .done: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    package var isActiveVisual: Bool {
        switch self {
        case .thinking, .runningTool, .waitingApproval, .waitingQuestion:
            return true
        case .idle, .done, .failed:
            return false
        }
    }
}

package enum ApprovalDecision: String, Codable, CaseIterable {
    case accept
    case acceptForSession
    case decline
    case cancel

    package var title: String {
        switch self {
        case .accept: "允许一次"
        case .acceptForSession: "本轮始终允许"
        case .decline: "拒绝"
        case .cancel: "取消任务"
        }
    }
}

package enum ApprovalResolutionState: String, Codable, CaseIterable, Equatable {
    case pending
    case resolving
    case accepted
    case declined
    case cancelled
    case timedOut
    case sendFailed
    case disconnected

    package var title: String {
        switch self {
        case .pending: "等待审批"
        case .resolving: "正在返回审批"
        case .accepted: "已允许"
        case .declined: "已拒绝"
        case .cancelled: "已取消"
        case .timedOut: "审批已超时"
        case .sendFailed: "回传失败"
        case .disconnected: "连接断开"
        }
    }

    package var isTerminal: Bool {
        switch self {
        case .accepted, .declined, .cancelled, .timedOut, .sendFailed, .disconnected:
            return true
        case .pending, .resolving:
            return false
        }
    }
}

package enum DisplayConfidence: String, Codable, CaseIterable, Equatable {
    case realtime
    case event
    case transcript
    case inferred

    package var title: String {
        switch self {
        case .realtime: "实时连接"
        case .event: "Hook 事件"
        case .transcript: "转录推断"
        case .inferred: "时间推断"
        }
    }
}

package enum HealthCheckStatus: String, Codable, CaseIterable, Equatable {
    case normal
    case needsAction
    case disabled

    package var title: String {
        switch self {
        case .normal: "正常"
        case .needsAction: "需要处理"
        case .disabled: "未启用"
        }
    }

    package var isActionable: Bool {
        self == .needsAction
    }

    package var isDisabled: Bool {
        self == .disabled
    }

    package var isNormal: Bool {
        self == .normal
    }
}

package struct HealthCheckItem: Identifiable, Equatable {
    package var id: String
    package var name: String
    package var status: HealthCheckStatus
    package var detail: String
    package var suggestedAction: String

    package init(id: String, name: String, status: HealthCheckStatus, detail: String, suggestedAction: String) {
        self.id = id
        self.name = name
        self.status = status
        self.detail = detail
        self.suggestedAction = suggestedAction
    }

    package var isActionable: Bool {
        status.isActionable && !suggestedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var isDisabled: Bool {
        status.isDisabled
    }

    package var isNormal: Bool {
        status.isNormal
    }

    package var shouldShowInExceptionOnlyUI: Bool {
        isActionable
    }
}

package struct AgentEvent: Identifiable, Codable, Equatable {
    package var id: String
    package var source: AgentSource
    package var kind: AgentEventKind
    package var workspace: String?
    package var sessionId: String?
    package var threadId: String?
    package var codexSessionStartSource: String?
    package var agentName: String?
    package var timestamp: Date
    package var payload: JSONValue

    package init(
        id: String = UUID().uuidString,
        source: AgentSource,
        kind: AgentEventKind,
        workspace: String? = nil,
        sessionId: String? = nil,
        threadId: String? = nil,
        codexSessionStartSource: String? = nil,
        agentName: String? = nil,
        timestamp: Date = Date(),
        payload: JSONValue = .object([:])
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.workspace = workspace
        self.sessionId = sessionId
        self.threadId = threadId
        self.codexSessionStartSource = codexSessionStartSource
        self.agentName = agentName
        self.timestamp = timestamp
        self.payload = payload
    }
}

package struct AgentSession: Identifiable, Equatable {
    package var id: String
    package var title: String
    package var prompt: String
    package var source: AgentSource
    package var workspace: String
    package var terminal: String
    package var threadID: String?
    package var codexSessionStartSource: String?
    package var updatedAt: Date
    package var status: SessionStatus
    package var activity: [ActivityItem]
    package var approval: ApprovalRequest?
    package var question: QuestionRequest?
    package var subagents: [SubagentItem]
    package var lastAssistantMessage: String?
    package var lastUserMessage: String?
    package var usage: UsageSnapshot?

    package init(
        id: String,
        title: String,
        prompt: String,
        source: AgentSource,
        workspace: String,
        terminal: String,
        threadID: String? = nil,
        codexSessionStartSource: String? = nil,
        updatedAt: Date,
        status: SessionStatus,
        activity: [ActivityItem],
        approval: ApprovalRequest? = nil,
        question: QuestionRequest? = nil,
        subagents: [SubagentItem],
        lastAssistantMessage: String? = nil,
        lastUserMessage: String? = nil,
        usage: UsageSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.source = source
        self.workspace = workspace
        self.terminal = terminal
        self.threadID = threadID
        self.codexSessionStartSource = codexSessionStartSource
        self.updatedAt = updatedAt
        self.status = status
        self.activity = activity
        self.approval = approval
        self.question = question
        self.subagents = subagents
        self.lastAssistantMessage = lastAssistantMessage
        self.lastUserMessage = lastUserMessage
        self.usage = usage
    }

    package var ageText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale.current
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

package struct ActivityItem: Identifiable, Equatable {
    package var id: String = UUID().uuidString
    package var symbol: String
    package var title: String
    package var detail: String
    package var date: Date = Date()

    package init(
        id: String = UUID().uuidString,
        symbol: String,
        title: String,
        detail: String,
        date: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.date = date
    }
}

package struct UsageSnapshot: Equatable {
    package var lastTokens: Int
    package var totalTokens: Int
    package var contextWindow: Int
    package var primaryUsedPercent: Double?
    package var secondaryUsedPercent: Double?
    package var primaryWindowMinutes: Int?
    package var secondaryWindowMinutes: Int?
    package var primaryResetsAt: Date?
    package var secondaryResetsAt: Date?
    package var planType: String?
    package var limitName: String?

    package init(
        lastTokens: Int,
        totalTokens: Int,
        contextWindow: Int,
        primaryUsedPercent: Double? = nil,
        secondaryUsedPercent: Double? = nil,
        primaryWindowMinutes: Int? = nil,
        secondaryWindowMinutes: Int? = nil,
        primaryResetsAt: Date? = nil,
        secondaryResetsAt: Date? = nil,
        planType: String? = nil,
        limitName: String? = nil
    ) {
        self.lastTokens = lastTokens
        self.totalTokens = totalTokens
        self.contextWindow = contextWindow
        self.primaryUsedPercent = primaryUsedPercent
        self.secondaryUsedPercent = secondaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryResetsAt = secondaryResetsAt
        self.planType = planType
        self.limitName = limitName
    }

    package var shortText: String {
        var parts = ["本轮 \(Self.compactNumber(lastTokens))"]
        if let primaryUsedPercent {
            parts.append("5h \(Self.percent(primaryUsedPercent))")
        }
        if let secondaryUsedPercent {
            parts.append("7d \(Self.percent(secondaryUsedPercent))")
        }
        return parts.joined(separator: " · ")
    }

    package var totalText: String {
        Self.compactNumber(totalTokens)
    }

    package var compactRateLimitText: String? {
        var parts: [String] = []
        if let primaryUsedPercent {
            parts.append(Self.rateLimitText(
                label: Self.windowLabel(minutes: primaryWindowMinutes, fallback: "5h"),
                percent: primaryUsedPercent,
                resetsAt: primaryResetsAt
            ))
        }
        if let secondaryUsedPercent {
            parts.append(Self.rateLimitText(
                label: Self.windowLabel(minutes: secondaryWindowMinutes, fallback: "7d"),
                percent: secondaryUsedPercent,
                resetsAt: secondaryResetsAt
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    package static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    package static func compactNumber(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            let number = Double(value) / 1_000_000
            return String(format: "%.1fM", number)
        }
        if absolute >= 1_000 {
            let number = Double(value) / 1_000
            return String(format: "%.1fK", number)
        }
        return "\(value)"
    }

    package static func windowLabel(minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes % 10_080 == 0 {
            return "\(minutes / 10_080 * 7)d"
        }
        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440)d"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    package static func remainingText(until date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(date.timeIntervalSince(Date())))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d\(hours)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(max(1, minutes))m"
    }

    package static func rateLimitText(label: String, percent: Double, resetsAt: Date?) -> String {
        let base = "\(label) \(Self.percent(percent))"
        guard let remaining = Self.remainingText(until: resetsAt) else {
            return base
        }
        return "\(base) \(remaining)"
    }
}

package struct CodexThreadSnapshot: Equatable {
    package var activities: [ActivityItem]
    package var usage: UsageSnapshot?
    package var lastAssistantMessage: String?
    package var lastUserMessage: String?
    package var isComplete: Bool
    package var completedAt: Date? = nil
    package var latestActiveAt: Date? = nil

    package init(
        activities: [ActivityItem],
        usage: UsageSnapshot?,
        lastAssistantMessage: String?,
        lastUserMessage: String?,
        isComplete: Bool,
        completedAt: Date? = nil,
        latestActiveAt: Date? = nil
    ) {
        self.activities = activities
        self.usage = usage
        self.lastAssistantMessage = lastAssistantMessage
        self.lastUserMessage = lastUserMessage
        self.isComplete = isComplete
        self.completedAt = completedAt
        self.latestActiveAt = latestActiveAt
    }
}

package struct AgentTranscriptSnapshot: Equatable {
    package var activities: [ActivityItem]
    package var usage: UsageSnapshot?
    package var lastAssistantMessage: String?
    package var lastUserMessage: String?
    package var isComplete: Bool
    package var completedAt: Date? = nil
    package var latestActiveAt: Date? = nil

    package init(
        activities: [ActivityItem],
        usage: UsageSnapshot?,
        lastAssistantMessage: String?,
        lastUserMessage: String?,
        isComplete: Bool,
        completedAt: Date? = nil,
        latestActiveAt: Date? = nil
    ) {
        self.activities = activities
        self.usage = usage
        self.lastAssistantMessage = lastAssistantMessage
        self.lastUserMessage = lastUserMessage
        self.isComplete = isComplete
        self.completedAt = completedAt
        self.latestActiveAt = latestActiveAt
    }
}

package struct ApprovalRequest: Identifiable, Equatable {
    package var id: String
    package var source: AgentSource
    package var title: String
    package var detail: String
    package var tool: String
    package var workspace: String?
    package var availableDecisions: [ApprovalDecision] = [.accept, .decline]
    package var suggestedSessionAllow: Bool
    package var supportsCancel: Bool
    package var isResolving: Bool = false
    package var isExpired: Bool = false
    package var resolutionState: ApprovalResolutionState = .pending
    package var resolutionMessage: String? = nil
    package var createdAt: Date

    package init(
        id: String,
        source: AgentSource,
        title: String,
        detail: String,
        tool: String,
        workspace: String?,
        availableDecisions: [ApprovalDecision] = [.accept, .decline],
        suggestedSessionAllow: Bool,
        supportsCancel: Bool,
        isResolving: Bool = false,
        isExpired: Bool = false,
        resolutionState: ApprovalResolutionState = .pending,
        resolutionMessage: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.tool = tool
        self.workspace = workspace
        self.availableDecisions = availableDecisions
        self.suggestedSessionAllow = suggestedSessionAllow
        self.supportsCancel = supportsCancel
        self.isResolving = isResolving
        self.isExpired = isExpired
        self.resolutionState = resolutionState
        self.resolutionMessage = resolutionMessage
        self.createdAt = createdAt
    }

    package func supports(_ decision: ApprovalDecision) -> Bool {
        availableDecisions.contains(decision)
    }
}

package struct QuestionRequest: Identifiable, Equatable {
    package var id: String = UUID().uuidString
    package var title: String
    package var options: [String]

    package init(id: String = UUID().uuidString, title: String, options: [String]) {
        self.id = id
        self.title = title
        self.options = options
    }
}

package struct SubagentItem: Identifiable, Equatable {
    package var id: String
    package var name: String
    package var status: SessionStatus
    package var detail: String

    package init(id: String, name: String, status: SessionStatus, detail: String) {
        self.id = id
        self.name = name
        self.status = status
        self.detail = detail
    }
}

package struct CodexThreadRecord: Identifiable, Equatable {
    package var id: String
    package var cwd: String
    package var title: String
    package var source: String
    package var approvalMode: String
    package var sandboxPolicy: String
    package var rolloutPath: String
    package var updatedAt: Date
    package var updatedAtMilliseconds: Int64
    package var model: String
    package var agentNickname: String
    package var agentRole: String
    package var parentThreadID: String?

    package init(
        id: String,
        cwd: String,
        title: String,
        source: String,
        approvalMode: String,
        sandboxPolicy: String,
        rolloutPath: String,
        updatedAt: Date,
        updatedAtMilliseconds: Int64,
        model: String,
        agentNickname: String,
        agentRole: String,
        parentThreadID: String?
    ) {
        self.id = id
        self.cwd = cwd
        self.title = title
        self.source = source
        self.approvalMode = approvalMode
        self.sandboxPolicy = sandboxPolicy
        self.rolloutPath = rolloutPath
        self.updatedAt = updatedAt
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.model = model
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.parentThreadID = parentThreadID
    }
}

package enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    package init(any value: Any?) {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as [String: Any]:
            self = .object(value.mapValues { JSONValue(any: $0) })
        case let value as [Any]:
            self = .array(value.map { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    package var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    package var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    package func flattenedText(limit: Int = 220) -> String {
        let text: String
        switch self {
        case .string(let value):
            text = value
        case .number(let value):
            text = String(value)
        case .bool(let value):
            text = String(value)
        case .object(let value):
            text = value.keys.sorted().prefix(6).joined(separator: ", ")
        case .array(let value):
            text = "\(value.count) items"
        case .null:
            text = ""
        }
        return String(text.prefix(limit))
    }
}
