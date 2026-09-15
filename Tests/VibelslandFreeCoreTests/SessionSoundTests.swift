import Foundation
import Testing
@testable import VibelslandFree
@testable import VibelslandFreeCore

@Suite @MainActor
struct SessionSoundTests {
    @Test func onlyAnActiveTaskBecomingDonePlaysASound() async throws {
        try await withStore { store, played in
            for before in SessionStatus.allCases {
                for after in SessionStatus.allCases {
                    played.kinds.removeAll()
                    store.soundCooldowns.removeAll()
                    let previous = session(status: before)
                    let current = session(status: after)
                    store.playStatusTransitionSound(previous: previous, current: current)
                    #expect(played.kinds == (before.isActiveVisual && after == .done ? [.taskCompleted] : []))
                }
            }
            played.kinds.removeAll()
            store.playStatusTransitionSound(previous: nil, current: session(status: .done))
            #expect(played.kinds.isEmpty)
        }
    }

    @Test func hookBurstsStayQuietUntilOneCompletion() async throws {
        try await withStore { store, played in
            for hook in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PreToolUse", "PostToolUse"] {
                store.ingest(event: EventParser.parseBridgeDictionary([
                    "source": "claude", "event": hook, "session_id": "test",
                    "payload": ["hook_event_name": hook, "tool_name": "Bash"]
                ]))
            }
            #expect(played.kinds.isEmpty)
            let complete = EventParser.parseBridgeDictionary([
                "source": "claude", "event": "Stop", "session_id": "test",
                "payload": ["hook_event_name": "Stop", "last_assistant_message": "完成了。"]
            ])
            store.ingest(event: complete)
            store.ingest(event: complete)
            await store.transcriptRefreshTask?.value
            #expect(played.kinds == [.taskCompleted])
        }
    }

    @Test func muteAndDoNotDisturbSuppressCompletion() async throws {
        try await withStore { store, played in
            store.configurationStore.config.enableSounds = false
            store.playStatusTransitionSound(previous: session(status: .thinking), current: session(status: .done))
            store.configurationStore.config.enableSounds = true
            store.configurationStore.config.doNotDisturb = true
            store.playStatusTransitionSound(previous: session(status: .thinking), current: session(status: .done))
            #expect(played.kinds.isEmpty)
        }
    }

    @Test func bothApprovalSourcesStaySilent() async throws {
        try await withStore { store, played in
            store.ingest(event: AgentEvent(source: .claudeCode, kind: .approval, sessionId: "claude",
                payload: .object(["tool_name": .string("Bash")])))
            store.ingest(codexDesktopApproval: CodexDesktopApproval(id: "approval-test", requestID: .string("test"),
                method: "item/commandExecution/requestApproval", kind: .commandExecution, threadID: "codex",
                tool: "exec", detail: "Example command", availableDecisions: [.accept, .decline]))
            await store.transcriptRefreshTask?.value
            #expect(store.sessions.compactMap(\.approval).count == 2)
            #expect(played.kinds.isEmpty)
        }
    }

    private func session(status: SessionStatus) -> AgentSession {
        AgentSession(id: "test", title: "Test", prompt: "Test", source: .codexDesktop,
            workspace: "", terminal: "", updatedAt: Date(), status: status, activity: [], subagents: [])
    }

    private final class SoundRecorder {
        var kinds: [RetroSoundKind] = []
    }

    private func withStore(_ body: (SessionStore, SoundRecorder) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = AppConfigurationStore(url: root.appendingPathComponent("config.json"))
        config.config.enableSounds = true
        config.config.enableApprovalNotifications = false
        config.config.enableClaude = false
        config.config.enableCodexCLI = false
        config.config.enableCodexDesktop = false
        let played = SoundRecorder()
        let store = SessionStore(configurationStore: config,
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json")),
            soundPlayer: { kind, _ in played.kinds.append(kind) })
        defer { store.statsStore.flush() }
        try await body(store, played)
    }
}
