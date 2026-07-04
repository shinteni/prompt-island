import AppKit
import VibelslandFreeCore
import Combine
import QuartzCore
import SwiftUI

final class IslandWindow: NSPanel {
    private var cancellables: Set<AnyCancellable> = []
    var outsideClickMonitor: Any?
    var outsideClickArmedAt: Date?
    var autoCollapseTimer: Timer?
    var autoCollapseWatchActive = false
    var systemOverviewTriggerMonitor: Any?
    var systemOverviewDetectionTimer: Timer?
    var systemOverviewDetectionTicks = 0
    var systemOverviewTimer: Timer?
    var systemOverviewEventMonitor: Any?
    var systemOverviewMinimumRestoreAt: Date?
    var systemOverviewForceRestoreAt: Date?
    var systemOverviewRestoreFrame: NSRect?
    var preferredCenterXForNextFrame: CGFloat?
    private var lastAppliedPosition: IslandPosition?
    private var lastAppliedExpanded: Bool?
    private var lastLayoutSignature: IslandLayoutSignature?
    var lastVisibleFrame: NSRect?
    private var transitionResetTask: Task<Void, Never>?
    private var frameDisplayLink: CADisplayLink?
    private var frameAnimationContext: FrameAnimationContext?
    private var hasPresented = false

    private struct FrameAnimationContext {
        let start: NSRect
        let target: NSRect
        let startedAt: CFTimeInterval
        let duration: TimeInterval
        let expanded: Bool
    }
    var hiddenForSystemOverview = false
    var suppressedForSettings = false
    weak var store: SessionStore?
    let logger = AppLogger.shared

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

        // 自动收起的进出追踪不能直接 addTrackingArea 到 NSHostingView：
        // SwiftUI 重建自身 tracking areas 时会把外来区域清掉且不会恢复，
        // 事件随之静默失效。用自愈式追踪视图（每次 updateTrackingAreas 都
        // 重新注册自己的区域）作为子视图覆盖整个内容区。
        let tracker = WindowHoverTrackingView()
        tracker.onEntered = { [weak self] in
            self?.autoCollapseMouseEntered()
        }
        tracker.onExited = { [weak self] in
            self?.autoCollapseMouseExited()
        }
        tracker.frame = hostingView.bounds
        tracker.autoresizingMask = [.width, .height]
        hostingView.addSubview(tracker)

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
            stopAutoCollapseWatch()
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

    func repairFrameIfNeeded(shouldOrder: Bool = true) {
        guard let store else { return }
        let target = targetFrame(
            expanded: store.isExpanded,
            position: store.configurationStore.config.islandPosition
        )
        guard let visibleFrame = targetScreen()?.visibleFrame else {
            logger.error("island.screen.unavailable", detail: "repairFrameIfNeeded")
            orderOut(nil)
            return
        }
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

    func applyFrame(
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
        let transitionDuration = IslandMotionPolicy.WindowTransition.duration(
            expanded: expanded,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let shouldAnimateFrame = animated && hasPresented && frameWillChange && transitionDuration > 0

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
            animateFrame(to: target, duration: transitionDuration, expanded: expanded)
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
        frameDisplayLink?.invalidate()
        frameDisplayLink = nil
        frameAnimationContext = nil
    }

    /// 帧动画由 CADisplayLink 驱动：跟随显示器实际刷新率（ProMotion 下满 120Hz），
    /// 替代旧的固定 60Hz Timer；缓动曲线在 IslandMotionPolicy 中按展开/收起区分。
    private func animateFrame(to target: NSRect, duration: TimeInterval, expanded: Bool) {
        stopFrameAnimation()
        guard duration > 0, let contentView else {
            setFrame(target, display: true)
            rememberVisibleFrame()
            return
        }
        frameAnimationContext = FrameAnimationContext(
            start: frame,
            target: target,
            startedAt: CACurrentMediaTime(),
            duration: duration,
            expanded: expanded
        )
        let link = contentView.displayLink(target: self, selector: #selector(stepFrameDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        frameDisplayLink = link
    }

    @objc private func stepFrameDisplayLink(_ link: CADisplayLink) {
        guard let context = frameAnimationContext else {
            stopFrameAnimation()
            return
        }
        let elapsed = CACurrentMediaTime() - context.startedAt
        let progress = min(max(elapsed / max(context.duration, 0.001), 0), 1)
        let eased = IslandMotionPolicy.WindowTransition.easedProgress(progress, expanded: context.expanded)
        let start = context.start
        let target = context.target
        let next = NSRect(
            x: start.minX + (target.minX - start.minX) * eased,
            y: start.minY + (target.minY - start.minY) * eased,
            width: start.width + (target.width - start.width) * eased,
            height: start.height + (target.height - start.height) * eased
        )
        setFrame(next, display: true)
        if progress >= 1 {
            stopFrameAnimation()
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
        guard let screenFrame = targetScreen()?.visibleFrame else {
            logger.error("island.screen.unavailable", detail: "targetFrame")
            if frame.width > 1, frame.height > 1 {
                return frame
            }
            return NSRect(
                x: 0,
                y: 0,
                width: expanded ? 620 : IslandPresentationPolicy.idleMiniDiameter,
                height: expanded ? 170 : IslandPresentationPolicy.idleMiniDiameter
            )
        }
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
        let approvalQueue = ApprovalQueuePolicy.queue(in: store.sessions)
        let hasPendingApproval = !approvalQueue.isEmpty
        let hasHealthWarning = store.healthChecks.contains { $0.status == .needsAction }
        let isShowingApprovalDetail = store.isApprovalDetailVisible && hasPendingApproval
        let configuredLimit = DashboardSessionPolicy.configuredVisibleSessionLimit(
            store.configurationStore.config.maxVisibleSessions
        )

        let visibleSessionCount = DashboardSessionPolicy.visibleSessions(
            from: store.sessions,
            excludingIDs: Set(approvalQueue.map(\.id)),
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
            } else if approvalQueue.count > 1 {
                height += ApprovalQueuePolicy.cardHeight(in: store.sessions) + rowSpacing
                height += CGFloat(visibleSessionCount) * (48 + rowSpacing)
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

    private func targetScreen() -> NSScreen? {
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
        return NSScreen.screens.first
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
