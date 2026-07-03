import AppKit
import VibelslandFreeCore
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = [] {
        didSet { scheduleVisibilityRefresh() }
    }
    @Published var selectedSessionID: AgentSession.ID?
    @Published var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            scheduleVisibilityRefresh()
            if refreshTimer != nil {
                scheduleNextCodexDesktopRefresh()
            }
        }
    }
    @Published var installReport: InstallReport?
    @Published var lastError: String?
    @Published var lastRepairMessage: String?
    @Published var codexAppServerReachable = false
    @Published var codexAppServerUserAgent: String?
    @Published var codexAppServerThreadListAvailable = false
    @Published var codexAppServerThreadCount = 0
    @Published var codexIPCSocketPath: String?
    @Published var codexDesktopApprovalConnected = false
    @Published var codexDesktopLastConnectedAt: Date?
    @Published var codexDesktopLastFailureMessage: String?
    @Published var isIslandTransitioning = false
    @Published var isApprovalDetailVisible = false
    @Published var healthChecks: [HealthCheckItem] = []
    @Published var sessionVisibilityRefreshToken = 0
    @Published var updateCheckState: UpdateCheckState = .idle

    let configurationStore: AppConfigurationStore

    let bridgeServer: BridgeServer
    let hookInstaller: HookInstaller
    let codexStateReader: CodexDesktopStateReader
    let codexLiveClient: CodexDesktopLiveClient
    let codexAppServerLiveClient: CodexAppServerLiveClient
    let transcriptReader: ConversationTranscriptReader
    let approvalNotificationCenter = ApprovalNotificationCenter()
    let statsStore = UsageStatsStore()
    let logger: AppLogger
    var pendingReplies: [String: (String?) -> Void] = [:]
    var pendingEvents: [String: AgentEvent] = [:]
    var pendingCodexDesktopApprovals: [String: CodexDesktopApproval] = [:]
    var pendingCodexDesktopDecisions: [String: ApprovalDecision] = [:]
    var refreshTimer: Timer?
    var visibilityTimer: Timer?
    var configCancellable: AnyCancellable?
    var soundCooldowns: [String: Date] = [:]
    var isRefreshingCodexDesktop = false
    var lastCodexDesktopRefreshAt: Date?
    var compactTapSuppressedUntil: Date?

    var selectedSession: AgentSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    var actionableHealthChecks: [HealthCheckItem] {
        healthChecks.filter(\.isActionable)
    }

    var disabledHealthChecks: [HealthCheckItem] {
        healthChecks.filter(\.isDisabled)
    }

    var normalHealthChecks: [HealthCheckItem] {
        healthChecks.filter(\.isNormal)
    }

    var exceptionOnlyHealthChecks: [HealthCheckItem] {
        healthChecks.filter(\.shouldShowInExceptionOnlyUI)
    }

    var hasActionableHealthChecks: Bool {
        !actionableHealthChecks.isEmpty
    }

    func suppressCompactTapBriefly() {
        compactTapSuppressedUntil = Date().addingTimeInterval(0.35)
    }

    func shouldSuppressCompactTap() -> Bool {
        guard let compactTapSuppressedUntil else { return false }
        if Date() < compactTapSuppressedUntil {
            return true
        }
        self.compactTapSuppressedUntil = nil
        return false
    }

    init(
        configurationStore: AppConfigurationStore,
        bridgeServer: BridgeServer = BridgeServer(),
        hookInstaller: HookInstaller = HookInstaller(),
        codexStateReader: CodexDesktopStateReader = CodexDesktopStateReader(),
        codexLiveClient: CodexDesktopLiveClient = CodexDesktopLiveClient(),
        codexAppServerLiveClient: CodexAppServerLiveClient = CodexAppServerLiveClient(),
        transcriptReader: ConversationTranscriptReader = ConversationTranscriptReader(),
        logger: AppLogger = .shared
    ) {
        self.configurationStore = configurationStore
        self.bridgeServer = bridgeServer
        self.hookInstaller = hookInstaller
        self.codexStateReader = codexStateReader
        self.codexLiveClient = codexLiveClient
        self.codexAppServerLiveClient = codexAppServerLiveClient
        self.transcriptReader = transcriptReader
        self.logger = logger

        codexAppServerLiveClient.onApproval = { [weak self] approval in
            self?.ingest(codexDesktopApproval: approval)
        }
        codexAppServerLiveClient.onResolved = { [weak self] requestKey in
            self?.markCodexDesktopRequestResolved(requestKey)
        }
        codexAppServerLiveClient.onStatusChanged = { [weak self] connected, path, lastConnectedAt, lastFailureMessage in
            self?.codexDesktopApprovalConnected = connected
            self?.codexDesktopLastConnectedAt = lastConnectedAt
            self?.codexDesktopLastFailureMessage = lastFailureMessage
            if let path {
                self?.codexIPCSocketPath = path
            }
            if connected {
                self?.lastError = nil
            }
            self?.refreshHealthChecks()
        }

        configCancellable = configurationStore.$config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleConfigurationChanged()
            }

        approvalNotificationCenter.approvalProvider = { [weak self] approvalID in
            self?.pendingApproval(withID: approvalID)
        }
        approvalNotificationCenter.onDecision = { [weak self] approvalID, decision in
            guard let self, let approval = self.pendingApproval(withID: approvalID) else { return }
            self.resolveApproval(approval, decision: decision)
        }
        approvalNotificationCenter.onOpenApproval = { [weak self] approvalID in
            guard let self else { return }
            if let session = self.sessions.first(where: { $0.approval?.id == approvalID }) {
                self.selectedSessionID = session.id
            }
            NSApp.activate(ignoringOtherApps: true)
            self.isExpanded = true
        }
    }

    func pendingApproval(withID id: String) -> ApprovalRequest? {
        sessions.compactMap(\.approval).first { $0.id == id }
    }

    func checkForUpdates() {
        guard updateCheckState != .checking else { return }
        updateCheckState = .checking
        let checker = UpdateChecker()
        Task { @MainActor [weak self] in
            let result = await checker.fetchLatestRelease()
            guard let self else { return }
            let current = UpdateChecker.currentVersion
            switch result {
            case .success(let release):
                if UpdateCheckPolicy.isNewer(remote: release.version, current: current) {
                    self.updateCheckState = .available(release)
                    self.logger.info("update.check.available", detail: release.version)
                } else {
                    self.updateCheckState = .upToDate(current: current)
                    self.logger.info("update.check.upToDate", detail: current)
                }
            case .failure(let error):
                self.updateCheckState = .failed(message: error.localizedDescription)
                self.logger.info("update.check.failed", detail: error.localizedDescription)
            }
        }
    }

    func notifyApprovalIfNeeded(_ approval: ApprovalRequest) {
        guard ApprovalNotificationPolicy.shouldNotify(
            enabled: configurationStore.config.enableApprovalNotifications,
            doNotDisturb: configurationStore.config.doNotDisturb,
            approval: approval
        ) else { return }
        approvalNotificationCenter.post(approval: approval, language: configurationStore.config.language)
    }

    func start() {
        do {
            try AppPaths.ensureRuntimeDirectories()
            try hookInstaller.installBridgeScript()
            try bridgeServer.start(path: AppPaths.socketURL.path) { [weak self] data, reply in
                DispatchQueue.main.async {
                    self?.handleBridgeData(data, reply: reply)
                }
            }
            refreshHealthChecks()
        } catch {
            lastError = AppText.pick(
                configurationStore.config.language,
                english: "Bridge failed to start: \(error.localizedDescription)",
                japanese: "Bridge の起動に失敗しました：\(error.localizedDescription)",
                chinese: "Bridge 启动失败：\(error.localizedDescription)"
            )
            logger.error("store.bridge.start.failed", detail: error.localizedDescription)
            refreshHealthChecks()
        }

        Task {
            await refreshCodexConnectivity()
            await refreshCodexDesktop(force: true)
            refreshHealthChecks()
        }
        if configurationStore.config.enableCodexDesktop {
            codexAppServerLiveClient.start()
            startCodexDesktopRefreshTimer()
        } else {
            stopCodexDesktopRefreshTimer()
        }
        if configurationStore.config.enableApprovalNotifications {
            approvalNotificationCenter.activate(language: configurationStore.config.language)
        }
        if configurationStore.config.autoCheckUpdates {
            checkForUpdates()
        }
        startVisibilityTimer()
    }

    func installSelectedHooks() {
        do {
            let report = try hookInstaller.installHooks(configuration: configurationStore.config)
            installReport = report
            lastError = nil
            refreshHealthChecks()
        } catch {
            lastError = AppText.pick(
                configurationStore.config.language,
                english: "Hook install failed: \(error.localizedDescription)",
                japanese: "Hook のインストールに失敗しました：\(error.localizedDescription)",
                chinese: "Hook 安装失败：\(error.localizedDescription)"
            )
            logger.error("store.hooks.install.failed", detail: error.localizedDescription)
            refreshHealthChecks()
        }
    }

    func repairConnections() {
        installSelectedHooks()
        if lastError == nil {
            lastRepairMessage = AppText.pick(
                configurationStore.config.language,
                english: "Connection repair ran. Hooks were installed or refreshed, and checks are running again.",
                japanese: "接続修復を実行しました。Hooks をインストールまたは更新し、チェックを再実行しています。",
                chinese: "已执行修复接入：Hooks 已安装或刷新，并已重新检测连接。"
            )
        }
        refreshDiagnostics()
    }

    func uninstallHooks() {
        do {
            let report = try hookInstaller.uninstallHooks()
            installReport = report
            lastError = nil
            refreshHealthChecks()
        } catch {
            lastError = AppText.pick(
                configurationStore.config.language,
                english: "Hook uninstall failed: \(error.localizedDescription)",
                japanese: "Hook のアンインストールに失敗しました：\(error.localizedDescription)",
                chinese: "Hook 卸载失败：\(error.localizedDescription)"
            )
            logger.error("store.hooks.uninstall.failed", detail: error.localizedDescription)
            refreshHealthChecks()
        }
    }

    func refreshDiagnostics() {
        refreshHealthChecks()
        if configurationStore.config.enableCodexDesktop {
            codexAppServerLiveClient.retryNow()
        }
        Task {
            await refreshCodexConnectivity()
            await refreshCodexDesktop(force: true)
            refreshHealthChecks()
        }
    }
}
