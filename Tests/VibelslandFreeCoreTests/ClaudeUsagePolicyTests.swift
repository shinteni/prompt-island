import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct ClaudeUsagePolicyTests {
    @Test func testParseTurnFromAssistantLine() throws {
        let object = try line(input: 1_000, output: 200, cacheWrite: 300, cacheRead: 5_000, model: "claude-sonnet-4-5")
        let turn = ClaudeUsagePolicy.parseTurn(from: object)
        XCTAssertEqual(turn?.inputTokens, 1_000, "Input tokens parse")
        XCTAssertEqual(turn?.outputTokens, 200, "Output tokens parse")
        XCTAssertEqual(turn?.cacheWriteTokens, 300, "Cache write tokens parse")
        XCTAssertEqual(turn?.cacheReadTokens, 5_000, "Cache read tokens parse")
        XCTAssertEqual(turn?.model, "claude-sonnet-4-5", "Model parses")
        XCTAssertEqual(turn?.totalTokens, 6_500, "Total sums every bucket")
    }

    @Test func testParseTurnRejectsNonAssistantAndEmptyUsage() throws {
        var userLine = try line(input: 10, output: 10, cacheWrite: 0, cacheRead: 0, model: "claude-sonnet-4-5")
        userLine["type"] = "user"
        XCTAssertTrue(ClaudeUsagePolicy.parseTurn(from: userLine) == nil, "User lines never parse as turns")

        let zero = try line(input: 0, output: 0, cacheWrite: 0, cacheRead: 0, model: "claude-sonnet-4-5")
        XCTAssertTrue(ClaudeUsagePolicy.parseTurn(from: zero) == nil, "Zero usage parses to nil")
    }

    @Test func testCostEstimatesPerModelFamily() {
        let opus = ClaudeUsagePolicy.costUSD(inputTokens: 1_000_000, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, model: "claude-opus-4")
        XCTAssertEqual(opus ?? 0, 15.0, "Opus input rate is 15 per MTok")

        let sonnetOutput = ClaudeUsagePolicy.costUSD(inputTokens: 0, outputTokens: 1_000_000, cacheWriteTokens: 0, cacheReadTokens: 0, model: "claude-sonnet-4-5")
        XCTAssertEqual(sonnetOutput ?? 0, 15.0, "Sonnet output rate is 15 per MTok")

        let haikuCacheRead = ClaudeUsagePolicy.costUSD(inputTokens: 0, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 1_000_000, model: "claude-haiku-4-5")
        XCTAssertEqual(haikuCacheRead ?? 0, 0.1, "Cache reads bill at a tenth of the input rate")

        let sonnetCacheWrite = ClaudeUsagePolicy.costUSD(inputTokens: 0, outputTokens: 0, cacheWriteTokens: 1_000_000, cacheReadTokens: 0, model: "claude-sonnet-4-5")
        XCTAssertEqual(sonnetCacheWrite ?? 0, 3.75, "Cache writes bill at 1.25x the input rate")

        XCTAssertTrue(
            ClaudeUsagePolicy.costUSD(inputTokens: 100, outputTokens: 100, cacheWriteTokens: 0, cacheReadTokens: 0, model: "unknown-model") == nil,
            "Unknown models produce no estimate"
        )
        XCTAssertTrue(
            ClaudeUsagePolicy.costUSD(inputTokens: 100, outputTokens: 100, cacheWriteTokens: 0, cacheReadTokens: 0, model: nil) == nil,
            "Missing model produces no estimate"
        )
    }

    @Test func testAggregateAccumulatesAndMapsToSnapshot() throws {
        var aggregate = ClaudeUsageAggregate()
        XCTAssertTrue(ClaudeUsagePolicy.usageSnapshot(from: aggregate) == nil, "Empty aggregate maps to nil")

        aggregate.add(ClaudeTurnUsage(inputTokens: 100, outputTokens: 50, cacheWriteTokens: 10, cacheReadTokens: 40, model: "claude-sonnet-4-5"))
        aggregate.add(ClaudeTurnUsage(inputTokens: 200, outputTokens: 100, cacheWriteTokens: 0, cacheReadTokens: 300, model: nil))

        XCTAssertEqual(aggregate.turns, 2, "Turn count accumulates")
        XCTAssertEqual(aggregate.totalTokens, 800, "Totals accumulate across turns")
        XCTAssertEqual(aggregate.lastTurnTokens, 600, "Last turn reflects the newest usage")
        XCTAssertEqual(aggregate.model, "claude-sonnet-4-5", "Model sticks once seen")

        let snapshot = ClaudeUsagePolicy.usageSnapshot(from: aggregate)
        XCTAssertEqual(snapshot?.lastTokens, 600, "Snapshot last tokens map")
        XCTAssertEqual(snapshot?.totalTokens, 800, "Snapshot totals map")
        XCTAssertTrue(snapshot?.estimatedCostUSD != nil, "Known model yields a cost estimate")
    }

    @Test func testCostTextFormatting() {
        XCTAssertEqual(UsageSnapshot.costText(0.005), "<$0.01", "Tiny costs floor to <$0.01")
        XCTAssertEqual(UsageSnapshot.costText(0.42), "$0.42", "Cents format to two places")
        XCTAssertEqual(UsageSnapshot.costText(12.3456), "$12.35", "Dollars round to two places")
    }

    @Test func testReaderAggregatesIncrementally() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelsland-usage-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = directory.appendingPathComponent("session.jsonl")

        let reader = ConversationTranscriptReader(homeURL: directory)
        try assistantLine(input: 100, output: 50, model: "claude-sonnet-4-5")
            .write(to: transcript, atomically: true, encoding: .utf8)

        let first = reader.claudeUsageAggregate(for: transcript)
        XCTAssertEqual(first?.turns, 1, "First scan finds the first turn")
        XCTAssertEqual(first?.totalTokens, 150, "First scan sums the first turn")

        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(assistantLine(input: 200, output: 100, model: "claude-sonnet-4-5").utf8))
        try handle.close()

        let second = reader.claudeUsageAggregate(for: transcript)
        XCTAssertEqual(second?.turns, 2, "Appended turn is picked up incrementally")
        XCTAssertEqual(second?.totalTokens, 450, "Totals include the appended turn")
        XCTAssertEqual(second?.lastTurnTokens, 300, "Last turn tracks the appended usage")

        let cached = reader.claudeUsageAggregate(for: transcript)
        XCTAssertEqual(cached?.totalTokens, 450, "Unchanged files return the cached aggregate")
    }

    private func assistantLine(input: Int, output: Int, model: String) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"2026-07-04T00:00:00Z\",\"message\":{\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0},\"content\":[]}}\n"
    }

    private func line(input: Int, output: Int, cacheWrite: Int, cacheRead: Int, model: String) throws -> [String: Any] {
        let json = """
        {
          "type": "assistant",
          "message": {
            "model": "\(model)",
            "usage": {
              "input_tokens": \(input),
              "output_tokens": \(output),
              "cache_creation_input_tokens": \(cacheWrite),
              "cache_read_input_tokens": \(cacheRead)
            }
          }
        }
        """.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: json) as! [String: Any]
    }
}
