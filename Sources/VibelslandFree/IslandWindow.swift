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
    private var frameDisplayLink: CADisplayLink?
    private var frameAnimationContext: FrameAnimationContext?
    private var hasPresented = false
    private var floatingCenter: NSPoint?
    private(set) var isDragging = false
    private var dragStart: (mouse: NSPoint, frame: NSRect)?

    private struct FrameAnimationContext {
        let start: NSRect
        let target: NSRect
        let startedAt: CFTimeInterval
        let duration: TimeInterval
        let velocity: [Double]
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
        isMovableByWindowBackground = false

        let hostingView = TransparentHostingView(
            rootView: IslandPanelView()
                .environmentObject(store)
                .environmentObject(store.configurationStore)
        )
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
        let animateEntrance = launchAnimated && !hasPresented
            && store?.isExpanded != true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        stopLaunchEntrance()
        hasPresented = true
        guard !shouldHideIdlePresentation(expanded: store?.isExpanded ?? false) else {
            alphaValue = 0
            orderOut(nil)
            return
        }
        if hiddenForSystemOverview {
            restoreAfterSystemOverviewIfNeeded(force: true)
        }
        alphaValue = 1
        if animateEntrance {
            if let config = store?.configurationStore.config,
               config.enableSounds, !config.doNotDisturb {
                RetroSoundPlayer.shared.prepare(.launch, theme: config.soundTheme)
                RetroSoundPlayer.shared.play(.launch, theme: config.soundTheme)
            }
            animateLaunchEntrance()
        }
        if store?.isExpanded == true {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }

    /// Animate the real island at its final position. Core Animation owns the
    /// short entrance; no extra window, display link, or delayed hand-off.
    private func animateLaunchEntrance() {
        contentView?.layoutSubtreeIfNeeded()
        guard let layer = contentView?.layer else { return }
        let scale: CGFloat = 0.88
        var transform = CATransform3DMakeScale(scale, scale, 1)
        // AppKit can use a noncentral layer anchor. Keep the visible island centered.
        transform.m41 = (layer.bounds.midX - layer.bounds.width * layer.anchorPoint.x) * (1 - scale)
        transform.m42 = (layer.bounds.midY - layer.bounds.height * layer.anchorPoint.y) * (1 - scale)
        let settle = CASpringAnimation(keyPath: "transform")
        settle.fromValue = NSValue(caTransform3D: transform)
        settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        settle.mass = 1
        settle.stiffness = 320
        settle.damping = 36
        settle.duration = 0.48

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.24
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let entrance = CAAnimationGroup()
        entrance.animations = [settle, fade]
        entrance.duration = settle.duration
        layer.add(entrance, forKey: "island.launchEntrance")
    }

    private func stopLaunchEntrance() {
        contentView?.layer?.removeAnimation(forKey: "island.launchEntrance")
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .keyDown {
            stopLaunchEntrance()
        }
        if event.type == .leftMouseDown, NSRect(origin: .zero, size: frame.size).contains(event.locationInWindow),
           store?.isExpanded == false || isHeaderDragPoint(event.locationInWindow) {
            dragStart = (convertPoint(toScreen: event.locationInWindow), frame)
            return
        }
        if event.type == .leftMouseDragged, let dragStart {
            let mouse = convertPoint(toScreen: event.locationInWindow)
            let dx = mouse.x - dragStart.mouse.x
            let dy = mouse.y - dragStart.mouse.y
            if isDragging || hypot(dx, dy) > 3 {
                if !isDragging {
                    isDragging = true
                    stopFrameAnimation()
                    stopAutoCollapseWatch()
                }
                setFrameOrigin(NSPoint(x: dragStart.frame.minX + dx, y: dragStart.frame.minY + dy))
            }
            return
        }
        if event.type == .leftMouseUp, dragStart != nil {
            dragStart = nil
            if isDragging {
                finishDragging()
            } else if store?.isExpanded == false {
                store?.isExpanded = true
            }
            return
        }
        super.sendEvent(event)
    }

    private func isHeaderDragPoint(_ point: NSPoint) -> Bool {
        point.y >= frame.height - 38 * IslandPresentationPolicy.windowScale
            && (point.x < 30 || (point.x > 240 && point.x < frame.width - 100))
    }

    func finishDragging() {
        isDragging = false
        guard let store, let screen = screenContainingFrame() else { return }
        store.suppressCompactTapBriefly()
        let visible = screen.visibleFrame
        if let edge = IslandDockingPolicy.edge(for: frame, in: visible) {
            floatingCenter = nil
            store.configurationStore.config.islandDockPlacement = IslandDockPlacement(
                edge: edge,
                displayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0,
                verticalFraction: (frame.midY - visible.minY) / visible.height
            )
            store.isExpanded = true
        } else {
            floatingCenter = NSPoint(x: frame.midX, y: frame.midY)
            store.configurationStore.config.islandDockPlacement = nil
        }
        applyFrame(expanded: store.isExpanded, position: store.configurationStore.config.islandPosition, animated: true)
        updateOutsideClickMonitor(expanded: store.isExpanded)
        rememberVisibleFrame()
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
                    position: config.islandPosition,
                    isLaunchPresenceActive: self?.store?.isLaunchPresenceActive ?? false,
                    dockPlacement: config.islandDockPlacement
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
        guard let store, !isDragging else { return }
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
        guard !isDragging else { return }
        if shouldHideIdlePresentation(expanded: expanded) {
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
        if frameWillChange || presentationChanged {
            stopLaunchEntrance()
        }
        let transitionDuration = IslandMotionPolicy.WindowTransition.duration(
            expanded: expanded,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let shouldAnimateFrame = animated && hasPresented && frameWillChange && transitionDuration > 0
            && !hiddenForSystemOverview && !suppressedForSettings

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
            animateFrame(to: target, duration: transitionDuration)
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
        if store.configurationStore.config.islandDockPlacement != nil { return false }
        // 启动亮相期内空闲也不隐藏，让用户看到应用已启动。
        if store.isLaunchPresenceActive {
            return false
        }
        return IslandPresentationPolicy.isIdleMiniPresentation(
            sessions: store.sessions,
            isExpanded: false
        )
    }

    override func orderOut(_ sender: Any?) {
        stopLaunchEntrance()
        stopFrameAnimation()
        super.orderOut(sender)
    }

    private func stopFrameAnimation() {
        frameDisplayLink?.invalidate()
        frameDisplayLink = nil
        frameAnimationContext = nil
        if store?.isIslandTransitioning == true { store?.isIslandTransitioning = false }
    }

    /// Display-synchronized, critically damped motion. Retarget from the visible
    /// frame and carry the previous spring velocity, even when clicks reverse it.
    private func animateFrame(to target: NSRect, duration: TimeInterval) {
        let velocity = frameAnimationContext.map {
            frameSample($0, elapsed: CACurrentMediaTime() - $0.startedAt).velocity
        } ?? [0, 0, 0, 0]
        stopFrameAnimation()
        guard duration > 0, let contentView else {
            setFrame(target, display: true)
            rememberVisibleFrame()
            return
        }
        store?.isIslandTransitioning = true
        frameAnimationContext = FrameAnimationContext(
            start: frame,
            target: target,
            startedAt: CACurrentMediaTime(),
            duration: duration,
            velocity: velocity
        )
        let link = contentView.displayLink(target: self, selector: #selector(stepFrameDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        frameDisplayLink = link
    }

    @objc private func stepFrameDisplayLink(_ link: CADisplayLink) {
        guard isVisible, !hiddenForSystemOverview, !suppressedForSettings,
              let context = frameAnimationContext else {
            stopFrameAnimation()
            return
        }
        let elapsed = CACurrentMediaTime() - context.startedAt
        setFrame(frameSample(context, elapsed: elapsed).frame, display: true)
        if elapsed >= context.duration {
            stopFrameAnimation()
            setFrame(context.target, display: true)
            rememberVisibleFrame()
        }
    }

    private func frameSample(_ context: FrameAnimationContext, elapsed: TimeInterval) -> (frame: NSRect, velocity: [Double]) {
        let start = [context.start.minX, context.start.minY, context.start.width, context.start.height]
        let target = [context.target.minX, context.target.minY, context.target.width, context.target.height]
        let samples = zip(start.indices, zip(start, target)).map { index, values in
            IslandMotionPolicy.WindowTransition.sample(start: values.0, target: values.1,
                velocity: context.velocity[index], elapsed: elapsed, duration: context.duration)
        }
        return (NSRect(x: samples[0].value, y: samples[1].value, width: samples[2].value, height: samples[3].value),
                samples.map(\.velocity))
    }

    private func applyLayout(_ signature: IslandLayoutSignature, animated: Bool) {
        let previousSignature = lastLayoutSignature
        if let previousSignature, previousSignature.position != signature.position {
            floatingCenter = nil
            if signature.dockPlacement != nil {
                store?.configurationStore.config.islandDockPlacement = nil
                return
            }
        }
        lastLayoutSignature = signature
        updateOutsideClickMonitor(expanded: signature.isExpanded)

        guard previousSignature != signature else { return }

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
                width: (expanded ? 620 : IslandPresentationPolicy.idleMiniDiameter) * IslandPresentationPolicy.windowScale,
                height: (expanded ? 170 : IslandPresentationPolicy.idleMiniDiameter) * IslandPresentationPolicy.windowScale
            )
        }
        let previousFrame = frame
        let preferredCenterX = preferredCenterXForNextFrame
        preferredCenterXForNextFrame = nil
        let canReuseCurrentCenter = previousFrame.width > 1 &&
            previousFrame.height > 1 &&
            lastAppliedPosition == position
        // 尺寸在设计空间计算，最后统一乘 windowScale；面板内容以设计尺寸
        // 布局后整体缩放（见 IslandPanelView），两侧保持一致。
        let compactSize = IslandPresentationPolicy.scaled(compactPreferredSize())
        let preferredSize = expanded
            ? IslandPresentationPolicy.scaled(CGSize(width: 620, height: expandedPreferredHeight()))
            : compactSize
        let minSize = expanded
            ? IslandPresentationPolicy.scaled(CGSize(width: 500, height: 118))
            : compactSize
        let size = CGSize(
            width: min(preferredSize.width, max(minSize.width, screenFrame.width - 48)),
            height: min(preferredSize.height, max(minSize.height, screenFrame.height - 32))
        )
        if let dock = store?.configurationStore.config.islandDockPlacement {
            return IslandDockingPolicy.frame(edge: dock.edge, size: size, screen: screenFrame,
                verticalFraction: dock.verticalFraction)
        }
        let x: CGFloat
        if let floatingCenter {
            x = floatingCenter.x - size.width / 2
        } else if let preferredCenterX {
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
        // AppKit rounds window frames to whole points. Compare against that same
        // frame so idle layout publications do not restart or cancel animations.
        return NSRect(
            x: min(max(x, screenFrame.minX + 12), screenFrame.maxX - size.width - 12),
            y: min(max(floatingCenter.map { $0.y - size.height / 2 } ?? (screenFrame.maxY - size.height - 10),
                       screenFrame.minY), screenFrame.maxY - size.height),
            width: size.width,
            height: size.height
        ).integral
    }

    private func compactPreferredSize() -> CGSize {
        if store?.configurationStore.config.islandDockPlacement != nil {
            return IslandDockingPolicy.tabSize
        }
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
        let headerHeight: CGFloat = 32
        let verticalPadding: CGFloat = 24
        let rowSpacing: CGFloat = 8
        var height = headerHeight + verticalPadding

        if hasHealthWarning {
            height += 28 + rowSpacing
        }

        if hasPendingApproval {
            if isShowingApprovalDetail {
                height += 178 + rowSpacing
            } else if approvalQueue.count > 1 {
                height += ApprovalQueuePolicy.cardHeight(in: store.sessions) + rowSpacing
                height += CGFloat(visibleSessionCount) * (56 + rowSpacing)
            } else {
                height += 108 + rowSpacing
                height += CGFloat(visibleSessionCount) * (56 + rowSpacing)
            }
        } else {
            switch visibleSessionCount {
            case 0:
                height += 76 + rowSpacing
            case 1:
                height += 76 + rowSpacing
            default:
                height += CGFloat(visibleSessionCount) * (56 + rowSpacing)
            }
        }

        height += 8
        return max(height, 126)
    }

    private func targetScreen() -> NSScreen? {
        if let dock = store?.configurationStore.config.islandDockPlacement,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == dock.displayID
           }) {
            return screen
        }
        if let screen = screenContainingFrame() {
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

    private func screenContainingFrame() -> NSScreen? {
        NSScreen.screens.filter { $0.frame.intersects(frame) }.max {
            let lhs = $0.frame.intersection(frame)
            let rhs = $1.frame.intersection(frame)
            return lhs.width * lhs.height < rhs.width * rhs.height
        }
    }

    private func applyWindowMask(expanded: Bool) {
        let isIdleMini = store.map {
            IslandPresentationPolicy.isIdleMiniPresentation(
                sessions: $0.sessions,
                isExpanded: expanded
            )
        } ?? false
        let radius: CGFloat = (expanded ? 22 : (isIdleMini ? frame.height / 2 / IslandPresentationPolicy.windowScale : 21)) * IslandPresentationPolicy.windowScale
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.cornerCurve = .continuous
        contentView?.layer?.cornerRadius = store?.configurationStore.config.islandDockPlacement == nil ? radius : 0
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

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.backgroundColor = .clear
        window?.isOpaque = false
    }
}
