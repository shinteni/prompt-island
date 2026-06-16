import AppKit
import Combine
import VibelslandFreeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSWindowDelegate {
    let configurationStore = AppConfigurationStore()
    lazy var store = SessionStore(configurationStore: configurationStore)

    private var islandWindow: IslandWindow?
    private var launchIntroWindow: LaunchIntroWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var configCancellable: AnyCancellable?
    private var runtimeObservers: [NSObjectProtocol] = []
    private var verificationObservers: [NSObjectProtocol] = []
    private var hasPlayedLaunchIntro = false
    private var settingsSuppressionActive = false
    private var restoreIslandAfterSettings = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToExistingInstanceIfNeeded() {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installRuntimeActions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsOpened),
            name: .vibelslandSettingsDidAppear,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsClosed),
            name: .vibelslandSettingsDidDisappear,
            object: nil
        )
        configurationStore.config.launchAtLogin = LaunchAtLoginController.isEnabled
        configureStatusItem()
        configCancellable = configurationStore.$config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLocalizedChrome()
            }
        installVerificationActionsIfNeeded()
        showIsland(launchAnimated: true)
        store.start()
    }

    private func handOffToExistingInstanceIfNeeded() -> Bool {
        guard let existingInstance = AppSingleInstancePolicy.existingInstance(
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            currentExecutableName: Bundle.main.executableURL?.lastPathComponent,
            currentBundleName: Bundle.main.bundleURL.lastPathComponent,
            runningApplications: NSWorkspace.shared.runningApplications.map { app in
                AppInstanceSnapshot(
                    processID: app.processIdentifier,
                    bundleIdentifier: app.bundleIdentifier,
                    executableName: app.executableURL?.lastPathComponent,
                    bundleName: app.bundleURL?.lastPathComponent,
                    localizedName: app.localizedName,
                    isTerminated: app.isTerminated
                )
            }
        ) else {
            return false
        }

        requestExistingInstanceToOpenPanel(processID: existingInstance.processID)
        NSApp.terminate(nil)
        return true
    }

    private func requestExistingInstanceToOpenPanel(processID: Int32) {
        DistributedNotificationCenter.default().postNotificationName(
            .vibelslandOpenExistingInstancePanel,
            object: nil,
            userInfo: ["targetProcessID": Int(processID)],
            deliverImmediately: true
        )
    }

    private func installRuntimeActions() {
        let center = DistributedNotificationCenter.default()
        runtimeObservers.append(center.addObserver(
            forName: .vibelslandOpenExistingInstancePanel,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let targetProcessID = notification.userInfo?["targetProcessID"] as? Int
            let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)
            guard targetProcessID == nil || targetProcessID == currentProcessID else {
                return
            }
            Task { @MainActor [weak self] in
                self?.openIslandPanel()
            }
        })
    }

    private func installVerificationActionsIfNeeded() {
        guard ProcessInfo.processInfo.environment["VIBELSLAND_ENABLE_VERIFICATION_ACTIONS"] == "1" else {
            return
        }
        let center = DistributedNotificationCenter.default()
        verificationObservers.append(center.addObserver(
            forName: .vibelslandVerifyResolveApproval,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawDecision = notification.userInfo?["decision"] as? String
            Task { @MainActor [weak self] in
                self?.resolveApprovalFromVerificationDecision(rawDecision)
            }
        })
        verificationObservers.append(center.addObserver(
            forName: .vibelslandVerifyRestart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restart()
            }
        })
        verificationObservers.append(center.addObserver(
            forName: .vibelslandVerifySetExpanded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawExpanded = notification.userInfo?["expanded"] as? String
            Task { @MainActor [weak self] in
                self?.setExpandedFromVerificationValue(rawExpanded)
            }
        })
    }

    private func resolveApprovalFromVerificationDecision(_ rawDecision: String?) {
        guard let rawDecision,
              let decision = ApprovalDecision(rawValue: rawDecision) else {
            store.lastError = "验证动作无效：无法识别审批选项"
            return
        }
        guard let approval = store.sessions.compactMap(\.approval).first(where: { $0.supports(decision) }) else {
            store.lastError = "验证动作无效：没有可处理的审批"
            return
        }
        store.resolveApproval(approval, decision: decision)
    }

    private func setExpandedFromVerificationValue(_ rawExpanded: String?) {
        switch rawExpanded?.lowercased() {
        case "1", "true", "yes":
            store.isExpanded = true
        case "0", "false", "no":
            store.isExpanded = false
        default:
            store.lastError = "验证动作无效：无法识别展开状态"
        }
    }

    private func configureStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIconFactory.vibelslandIcon()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = ">_ - island"
        }

        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func refreshLocalizedChrome() {
        statusItem?.menu = makeStatusMenu()
        settingsWindow?.title = settingsWindowTitle
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Open panel", japanese: "パネルを開く", chinese: "打开面板"), action: #selector(openIslandPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Install hooks", japanese: "Hooks をインストール", chinese: "安装 Hooks"), action: #selector(installHooks), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Settings...", japanese: "設定...", chinese: "设置..."), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Open logs", japanese: "ログを開く", chinese: "打开日志"), action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Restart >_ - island", japanese: ">_ - island を再起動", chinese: "重启 >_ - island"), action: #selector(restart), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: AppText.pick(language, english: "Quit >_ - island", japanese: ">_ - island を終了", chinese: "退出 >_ - island"), action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func showIsland(launchAnimated: Bool = false) {
        if islandWindow == nil {
            islandWindow = IslandWindow(
                contentRect: initialIslandFrame(),
                store: store
            )
        }
        guard let islandWindow else { return }
        guard launchAnimated, !hasPlayedLaunchIntro else {
            islandWindow.present(launchAnimated: false)
            return
        }

        hasPlayedLaunchIntro = true
        let finalFrame = islandWindow.targetFrame(
            expanded: store.isExpanded,
            position: configurationStore.config.islandPosition
        )
        let introWindow = LaunchIntroWindow(finalFrame: finalFrame, store: store) { [weak self] in
            self?.launchIntroWindow = nil
            self?.islandWindow?.present(launchAnimated: false)
        }
        launchIntroWindow = introWindow
        introWindow.start()
    }

    private func initialIslandFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 640
        let height: CGFloat = 420
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height - 8,
            width: width,
            height: height
        )
    }

    @objc func openIslandPanel() {
        store.isExpanded = true
        switch MenuBarIslandActionPolicy.openPanelAction(
            windowExists: islandWindow != nil,
            windowVisible: islandWindow?.isVisible == true
        ) {
        case .createAndShow:
            showIsland()
        case .restoreVisible, .keepVisible:
            islandWindow?.present(launchAnimated: false)
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = settingsWindowTitle
            window.center()
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .environmentObject(store)
                    .environmentObject(configurationStore)
            )
            settingsWindow = window
        }

        settingsWindow?.title = settingsWindowTitle
        settingsOpened()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        settingsWindow = nil
        settingsClosed()
    }

    @objc func settingsOpened() {
        guard !settingsSuppressionActive else { return }
        settingsSuppressionActive = true
        restoreIslandAfterSettings = islandWindow?.isVisible == true
        islandWindow?.setSuppressedForSettings(true)
    }

    @objc func settingsClosed() {
        guard settingsSuppressionActive else { return }
        settingsSuppressionActive = false
        islandWindow?.setSuppressedForSettings(false)
        if restoreIslandAfterSettings {
            showIsland()
        }
        restoreIslandAfterSettings = false
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func restart() {
        let appPath = Bundle.main.bundleURL.path
        guard let command = AppRestartPolicy.command(bundlePath: appPath) else {
            store.lastError = AppText.pick(language, english: "Restart failed: could not determine app path", japanese: "再起動に失敗しました：アプリのパスを判定できません", chinese: "重启失败：无法确定应用路径")
            openSettings()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            store.lastError = AppText.pick(language, english: "Restart failed: \(error.localizedDescription)", japanese: "再起動に失敗しました：\(error.localizedDescription)", chinese: "重启失败：\(error.localizedDescription)")
            openSettings()
        }
    }

    @objc func installHooks() {
        store.installSelectedHooks()
    }

    @objc func openLogs() {
        store.openLogs()
    }

    private var language: AppLanguage {
        configurationStore.config.language
    }

    private var settingsWindowTitle: String {
        AppText.pick(language, english: "Settings", japanese: "設定", chinese: "设置")
    }
}

private enum MenuBarIconFactory {
    static func vibelslandIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.black.withAlphaComponent(0.92)
            color.setStroke()

            let mark = NSBezierPath()
            mark.lineWidth = 2.1
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.move(to: NSPoint(x: rect.minX + 3.8, y: rect.minY + 13.2))
            mark.line(to: NSPoint(x: rect.minX + 8.2, y: rect.minY + 9.0))
            mark.line(to: NSPoint(x: rect.minX + 3.8, y: rect.minY + 4.8))

            mark.move(to: NSPoint(x: rect.minX + 10.1, y: rect.minY + 6.4))
            mark.line(to: NSPoint(x: rect.minX + 12.5, y: rect.minY + 6.4))
            mark.move(to: NSPoint(x: rect.minX + 14.0, y: rect.minY + 6.4))
            mark.line(to: NSPoint(x: rect.minX + 15.4, y: rect.minY + 6.4))
            mark.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = ">_ - island"
        return image
    }
}

extension Notification.Name {
    static let vibelslandSettingsDidAppear = Notification.Name("free.vibelsland.settings.didAppear")
    static let vibelslandSettingsDidDisappear = Notification.Name("free.vibelsland.settings.didDisappear")
    static let vibelslandOpenExistingInstancePanel = Notification.Name("free.vibelsland.openExistingInstancePanel")
    static let vibelslandVerifyResolveApproval = Notification.Name("free.vibelsland.verify.resolveApproval")
    static let vibelslandVerifyRestart = Notification.Name("free.vibelsland.verify.restart")
    static let vibelslandVerifySetExpanded = Notification.Name("free.vibelsland.verify.setExpanded")
}
