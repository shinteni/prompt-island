import AppKit
import VibelslandFreeCore
import SwiftUI

/// 调度中心/Mission Control 出现时隐藏浮岛、结束后恢复的检测与状态机。
extension IslandWindow {
    func startSystemOverviewDetectionTimer() {
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

    func stopSystemOverviewDetectionTimer() {
        systemOverviewDetectionTimer?.invalidate()
        systemOverviewDetectionTimer = nil
        systemOverviewDetectionTicks = 0
    }

    func startSystemOverviewTriggerMonitor() {
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

    func handleActiveApplicationChanged(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard application?.bundleIdentifier == "com.apple.dock" else {
            restoreAfterSystemOverviewIfNeeded()
            return
        }
        hideForSystemOverview(minimumDuration: 0.7)
    }

    func hideForSystemOverview(minimumDuration: TimeInterval) {
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
        stopAutoCollapseWatch()
    }

    private func systemOverviewHiddenFrame() -> NSRect {
        let screenFrame = NSScreen.main?.frame ?? .zero
        return NSRect(x: screenFrame.maxX + 200, y: screenFrame.maxY + 200, width: 1, height: 1)
    }

    func startSystemOverviewEventMonitor() {
        guard systemOverviewEventMonitor == nil else { return }
        systemOverviewEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyUp, .swipe]
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self?.restoreAfterSystemOverviewIfNeeded()
            }
        }
    }

    func stopSystemOverviewEventMonitor() {
        if let systemOverviewEventMonitor {
            NSEvent.removeMonitor(systemOverviewEventMonitor)
            self.systemOverviewEventMonitor = nil
        }
    }

    func startSystemOverviewTimer() {
        systemOverviewTimer?.invalidate()
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.restoreAfterSystemOverviewIfNeeded()
            }
        }
        systemOverviewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopSystemOverviewTimer() {
        systemOverviewTimer?.invalidate()
        systemOverviewTimer = nil
    }

    func restoreAfterSystemOverviewIfNeeded(force: Bool = false) {
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
}
