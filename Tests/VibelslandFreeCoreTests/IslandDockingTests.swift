import AppKit
import Testing
@testable import VibelslandFree
@testable import VibelslandFreeCore

@Suite(.serialized) @MainActor
struct IslandDockingTests {
    @Test func onlySideEdgesSnapIncludingDisplaysWithNegativeOrigins() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 950)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: -1500, y: 500, width: 240, height: 40), in: screen) == .left)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: -250, y: 500, width: 240, height: 40), in: screen) == .right)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: -900, y: 1110, width: 240, height: 40), in: screen) == nil)
    }

    @Test func draggingPastEitherEdgeStillSnaps() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 950)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: -1612, y: 500, width: 240, height: 40), in: screen) == .left)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: -100, y: 500, width: 240, height: 40), in: screen) == .right)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: screen.minX + 25, y: 500, width: 240, height: 40), in: screen) == nil)
        #expect(IslandDockingPolicy.edge(for: CGRect(x: screen.maxX - 265, y: 500, width: 240, height: 40), in: screen) == nil)
    }

    @Test func tabAndExpandedPanelStayOnTheirScreenAndRestoreTheirAnchor() {
        let screen = CGRect(x: -1512, y: -900, width: 1512, height: 900)
        for edge in [IslandDockEdge.left, .right] {
            for fraction in [0.0, 0.5, 1.0] {
                let tab = IslandDockingPolicy.frame(edge: edge, size: CGSize(width: 29, height: 58), screen: screen, verticalFraction: fraction)
                let panel = IslandDockingPolicy.frame(edge: edge, size: CGSize(width: 496, height: 300), screen: screen, verticalFraction: fraction)
                #expect(screen.contains(tab))
                #expect(screen.contains(panel))
                #expect(edge == .left ? tab.minX == screen.minX : tab.maxX == screen.maxX)
                #expect(edge == .left ? panel.minX == tab.minX : panel.maxX == tab.maxX)
                #expect(tab == IslandDockingPolicy.frame(edge: edge, size: tab.size, screen: screen, verticalFraction: fraction))
            }
        }
    }

    @Test func placementSurvivesRestartAndOlderConfigurationStillLoads() throws {
        var configuration = AppConfiguration.default
        let oldData = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: oldData).islandDockPlacement == nil)
        configuration.islandDockPlacement = IslandDockPlacement(edge: .right, displayID: 42, verticalFraction: 0.7)
        let restored = try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(restored.islandDockPlacement == configuration.islandDockPlacement)
    }

    @Test func ringColorsIdentifyTheProviderAcrossBothCodexSources() {
        let claude = AgentSource.claudeCode.progressRingColors
        let codex = AgentSource.codexDesktop.progressRingColors
        #expect(claude.allSatisfy { $0.redComponent > $0.greenComponent && $0.greenComponent > $0.blueComponent })
        #expect(codex.allSatisfy { $0.blueComponent > $0.redComponent && $0.blueComponent > $0.greenComponent })
        #expect(codex[0].greenComponent > codex[0].redComponent)
        #expect(codex[1].redComponent > codex[1].greenComponent)
        #expect(AgentSource.codexCli.progressRingColors == codex)
    }

    @Test func draggingToEitherEdgeCollapsesToATabAndHoverReopensIt() async throws {
        try await withWindow { window, store in
            let screen = try #require(NSScreen.main?.visibleFrame)
            for edge in [IslandDockEdge.left, .right] {
                store.isExpanded = false
                window.setFrame(CGRect(x: edge == .left ? screen.minX : screen.maxX - 240,
                    y: screen.midY, width: 240, height: 40), display: true)
                window.finishDragging()
                #expect(store.configurationStore.config.islandDockPlacement?.edge == edge)
                store.isExpanded = false
                window.applyFrame(expanded: false, position: .topCenter, animated: false)
                let tab = window.frame
                #expect(window.isVisible)
                #expect(tab.width <= 30 && tab.height <= 60)
                #expect(abs(tab.midY - (screen.midY + 20)) <= 1)
                window.autoCollapseMouseEntered()
                #expect(store.isExpanded)
                window.applyFrame(expanded: true, position: .topCenter, animated: false)
                #expect(window.frame.width > 400)
                store.isExpanded = false
                window.applyFrame(expanded: false, position: .topCenter, animated: false)
                #expect(window.frame == tab)
            }
        }
    }

    @Test func mouseDragEventsMoveTheWindowInsteadOfOpeningItAsAClick() async throws {
        try await withWindow { window, store in
            let screen = try #require(NSScreen.main?.visibleFrame)
            let initial = CGRect(x: screen.midX - 120, y: screen.midY, width: 240, height: 40)
            window.setFrame(initial, display: true)
            func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            }
            window.sendEvent(try event(.leftMouseDown, NSPoint(x: -100, y: -100)))
            window.sendEvent(try event(.leftMouseUp, NSPoint(x: -100, y: -100)))
            #expect(!store.isExpanded)
            window.sendEvent(try event(.leftMouseDown, NSPoint(x: 100, y: 20)))
            window.sendEvent(try event(.leftMouseDragged, NSPoint(x: 100 + screen.minX - initial.minX, y: 20)))
            #expect(window.isDragging)
            #expect(!store.isExpanded)
            #expect(window.frame.minX == screen.minX)
            window.sendEvent(try event(.leftMouseUp, NSPoint(x: 100, y: 20)))
            #expect(!window.isDragging)
            #expect(store.configurationStore.config.islandDockPlacement?.edge == .left)
        }
    }

    @Test func droppingThePointerAtEitherScreenEdgeDocksCompactAndExpandedWindows() async throws {
        try await withWindow { window, store in
            let screen = try #require(NSScreen.main?.visibleFrame)
            for expanded in [false, true] {
                for edge in [IslandDockEdge.left, .right] {
                    store.configurationStore.config.islandDockPlacement = nil
                    store.isExpanded = expanded
                    let size = expanded ? CGSize(width: 496, height: 200) : CGSize(width: 240, height: 40)
                    let initial = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                        width: size.width, height: size.height)
                    window.setFrame(initial, display: true)
                    let grab = NSPoint(x: expanded ? 300 : 100, y: size.height - 12)
                    let dropX = edge == .left ? screen.minX + 1 : screen.maxX - 1
                    let windowNumber = window.windowNumber
                    func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
                        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                    }
                    window.sendEvent(try event(.leftMouseDown, grab))
                    window.sendEvent(try event(.leftMouseDragged, NSPoint(x: dropX - initial.minX, y: grab.y)))
                    #expect(window.isDragging)
                    #expect(edge == .left ? window.frame.minX < screen.minX : window.frame.maxX > screen.maxX)
                    window.sendEvent(try event(.leftMouseUp, grab))
                    #expect(!window.isDragging)
                    #expect(store.configurationStore.config.islandDockPlacement?.edge == edge)
                    store.isExpanded = false
                    window.applyFrame(expanded: false, position: .topCenter, animated: false)
                    #expect(window.frame.width <= 30 && window.frame.height <= 60)
                    #expect(edge == .left ? window.frame.minX == screen.minX : window.frame.maxX == screen.maxX)
                }
            }
        }
    }

    @Test func draggingAwayUndocksWithoutJumpingBackToTheTop() async throws {
        try await withWindow { window, store in
            let screen = try #require(NSScreen.main?.visibleFrame)
            store.configurationStore.config.islandDockPlacement = IslandDockPlacement(edge: .left, displayID: 0, verticalFraction: 0.5)
            store.isExpanded = true
            let droppedFrame = CGRect(x: screen.midX - 248, y: screen.midY - 100, width: 496, height: 200)
            window.setFrame(droppedFrame, display: true)
            window.finishDragging()
            #expect(store.configurationStore.config.islandDockPlacement == nil)
            window.applyFrame(expanded: true, position: .topCenter, animated: false)
            #expect(abs(window.frame.midY - droppedFrame.midY) <= 1)
            window.repairFrameIfNeeded()
            #expect(abs(window.frame.midY - droppedFrame.midY) <= 1)
        }
    }

    @Test func idleDockRemainsReachableAndRestoresAfterSettings() async throws {
        try await withWindow { window, store in
            store.launchPresenceUntil = nil
            store.configurationStore.config.islandDockPlacement = IslandDockPlacement(edge: .right, displayID: 0, verticalFraction: 0.5)
            store.isExpanded = false
            window.applyFrame(expanded: false, position: .topCenter, animated: false)
            let tab = window.frame
            #expect(window.isVisible)
            window.setSuppressedForSettings(true)
            #expect(!window.isVisible)
            window.setSuppressedForSettings(false)
            window.present(launchAnimated: false)
            #expect(window.isVisible)
            #expect(window.frame == tab)
        }
    }

    @Test func hoverCancelsCollapseAndNewApprovalKeepsTheDockOpen() async throws {
        try await withWindow { window, store in
            let screen = try #require(NSScreen.main?.visibleFrame)
            let edge: IslandDockEdge = NSEvent.mouseLocation.x < screen.midX ? .right : .left
            store.configurationStore.config.islandDockPlacement = IslandDockPlacement(edge: edge, displayID: 0, verticalFraction: 0.5)
            store.isExpanded = true
            window.applyFrame(expanded: true, position: .topCenter, animated: false)
            window.updateOutsideClickMonitor(expanded: true)
            window.autoCollapseMouseExited()
            try await Task.sleep(for: .milliseconds(350))
            window.autoCollapseMouseEntered()
            try await Task.sleep(for: .milliseconds(500))
            #expect(store.isExpanded)
            window.autoCollapseMouseExited()
            try await Task.sleep(for: .milliseconds(850))
            #expect(!store.isExpanded)
            store.ingest(event: AgentEvent(source: .claudeCode, kind: .approval,
                sessionId: "docked-approval", payload: .object(["tool_name": .string("Read")])))
            try await Task.sleep(for: .milliseconds(1100))
            #expect(store.isExpanded)
            #expect(window.frame.width > 400)
            #expect(window.autoCollapseTimer == nil)
        }
    }

    @Test func savingDockPlacementDoesNotRefreshBackendConnections() async throws {
        try await withWindow { _, store in
            let generation = store.codexRefreshGeneration
            store.configurationStore.config.islandDockPlacement = IslandDockPlacement(edge: .left, displayID: 0, verticalFraction: 0.5)
            try await Task.sleep(for: .milliseconds(50))
            #expect(store.codexRefreshGeneration == generation)
            store.configurationStore.config.doNotDisturb.toggle()
            try await Task.sleep(for: .milliseconds(50))
            #expect(store.codexRefreshGeneration == generation + 1)
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
        window.present(launchAnimated: false)
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
