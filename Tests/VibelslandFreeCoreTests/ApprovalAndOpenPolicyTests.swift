import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct ApprovalAndOpenPolicyTests {
    @Test func testApprovalResolutionStateTextAndTerminalStates() {
        XCTAssertEqual(ApprovalResolutionState.pending.title, "等待审批")
        XCTAssertEqual(ApprovalResolutionState.resolving.title, "正在返回审批")
        XCTAssertEqual(ApprovalResolutionState.accepted.title, "已允许")
        XCTAssertEqual(ApprovalResolutionState.declined.title, "已拒绝")
        XCTAssertEqual(ApprovalResolutionState.cancelled.title, "已取消")
        XCTAssertEqual(ApprovalResolutionState.timedOut.title, "审批已超时")
        XCTAssertEqual(ApprovalResolutionState.sendFailed.title, "回传失败")
        XCTAssertEqual(ApprovalResolutionState.disconnected.title, "连接断开")

        XCTAssertFalse(ApprovalResolutionState.pending.isTerminal)
        XCTAssertFalse(ApprovalResolutionState.resolving.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.accepted.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.declined.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.cancelled.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.timedOut.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.sendFailed.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.disconnected.isTerminal)
    }

    @Test func testApprovalTerminalStatesDisplayExplicitStatus() {
        let cancelled = SessionDisplaySnapshot(session: approvalDisplaySession(state: .cancelled))
        XCTAssertEqual(cancelled.statusText, "已取消")
        XCTAssertEqual(cancelled.primaryLine, "已取消")

        let timedOut = SessionDisplaySnapshot(session: approvalDisplaySession(state: .timedOut, expired: true))
        XCTAssertEqual(timedOut.statusText, "审批已超时")
        XCTAssertEqual(timedOut.primaryLine, "审批已超时")

        let disconnected = SessionDisplaySnapshot(session: approvalDisplaySession(state: .disconnected))
        XCTAssertEqual(disconnected.statusText, "连接断开")
        XCTAssertEqual(disconnected.primaryLine, "连接断开")
    }

    @Test func testCodexThreadLinkPolicyUsesExplicitThreadID() {
        let cliNonUUID = linkPolicySession(
            id: "display-session-id",
            source: .codexCli,
            threadID: "thread-non-uuid"
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliNonUUID),
            "thread-non-uuid",
            "Codex CLI deep links use explicit thread id even when it is not a UUID"
        )

        let cliLegacyUUID = linkPolicySession(
            id: "123E4567-E89B-12D3-A456-426614174000",
            source: .codexCli
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliLegacyUUID),
            "123E4567-E89B-12D3-A456-426614174000",
            "Older UUID-backed Codex CLI sessions still deep link"
        )

        let cliWorkspaceFallback = linkPolicySession(
            id: "codexCli-/tmp/work",
            source: .codexCli
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliWorkspaceFallback),
            nil,
            "Synthetic workspace fallback ids are not treated as Codex thread ids"
        )

        let desktop = linkPolicySession(
            id: "codex-desktop-thread-1",
            source: .codexDesktop
        )
        XCTAssertEqual(CodexThreadLinkPolicy.threadID(for: desktop), "thread-1")
        XCTAssertEqual(CodexThreadLinkPolicy.deepLink(for: "thread-1"), "codex://threads/thread-1")
    }

    @Test func testSessionOpenPolicyRoutesCardsToExpectedTargets() {
        let desktop = linkPolicySession(
            id: "codex-desktop-thread-1",
            source: .codexDesktop
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: desktop),
            .openCodexThread(
                threadID: "thread-1",
                logNamespace: "codex.desktop",
                errorMessage: "无法跳转到 Codex 对话"
            ),
            "Codex Desktop cards deep link to their thread instead of only selecting the row"
        )

        let cliExplicitThread = linkPolicySession(
            id: "display-id",
            source: .codexCli,
            threadID: "thread-non-uuid"
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: cliExplicitThread),
            .openCodexThread(
                threadID: "thread-non-uuid",
                logNamespace: "codex.cli",
                errorMessage: "无法跳转到 Codex CLI 会话"
            ),
            "Codex CLI cards use explicit non-UUID thread ids from hook payloads"
        )

        let cliWithoutThread = linkPolicySession(
            id: "workspace-fallback",
            source: .codexCli
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: cliWithoutThread),
            .focusApplication(.codexCli),
            "Codex CLI sessions without a real thread id still focus Codex instead of failing silently"
        )

        let claudeUUID = linkPolicySession(
            id: "123E4567-E89B-12D3-A456-426614174000",
            source: .claudeCode
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: claudeUUID),
            .focusClaudeCodeTerminal(sessionID: "123E4567-E89B-12D3-A456-426614174000"),
            "Claude CLI cards prefer the matching terminal process when the session id is usable"
        )

        let claudeSynthetic = linkPolicySession(
            id: "claude-/tmp/work",
            source: .claudeCode
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: claudeSynthetic),
            .focusClaudeCodeTerminal(sessionID: nil),
            "Synthetic Claude ids focus a running Claude terminal without pretending to know the exact session"
        )

        let unknown = linkPolicySession(
            id: "unknown",
            source: .unknown
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: unknown),
            .selectOnly,
            "Unknown cards are selectable but do not try to open an unrelated app"
        )
    }

    @Test func testClaudeTerminalFocusPolicyRequiresRealClaudeProcess() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh")
                ],
                runningAppsByPID: [10: "com.apple.Terminal"]
            ),
            nil,
            "A random running terminal should not be focused for an old Claude card when no Claude CLI process is present"
        )
    }

    @Test func testClaudeTerminalFocusPolicyFindsParentTerminal() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh"),
                    ProcessSnapshot(pid: 12, ppid: 11, arguments: "claude --dangerously-skip-permissions")
                ],
                runningAppsByPID: [10: "com.apple.Terminal"]
            ),
            "com.apple.Terminal",
            "Claude CLI cards should focus the terminal that owns the active Claude process"
        )
    }

    @Test func testClaudeTerminalFocusPolicyDoesNotFocusClaudeDesktopParent() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 20, ppid: 1, arguments: "/Applications/Claude.app/Contents/MacOS/Claude"),
                    ProcessSnapshot(pid: 21, ppid: 20, arguments: "claude --print")
                ],
                runningAppsByPID: [20: "com.anthropic.claudefordesktop"]
            ),
            nil,
            "Claude CLI cards must not jump to Claude Desktop when the process parent is not a supported terminal"
        )
    }

    @Test func testClaudeTerminalFocusPolicyPrefersMatchingSessionID() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: "target-session",
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh"),
                    ProcessSnapshot(pid: 12, ppid: 11, arguments: "claude old-session"),
                    ProcessSnapshot(pid: 30, ppid: 1, arguments: "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
                    ProcessSnapshot(pid: 31, ppid: 30, arguments: "-zsh"),
                    ProcessSnapshot(pid: 32, ppid: 31, arguments: "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js target-session")
                ],
                runningAppsByPID: [
                    10: "com.apple.Terminal",
                    30: "com.googlecode.iterm2"
                ]
            ),
            "com.googlecode.iterm2",
            "When a session id is available, jump to the terminal that owns that Claude process"
        )
    }

    @Test func testCodexOpenCommandPolicyForcesDeepLinkIntoCodexApp() {
        XCTAssertEqual(
            CodexOpenCommandPolicy.deepLinkArguments(
                bundleID: "com.openai.codex",
                deepLink: "codex://threads/thread-1"
            ),
            ["-b", "com.openai.codex", "codex://threads/thread-1"],
            "Codex thread deep links should be opened by the Codex app directly"
        )
        XCTAssertEqual(
            CodexOpenCommandPolicy.fallbackDeepLinkArguments("codex://threads/thread-1"),
            ["codex://threads/thread-1"]
        )
        XCTAssertEqual(
            CodexOpenCommandPolicy.focusArguments(bundleID: "com.openai.codex"),
            ["-b", "com.openai.codex"]
        )
    }

    @Test func testMenuBarOpenPanelDoesNotHideVisibleIsland() {
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: false, windowVisible: false),
            .createAndShow
        )
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: true, windowVisible: false),
            .restoreVisible
        )
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: true, windowVisible: true),
            .keepVisible,
            "Menu bar Open Panel should never act as a hide toggle"
        )
    }

    private func approvalDisplaySession(
        state: ApprovalResolutionState,
        expired: Bool = false
    ) -> AgentSession {
        let approval = ApprovalRequest(
            id: "approval-\(state.rawValue)",
            source: .codexDesktop,
            title: "命令执行",
            detail: "swift test",
            tool: "命令执行",
            workspace: "/tmp/vibelsland",
            availableDecisions: [.accept, .decline, .cancel],
            suggestedSessionAllow: false,
            supportsCancel: true,
            isResolving: state == .resolving,
            isExpired: expired,
            resolutionState: state,
            resolutionMessage: state.title,
            createdAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
        return AgentSession(
            id: "approval-display-\(state.rawValue)",
            title: "vibelsland",
            prompt: "vibelsland",
            source: .codexDesktop,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_401),
            status: .waitingApproval,
            activity: [],
            approval: approval,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }

    private func linkPolicySession(
        id: String,
        source: AgentSource,
        threadID: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "session",
            prompt: "session",
            source: source,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            threadID: threadID,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500),
            status: .thinking,
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
