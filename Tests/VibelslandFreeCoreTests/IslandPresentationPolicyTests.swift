import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct IslandPresentationPolicyTests {
    @Test func testIslandPresentationPolicyKeepsIdleStateSmall() {
        let now = Date(timeIntervalSince1970: 1_800_001_300)
        let recentDone = presentationPolicySession(
            id: "recent-done",
            status: .done,
            updatedAt: now.addingTimeInterval(-20)
        )
        let staleThinking = presentationPolicySession(
            id: "stale-thinking",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-3 * 60 * 60)
        )
        let activeTool = presentationPolicySession(
            id: "active-tool",
            status: .runningTool,
            updatedAt: now
        )
        let pendingApproval = AgentSession(
            id: "approval-session",
            title: "approval",
            prompt: "approval",
            source: .codexCli,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            updatedAt: now,
            status: .waitingApproval,
            activity: [],
            approval: ApprovalRequest(
                id: "approval",
                source: .codexCli,
                title: "Codex 请求权限",
                detail: "swift test",
                tool: "Bash",
                workspace: "/tmp/vibelsland",
                availableDecisions: [.accept, .decline],
                suggestedSessionAllow: false,
                supportsCancel: false,
                createdAt: now
            ),
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )

        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [], isExpanded: false, now: now),
            .idleMini,
            "No sessions should present the small idle circle"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [recentDone, staleThinking], isExpanded: false, now: now),
            .idleMini,
            "Recent completed and stale active-looking sessions do not keep the task pill open"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.compactSize(sessions: [recentDone], now: now),
            CGSize(width: 34, height: 34),
            "Idle compact size is the small circle"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [activeTool], isExpanded: false, now: now),
            .compactTask,
            "Active work expands to the task pill"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [pendingApproval], isExpanded: false, now: now),
            .compactTask,
            "Pending approval keeps the task pill visible"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.compactSize(sessions: [activeTool], now: now),
            CGSize(width: 244, height: 42),
            "Active compact size stays stable"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [activeTool], isExpanded: true, now: now),
            .expanded,
            "Expanded presentation is explicit regardless of active status"
        )
    }

    @Test func testBridgeRuntimeHealthPolicyRequiresRealSecureSocket() {
        let healthySocket = BridgeSocketInspection(
            exists: true,
            isSocket: true,
            ownerMatchesCurrentUser: true,
            permissions: 0o600
        )
        let healthy = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: true,
            bridgeExecutable: true,
            socket: healthySocket
        )
        XCTAssertEqual(healthy.status, .normal)
        XCTAssertEqual(healthy.detail, "本机桥接脚本和 socket 正常")

        let regularFileSocket = BridgeSocketInspection(
            exists: true,
            isSocket: false,
            ownerMatchesCurrentUser: true,
            permissions: 0o600
        )
        XCTAssertEqual(
            BridgeRuntimeHealthPolicy.item(
                bridgeEnabled: true,
                bridgeExecutable: true,
                socket: regularFileSocket
            ).status,
            .needsAction,
            "A stale regular file at the socket path must not be shown as healthy"
        )

        let loosePermissionsSocket = BridgeSocketInspection(
            exists: true,
            isSocket: true,
            ownerMatchesCurrentUser: true,
            permissions: 0o644
        )
        let loosePermissions = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: true,
            bridgeExecutable: true,
            socket: loosePermissionsSocket
        )
        XCTAssertEqual(loosePermissions.status, .needsAction)
        XCTAssertTrue(
            loosePermissions.detail.contains("权限应为 600"),
            "Wrong socket permissions should tell the user what to repair"
        )

        let disabled = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: false,
            bridgeExecutable: false,
            socket: .missing
        )
        XCTAssertEqual(disabled.status, .disabled)
        XCTAssertFalse(
            disabled.isActionable,
            "Disabled sources stay out of exception-only health UI"
        )
    }

    @Test func testIslandLayoutSignatureOnlyChangesForLayoutRelevantState() {
        let now = Date(timeIntervalSince1970: 1_800_001_500)
        let active = presentationPolicySession(
            id: "active",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-20)
        )
        let sameLayoutTextChange = presentationPolicySession(
            id: "active",
            title: "updated text",
            prompt: "updated text",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-10)
        )
        let expiringActive = presentationPolicySession(
            id: "expiring-active",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-DashboardSessionPolicy.activeHideAfter + 1)
        )
        let healthWarning = HealthCheckItem(
            id: "bridge",
            name: "Bridge",
            status: .needsAction,
            detail: "需要重新安装 Hook",
            suggestedAction: "安装 Hooks"
        )

        XCTAssertEqual(
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [sameLayoutTextChange],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            "Text-only session refreshes should not resize or reorder the window"
        )

        XCTAssertNotEqual(
            IslandLayoutSignature(
                sessions: [expiringActive],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [expiringActive],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now.addingTimeInterval(2)
            ),
            "Aging active sessions must still shrink the compact task pill back to the idle circle"
        )

        XCTAssertNotEqual(
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [],
                isExpanded: true,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [healthWarning],
                isExpanded: true,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            "Health warnings affect expanded window height"
        )
    }

    @Test func testIslandMotionPolicyKeepsLoadingSpinnerCalm() {
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool), 4.2)
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .thinking), 4.8)
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .waitingApproval), 5.2)
        XCTAssertTrue(
            IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool) >= 4.0,
            "Running spinner should stay slower than the earlier too-fast animation"
        )
        XCTAssertTrue(
            IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .thinking)
                > IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool),
            "Thinking state should feel calmer than active tool execution"
        )
    }

    @Test func testIslandMotionPolicyBoundsMiniRingAndBreathingLights() {
        XCTAssertEqual(IslandMotionPolicy.MiniProgressRing.rotationDegrees(time: 3.4, status: .runningTool), 0)
        XCTAssertEqual(IslandMotionPolicy.MiniProgressRing.rotationDegrees(time: 2.0, status: .idle), 0)
        XCTAssertTrue(
            IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .idle)
                > IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .runningTool),
            "Idle mini ring should refresh less often than active mini ring"
        )
        XCTAssertTrue(
            IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .runningTool) <= 1.0 / 55.0,
            "Active mini ring should render close to display refresh instead of visibly stepping"
        )
        XCTAssertTrue(
            IslandMotionPolicy.BreathingLights.refreshInterval(for: .thinking) <= 1.0 / 28.0,
            "Breathing lights need a smooth active cadence"
        )
        XCTAssertFalse(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .idle), "Idle mini lights should not keep a timeline alive")
        XCTAssertFalse(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .failed), "Static warning lights avoid idle CPU work")
        XCTAssertTrue(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .thinking), "Active sessions keep breathing lights animated")
        XCTAssertTrue(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .waitingApproval), "Approval states keep breathing lights animated")

        for status in [SessionStatus.idle, .thinking, .runningTool, .waitingApproval, .done, .failed] {
            let lowOpacity = IslandMotionPolicy.BreathingLights.opacity(for: 0, status: status)
            let highOpacity = IslandMotionPolicy.BreathingLights.opacity(for: 1, status: status)
            XCTAssertTrue((0...1).contains(lowOpacity), "Breathing light low opacity is bounded")
            XCTAssertTrue((0...1).contains(highOpacity), "Breathing light high opacity is bounded")
            XCTAssertTrue(highOpacity >= lowOpacity, "Breathing light opacity increases with pulse")
        }
    }

    @Test func testIslandWindowTransitionPolicyAnimatesCollapse() {
        XCTAssertEqual(IslandMotionPolicy.WindowTransition.duration(expanded: true), 0.32)
        XCTAssertEqual(IslandMotionPolicy.WindowTransition.duration(expanded: false), 0.42)
        XCTAssertEqual(IslandMotionPolicy.ContentTransition.crossfadeDuration, 0.18)
        XCTAssertTrue(
            IslandMotionPolicy.WindowTransition.duration(expanded: false) >= 0.36,
            "Collapse should be long enough to survive SwiftUI content relayout instead of snapping closed"
        )
        XCTAssertTrue(
            IslandMotionPolicy.ContentTransition.crossfadeDuration <
                IslandMotionPolicy.WindowTransition.duration(expanded: false),
            "Content should crossfade inside the longer collapse frame transition"
        )
        XCTAssertTrue(
            IslandMotionPolicy.WindowTransition.resetDelay(expanded: false) >
                UInt64(IslandMotionPolicy.WindowTransition.duration(expanded: false) * 1_000_000_000),
            "Transition flags should clear only after the collapse animation settles"
        )
    }

    private func presentationPolicySession(
        id: String,
        title: String? = nil,
        prompt: String? = nil,
        status: SessionStatus,
        updatedAt: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: title ?? id,
            prompt: prompt ?? id,
            source: .codexDesktop,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
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
}
