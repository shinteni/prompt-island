import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct GlobalHotKeyPolicyTests {
    @Test func testActionsFollowEnabledSwitch() {
        XCTAssertEqual(GlobalHotKeyPolicy.actions(enabled: false).count, 0, "Disabled hotkeys register nothing")
        XCTAssertEqual(
            GlobalHotKeyPolicy.actions(enabled: true),
            GlobalHotKeyAction.allCases,
            "Enabled hotkeys register every action"
        )
    }

    @Test func testHotKeyIdentifiersAndCombosAreUnique() {
        let ids = GlobalHotKeyAction.allCases.map(\.carbonHotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count, "Carbon hotkey IDs must be unique")

        let combos = GlobalHotKeyAction.allCases.map { "\($0.keyCode)-\($0.carbonModifiers)" }
        XCTAssertEqual(Set(combos).count, combos.count, "Key combos must not collide")
    }

    @Test func testActionLookupRoundTrip() {
        for action in GlobalHotKeyAction.allCases {
            XCTAssertEqual(
                GlobalHotKeyPolicy.action(forHotKeyID: action.carbonHotKeyID),
                action,
                "Registered ID resolves back to its action"
            )
        }
        XCTAssertTrue(
            GlobalHotKeyPolicy.action(forHotKeyID: 9_999) == nil,
            "Unknown hotkey ID resolves to nil"
        )
    }

    @Test func testCarbonModifiersUseControlOption() {
        for action in GlobalHotKeyAction.allCases {
            XCTAssertEqual(action.carbonModifiers, 0x1800, "Default combo is control+option")
        }
    }

    @Test func testApprovalTargetPicksOldestUnexpiredApproval() {
        let now = Date()
        let sessions = [
            hotKeySession(id: "no-approval", approval: nil),
            hotKeySession(id: "newer", approval: approval(id: "a-newer", createdAt: now)),
            hotKeySession(id: "older", approval: approval(id: "a-older", createdAt: now.addingTimeInterval(-120))),
            hotKeySession(id: "expired", approval: approval(id: "a-expired", createdAt: now.addingTimeInterval(-600), expired: true))
        ]
        XCTAssertEqual(
            GlobalHotKeyPolicy.approvalTargetSessionID(in: sessions),
            "older",
            "Jump target is the oldest unexpired approval"
        )
    }

    @Test func testApprovalTargetIsNilWithoutPendingApprovals() {
        let sessions = [
            hotKeySession(id: "plain", approval: nil),
            hotKeySession(id: "expired", approval: approval(id: "a-expired", createdAt: Date(), expired: true))
        ]
        XCTAssertTrue(
            GlobalHotKeyPolicy.approvalTargetSessionID(in: sessions) == nil,
            "No pending approval means no jump target"
        )
    }

    @Test func testConfigurationDefaultsToDisabledAndDecodesLegacyConfig() throws {
        XCTAssertFalse(AppConfiguration.default.enableGlobalHotKeys, "Hotkeys are opt-in")

        let legacyConfig = """
        {
          "enableClaude": true,
          "enableCodexCLI": true,
          "enableCodexDesktop": true,
          "enableSounds": true,
          "soundTheme": "soft",
          "doNotDisturb": false,
          "launchAtLogin": false,
          "islandPosition": "topCenter",
          "approvalTimeoutSeconds": 7200,
          "maxVisibleSessions": 5
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: legacyConfig)
        XCTAssertFalse(decoded.enableGlobalHotKeys, "Legacy configs without the key stay disabled")
    }

    private func approval(id: String, createdAt: Date, expired: Bool = false) -> ApprovalRequest {
        ApprovalRequest(
            id: id,
            source: .claudeCode,
            title: "Approval",
            detail: "run command",
            tool: "Bash",
            workspace: "/tmp/vibelsland",
            suggestedSessionAllow: false,
            supportsCancel: false,
            isExpired: expired,
            createdAt: createdAt
        )
    }

    private func hotKeySession(id: String, approval: ApprovalRequest?) -> AgentSession {
        AgentSession(
            id: id,
            title: id,
            prompt: id,
            source: .claudeCode,
            workspace: "/tmp/vibelsland",
            terminal: "Claude Code",
            updatedAt: Date(),
            status: approval == nil ? .runningTool : .waitingApproval,
            activity: [],
            approval: approval,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }
}
