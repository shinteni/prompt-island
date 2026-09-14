import Foundation
import Testing
@testable import VibelslandFreeCore

struct ToolDisplayTests {
    @Test func liveHooksShowToolNamesWithoutExposingCommandsOrResponses() {
        for (hook, expectedTitle) in [("PreToolUse", "工具调用"), ("PostToolUse", "工具完成")] {
            let event = EventParser.parseBridgeDictionary([
                "source": "claude", "event": hook,
                "payload": ["hook_event_name": hook, "tool_name": "Bash",
                    "command": "echo private-test-value", "message": "create: 200 private-test-value"]
            ])
            let activity = EventParser.activity(for: event)
            #expect(activity.title == expectedTitle)
            #expect(activity.detail == "Bash")
            #expect(EventParser.title(for: event) == "Bash")
        }
    }

    @Test func claudeToolResultsNeverBecomeDisplayText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tool-display-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"echo private","description":"Create demo"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tool-1","content":"create: 200 {\"token\":\"private-test-value\"}"}]}}"#
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let snapshot = try #require(ConversationTranscriptReader().loadSnapshot(from: url, source: .claudeCode))
        #expect(!snapshot.activities.contains { $0.detail.contains("private-test-value") || $0.detail.contains("create: 200") })
        let display = SessionDisplaySnapshot(session: session(activity: snapshot.activities))
        #expect(display.primaryLine == "工具：Bash")
        #expect(display.signals.first?.text == "Bash")
    }

    @Test func historicalResultIsNotUsedAsToolName() {
        let activity = [
            ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: "Bash", date: Date()),
            ActivityItem(symbol: "checkmark.circle", title: "工具完成", detail: #"create: 200 {"token":"private-test-value"}"#, date: Date())
        ]
        let display = SessionDisplaySnapshot(session: session(activity: activity))
        #expect(display.primaryLine == "工具：Bash")
        #expect(display.signals.first?.text == "Bash")
    }

    @Test func failedResultOnlyShowsTheFailureState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tool-error-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"{\"token\":\"private-test-value\"}"}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let snapshot = try #require(ConversationTranscriptReader().loadSnapshot(from: url, source: .claudeCode))
        #expect(snapshot.activities.first?.title == "工具失败")
        #expect(SessionMemoryPolicy.compactActivities(snapshot.activities).count == 1)
        let display = SessionDisplaySnapshot(session: session(activity: snapshot.activities))
        #expect(display.primaryLine.contains("工具失败"))
        #expect(!display.primaryLine.contains("private-test-value"))
    }

    @Test func codexCompletionDoesNotReplaceToolNameWithCallID() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-tool-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [
            #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-internal-id"}}"#,
            #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call-internal-id","output":"private-test-value"}}"#
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let snapshot = try #require(ConversationTranscriptReader().loadSnapshot(from: url, source: .codexCli))
        let display = SessionDisplaySnapshot(session: session(activity: snapshot.activities))
        #expect(display.primaryLine == "工具：exec_command")
        #expect(display.signals.first?.text == "exec_command")
        #expect(!snapshot.activities.contains { $0.detail.contains("call-internal-id") || $0.detail.contains("private-test-value") })
    }

    private func session(activity: [ActivityItem]) -> AgentSession {
        AgentSession(id: "test", title: "Test", prompt: "Test", source: .claudeCode,
            workspace: "/tmp/test", terminal: "Claude", updatedAt: Date(), status: .runningTool,
            activity: activity, approval: nil, question: nil, subagents: [])
    }
}
