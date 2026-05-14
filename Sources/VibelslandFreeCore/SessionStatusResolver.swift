import Foundation

package enum SessionStatusResolver {
    package static func status(for event: AgentEvent) -> SessionStatus {
        if isFailure(event) {
            return .failed
        }
        if isCompletion(event) {
            return .done
        }

        switch event.kind {
        case .approval:
            return .waitingApproval
        case .tool:
            return isToolEnd(event) ? .thinking : .runningTool
        case .prompt:
            return .thinking
        case .session:
            return .thinking
        case .notification:
            return .thinking
        case .subagent:
            return .thinking
        case .status:
            return .thinking
        }
    }

    package static func codexDesktopStatus(
        recordUpdatedAt: Date,
        snapshot: CodexThreadSnapshot?,
        hasPendingApproval: Bool,
        now: Date = Date()
    ) -> SessionStatus {
        if hasPendingApproval {
            return .waitingApproval
        }
        if let snapshot, snapshot.isComplete {
            if let completedAt = snapshot.completedAt {
                if let latestActiveAt = snapshot.latestActiveAt,
                   latestActiveAt > completedAt {
                    return .thinking
                }
            }
            return .done
        }
        if let latest = snapshot?.activities.last {
            let age = now.timeIntervalSince(latest.date)
            if latest.title == "工具调用" || latest.title == "修改文件" {
                return age < 120 ? .runningTool : .thinking
            }
            if latest.title == "用户输入" || latest.title == "消息" || latest.title == "工具完成" {
                return .thinking
            }
        }
        return now.timeIntervalSince(recordUpdatedAt) < 45 ? .thinking : .idle
    }

    package static func shouldPreserveDoneStatus(current: SessionStatus, next: SessionStatus, event: AgentEvent) -> Bool {
        current == .done && next == .thinking && !isNewWorkStart(event)
    }

    private static func isCompletion(_ event: AgentEvent) -> Bool {
        let tokens = statusTokens(for: event)
        if tokens.contains(where: completionToken) {
            return true
        }

        guard [.session, .notification, .status].contains(event.kind) else {
            return false
        }

        return messageTokens(for: event).contains(where: completionMessage)
    }

    private static func isFailure(_ event: AgentEvent) -> Bool {
        let tokens = statusTokens(for: event)
        if tokens.contains(where: failureToken) {
            return true
        }

        guard [.session, .notification, .status].contains(event.kind) else {
            return false
        }

        return messageTokens(for: event).contains(where: failureMessage)
    }

    private static func isToolEnd(_ event: AgentEvent) -> Bool {
        statusTokens(for: event).contains { token in
            token == "posttooluse"
                || token == "post_tool_use"
                || token == "tool_complete"
                || token == "toolcompleted"
                || token == "tool_end"
                || token == "toolend"
        }
    }

    package static func isNewWorkStart(_ event: AgentEvent) -> Bool {
        if event.kind == .prompt || event.kind == .approval {
            return true
        }

        return statusTokens(for: event).contains { token in
            token == "sessionstart"
                || token == "session_start"
                || token == "userpromptsubmit"
                || token == "user_prompt_submit"
                || token == "pretooluse"
                || token == "pre_tool_use"
                || token == "subagentstart"
                || token == "subagent_start"
        }
    }

    package static func isSubagentCompletion(_ event: AgentEvent) -> Bool {
        guard event.kind == .subagent else { return false }
        return statusTokens(for: event).contains { token in
            token == "subagentstop" || token == "subagent_stop"
        }
    }

    private static func statusTokens(for event: AgentEvent) -> [String] {
        let object = event.payload.objectValue ?? [:]
        let keys = [
            "hook_event_name",
            "event",
            "type",
            "codex_event_type",
            "status",
            "state",
            "phase",
            "result"
        ]

        var tokens = keys.compactMap { object[$0]?.stringValue }
        tokens.append(event.kind.rawValue)
        tokens.append(EventParser.title(for: event))
        return tokens.map(normalize)
    }

    private static func messageTokens(for event: AgentEvent) -> [String] {
        let object = event.payload.objectValue ?? [:]
        let keys = [
            "message",
            "reason",
            "codex_last_assistant_message",
            "last_assistant_message",
            "last_agent_message",
            "assistant_response"
        ]
        return keys.compactMap { object[$0]?.stringValue }.map(normalize)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func completionToken(_ token: String) -> Bool {
        [
            "stop",
            "stopped",
            "sessionend",
            "session_end",
            "task_complete",
            "taskcomplete",
            "completed",
            "complete",
            "done",
            "finished",
            "finish",
            "success",
            "succeeded"
        ].contains(token)
    }

    private static func completionMessage(_ token: String) -> Bool {
        if token.contains("未完成")
            || token.contains("没有完成")
            || token.contains("not completed")
            || token.contains("not complete") {
            return false
        }

        return token.contains("task_complete")
            || token.contains("completed")
            || token.contains("finished")
            || token.contains("已完成")
            || token.contains("任务完成")
            || token.contains("执行完成")
            || token.contains("处理完成")
            || token.contains("回复完成")
    }

    private static func failureToken(_ token: String) -> Bool {
        [
            "failed",
            "failure",
            "error",
            "errored",
            "abort",
            "aborted",
            "turn_aborted",
            "turnaborted",
            "cancelled",
            "canceled",
            "denied",
            "declined"
        ].contains(token)
    }

    private static func failureMessage(_ token: String) -> Bool {
        token.contains("failed")
            || token.contains("failure")
            || token.contains("error")
            || token.contains("失败")
            || token.contains("错误")
            || token.contains("出错")
            || token.contains("取消")
            || token.contains("拒绝")
    }
}
