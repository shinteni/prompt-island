import Foundation

package enum ApprovalResponseMapper {
    package static func hookResponse(for event: AgentEvent, decision: ApprovalDecision) -> String? {
        switch event.source {
        case .claudeCode:
            return claudeResponse(for: event, decision: decision)
        case .codexCli:
            return codexHookResponse(for: event, decision: decision)
        case .codexDesktop:
            return codexAppServerResponse(for: decision)
        case .unknown:
            return nil
        }
    }

    package static func codexAppServerResponse(for decision: ApprovalDecision) -> String? {
        let value: String
        switch decision {
        case .accept: value = "accept"
        case .acceptForSession: value = "acceptForSession"
        case .decline: value = "decline"
        case .cancel: value = "cancel"
        }
        return encode(["decision": value])
    }

    package static func codexHookResponse(for event: AgentEvent, decision: ApprovalDecision) -> String? {
        let eventName = event.payload["hook_event_name"]?.stringValue ?? event.payload["event"]?.stringValue
        guard eventName == "PermissionRequest" || (eventName == nil && event.kind == .approval) else {
            return nil
        }

        switch decision {
        case .accept:
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": ["behavior": "allow"]
                ]
            ])
        case .decline:
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": [
                        "behavior": "deny",
                        "message": "Denied in Vibelsland Free."
                    ]
                ]
            ])
        case .acceptForSession, .cancel:
            return nil
        }
    }

    package static func claudeResponse(for event: AgentEvent, decision: ApprovalDecision) -> String? {
        let object = event.payload.objectValue ?? [:]
        let eventName = object["hook_event_name"]?.stringValue ?? ""

        if eventName == "PreToolUse" {
            let permissionDecision: String
            switch decision {
            case .accept, .acceptForSession: permissionDecision = "allow"
            case .decline: permissionDecision = "deny"
            case .cancel: permissionDecision = "defer"
            }
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": permissionDecision,
                    "permissionDecisionReason": "Vibelsland Free"
                ]
            ])
        }

        if eventName == "PermissionRequest" {
            var responseDecision: [String: Any] = [:]
            switch decision {
            case .accept:
                responseDecision["behavior"] = "allow"
            case .acceptForSession:
                responseDecision["behavior"] = "allow"
                if let suggestion = safeSessionPermissionSuggestion(from: object["permission_suggestions"]) {
                    responseDecision["updatedPermissions"] = [suggestion]
                }
            case .decline:
                responseDecision["behavior"] = "deny"
                responseDecision["message"] = "Permission denied in Vibelsland Free."
            case .cancel:
                responseDecision["behavior"] = "deny"
                responseDecision["message"] = "Permission cancelled in Vibelsland Free."
                responseDecision["interrupt"] = true
            }
            return encode([
                "hookSpecificOutput": [
                    "hookEventName": "PermissionRequest",
                    "decision": responseDecision
                ]
            ])
        }

        return nil
    }

    private static func safeSessionPermissionSuggestion(from value: JSONValue?) -> Any? {
        jsonObject(from: PermissionSuggestionSanitizer.sanitizedClaudeSessionSuggestion(from: value))
    }

    private static func encode(_ value: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private static func jsonObject(from value: JSONValue?) -> Any? {
        switch value {
        case .string(let string): string
        case .number(let double): double
        case .bool(let bool): bool
        case .object(let object): object.mapValues { jsonObject(from: $0) ?? NSNull() }
        case .array(let array): array.map { jsonObject(from: $0) ?? NSNull() }
        case .null, nil: nil
        }
    }
}

package enum PermissionSuggestionSanitizer {
    package static func hasSafeClaudeSessionSuggestion(_ value: JSONValue?) -> Bool {
        sanitizedClaudeSessionSuggestion(from: value) != nil
    }

    package static func sanitizedClaudeSessionSuggestion(from value: JSONValue?) -> JSONValue? {
        guard case .array(let suggestions) = value else { return nil }
        return suggestions.lazy.compactMap(sanitizeSessionSuggestion).first
    }

    private static func sanitizeSessionSuggestion(_ suggestion: JSONValue) -> JSONValue? {
        guard case .object(let object) = suggestion,
              object["destination"]?.stringValue == "session",
              let type = object["type"]?.stringValue else {
            return nil
        }

        switch type {
        case "addRules":
            return sanitizeAddRules(object)
        case "setMode":
            return sanitizeSetMode(object)
        default:
            return nil
        }
    }

    private static func sanitizeAddRules(_ object: [String: JSONValue]) -> JSONValue? {
        guard Set(object.keys).isSubset(of: ["type", "rules", "behavior", "destination"]),
              object["behavior"]?.stringValue == "allow",
              case .array(let rules) = object["rules"] else {
            return nil
        }

        let sanitizedRules = rules.compactMap(sanitizeRule)
        guard sanitizedRules.count == rules.count, !sanitizedRules.isEmpty else {
            return nil
        }

        return .object([
            "type": .string("addRules"),
            "rules": .array(sanitizedRules),
            "behavior": .string("allow"),
            "destination": .string("session")
        ])
    }

    private static func sanitizeRule(_ value: JSONValue) -> JSONValue? {
        guard case .object(let object) = value,
              Set(object.keys).isSubset(of: ["toolName", "ruleContent"]),
              let toolName = object["toolName"]?.stringValue,
              !toolName.isEmpty else {
            return nil
        }

        var sanitized: [String: JSONValue] = ["toolName": .string(toolName)]
        if let ruleContent = object["ruleContent"]?.stringValue {
            sanitized["ruleContent"] = .string(ruleContent)
        }
        return .object(sanitized)
    }

    private static func sanitizeSetMode(_ object: [String: JSONValue]) -> JSONValue? {
        guard Set(object.keys).isSubset(of: ["type", "mode", "destination"]),
              let mode = object["mode"]?.stringValue,
              ["acceptEdits", "dontAsk"].contains(mode) else {
            return nil
        }

        return .object([
            "type": .string("setMode"),
            "mode": .string(mode),
            "destination": .string("session")
        ])
    }
}
