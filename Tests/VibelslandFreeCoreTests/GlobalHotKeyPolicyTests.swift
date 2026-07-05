import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct GlobalHotKeyPolicyTests {
    @Test func testActionsFollowEnabledAndApprovalScope() {
        XCTAssertEqual(
            GlobalHotKeyPolicy.actions(enabled: false, hasPendingApproval: true).count,
            0,
            "Disabled hotkeys register nothing"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.actions(enabled: true, hasPendingApproval: false),
            [.toggleIsland, .jumpToApproval],
            "Without pending approvals only the resident combos register"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.actions(enabled: true, hasPendingApproval: true),
            GlobalHotKeyAction.allCases,
            "Pending approvals additionally register the bare approve/decline keys"
        )
    }

    @Test func testHotKeyIdentifiersAndDefaultBindingsAreUnique() {
        let ids = GlobalHotKeyAction.allCases.map(\.carbonHotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count, "Carbon hotkey IDs must be unique")

        let combos = GlobalHotKeyAction.allCases.map { action -> String in
            let binding = GlobalHotKeyPolicy.defaultBinding(for: action)
            return "\(binding.keyCode)-\(binding.carbonModifiers)"
        }
        XCTAssertEqual(Set(combos).count, combos.count, "Default bindings must not collide")
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

    @Test func testDefaultBindingsMatchSpec() {
        XCTAssertEqual(
            GlobalHotKeyPolicy.defaultBinding(for: .approveApproval),
            HotKeyBinding(keyCode: 49, carbonModifiers: 0),
            "Approve defaults to bare Space"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.defaultBinding(for: .declineApproval),
            HotKeyBinding(keyCode: 51, carbonModifiers: 0),
            "Decline defaults to bare Delete"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.defaultBinding(for: .toggleIsland),
            HotKeyBinding(keyCode: 34, carbonModifiers: 0x1800),
            "Toggle stays on control+option+I"
        )
        XCTAssertTrue(GlobalHotKeyAction.approveApproval.isApprovalScoped, "Approve is approval-scoped")
        XCTAssertTrue(GlobalHotKeyAction.declineApproval.isApprovalScoped, "Decline is approval-scoped")
        XCTAssertFalse(GlobalHotKeyAction.toggleIsland.isApprovalScoped, "Toggle is resident")
    }

    @Test func testBindingOverridesConflictsAndDisplay() {
        let custom = HotKeyBinding(keyCode: 3, carbonModifiers: GlobalHotKeyPolicy.commandKeyMask) // ⌘F
        let overrides = [GlobalHotKeyAction.approveApproval.rawValue: custom]
        XCTAssertEqual(
            GlobalHotKeyPolicy.binding(for: .approveApproval, overrides: overrides),
            custom,
            "Overrides win over defaults"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.binding(for: .declineApproval, overrides: overrides),
            GlobalHotKeyPolicy.defaultBinding(for: .declineApproval),
            "Actions without overrides keep their defaults"
        )

        XCTAssertEqual(
            GlobalHotKeyPolicy.conflictingAction(binding: custom, excluding: .declineApproval, overrides: overrides),
            .approveApproval,
            "Recording a key already bound elsewhere reports the conflict"
        )
        XCTAssertTrue(
            GlobalHotKeyPolicy.conflictingAction(binding: custom, excluding: .approveApproval, overrides: overrides) == nil,
            "An action never conflicts with its own binding"
        )

        XCTAssertEqual(GlobalHotKeyPolicy.displayText(for: HotKeyBinding(keyCode: 49)), "Space", "Space displays by name")
        XCTAssertEqual(GlobalHotKeyPolicy.displayText(for: HotKeyBinding(keyCode: 51)), "⌫", "Delete displays as backspace glyph")
        XCTAssertEqual(
            GlobalHotKeyPolicy.displayText(for: HotKeyBinding(keyCode: 34, carbonModifiers: 0x1800)),
            "⌃⌥I",
            "Modifier combos render with symbols"
        )
    }

    @Test func testHotKeyBindingCodableRoundTrip() throws {
        let config = AppConfiguration.default
        XCTAssertTrue(config.hotKeyBindings.isEmpty, "Defaults carry no overrides")

        var custom = config
        custom.hotKeyBindings[GlobalHotKeyAction.approveApproval.rawValue] = HotKeyBinding(keyCode: 36, carbonModifiers: 0)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(
            decoded.hotKeyBindings[GlobalHotKeyAction.approveApproval.rawValue],
            HotKeyBinding(keyCode: 36, carbonModifiers: 0),
            "Bindings survive an encode/decode round trip"
        )

        let legacy = try JSONDecoder().decode(AppConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.hotKeyBindings.isEmpty, "Legacy configs without the key decode to no overrides")
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
