import Foundation
import SQLite3
import Testing
@testable import VibelslandFreeCore

@Suite
struct BackgroundReaderTests {
    @Test func explicitTranscriptDoesNotEnumerateHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("session.jsonl")
        try Data("{\"type\":\"user\",\"message\":{\"content\":\"hello\"}}\n".utf8).write(to: url)
        let manager = CountingFileManager()
        let history = root.appendingPathComponent(".claude/projects")
        try manager.createDirectory(at: history, withIntermediateDirectories: true)
        let reader = ConversationTranscriptReader(fileManager: manager, homeURL: root)
        let event = AgentEvent(source: .claudeCode, kind: .prompt, sessionId: "session",
                               payload: .object(["transcript_path": .string(url.path)]))
        #expect(reader.loadSnapshot(for: event)?.lastUserMessage == "hello")
        #expect(manager.historyChecks == 0)
    }

    @Test func missingExplicitTranscriptFallsBackToDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = root.appendingPathComponent(".claude/projects/project")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"type\":\"user\",\"message\":{\"content\":\"found\"}}\n".utf8)
            .write(to: history.appendingPathComponent("session.jsonl"))
        let reader = ConversationTranscriptReader(homeURL: root)
        let event = AgentEvent(source: .claudeCode, kind: .prompt, sessionId: "session",
                               payload: .object(["transcript_path": .string(root.appendingPathComponent("missing.jsonl").path)]))
        #expect(reader.loadSnapshot(for: event)?.lastUserMessage == "found")
    }

    @Test func databaseFailureIsNotAnEmptySnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a database".utf8).write(to: url)
        let reader = CodexDesktopStateReader(stateURL: url)
        #expect(throws: (any Error).self) { try reader.loadRecentThreads() }
    }

    @Test func nativeDatabaseReadsParentsChildrenAndEmptyResults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT, title TEXT, source TEXT,
        approval_mode TEXT, sandbox_policy TEXT, rollout_path TEXT, updated_at INTEGER,
        updated_at_ms INTEGER, model TEXT, agent_nickname TEXT, agent_role TEXT, archived INTEGER);
        """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        let reader = CodexDesktopStateReader(stateURL: url)
        #expect(try reader.loadRecentThreads().isEmpty)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sql = """
        INSERT INTO threads (id, title, source, updated_at, updated_at_ms, archived) VALUES
        ('parent', '父任务 '' quoted', 'desktop', 1999999990, 1999999990123, 0),
        ('child', '子任务', '{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}', 1999999995, 1999999995000, 0),
        ('archived', 'archived', 'desktop', 2000000000, 2000000000000, 1),
        ('old-child', 'stale', '{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}', 1000000000, 1000000000000, 0);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        let records = try reader.loadRecentThreads(limit: 1, now: now)
        #expect(records.map(\.id) == ["parent", "child"])
        #expect(records.first?.title == "父任务 ' quoted")
        #expect(records.first?.updatedAtMilliseconds == 1_999_999_990_123)
        #expect(records.first?.updatedAt == Date(timeIntervalSince1970: 1_999_999_990))
        #expect(records.last?.parentThreadID == "parent")
        // A new read must observe committed updates, without retaining the old read transaction.
        #expect(sqlite3_exec(db, "UPDATE threads SET archived = 1", nil, nil, nil) == SQLITE_OK)
        #expect(try reader.loadRecentThreads(now: now).isEmpty)
    }
}

private final class CountingFileManager: FileManager, @unchecked Sendable {
    var historyChecks = 0

    override func fileExists(atPath path: String) -> Bool {
        if path.hasSuffix("/.claude/projects") { historyChecks += 1 }
        return super.fileExists(atPath: path)
    }
}
