import AppKit
import QuartzCore
import Testing
@testable import VibelslandFree
@testable import VibelslandFreeCore

@Suite(.serialized) @MainActor
struct IslandLaunchEntranceTests {
    @Test func entranceUsesTheRealWindowAndSettlesWithoutMovingIt() async throws {
        try await withWindow { window, _ in
            let frame = window.frame
            window.present(launchAnimated: true)
            #expect(window.isVisible)
            #expect(!window.isKeyWindow)
            #expect(window.frame == frame)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(window.contentView?.layer?.animationKeys()?.isEmpty == false)
            }
            var sawFade = false
            var sawScale = false
            for _ in 0..<15 {
                try await Task.sleep(for: .milliseconds(40))
                #expect(window.frame == frame)
                if let visible = window.contentView?.layer?.presentation() {
                    sawFade = sawFade || (visible.opacity > 0 && visible.opacity < 0.99)
                    sawScale = sawScale || (visible.transform.m11 > 0.88 && visible.transform.m11 < 0.999)
                    #expect(visible.transform.m11 <= 1.001)
                }
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(sawFade)
                #expect(sawScale)
            }
            #expect(window.isVisible)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
            #expect(window.contentView?.layer?.opacity == 1)
            #expect(CATransform3DIsIdentity(try #require(window.contentView?.layer?.transform)))
        }
    }

    @Test func hidingDuringEntranceCannotBringTheIslandBack() async throws {
        try await withWindow { window, _ in
            window.present(launchAnimated: true)
            window.hideForSystemOverview(minimumDuration: 1)
            try await Task.sleep(for: .milliseconds(600))
            #expect(!window.isVisible)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
        }
    }

    @Test func openingSettingsCancelsEntranceAndRestoresImmediately() async throws {
        try await withWindow { window, _ in
            window.present(launchAnimated: true)
            window.setSuppressedForSettings(true)
            #expect(!window.isVisible)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
            window.setSuppressedForSettings(false)
            window.present(launchAnimated: false)
            #expect(window.isVisible)
            #expect(window.alphaValue == 1)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
        }
    }

    @Test func approvalDuringEntranceReplacesItImmediately() async throws {
        try await withWindow { window, store in
            window.present(launchAnimated: true)
            store.ingest(event: AgentEvent(source: .claudeCode, kind: .approval,
                sessionId: "startup-approval", payload: .object(["tool_name": .string("Read")])))
            store.isExpanded = true
            window.applyFrame(expanded: true, position: .topCenter, animated: false)
            #expect(window.isVisible)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
            #expect(window.frame.width > 400)
            #expect(store.sessions.first?.approval != nil)
        }
    }

    @Test func reopeningAndSkippingEntranceShowFinalState() async throws {
        try await withWindow { window, _ in
            window.present(launchAnimated: false)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
            window.orderOut(nil)
            window.present(launchAnimated: true)
            #expect(window.isVisible)
            #expect(window.contentView?.layer?.animationKeys()?.isEmpty != false)
        }
    }

    private func withWindow(_ body: @MainActor (IslandWindow, SessionStore) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = AppConfigurationStore(url: root.appendingPathComponent("config.json"))
        configuration.config.enableSounds = false
        configuration.config.enableClaude = false
        configuration.config.enableCodexCLI = false
        configuration.config.enableCodexDesktop = false
        let store = SessionStore(configurationStore: configuration,
            transcriptReader: ConversationTranscriptReader(homeURL: root),
            statsStore: UsageStatsStore(url: root.appendingPathComponent("stats.json")))
        store.launchPresenceUntil = Date().addingTimeInterval(8)
        let window = IslandWindow(contentRect: .zero, store: store)
        defer {
            window.setSuppressedForSettings(true)
            if let monitor = window.systemOverviewTriggerMonitor { NSEvent.removeMonitor(monitor) }
            window.close()
            store.statsStore.flush()
            try? FileManager.default.removeItem(at: root)
        }
        try await body(window, store)
    }
}
