import AppKit
import VibelslandFreeCore
import SwiftUI

/// 展开面板的外点收起与鼠标离开自动收起（tracking area 事件驱动）。
extension IslandWindow {
    func updateOutsideClickMonitor(expanded: Bool) {
        if hiddenForSystemOverview {
            stopOutsideClickMonitor()
            stopAutoCollapseWatch()
            return
        }
        if expanded {
            startOutsideClickMonitor()
            if hasPendingApproval {
                stopAutoCollapseWatch()
            } else {
                startAutoCollapseWatch()
            }
        } else {
            stopOutsideClickMonitor()
            stopAutoCollapseWatch()
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

    func stopOutsideClickMonitor() {
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

    /// 事件驱动的离开收起：tracking area 的进出事件代替旧的 0.22 秒鼠标轮询。
    /// 鼠标离开（或启动监视时就在窗外）后启动一次性宽限定时器，重新进入即取消。
    /// 幂等：布局刷新会反复调用这里（applyLayout → updateOutsideClickMonitor），
    /// 已在监视中时不得重置倒计时，否则周期性刷新会把收起无限推迟。
    private func startAutoCollapseWatch() {
        let wasActive = autoCollapseWatchActive
        autoCollapseWatchActive = true
        guard !wasActive else { return }
        if !frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
            armAutoCollapseTimer()
        }
    }

    func stopAutoCollapseWatch() {
        autoCollapseWatchActive = false
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    func autoCollapseMouseEntered() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    func autoCollapseMouseExited() {
        if autoCollapseWatchActive {
            armAutoCollapseTimer()
        }
    }

    private func armAutoCollapseTimer() {
        guard autoCollapseWatchActive, store?.isExpanded == true, !hasPendingApproval else { return }
        autoCollapseTimer?.invalidate()
        let timer = Timer(timeInterval: IslandAutoCollapsePolicy.graceDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.fireAutoCollapse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoCollapseTimer = timer
    }

    private func fireAutoCollapse() {
        autoCollapseTimer = nil
        guard autoCollapseWatchActive, let store, store.isExpanded, !hasPendingApproval else { return }
        // 窗口动画期间可能漏掉进入事件，收起前再确认鼠标确实在窗外。
        guard !frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) else { return }
        collapseIfExpanded()
    }

    private var hasPendingApproval: Bool {
        guard let store else { return false }
        return store.sessions.contains { session in
            guard let approval = session.approval else { return false }
            return !approval.isExpired
        }
    }
}

/// 覆盖整个浮岛内容区的自愈式进出追踪视图。
/// 自己的 updateTrackingAreas 每次都重新注册区域，SwiftUI 的 tracking 重建
/// 清不掉它；对点击完全透明。
final class WindowHoverTrackingView: NSView {
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        onEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onExited?()
    }
}
