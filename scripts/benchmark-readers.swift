// Build with: swiftc -O -parse-as-library -package-name VibelslandFree Sources/VibelslandFreeCore/*.swift scripts/benchmark-readers.swift -o /tmp/benchmark-readers
// Uses synthetic data only. Compare optimized builds on the same machine.
import Foundation
import SQLite3

@main
struct ReaderBenchmark {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("island-benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = root.appendingPathComponent(".claude/projects/project")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        for index in 0..<5_000 {
            try Data().write(to: history.appendingPathComponent("history-\(index).jsonl"))
        }
        let transcript = root.appendingPathComponent("active.jsonl")
        try Data("{\"type\":\"user\",\"message\":{\"content\":\"benchmark\"}}\n".utf8).write(to: transcript)
        let event = AgentEvent(source: .claudeCode, kind: .prompt, sessionId: "active",
                               payload: .object(["transcript_path": .string(transcript.path)]))
        let reader = ConversationTranscriptReader(homeURL: root)
        let clock = ContinuousClock()
        let transcriptTime = clock.measure {
            for _ in 0..<100 { _ = reader.loadSnapshot(for: event) }
        }

        let state = root.appendingPathComponent("state.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(state.path, &db) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT, title TEXT, source TEXT,
        approval_mode TEXT, sandbox_policy TEXT, rollout_path TEXT, updated_at INTEGER,
        updated_at_ms INTEGER, model TEXT, agent_nickname TEXT, agent_role TEXT, archived INTEGER);
        WITH RECURSIVE counter(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM counter WHERE n < 5000)
        INSERT INTO threads (id, title, source, updated_at, updated_at_ms, archived)
        SELECT 'thread-' || n, 'synthetic task', 'desktop', 2000000000 + n, 2000000000000 + n * 1000, 0 FROM counter;
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        let stateReader = CodexDesktopStateReader(stateURL: state)
        let databaseTime = try clock.measure {
            for _ in 0..<100 { _ = try stateReader.loadRecentThreads(limit: 5) }
        }
        print("100 explicit-path reads, 5000 history files: \(transcriptTime)")
        print("100 database refreshes, 5000 threads: \(databaseTime)")
    }
}
