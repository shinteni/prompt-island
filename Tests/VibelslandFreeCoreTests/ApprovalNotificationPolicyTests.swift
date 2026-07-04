import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct ApprovalNotificationPolicyTests {
    @Test func testNotificationIdentifierRoundTrip() {
        let identifier = ApprovalNotificationPolicy.notificationIdentifier(approvalID: "claude-approval-42")
        XCTAssertEqual(
            ApprovalNotificationPolicy.approvalID(fromNotificationIdentifier: identifier),
            "claude-approval-42",
            "Identifier encodes and decodes the approval ID"
        )
        XCTAssertTrue(
            ApprovalNotificationPolicy.approvalID(fromNotificationIdentifier: "other.notification") == nil,
            "Foreign identifiers decode to nil"
        )
        XCTAssertTrue(
            ApprovalNotificationPolicy.approvalID(
                fromNotificationIdentifier: ApprovalNotificationPolicy.notificationIdentifier(approvalID: "")
            ) == nil,
            "Empty approval ID decodes to nil"
        )
    }

    @Test func testShouldNotifyTruthTable() {
        let pending = notificationApproval()
        XCTAssertTrue(
            ApprovalNotificationPolicy.shouldNotify(enabled: true, doNotDisturb: false, approval: pending),
            "Enabled without DND notifies"
        )
        XCTAssertFalse(
            ApprovalNotificationPolicy.shouldNotify(enabled: false, doNotDisturb: false, approval: pending),
            "Disabled never notifies"
        )
        XCTAssertFalse(
            ApprovalNotificationPolicy.shouldNotify(enabled: true, doNotDisturb: true, approval: pending),
            "Do Not Disturb suppresses notifications"
        )
        XCTAssertFalse(
            ApprovalNotificationPolicy.shouldNotify(
                enabled: true,
                doNotDisturb: false,
                approval: notificationApproval(expired: true)
            ),
            "Expired approvals do not notify"
        )
        XCTAssertFalse(
            ApprovalNotificationPolicy.shouldNotify(
                enabled: true,
                doNotDisturb: false,
                approval: notificationApproval(resolutionState: .resolving)
            ),
            "Approvals already resolving do not notify"
        )
    }

    @Test func testDecisionMappingHonorsAvailableDecisions() {
        let approval = notificationApproval()
        XCTAssertEqual(
            ApprovalNotificationPolicy.decision(
                forActionIdentifier: ApprovalNotificationPolicy.acceptActionIdentifier,
                approval: approval
            ),
            .accept,
            "Accept action maps to accept"
        )
        XCTAssertEqual(
            ApprovalNotificationPolicy.decision(
                forActionIdentifier: ApprovalNotificationPolicy.declineActionIdentifier,
                approval: approval
            ),
            .decline,
            "Decline action maps to decline"
        )
        XCTAssertTrue(
            ApprovalNotificationPolicy.decision(forActionIdentifier: "unknown.action", approval: approval) == nil,
            "Unknown actions map to nil"
        )

        let declineOnly = notificationApproval(availableDecisions: [.decline])
        XCTAssertTrue(
            ApprovalNotificationPolicy.decision(
                forActionIdentifier: ApprovalNotificationPolicy.acceptActionIdentifier,
                approval: declineOnly
            ) == nil,
            "Unsupported decisions map to nil even for known actions"
        )
    }

    @Test func testBodyPrefersDetailAndTruncates() {
        XCTAssertEqual(
            ApprovalNotificationPolicy.body(for: notificationApproval(detail: "rm -rf build")),
            "rm -rf build",
            "Body uses the approval detail"
        )
        XCTAssertEqual(
            ApprovalNotificationPolicy.body(for: notificationApproval(detail: "")),
            "Bash",
            "Empty detail falls back to the tool name"
        )
        let long = String(repeating: "x", count: 200)
        let body = ApprovalNotificationPolicy.body(for: notificationApproval(detail: long))
        XCTAssertEqual(body.count, 141, "Long bodies truncate to the limit plus ellipsis")
        XCTAssertTrue(body.hasSuffix("…"), "Truncated bodies end with an ellipsis")
        XCTAssertEqual(
            ApprovalNotificationPolicy.body(for: notificationApproval(detail: "line one\nline two")),
            "line one line two",
            "Newlines flatten into single spaces"
        )
    }

    @Test func testConfigurationDefaultsToDisabledAndDecodesLegacyConfig() throws {
        XCTAssertFalse(AppConfiguration.default.enableApprovalNotifications, "Notifications are opt-in")

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
        XCTAssertFalse(decoded.enableApprovalNotifications, "Legacy configs without the key stay disabled")
    }

    private func notificationApproval(
        detail: String = "run command",
        availableDecisions: [ApprovalDecision] = [.accept, .decline],
        expired: Bool = false,
        resolutionState: ApprovalResolutionState = .pending
    ) -> ApprovalRequest {
        ApprovalRequest(
            id: "approval-1",
            source: .claudeCode,
            title: "Approval",
            detail: detail,
            tool: "Bash",
            workspace: "/tmp/vibelsland",
            availableDecisions: availableDecisions,
            suggestedSessionAllow: false,
            supportsCancel: false,
            isExpired: expired,
            resolutionState: resolutionState,
            createdAt: Date()
        )
    }
}
