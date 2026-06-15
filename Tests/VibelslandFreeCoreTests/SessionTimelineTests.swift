import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct SessionTimelineTests {
    @Test func testSessionTimelineSortsEventsAndTracksToolLifecycle() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let toolStart = sessionEvent(
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(10),
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let userPrompt = sessionEvent(
            kind: .prompt,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("UserPromptSubmit")]
        )
        let toolEnd = sessionEvent(
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(20),
            payload: ["hook_event_name": .string("PostToolUse")]
        )

        var timeline = SessionTimeline(events: [toolStart, userPrompt])
        XCTAssertEqual(timeline.events.map(\.id), ["prompt", "tool"], "Timeline keeps events sorted by timestamp")
        XCTAssertEqual(timeline.status, .runningTool)
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.status(for: timeline), .runningTool)

        timeline.append(toolEnd)
        XCTAssertEqual(timeline.status, .thinking, "Tool end returns the session to thinking, not completed")
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.status(after: .runningTool, event: toolEnd), .thinking)
    }

    @Test func testToolEndDisplayDoesNotLookCompleted() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_050)
        let toolStart = sessionEvent(
            id: "tool-start",
            kind: .tool,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let toolEnd = sessionEvent(
            id: "tool-end",
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(15),
            payload: ["hook_event_name": .string("PostToolUse")]
        )
        let timeline = SessionTimeline(events: [toolStart, toolEnd])
        let session = AgentSession(
            id: "active-after-tool-end",
            title: "vibelsland free",
            prompt: "继续修复",
            source: .codexCli,
            workspace: "/Users/example/projects/vibelsland-free",
            terminal: "Codex",
            updatedAt: baseDate.addingTimeInterval(15),
            status: timeline.status,
            activity: [
                ActivityItem(
                    symbol: "wrench.and.screwdriver",
                    title: "工具调用",
                    detail: "Bash",
                    date: baseDate.addingTimeInterval(15)
                )
            ],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: "我继续处理这个问题。",
            lastUserMessage: "工具调用后还在处理",
            usage: nil
        )
        let display = SessionDisplaySnapshot(session: session)

        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertFalse(["已完成", "可能已完成"].contains(display.statusText), "Tool completion must not be shown as task completion")
        XCTAssertFalse(display.primaryLine.contains("已完成"), "The visible card body must not imply the full turn is complete")
    }

    @Test func testSessionTimelineKeepsAssistantContinuationActive() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_100)
        let toolStart = sessionEvent(
            id: "tool-start",
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(-1),
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let toolEnd = sessionEvent(
            id: "tool-end",
            kind: .tool,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("PostToolUse")]
        )
        let assistantContinues = sessionEvent(
            id: "assistant-continues",
            kind: .status,
            timestamp: baseDate.addingTimeInterval(1),
            payload: [
                "type": .string("agent_message"),
                "message": .string("继续处理")
            ]
        )

        let timeline = SessionTimeline(events: [toolStart, toolEnd, assistantContinues])
        XCTAssertEqual(timeline.status, .thinking)
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.resolutionState(for: timeline.events), .active)
    }

    @Test func testSessionTimelineResolvesCompletionAndFailure() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_200)
        let completion = sessionEvent(
            kind: .status,
            timestamp: baseDate,
            payload: ["codex_event_type": .string("task_complete")]
        )
        let failure = sessionEvent(
            kind: .status,
            timestamp: baseDate,
            payload: ["status": .string("failed")]
        )

        let completedTimeline = SessionTimeline(events: [completion])
        XCTAssertEqual(completedTimeline.status, .done)
        XCTAssertEqual(completedTimeline.resolutionState, .completed)

        let failedTimeline = SessionTimeline(events: [failure])
        XCTAssertEqual(failedTimeline.status, .failed)
        XCTAssertEqual(failedTimeline.resolutionState, .failed)
    }

    @Test func testSessionTimelineReopensAfterNewPromptButPreservesLateNotificationCompletion() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_300)
        let completion = sessionEvent(
            id: "complete",
            kind: .status,
            timestamp: baseDate,
            payload: ["codex_event_type": .string("task_complete")]
        )
        let newPrompt = sessionEvent(
            id: "new-prompt",
            kind: .prompt,
            timestamp: baseDate.addingTimeInterval(1),
            payload: ["hook_event_name": .string("UserPromptSubmit")]
        )
        let lateNotification = sessionEvent(
            id: "late-notification",
            kind: .notification,
            timestamp: baseDate.addingTimeInterval(1),
            payload: ["message": .string("后台同步")]
        )

        let reopenedTimeline = SessionTimeline(events: [completion, newPrompt])
        XCTAssertEqual(reopenedTimeline.status, .thinking)
        XCTAssertEqual(reopenedTimeline.resolutionState, .active)

        let preservedTimeline = SessionTimeline(events: [completion, lateNotification])
        XCTAssertEqual(preservedTimeline.status, .done)
        XCTAssertEqual(preservedTimeline.resolutionState, .completed)
    }

    @Test func testStaleTranscriptCompletionDoesNotOverrideNewPrompt() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_000)
        let prompt = AgentEvent(
            id: "new-claude-prompt",
            source: .claudeCode,
            kind: .prompt,
            timestamp: baseDate,
            payload: .object(["hook_event_name": .string("UserPromptSubmit")])
        )
        let staleTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "上一轮回答",
            lastUserMessage: "上一轮任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(-60),
            latestActiveAt: baseDate.addingTimeInterval(-70)
        )

        XCTAssertFalse(SessionStateReducer.shouldApplyTranscriptCompletion(staleTranscript, to: prompt))
        XCTAssertFalse(SessionStateReducer.shouldApplyTranscriptContent(staleTranscript, to: prompt))
        XCTAssertEqual(SessionStateReducer.status(after: .done, event: prompt), .thinking)
    }

    @Test func testCurrentTranscriptContentAppliesToNewPrompt() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_050)
        let prompt = AgentEvent(
            id: "current-claude-prompt",
            source: .claudeCode,
            kind: .prompt,
            timestamp: baseDate,
            payload: .object([
                "hook_event_name": .string("UserPromptSubmit"),
                "prompt": .string("对比和功能")
            ])
        )
        let currentTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: nil,
            lastUserMessage: "对比和功能",
            isComplete: false,
            completedAt: baseDate.addingTimeInterval(-60),
            latestActiveAt: baseDate.addingTimeInterval(-1)
        )

        XCTAssertTrue(SessionStateReducer.shouldApplyTranscriptContent(currentTranscript, to: prompt))
    }

    @Test func testFreshTranscriptCompletionCanResolveSession() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_100)
        let stop = AgentEvent(
            id: "claude-stop",
            source: .claudeCode,
            kind: .session,
            timestamp: baseDate,
            payload: .object(["hook_event_name": .string("Stop")])
        )
        let freshTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "已完成",
            lastUserMessage: "当前任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(1),
            latestActiveAt: baseDate.addingTimeInterval(-1)
        )

        XCTAssertTrue(SessionStateReducer.shouldApplyTranscriptCompletion(freshTranscript, to: stop))
    }

    @Test func testTranscriptCompletionDoesNotOverrideFailureEvent() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_150)
        let failure = AgentEvent(
            id: "codex-aborted",
            source: .codexCli,
            kind: .status,
            timestamp: baseDate,
            payload: .object(["codex_event_type": .string("turn_aborted")])
        )
        let oldCompleteTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "上一轮已完成",
            lastUserMessage: "上一轮任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(-20),
            latestActiveAt: baseDate.addingTimeInterval(-21)
        )

        XCTAssertFalse(
            SessionStateReducer.shouldApplyTranscriptCompletion(oldCompleteTranscript, to: failure),
            "Failed or aborted events must not be overwritten by stale transcript completion"
        )
        XCTAssertEqual(SessionStateReducer.status(after: .thinking, event: failure), .failed)
    }

    private func sessionEvent(
        id: String? = nil,
        kind: AgentEventKind,
        timestamp: Date,
        payload: [String: JSONValue]
    ) -> AgentEvent {
        AgentEvent(
            id: id ?? kind.rawValue,
            source: .codexCli,
            kind: kind,
            timestamp: timestamp,
            payload: .object(payload)
        )
    }
}
