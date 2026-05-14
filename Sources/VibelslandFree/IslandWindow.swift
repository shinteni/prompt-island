import AppKit
import VibelslandFreeCore
import Combine
import QuartzCore
import SwiftUI

final class IslandWindow: NSPanel {
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var outsideClickArmedAt: Date?
    private var outsideMouseTimer: Timer?
    private var outsideMouseTicks = 0
    private var systemOverviewTriggerMonitor: Any?
    private var systemOverviewDetectionTimer: Timer?
    private var systemOverviewDetectionTicks = 0
    private var systemOverviewTimer: Timer?
    private var systemOverviewEventMonitor: Any?
    private var systemOverviewMinimumRestoreAt: Date?
    private var systemOverviewForceRestoreAt: Date?
    private var systemOverviewRestoreFrame: NSRect?
    private var preferredCenterXForNextFrame: CGFloat?
    private var lastAppliedPosition: IslandPosition?
    private var lastAppliedExpanded: Bool?
    private var lastLayoutSignature: IslandLayoutSignature?
    private var lastVisibleFrame: NSRect?
    private var transitionResetTask: Task<Void, Never>?
    private var frameAnimationTimer: Timer?
    private var hasPresented = false
    private var hiddenForSystemOverview = false
    private var suppressedForSettings = false
    private weak var store: SessionStore?
    private let logger = AppLogger.shared

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect, store: SessionStore) {
        self.store = store
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = true

        let hostingView = TransparentHostingView(
            rootView: IslandPanelView()
                .environmentObject(store)
                .environmentObject(store.configurationStore)
        )
        hostingView.onDragEnded = { [weak self, weak store] in
            store?.suppressCompactTapBriefly()
            self?.rememberVisibleFrame()
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hostingView

        observeLayout()
        applyFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition,
            animated: false,
            shouldOrder: false
        )
    }

    func present(launchAnimated: Bool) {
        guard !suppressedForSettings else { return }
        hasPresented = true
        guard !shouldHideIdlePresentation(expanded: store?.isExpanded ?? false) else {
            alphaValue = 0
            orderOut(nil)
            return
        }
        if hiddenForSystemOverview {
            restoreAfterSystemOverviewIfNeeded(force: true)
        }
        if store?.isExpanded == true {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }

    func setSuppressedForSettings(_ suppressed: Bool) {
        guard suppressedForSettings != suppressed else { return }
        suppressedForSettings = suppressed
        if suppressed {
            orderOut(nil)
            stopOutsideClickMonitor()
            stopOutsideMouseTimer()
            stopSystemOverviewDetectionTimer()
            stopSystemOverviewTimer()
            stopSystemOverviewEventMonitor()
            return
        }
        guard let store else { return }
        if hiddenForSystemOverview {
            startSystemOverviewEventMonitor()
            startSystemOverviewTimer()
            restoreAfterSystemOverviewIfNeeded()
            return
        }
        alphaValue = 1
        applyFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition,
            animated: false,
            shouldOrder: false
        )
        repairFrameIfNeeded(shouldOrder: false)
    }

    private func observeLayout() {
        guard let store else { return }
        let contentState = Publishers.CombineLatest4(
            store.$sessions,
            store.$healthChecks,
            store.$isApprovalDetailVisible,
            store.$sessionVisibilityRefreshToken
        )
        Publishers.CombineLatest3(store.$isExpanded, store.configurationStore.$config, contentState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isExpanded, config, content in
                let signature = IslandLayoutSignature(
                    sessions: content.0,
                    healthChecks: content.1,
                    isExpanded: isExpanded,
                    isApprovalDetailVisible: content.2,
                    maxVisibleSessions: config.maxVisibleSessions,
                    position: config.islandPosition
                )
                self?.applyLayout(signature, animated: true)
            }
            .store(in: &cancellables)

        let notificationCenter = NotificationCenter.default
        Publishers.Merge(
            notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification),
            notificationCenter.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.repairFrameIfNeeded()
        }
        .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleActiveApplicationChanged(notification)
            }
            .store(in: &cancellables)

        let distributedCenter = DistributedNotificationCenter.default()
        let overviewNotifications = [
            "com.apple.expose.awake",
            "com.apple.expose.front.awake",
            "com.apple.workspaces.awake",
            "com.apple.showdesktop.awake"
        ].map { Notification.Name($0) }
        Publishers.MergeMany(overviewNotifications.map { distributedCenter.publisher(for: $0) })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.info("island.system-overview.notification")
                self?.startSystemOverviewDetectionTimer()
                self?.hideForSystemOverview(minimumDuration: 1.0)
            }
            .store(in: &cancellables)

        distributedCenter.publisher(for: Notification.Name("com.apple.spaces.activeSpaceDidChange"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.info("island.space.changed")
                self?.startSystemOverviewDetectionTimer()
                self?.hideForSystemOverview(minimumDuration: 0.45)
            }
            .store(in: &cancellables)

        startSystemOverviewTriggerMonitor()
    }

    private func startSystemOverviewDetectionTimer() {
        guard systemOverviewDetectionTimer == nil else { return }
        systemOverviewDetectionTicks = 0
        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.hiddenForSystemOverview else { return }
                self.systemOverviewDetectionTicks += 1
                if self.systemOverviewLikelyVisible() {
                    self.hideForSystemOverview(minimumDuration: 0.45)
                    self.stopSystemOverviewDetectionTimer()
                    return
                }
                if self.systemOverviewDetectionTicks >= 12 {
                    self.stopSystemOverviewDetectionTimer()
                }
            }
        }
        systemOverviewDetectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSystemOverviewDetectionTimer() {
        systemOverviewDetectionTimer?.invalidate()
        systemOverviewDetectionTimer = nil
        systemOverviewDetectionTicks = 0
    }

    private func startSystemOverviewTriggerMonitor() {
        guard systemOverviewTriggerMonitor == nil else { return }
        systemOverviewTriggerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .swipe, .gesture]
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.handlePotentialSystemOverviewEvent(event)
            }
        }
    }

    private func handlePotentialSystemOverviewEvent(_ event: NSEvent) {
        switch event.type {
        case .swipe, .gesture:
            startSystemOverviewDetectionTimer()
            hideForSystemOverview(minimumDuration: 0.9)
        case .keyDown:
            let isMissionControlShortcut =
                event.keyCode == 99 ||
                (event.keyCode == 126 && event.modifierFlags.contains(.control))
            if isMissionControlShortcut {
                startSystemOverviewDetectionTimer()
                hideForSystemOverview(minimumDuration: 0.9)
            }
        default:
            break
        }
    }

    private func handleActiveApplicationChanged(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard application?.bundleIdentifier == "com.apple.dock" else {
            restoreAfterSystemOverviewIfNeeded()
            return
        }
        hideForSystemOverview(minimumDuration: 0.7)
    }

    private func hideForSystemOverview(minimumDuration: TimeInterval) {
        let now = Date()
        let minimumRestoreAt = now.addingTimeInterval(minimumDuration)
        let forceRestoreAt = now.addingTimeInterval(max(minimumDuration + 2.4, 3.0))
        if let current = systemOverviewMinimumRestoreAt {
            systemOverviewMinimumRestoreAt = max(current, minimumRestoreAt)
        } else {
            systemOverviewMinimumRestoreAt = minimumRestoreAt
        }
        if let current = systemOverviewForceRestoreAt {
            systemOverviewForceRestoreAt = max(current, forceRestoreAt)
        } else {
            systemOverviewForceRestoreAt = forceRestoreAt
        }
        startSystemOverviewEventMonitor()
        startSystemOverviewTimer()
        stopSystemOverviewDetectionTimer()
        guard !hiddenForSystemOverview else { return }
        let restoreFrame = lastVisibleFrame ?? frame
        if restoreFrame.width > 1, restoreFrame.height > 1 {
            systemOverviewRestoreFrame = restoreFrame
        }
        hiddenForSystemOverview = true
        logger.info("island.system-overview.hidden")
        alphaValue = 0
        setFrame(systemOverviewHiddenFrame(), display: false)
        orderOut(nil)
        stopOutsideClickMonitor()
        stopOutsideMouseTimer()
    }

    private func systemOverviewHiddenFrame() -> NSRect {
        let screenFrame = NSScreen.main?.frame ?? .zero
        return NSRect(x: screenFrame.maxX + 200, y: screenFrame.maxY + 200, width: 1, height: 1)
    }

    private func startSystemOverviewEventMonitor() {
        guard systemOverviewEventMonitor == nil else { return }
        systemOverviewEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyUp, .swipe]
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self?.restoreAfterSystemOverviewIfNeeded()
            }
        }
    }

    private func stopSystemOverviewEventMonitor() {
        if let systemOverviewEventMonitor {
            NSEvent.removeMonitor(systemOverviewEventMonitor)
            self.systemOverviewEventMonitor = nil
        }
    }

    private func startSystemOverviewTimer() {
        systemOverviewTimer?.invalidate()
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreAfterSystemOverviewIfNeeded()
            }
        }
        systemOverviewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSystemOverviewTimer() {
        systemOverviewTimer?.invalidate()
        systemOverviewTimer = nil
    }

    private func restoreAfterSystemOverviewIfNeeded(force: Bool = false) {
        guard hiddenForSystemOverview else { return }
        guard !suppressedForSettings else { return }
        let now = Date()
        let decision = SystemOverviewRestorePolicy.decision(
            force: force,
            now: now,
            minimumRestoreAt: systemOverviewMinimumRestoreAt,
            forceRestoreAt: systemOverviewForceRestoreAt,
            overviewLikelyVisible: systemOverviewLikelyVisible(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        switch decision {
        case .wait:
            return
        case .forceRestore:
            logger.info("island.system-overview.restore.forced")
        case .restore:
            break
        }
        hiddenForSystemOverview = false
        systemOverviewMinimumRestoreAt = nil
        systemOverviewForceRestoreAt = nil
        logger.info("island.system-overview.restored")
        stopSystemOverviewTimer()
        stopSystemOverviewEventMonitor()
        stopSystemOverviewDetectionTimer()
        guard let store else { return }
        if let systemOverviewRestoreFrame {
            preferredCenterXForNextFrame = systemOverviewRestoreFrame.midX
            setFrame(systemOverviewRestoreFrame, display: false)
            self.systemOverviewRestoreFrame = nil
        }
        alphaValue = 1
        applyFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition,
            animated: false
        )
        if store.isExpanded {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
        repairFrameIfNeeded()
    }

    private func systemOverviewLikelyVisible() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let screenFrame = screen.frame
        return windowList.contains { info in
            guard isDockWindow(info) else {
                return false
            }
            let name = info[kCGWindowName as String] as? String ?? ""
            if name.localizedCaseInsensitiveContains("mission") ||
                name.localizedCaseInsensitiveContains("expose") ||
                name.localizedCaseInsensitiveContains("spaces") {
                return true
            }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                return false
            }
            return width > screenFrame.width * 0.55 && height > screenFrame.height * 0.45
        }
    }

    private func isDockWindow(_ info: [String: Any]) -> Bool {
        if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
           NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == "com.apple.dock" {
            return true
        }
        let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
        return ownerName == "Dock" || ownerName == "程序坞"
    }

    private func repairFrameIfNeeded(shouldOrder: Bool = true) {
        guard let store else { return }
        let target = targetFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition
        )
        let visibleFrame = targetScreen().visibleFrame
        guard abs(frame.minX - target.minX) > 0.5 ||
              abs(frame.minY - target.minY) > 0.5 ||
              abs(frame.width - target.width) > 0.5 ||
              abs(frame.height - target.height) > 0.5 ||
              !visibleFrame.insetBy(dx: -8, dy: -8).intersects(frame) else {
            return
        }
        applyFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition,
            animated: false,
            shouldOrder: shouldOrder
        )
    }

    private func applyFrame(
        expanded: Bool,
        position: IslandPosition,
        animated: Bool,
        shouldOrder: Bool = true
    ) {
        if shouldHideIdlePresentation(expanded: expanded) {
            transitionResetTask?.cancel()
            stopFrameAnimation()
            store?.isIslandTransitioning = false
            alphaValue = 0
            orderOut(nil)
            lastAppliedPosition = position
            lastAppliedExpanded = expanded
            return
        }

        let target = targetFrame(expanded: expanded, position: position)
        let frameWillChange =
            abs(frame.minX - target.minX) > 0.5 ||
            abs(frame.minY - target.minY) > 0.5 ||
            abs(frame.width - target.width) > 0.5 ||
            abs(frame.height - target.height) > 0.5
        let presentationChanged = lastAppliedExpanded != expanded
        let shouldAnimateFrame = animated && hasPresented && frameWillChange

        if shouldAnimateFrame {
            store?.isIslandTransitioning = true
            transitionResetTask?.cancel()
            let resetDelay = IslandMotionPolicy.WindowTransition.resetDelay(expanded: expanded)
            transitionResetTask = Task { [weak store] in
                try? await Task.sleep(nanoseconds: resetDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    store?.isIslandTransitioning = false
                }
            }
        } else {
            transitionResetTask?.cancel()
            stopFrameAnimation()
            store?.isIslandTransitioning = false
        }

        let shouldRefreshOrdering = presentationChanged || frameWillChange || !isVisible || alphaValue < 0.99
        if shouldOrder && hasPresented && shouldRefreshOrdering && !hiddenForSystemOverview && !suppressedForSettings {
            alphaValue = 1
            if expanded {
                makeKeyAndOrderFront(nil)
            } else {
                orderFrontRegardless()
            }
        }

        if shouldAnimateFrame {
            animateFrame(to: target, duration: IslandMotionPolicy.WindowTransition.duration(expanded: expanded))
        } else if frameWillChange {
            stopFrameAnimation()
            setFrame(target, display: true)
        } else {
            contentView?.needsDisplay = true
        }
        applyWindowMask(expanded: expanded)
        if hiddenForSystemOverview || suppressedForSettings {
            lastAppliedPosition = position
            lastAppliedExpanded = expanded
            return
        }
        rememberVisibleFrame()
        lastAppliedPosition = position
        lastAppliedExpanded = expanded
        if !shouldAnimateFrame {
            store?.isIslandTransitioning = false
        }
    }

    private func shouldHideIdlePresentation(expanded: Bool) -> Bool {
        guard let store, !expanded else { return false }
        return IslandPresentationPolicy.isIdleMiniPresentation(
            sessions: store.sessions,
            isExpanded: false
        )
    }

    private func stopFrameAnimation() {
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
    }

    private func animateFrame(to target: NSRect, duration: TimeInterval) {
        stopFrameAnimation()
        let start = frame
        let startedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard timer.isValid else { return }
            MainActor.assumeIsolated {
                self?.stepFrameAnimation(
                    start: start,
                    target: target,
                    startedAt: startedAt,
                    duration: duration
                )
            }
        }
        frameAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepFrameAnimation(
        start: NSRect,
        target: NSRect,
        startedAt: CFTimeInterval,
        duration: TimeInterval
    ) {
        let elapsed = CACurrentMediaTime() - startedAt
        let progress = min(max(elapsed / max(duration, 0.001), 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        let next = NSRect(
            x: start.minX + (target.minX - start.minX) * eased,
            y: start.minY + (target.minY - start.minY) * eased,
            width: start.width + (target.width - start.width) * eased,
            height: start.height + (target.height - start.height) * eased
        )
        setFrame(next, display: true)
        if progress >= 1 {
            frameAnimationTimer?.invalidate()
            frameAnimationTimer = nil
            setFrame(target, display: true)
            rememberVisibleFrame()
        }
    }

    private func applyLayout(_ signature: IslandLayoutSignature, animated: Bool) {
        let previousSignature = lastLayoutSignature
        lastLayoutSignature = signature
        updateOutsideClickMonitor(expanded: signature.isExpanded)

        guard previousSignature != signature else {
            contentView?.needsDisplay = true
            return
        }

        applyFrame(
            expanded: signature.isExpanded,
            position: signature.position,
            animated: animated
        )
    }

    func targetFrame(expanded: Bool, position: IslandPosition) -> NSRect {
        let screenFrame = targetScreen().visibleFrame
        let previousFrame = frame
        let preferredCenterX = preferredCenterXForNextFrame
        preferredCenterXForNextFrame = nil
        let canReuseCurrentCenter = previousFrame.width > 1 &&
            previousFrame.height > 1 &&
            lastAppliedPosition == position
        let compactSize = compactPreferredSize()
        let preferredSize = expanded ? CGSize(width: 620, height: expandedPreferredHeight()) : compactSize
        let minSize = expanded ? CGSize(width: 500, height: 118) : compactSize
        let size = CGSize(
            width: min(preferredSize.width, max(minSize.width, screenFrame.width - 48)),
            height: min(preferredSize.height, max(minSize.height, screenFrame.height - 32))
        )
        let x: CGFloat
        if let preferredCenterX {
            x = preferredCenterX - size.width / 2
        } else if canReuseCurrentCenter {
            x = previousFrame.midX - size.width / 2
        } else {
            switch position {
            case .topCenter:
                x = screenFrame.midX - size.width / 2
            case .topLeft:
                x = screenFrame.minX + 24
            case .topRight:
                x = screenFrame.maxX - size.width - 24
            }
        }
        return NSRect(
            x: min(max(x, screenFrame.minX + 12), screenFrame.maxX - size.width - 12),
            y: screenFrame.maxY - size.height - 10,
            width: size.width,
            height: size.height
        )
    }

    private func compactPreferredSize() -> CGSize {
        guard let store else {
            return CGSize(
                width: IslandPresentationPolicy.idleMiniDiameter,
                height: IslandPresentationPolicy.idleMiniDiameter
            )
        }
        return IslandPresentationPolicy.compactSize(sessions: store.sessions)
    }

    private func expandedPreferredHeight() -> CGFloat {
        guard let store else { return 170 }
        let pendingApproval = DashboardSessionPolicy.pendingApprovalSession(in: store.sessions)
        let hasPendingApproval = pendingApproval != nil
        let hasHealthWarning = store.healthChecks.contains { $0.status == .needsAction }
        let isShowingApprovalDetail = store.isApprovalDetailVisible && hasPendingApproval
        let configuredLimit = DashboardSessionPolicy.configuredVisibleSessionLimit(
            store.configurationStore.config.maxVisibleSessions
        )

        let visibleSessionCount = DashboardSessionPolicy.visibleSessions(
            from: store.sessions,
            excluding: pendingApproval?.id,
            limit: hasPendingApproval
                ? max(0, configuredLimit - 1)
                : configuredLimit
        ).count
        let headerHeight: CGFloat = 24
        let verticalPadding: CGFloat = 16
        let rowSpacing: CGFloat = 6
        var height = headerHeight + verticalPadding

        if hasHealthWarning {
            height += 28 + rowSpacing
        }

        if hasPendingApproval {
            if isShowingApprovalDetail {
                height += 178 + rowSpacing
            } else {
                height += 88 + rowSpacing
                height += CGFloat(visibleSessionCount) * (48 + rowSpacing)
            }
        } else {
            switch visibleSessionCount {
            case 0:
                height += 62 + rowSpacing
            case 1:
                height += 62 + rowSpacing
            default:
                height += CGFloat(visibleSessionCount) * (48 + rowSpacing)
            }
        }

        height += 8
        let maximumHeight: CGFloat
        if isShowingApprovalDetail {
            maximumHeight = hasHealthWarning ? 430 : 394
        } else if hasPendingApproval {
            maximumHeight = hasHealthWarning ? 410 : 374
        } else {
            maximumHeight = hasHealthWarning ? 376 : 342
        }
        return min(max(height, 126), maximumHeight)
    }

    private func updateOutsideClickMonitor(expanded: Bool) {
        if hiddenForSystemOverview {
            stopOutsideClickMonitor()
            stopOutsideMouseTimer()
            return
        }
        if expanded {
            startOutsideClickMonitor()
            if hasPendingApproval {
                stopOutsideMouseTimer()
            } else {
                startOutsideMouseTimer()
            }
        } else {
            stopOutsideClickMonitor()
            stopOutsideMouseTimer()
        }
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickArmedAt = Date().addingTimeInterval(0.8)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseIfOutsideClick()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        outsideClickArmedAt = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func collapseIfOutsideClick() {
        guard let store, store.isExpanded else { return }
        if let outsideClickArmedAt, Date() < outsideClickArmedAt {
            return
        }
        if frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) {
            return
        }
        collapseIfExpanded()
    }

    private func collapseIfExpanded() {
        guard let store, store.isExpanded else { return }
        store.isExpanded = false
    }

    private func startOutsideMouseTimer() {
        guard outsideMouseTimer == nil else { return }
        outsideMouseTicks = 0
        outsideMouseTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseIfMouseStayedOutside()
            }
        }
    }

    private func stopOutsideMouseTimer() {
        outsideMouseTimer?.invalidate()
        outsideMouseTimer = nil
        outsideMouseTicks = 0
    }

    private func collapseIfMouseStayedOutside() {
        guard let store, store.isExpanded else {
            stopOutsideMouseTimer()
            return
        }
        if hasPendingApproval {
            stopOutsideMouseTimer()
            return
        }
        if frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
            outsideMouseTicks = 0
            return
        }
        outsideMouseTicks += 1
        if outsideMouseTicks >= 30 {
            collapseIfExpanded()
        }
    }

    private var hasPendingApproval: Bool {
        guard let store else { return false }
        return store.sessions.contains { session in
            guard let approval = session.approval else { return false }
            return !approval.isExpired
        }
    }

    private func targetScreen() -> NSScreen {
        if frame.width > 1,
           frame.height > 1,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return screen
        }

        if let screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        if let mainScreen = NSScreen.main {
            return mainScreen
        }
        guard let firstScreen = NSScreen.screens.first else {
            fatalError("No available screen for island window")
        }
        return firstScreen
    }

    private func applyWindowMask(expanded: Bool) {
        let isIdleMini = store.map {
            IslandPresentationPolicy.isIdleMiniPresentation(
                sessions: $0.sessions,
                isExpanded: expanded
            )
        } ?? false
        let radius: CGFloat = expanded ? 22 : (isIdleMini ? frame.height / 2 : 21)
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.cornerRadius = radius
    }

    private func rememberVisibleFrame() {
        guard !hiddenForSystemOverview,
              !suppressedForSettings,
              frame.width > 1,
              frame.height > 1 else {
            return
        }
        lastVisibleFrame = frame
    }

}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    var onDragEnded: (() -> Void)?
    private var mouseDownLocation: NSPoint?
    private var didDrag = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didDrag = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let mouseDownLocation {
            let dx = event.locationInWindow.x - mouseDownLocation.x
            let dy = event.locationInWindow.y - mouseDownLocation.y
            if hypot(dx, dy) > 3 {
                didDrag = true
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnded?()
        }
        super.mouseUp(with: event)
        mouseDownLocation = nil
        didDrag = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
    }
}
