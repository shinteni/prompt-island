import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct UsageStatsTests {
    @Test func testDayKeyFormatsCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 2026-07-04 00:30 JST
        let date = DateComponents(calendar: calendar, year: 2026, month: 7, day: 4, hour: 0, minute: 30).date!
        XCTAssertEqual(UsageStatsPolicy.dayKey(for: date, calendar: calendar), "2026-07-04", "Day key uses the local calendar day")
    }

    @Test func testRecentDayKeysAreOrderedOldestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = DateComponents(calendar: calendar, year: 2026, month: 7, day: 4, hour: 12).date!
        let keys = UsageStatsPolicy.recentDayKeys(endingAt: date, count: 3, calendar: calendar)
        XCTAssertEqual(keys, ["2026-07-02", "2026-07-03", "2026-07-04"], "Keys run oldest to newest and include today")
    }

    @Test func testPruneKeepsOnlyRetentionWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = DateComponents(calendar: calendar, year: 2026, month: 7, day: 4, hour: 12).date!
        var days: [String: DailyStats] = [:]
        days["2026-07-04"] = DailyStats()
        days["2026-06-05"] = DailyStats() // 29 天前，保留
        days["2026-06-01"] = DailyStats() // 33 天前，裁掉
        days["2020-01-01"] = DailyStats()
        let pruned = UsageStatsPolicy.prune(days, now: now, calendar: calendar)
        XCTAssertTrue(pruned["2026-07-04"] != nil, "Today survives pruning")
        XCTAssertTrue(pruned["2026-06-05"] != nil, "Days inside the window survive")
        XCTAssertTrue(pruned["2026-06-01"] == nil, "Days outside the window are pruned")
        XCTAssertTrue(pruned["2020-01-01"] == nil, "Ancient days are pruned")
    }

    @Test func testDailyStatsRecordingAndMerge() {
        var day = DailyStats()
        day.recordSessionStarted(source: .claudeCode)
        day.recordSessionStarted(source: .claudeCode)
        day.recordSessionStarted(source: .codexCli)
        day.recordApprovalResolution(.accepted)
        day.recordApprovalResolution(.declined)
        day.recordApprovalResolution(.cancelled)
        day.recordApprovalResolution(.timedOut)

        XCTAssertEqual(day.sessionsStartedTotal, 3, "Started sessions sum across sources")
        XCTAssertEqual(day.sessionsStarted["claudeCode"], 2, "Per-source counts accumulate")
        XCTAssertEqual(day.approvalsAccepted, 1, "Accepted resolutions count")
        XCTAssertEqual(day.approvalsDeclined, 1, "Declined resolutions count")
        XCTAssertEqual(day.approvalsCancelled, 1, "Cancelled resolutions count")

        var other = DailyStats()
        other.recordSessionStarted(source: .claudeCode)
        other.tokens = 500
        other.estimatedCostUSD = 0.5
        day.merge(other)
        XCTAssertEqual(day.sessionsStarted["claudeCode"], 3, "Merge adds per-source counts")
        XCTAssertEqual(day.tokens, 500, "Merge adds tokens")
    }

    @Test func testUsageDeltaHandlesGrowthResetAndNil() {
        let previous = UsageSnapshot(lastTokens: 100, totalTokens: 1_000, contextWindow: 0, estimatedCostUSD: 1.0)
        let grown = UsageSnapshot(lastTokens: 200, totalTokens: 1_500, contextWindow: 0, estimatedCostUSD: 1.4)
        let growth = UsageStatsPolicy.usageDelta(previous: previous, current: grown)
        XCTAssertEqual(growth.tokens, 500, "Growth records the positive delta")
        XCTAssertTrue(abs(growth.costUSD - 0.4) < 1e-9, "Cost delta follows the same rule")

        let first = UsageStatsPolicy.usageDelta(previous: nil, current: previous)
        XCTAssertEqual(first.tokens, 1_000, "First observation counts the full total")

        let reset = UsageSnapshot(lastTokens: 50, totalTokens: 200, contextWindow: 0, estimatedCostUSD: 0.1)
        let afterReset = UsageStatsPolicy.usageDelta(previous: previous, current: reset)
        XCTAssertEqual(afterReset.tokens, 200, "A reset restarts from the new total")

        let none = UsageStatsPolicy.usageDelta(previous: previous, current: nil)
        XCTAssertEqual(none.tokens, 0, "Missing current usage records nothing")
    }

    @Test @MainActor func testStoreRoundTripAndClear() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelsland-stats-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.json")

        let store = UsageStatsStore(url: url)
        store.record { day in
            day.recordSessionStarted(source: .claudeCode)
            day.tokens += 1_234
        }
        store.record { $0.recordApprovalResolution(.accepted) }
        store.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Flush writes the stats file")

        let reloaded = UsageStatsStore(url: url)
        XCTAssertEqual(reloaded.todayStats().sessionsStartedTotal, 1, "Counts survive a reload")
        XCTAssertEqual(reloaded.todayStats().tokens, 1_234, "Tokens survive a reload")
        XCTAssertEqual(reloaded.todayStats().approvalsAccepted, 1, "Approval counts survive a reload")
        XCTAssertEqual(reloaded.weekStats().tokens, 1_234, "Week totals include today")

        reloaded.clearAll()
        XCTAssertEqual(reloaded.todayStats().sessionsStartedTotal, 0, "Clear resets counters")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Clear removes the file")
    }
}
