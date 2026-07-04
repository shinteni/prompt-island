import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct RefreshSchedulingPolicyTests {
    @Test func testCodexCadenceMatchesLegacyThrottle() {
        let now = Date()
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [], isExpanded: true, now: now),
            2.0,
            "Expanded island refreshes every 2 seconds"
        )
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [], isExpanded: false, now: now),
            8.0,
            "Idle with no desktop sessions backs off to 8 seconds"
        )

        let active = schedulingSession(id: "a", source: .codexDesktop, status: .runningTool, updatedAt: now)
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [active], isExpanded: false, now: now),
            2.5,
            "Active desktop session keeps the 2.5 second cadence"
        )

        let recent = schedulingSession(id: "r", source: .codexDesktop, status: .done, updatedAt: now.addingTimeInterval(-30))
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [recent], isExpanded: false, now: now),
            2.5,
            "Recently updated desktop session counts as active"
        )

        let stale = schedulingSession(id: "s", source: .codexDesktop, status: .done, updatedAt: now.addingTimeInterval(-90))
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [stale], isExpanded: false, now: now),
            8.0,
            "Stale desktop session backs off"
        )

        let claudeOnly = schedulingSession(id: "c", source: .claudeCode, status: .runningTool, updatedAt: now)
        XCTAssertEqual(
            CodexRefreshCadencePolicy.interval(sessions: [claudeOnly], isExpanded: false, now: now),
            8.0,
            "Non-desktop sessions do not affect the desktop cadence"
        )
    }

    @Test func testAgingScheduleSkipsWorkWhenNothingChanges() {
        let now = Date()
        XCTAssertTrue(
            SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [], isExpanded: true, now: now) == nil,
            "No sessions means no timer at all"
        )

        let hidden = schedulingSession(id: "h", source: .claudeCode, status: .done, updatedAt: now.addingTimeInterval(-600))
        XCTAssertTrue(
            SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [hidden], isExpanded: false, now: now) == nil,
            "Collapsed with only already-hidden sessions never wakes"
        )

        let approval = approvalSchedulingSession(id: "ap", createdAt: now)
        XCTAssertTrue(
            SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [approval], isExpanded: false, now: now) == nil,
            "Pending approvals are event-driven, not time-driven"
        )
    }

    @Test func testAgingScheduleWakesAtVisibilityBoundaries() {
        let now = Date()
        let idle = schedulingSession(id: "i", source: .claudeCode, status: .idle, updatedAt: now.addingTimeInterval(-30))
        let delay = SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [idle], isExpanded: false, now: now)
        XCTAssertEqual(delay ?? -1, 15, "Idle session hides at 45s, so wake in 15s")

        let done = schedulingSession(id: "d", source: .claudeCode, status: .done, updatedAt: now.addingTimeInterval(-100))
        let doneDelay = SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [done], isExpanded: false, now: now)
        XCTAssertEqual(doneDelay ?? -1, 20, "Done session hides at 120s, so wake in 20s")

        let both = SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [idle, done], isExpanded: false, now: now)
        XCTAssertEqual(both ?? -1, 15, "The earliest boundary wins")

        let expanded = SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [done], isExpanded: true, now: now)
        XCTAssertEqual(expanded ?? -1, 15, "Expanded panel keeps the 15s relative-time refresh")

        let imminent = schedulingSession(id: "m", source: .claudeCode, status: .idle, updatedAt: now.addingTimeInterval(-44.9))
        let clamped = SessionAgingSchedulePolicy.nextRefreshDelay(sessions: [imminent], isExpanded: false, now: now)
        XCTAssertEqual(clamped ?? -1, SessionAgingSchedulePolicy.minimumDelay, "Imminent boundaries clamp to the minimum delay")
    }

    @Test func testAutoCollapseGraceMatchesLegacyPolling() {
        XCTAssertEqual(
            IslandAutoCollapsePolicy.graceDuration,
            6.6,
            "Grace duration preserves the old 30 ticks at 0.22s"
        )
    }

    private func schedulingSession(
        id: String,
        source: AgentSource,
        status: SessionStatus,
        updatedAt: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            prompt: id,
            source: source,
            workspace: "/tmp/vibelsland",
            terminal: source.displayName,
            updatedAt: updatedAt,
            status: status,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }

    private func approvalSchedulingSession(id: String, createdAt: Date) -> AgentSession {
        var session = schedulingSession(id: id, source: .claudeCode, status: .waitingApproval, updatedAt: createdAt)
        session.approval = ApprovalRequest(
            id: "approval-\(id)",
            source: .claudeCode,
            title: "Approval",
            detail: "run command",
            tool: "Bash",
            workspace: "/tmp/vibelsland",
            suggestedSessionAllow: false,
            supportsCancel: false,
            createdAt: createdAt
        )
        return session
    }
}
