import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct ApprovalQueuePolicyTests {
    @Test func testQueueOrdersByOldestApprovalAndSkipsExpired() {
        let now = Date()
        let sessions = [
            queueSession(id: "plain", approvalCreatedAt: nil),
            queueSession(id: "newest", approvalCreatedAt: now),
            queueSession(id: "oldest", approvalCreatedAt: now.addingTimeInterval(-300)),
            queueSession(id: "middle", approvalCreatedAt: now.addingTimeInterval(-60)),
            queueSession(id: "expired", approvalCreatedAt: now.addingTimeInterval(-900), expired: true)
        ]
        let queue = ApprovalQueuePolicy.queue(in: sessions)
        XCTAssertEqual(queue.map(\.id), ["oldest", "middle", "newest"], "Queue sorts oldest first and drops expired")
        XCTAssertEqual(ApprovalQueuePolicy.count(in: sessions), 3, "Count matches queue size")
        XCTAssertEqual(ApprovalQueuePolicy.primarySession(in: sessions)?.id, "oldest", "Primary is the oldest approval")
    }

    @Test func testPrimarySelectionStaysConsistentAcrossPolicies() {
        let now = Date()
        let sessions = [
            queueSession(id: "newer", approvalCreatedAt: now),
            queueSession(id: "older", approvalCreatedAt: now.addingTimeInterval(-120))
        ]
        let primaryID = ApprovalQueuePolicy.primarySession(in: sessions)?.id
        XCTAssertEqual(
            DashboardSessionPolicy.pendingApprovalSession(in: sessions)?.id,
            primaryID,
            "Dashboard primary approval matches the queue"
        )
        XCTAssertEqual(
            GlobalHotKeyPolicy.approvalTargetSessionID(in: sessions),
            primaryID,
            "Hotkey jump target matches the queue"
        )
    }

    @Test func testVisibleRowsAndOverflow() {
        let now = Date()
        let sessions = (0..<5).map { index in
            queueSession(id: "s\(index)", approvalCreatedAt: now.addingTimeInterval(TimeInterval(-index)))
        }
        XCTAssertEqual(
            ApprovalQueuePolicy.visibleRows(in: sessions).count,
            ApprovalQueuePolicy.maximumVisibleRows,
            "Visible rows cap at the maximum"
        )
        XCTAssertEqual(ApprovalQueuePolicy.overflowCount(in: sessions), 2, "Overflow counts the hidden approvals")

        let two = Array(sessions.prefix(2))
        XCTAssertEqual(ApprovalQueuePolicy.visibleRows(in: two).count, 2, "Small queues show every row")
        XCTAssertEqual(ApprovalQueuePolicy.overflowCount(in: two), 0, "Small queues have no overflow")
    }

    @Test func testCardHeightFormula() {
        XCTAssertEqual(ApprovalQueuePolicy.cardHeight(rowCount: 0, overflowCount: 0), 0, "Empty queue renders no card")

        let two = ApprovalQueuePolicy.cardHeight(rowCount: 2, overflowCount: 0)
        let expectedTwo = ApprovalQueuePolicy.cardVerticalPadding * 2
            + ApprovalQueuePolicy.headerHeight
            + 2 * ApprovalQueuePolicy.rowHeight
            + 2 * ApprovalQueuePolicy.elementSpacing
        XCTAssertEqual(two, expectedTwo, "Two-row card height matches layout constants")

        let threeOverflow = ApprovalQueuePolicy.cardHeight(rowCount: 3, overflowCount: 2)
        let expectedThree = ApprovalQueuePolicy.cardVerticalPadding * 2
            + ApprovalQueuePolicy.headerHeight
            + 3 * ApprovalQueuePolicy.rowHeight
            + ApprovalQueuePolicy.overflowFooterHeight
            + 4 * ApprovalQueuePolicy.elementSpacing
        XCTAssertEqual(threeOverflow, expectedThree, "Overflow adds footer height plus one gap")
        XCTAssertTrue(threeOverflow > two, "Height grows with the queue")
    }

    @Test func testVisibleSessionsExcludingIDSetMatchesSingleExclusion() {
        let now = Date()
        let approvalA = queueSession(id: "approval-a", approvalCreatedAt: now.addingTimeInterval(-10))
        let approvalB = queueSession(id: "approval-b", approvalCreatedAt: now)
        let worker = queueSession(id: "worker", approvalCreatedAt: nil)
        let sessions = [approvalA, approvalB, worker]

        let excludedBoth = DashboardSessionPolicy.visibleSessions(
            from: sessions,
            excludingIDs: ["approval-a", "approval-b"]
        )
        XCTAssertEqual(excludedBoth.map(\.id), ["worker"], "Set exclusion removes every queued session")

        let single = DashboardSessionPolicy.visibleSessions(from: sessions, excluding: "approval-a")
        XCTAssertTrue(
            single.contains { $0.id == "approval-b" },
            "Single-ID exclusion keeps the other sessions"
        )
    }

    private func queueSession(
        id: String,
        approvalCreatedAt: Date?,
        expired: Bool = false
    ) -> AgentSession {
        let approval = approvalCreatedAt.map { createdAt in
            ApprovalRequest(
                id: "approval-\(id)",
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
        return AgentSession(
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
