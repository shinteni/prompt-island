import Combine
import Foundation
import Testing
@testable import VibelslandFree
@testable import VibelslandFreeCore

@Suite @MainActor
struct SessionStorePublicationTests {
    @Test func transcriptEnrichmentDoesNotBlockOrPublishStaleContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFile = root.appendingPathComponent("old.jsonl")
        let newFile = root.appendingPathComponent("new.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try Data("{\"type\":\"user\",\"timestamp\":\"\(timestamp)\",\"message\":{\"content\":\"stale transcript\"}}\n".utf8).write(to: oldFile)
        try Data("{\"type\":\"user\",\"timestamp\":\"\(timestamp)\",\"message\":{\"content\":\"fresh transcript\"}}\n".utf8).write(to: newFile)
        let manager = PausedTranscriptFileManager(pausedPath: oldFile.path)
        defer { manager.resume.signal() }
        let store = SessionStore(
            configurationStore: AppConfigurationStore(url: root.appendingPathComponent("config.json")),
            transcriptReader: ConversationTranscriptReader(fileManager: manager, homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json"))
        )
        defer { store.statsStore.flush() }
        var messages: [String] = []
        let observation = store.$sessions.sink { sessions in
            messages += sessions.compactMap(\.lastUserMessage)
        }
        defer { observation.cancel() }
        store.ingest(event: AgentEvent(source: .claudeCode, kind: .prompt, sessionId: "session",
            payload: .object(["prompt": .string("first hook"), "transcript_path": .string(oldFile.path)])))
        #expect(store.sessions.first?.lastUserMessage == "first hook")
        let started = await Task.detached { @Sendable [manager] in manager.waitUntilReadPaused() }.value
        #expect(started)
        store.ingest(event: AgentEvent(source: .claudeCode, kind: .prompt, sessionId: "session",
            payload: .object(["prompt": .string("second hook"), "transcript_path": .string(newFile.path)])))
        #expect(store.sessions.first?.lastUserMessage == "second hook")
        manager.resume.signal()
        await store.transcriptRefreshTask?.value
        #expect(store.sessions.first?.lastUserMessage == "fresh transcript")
        #expect(!messages.contains("stale transcript"))
    }

    @Test func upsertPublishesOnlyTheFinalStateAndSkipsIdenticalValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(
            configurationStore: AppConfigurationStore(url: root.appendingPathComponent("config.json")),
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json"))
        )
        var publications = 0
        let observation = store.$sessions.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel(); store.statsStore.flush() }
        let event = AgentEvent(source: .codexCli, kind: .prompt, sessionId: "test",
                               payload: .object(["prompt": .string("test")]))
        store.ingest(event: event)
        #expect(publications == 1)
        let session = try #require(store.sessions.first)
        store.upsert(session)
        #expect(publications == 1)
        #expect(store.statsStore.todayStats().sessionsStarted.values.reduce(0, +) == 1)
    }

    @Test func pendingApprovalsSurviveTheVisibleSessionLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(
            configurationStore: AppConfigurationStore(url: root.appendingPathComponent("config.json")),
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json"))
        )
        defer { store.statsStore.flush() }
        for index in 0..<8 {
            let event = AgentEvent(source: .codexCli, kind: .approval, sessionId: "approval-\(index)",
                                   payload: .object(["tool_name": .string("test-tool")]))
            store.ingest(event: event)
        }
        #expect(store.sessions.compactMap(\.approval).count == 8)
    }

    @Test func failedRefreshPreservesTheLastGoodSessions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("state.sqlite")
        try Data("broken database".utf8).write(to: database)
        let store = SessionStore(
            configurationStore: AppConfigurationStore(url: root.appendingPathComponent("config.json")),
            codexStateReader: CodexDesktopStateReader(stateURL: database),
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json")),
            logger: AppLogger(fileURL: root.appendingPathComponent("app.log"))
        )
        defer { store.statsStore.flush() }
        store.ingest(event: AgentEvent(source: .codexDesktop, kind: .prompt, sessionId: "codex-desktop-kept"))
        let before = store.sessions
        await store.refreshCodexDesktop(force: true)
        #expect(store.sessions == before)
    }

    @Test func batchRefreshPublishesOnceAndDoesNotRepeatStatistics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(
            configurationStore: AppConfigurationStore(url: root.appendingPathComponent("config.json")),
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json"))
        )
        defer { store.statsStore.flush() }
        store.ingest(event: AgentEvent(source: .codexCli, kind: .prompt, sessionId: "first"))
        let first = try #require(store.sessions.first)
        var second = first
        second.id = "second"
        second.updatedAt = first.updatedAt.addingTimeInterval(1)
        var values: [[AgentSession]] = []
        let observation = store.$sessions.dropFirst().sink { values.append($0) }
        defer { observation.cancel() }
        store.publishSessions([first, second])
        store.publishSessions([first, second])
        #expect(values.count == 1)
        #expect(values.first?.map(\.id) == ["second", "first"])
    }
}

private final class PausedTranscriptFileManager: FileManager, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let pausedPath: String

    init(pausedPath: String) {
        self.pausedPath = pausedPath
        super.init()
    }

    func waitUntilReadPaused() -> Bool {
        started.wait(timeout: .now() + 3) == .success
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if path == pausedPath {
            started.signal()
            _ = resume.wait(timeout: .now() + 5)
        }
        return try super.attributesOfItem(atPath: path)
    }
}
