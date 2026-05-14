import Foundation

package enum EventParser {
    enum ParserError: Error {
        case invalidUTF8
        case invalidJSON
    }

    package static func parseBridgeData(_ data: Data) throws -> AgentEvent {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidUTF8
        }

        let line = text
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init) ?? text
        guard let payloadData = line.data(using: .utf8) else {
            throw ParserError.invalidUTF8
        }
        let object = try JSONSerialization.jsonObject(with: payloadData)
        guard let dictionary = object as? [String: Any] else {
            throw ParserError.invalidJSON
        }
        return parseBridgeDictionary(dictionary)
    }

    package static func parseBridgeDictionary(_ dictionary: [String: Any]) -> AgentEvent {
        let payloadAny = dictionary["payload"] ?? dictionary["input"] ?? dictionary
        let payload = JSONValue(any: payloadAny)
        let payloadObject = payload.objectValue ?? [:]

        let source = AgentSource(hookSource: string(dictionary["source"]) ?? string(payloadObject["source"]))
        let eventName = string(dictionary["event"])
            ?? string(dictionary["hook_event_name"])
            ?? string(payloadObject["hook_event_name"])
            ?? string(payloadObject["event"])
            ?? string(payloadObject["type"])

        let workspace = string(dictionary["workspace"])
            ?? string(dictionary["cwd"])
            ?? string(payloadObject["cwd"])
            ?? string(payloadObject["workspace"])

        let sessionId = string(dictionary["session_id"])
            ?? string(payloadObject["session_id"])
            ?? string(payloadObject["sessionId"])

        let threadId = string(dictionary["thread_id"])
            ?? string(payloadObject["thread_id"])
            ?? string(payloadObject["threadId"])

        let codexSessionStartSource = string(dictionary["codex_session_start_source"])
            ?? string(payloadObject["codex_session_start_source"])

        let agentName = string(dictionary["agent_name"])
            ?? string(payloadObject["agent_name"])
            ?? string(payloadObject["agentName"])

        return AgentEvent(
            source: source,
            kind: inferKind(eventName: eventName, payload: payloadObject),
            workspace: workspace,
            sessionId: sessionId,
            threadId: threadId,
            codexSessionStartSource: codexSessionStartSource,
            agentName: agentName,
            timestamp: parseTimestamp(dictionary["timestamp"]) ?? Date(),
            payload: payload
        )
    }

    package static func inferKind(eventName: String?, payload: [String: JSONValue]) -> AgentEventKind {
        let name = (eventName ?? "").lowercased()
        if name.contains("permission") || name.contains("approval") {
            return .approval
        }
        if name.contains("notification") {
            return .notification
        }
        if name.contains("prompt") {
            return .prompt
        }
        if name.contains("subagent") {
            return .subagent
        }
        if name.contains("session") || name == "stop" {
            return .session
        }
        if name.contains("status") {
            return .status
        }
        if payload["tool_name"] != nil || payload["tool"] != nil || name.contains("tool") {
            return .tool
        }
        return .status
    }

    package static func title(for event: AgentEvent) -> String {
        let object = event.payload.objectValue ?? [:]
        if let value = string(object["prompt"]) ?? string(object["message"]) {
            return DisplayTextSanitizer.sanitize(String(value.prefix(80)))
        }
        if let tool = string(object["tool_name"]) ?? string(object["tool"]) {
            return DisplayTextSanitizer.sanitize(tool)
        }
        if let workspace = event.workspace {
            return DisplayTextSanitizer.sanitize(URL(fileURLWithPath: workspace).lastPathComponent)
        }
        return event.source.shortName
    }

    package static func approvalRequest(for event: AgentEvent) -> ApprovalRequest? {
        guard event.kind == .approval else { return nil }
        let object = event.payload.objectValue ?? [:]
        let tool = string(object["tool_name"])
            ?? string(object["tool"])
            ?? string(object["command"])
            ?? "请求"
        let input = object["tool_input"] ?? object["input"] ?? object["params"] ?? .null
        let hasSessionAllow = hasSafeSessionPermissionSuggestion(object["permission_suggestions"])
        let detail = detailText(from: input)
            ?? string(object["command"])
            ?? string(object["reason"])
            ?? input.flattenedText(limit: 260)
        var availableDecisions: [ApprovalDecision] = [.accept, .decline]
        if event.source == .claudeCode {
            if hasSessionAllow {
                availableDecisions.append(.acceptForSession)
            }
            availableDecisions.append(.cancel)
        }

        return ApprovalRequest(
            id: event.id,
            source: event.source,
            title: "\(event.source.shortName) 请求权限",
            detail: detail,
            tool: tool,
            workspace: event.workspace,
            availableDecisions: availableDecisions,
            suggestedSessionAllow: hasSessionAllow,
            supportsCancel: event.source == .claudeCode || event.source == .codexDesktop,
            createdAt: event.timestamp
        )
    }

    package static func hasSafeSessionPermissionSuggestion(_ value: JSONValue?) -> Bool {
        PermissionSuggestionSanitizer.hasSafeClaudeSessionSuggestion(value)
    }

    package static func activity(for event: AgentEvent) -> ActivityItem {
        let object = event.payload.objectValue ?? [:]
        let tool = string(object["tool_name"]) ?? string(object["tool"]) ?? event.kind.rawValue
        let detail = string(object["message"])
            ?? string(object["command"])
            ?? string(object["cwd"])
            ?? detailText(from: object["tool_input"])
            ?? object["tool_input"]?.flattenedText(limit: 140)
            ?? event.payload.flattenedText(limit: 140)

        return ActivityItem(
            symbol: symbol(for: event.kind, tool: tool),
            title: tool,
            detail: detail,
            date: event.timestamp
        )
    }

    private static func symbol(for kind: AgentEventKind, tool: String) -> String {
        let lowercasedTool = tool.lowercased()
        if lowercasedTool.contains("bash") || lowercasedTool.contains("shell") {
            return "terminal"
        }
        if lowercasedTool.contains("edit") || lowercasedTool.contains("write") {
            return "square.and.pencil"
        }
        if lowercasedTool.contains("read") {
            return "doc.text"
        }
        switch kind {
        case .approval: return "hand.raised"
        case .notification: return "bell"
        case .prompt: return "text.bubble"
        case .session: return "rectangle.stack"
        case .subagent: return "person.2"
        case .status: return "waveform.path"
        case .tool: return "wrench.and.screwdriver"
        }
    }

    private static func detailText(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let string = value.stringValue {
            return string
        }
        guard let object = value.objectValue else { return nil }
        for key in ["command", "file_path", "path", "url", "pattern", "description", "reason"] {
            if let value = string(object[key]) {
                return DisplayTextSanitizer.sanitize(String(value.prefix(260)))
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            value.isEmpty ? nil : value
        case let value as NSNumber:
            value.stringValue
        case let value as JSONValue:
            value.stringValue
        default:
            nil
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        switch value {
        case let value as Double:
            return Date(timeIntervalSince1970: value)
        case let value as Int:
            return Date(timeIntervalSince1970: TimeInterval(value))
        case let value as String:
            if let seconds = TimeInterval(value) {
                return Date(timeIntervalSince1970: seconds)
            }
            return ISO8601DateFormatter().date(from: value)
        default:
            return nil
        }
    }
}
