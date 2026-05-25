import AppKit
import VibelslandFreeCore
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var selectedSessionID: AgentSession.ID?
    @Published var isExpanded = false
    @Published var installReport: InstallReport?
    @Published var lastError: String?
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

    let configurationStore: AppConfigurationStore

    private let bridgeServer: BridgeServer
    private let hookInstaller: HookInstaller
    private let codexStateReader: CodexDesktopStateReader
    private let codexLiveClient: CodexDesktopLiveClient
    private let codexAppServerLiveClient: CodexAppServerLiveClient
    private let transcriptReader: ConversationTranscriptReader
    private let logger: AppLogger
    private var pendingReplies: [String: (String?) -> Void] = [:]
    private var pendingEvents: [String: AgentEvent] = [:]
    private var pendingCodexDesktopApprovals: [String: CodexDesktopApproval] = [:]
    private var pendingCodexDesktopDecisions: [String: ApprovalDecision] = [:]
    private var refreshTimer: Timer?
    private var visibilityTimer: Timer?
    private var configCancellable: AnyCancellable?
    private var soundCooldowns: [String: Date] = [:]
    private var isRefreshingCodexDesktop = false
    private var lastCodexDesktopRefreshAt: Date?
    private var compactTapSuppressedUntil: Date?

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
            lastError = "Bridge 启动失败：\(error.localizedDescription)"
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
        startVisibilityTimer()
    }

    func installSelectedHooks() {
        do {
            let report = try hookInstaller.installHooks(configuration: configurationStore.config)
            installReport = report
            lastError = nil
            refreshHealthChecks()
        } catch {
            lastError = "Hook 安装失败：\(error.localizedDescription)"
            logger.error("store.hooks.install.failed", detail: error.localizedDescription)
            refreshHealthChecks()
        }
    }

    func repairConnections() {
        installSelectedHooks()
        refreshDiagnostics()
    }

    func uninstallHooks() {
        do {
            let report = try hookInstaller.uninstallHooks()
            installReport = report
            lastError = nil
            refreshHealthChecks()
        } catch {
            lastError = "Hook 卸载失败：\(error.localizedDescription)"
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

    func openLogs() {
        do {
            try AppPaths.ensureRuntimeDirectories()
            if FileManager.default.fileExists(atPath: AppPaths.logURL.path) {
                let didSelect = NSWorkspace.shared.selectFile(
                    AppPaths.logURL.path,
                    inFileViewerRootedAtPath: AppPaths.logsDirectory.path
                )
                if !didSelect {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logURL])
                }
            } else {
                NSWorkspace.shared.open(AppPaths.logsDirectory)
            }
            lastError = nil
        } catch {
            lastError = "无法打开日志：\(error.localizedDescription)"
            logger.error("store.logs.open.failed", detail: error.localizedDescription)
        }
    }

    func resolveApproval(_ approval: ApprovalRequest, decision: ApprovalDecision) {
        if let desktopApproval = pendingCodexDesktopApprovals[approval.id] {
            guard desktopApproval.availableDecisions.contains(decision) else {
                markApprovalFailed(approval.id, message: "当前请求不支持“\(decision.title)”", state: .sendFailed)
                logger.info("codex.desktop.approval.unsupported", detail: "\(desktopApproval.method) \(decision.rawValue)")
                return
            }
            markApprovalResolving(approval.id)
            pendingCodexDesktopDecisions[approval.id] = decision
            codexAppServerLiveClient.respond(to: desktopApproval, decision: decision) { [weak self] result in
                switch result {
                case .success:
                    self?.scheduleCodexDesktopResolveTimeout(id: approval.id)
                case .failure(let error):
                    self?.markApprovalFailed(
                        approval.id,
                        message: error.userMessage,
                        state: error == .disconnected ? .disconnected : .sendFailed
                    )
                }
            }
            logger.info("codex.desktop.approval.sent", detail: "\(desktopApproval.method) \(decision.rawValue)")
            return
        }

        guard approval.supports(decision) else {
            markApprovalFailed(approval.id, message: "当前请求不支持“\(decision.title)”", state: .sendFailed)
            return
        }

        guard let event = pendingEvents[approval.id],
              let reply = pendingReplies[approval.id] else {
            markApprovalResolved(approval.id, decision: decision)
            return
        }

        guard let response = ApprovalResponseMapper.hookResponse(for: event, decision: decision) else {
            reply(nil)
            pendingReplies.removeValue(forKey: approval.id)
            pendingEvents.removeValue(forKey: approval.id)
            markApprovalTimedOut(approval.id)
            logger.info("approval.fallback", detail: event.source.rawValue)
            return
        }
        reply(response)
        pendingReplies.removeValue(forKey: approval.id)
        pendingEvents.removeValue(forKey: approval.id)
        markApprovalResolved(approval.id, decision: decision)
        logger.info("approval.resolved", detail: "\(event.source.rawValue) \(decision.rawValue)")
    }

    func focusCodexDesktop() {
        focusApplication(for: .codexDesktop)
    }

    func openSession(_ session: AgentSession) {
        logger.info("session.open.request", detail: "\(session.id) \(session.source.rawValue)")
        selectedSessionID = session.id
        switch SessionOpenPolicy.action(for: session) {
        case .selectOnly:
            return
        case let .openCodexThread(threadID, logNamespace, errorMessage):
            openCodexThread(
                threadID,
                expectedSessionID: session.id,
                logNamespace: logNamespace,
                errorMessage: errorMessage
            )
        case let .focusClaudeCodeTerminal(sessionID):
            focusClaudeCodeTerminal(sessionID: sessionID)
        case let .focusApplication(source):
            focusApplication(for: source)
        }
    }

    func focusApplication(for source: AgentSource) {
        guard let bundleID = source.applicationBundleIdentifier else {
            lastError = "无法确定要打开的应用"
            return
        }
        focusApplication(
            bundleID: bundleID,
            displayName: source.shortName,
            fallbackPaths: source.fallbackApplicationPath.map { [$0] } ?? []
        )
    }

    private func focusApplication(bundleID: String, displayName: String, fallbackPaths: [String]) {
        if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            application.unhide()
        }

        if runOpenCommand(arguments: CodexOpenCommandPolicy.focusArguments(bundleID: bundleID)) {
            confirmApplicationFocused(bundleID: bundleID, errorMessage: "无法打开 \(displayName)")
            return
        }

        let fallbackURL = fallbackPaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? fallbackURL else {
            lastError = "无法找到 \(displayName) 应用"
            return
        }

        if runOpenCommand(arguments: [url.path]) {
            confirmApplicationFocused(bundleID: bundleID, errorMessage: "无法打开 \(displayName)")
        } else {
            lastError = "无法打开 \(displayName)"
        }
    }

    private func confirmApplicationFocused(bundleID: String, errorMessage: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontmostBundleID == bundleID {
                isExpanded = false
                lastError = nil
            } else {
                lastError = errorMessage
                logger.error("application.focus.notFrontmost", detail: "\(bundleID) \(frontmostBundleID ?? "none")")
            }
        }
    }

    private func openCodexThread(
        _ threadID: String,
        expectedSessionID: String,
        logNamespace: String,
        errorMessage: String
    ) {
        guard let bundleID = AgentSource.codexDesktop.applicationBundleIdentifier else {
            lastError = "无法确定要打开的 Codex 应用"
            return
        }

        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?
            .unhide()

        let deepLink = CodexThreadLinkPolicy.deepLink(for: threadID)
        logger.info("session.open.\(logNamespace).deeplink", detail: deepLink)
        if runOpenCommand(arguments: CodexOpenCommandPolicy.deepLinkArguments(bundleID: bundleID, deepLink: deepLink)) {
            verifyCodexOpen(
                threadID: threadID,
                expectedSessionID: expectedSessionID,
                logNamespace: logNamespace,
                errorMessage: errorMessage
            )
            return
        }

        logger.error("session.open.\(logNamespace).deeplink.bundle.failed", detail: threadID)
        if runOpenCommand(arguments: CodexOpenCommandPolicy.fallbackDeepLinkArguments(deepLink)) {
            _ = runOpenCommand(arguments: CodexOpenCommandPolicy.focusArguments(bundleID: bundleID))
            verifyCodexOpen(
                threadID: threadID,
                expectedSessionID: expectedSessionID,
                logNamespace: logNamespace,
                errorMessage: errorMessage
            )
            return
        }

        logger.error("session.open.\(logNamespace).deeplink.failed", detail: threadID)
        lastError = errorMessage
    }

    private func verifyCodexOpen(
        threadID: String,
        expectedSessionID: String,
        logNamespace: String,
        errorMessage: String
    ) {
        guard let bundleID = AgentSource.codexDesktop.applicationBundleIdentifier else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard selectedSessionID == expectedSessionID else { return }

            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            logger.info(
                "session.open.\(logNamespace).frontmost",
                detail: "\(threadID) \(frontmostBundleID ?? "none")"
            )

            if frontmostBundleID == bundleID {
                codexAppServerLiveClient.checkThreadLoaded(threadID) { [weak self] loaded in
                    guard let self,
                          self.selectedSessionID == expectedSessionID else {
                        return
                    }
                    if loaded {
                        self.isExpanded = false
                        self.lastError = nil
                        self.logger.info("session.open.\(logNamespace).verified", detail: threadID)
                    } else {
                        self.lastError = "已打开 Codex，但未确认目标对话"
                        self.logger.error("session.open.\(logNamespace).thread.unverified", detail: threadID)
                    }
                }
                return
            }

            lastError = errorMessage
            logger.error(
                "session.open.\(logNamespace).notFrontmost",
                detail: "\(threadID) \(frontmostBundleID ?? "none")"
            )
        }
    }

    private func focusClaudeCodeTerminal(sessionID: String?) {
        if let bundleID = terminalBundleIdentifierForRunningClaude(sessionID: sessionID) {
            logger.info("session.open.claude.cli.terminal", detail: "\(sessionID ?? "unknown") \(bundleID)")
            focusApplication(bundleID: bundleID, displayName: "Claude CLI 终端", fallbackPaths: [])
            return
        }

        lastError = "没有找到正在运行的 Claude CLI 终端"
        logger.error("session.open.claude.cli.terminal.notFound", detail: sessionID ?? "unknown")
    }

    private func terminalBundleIdentifierForRunningClaude(sessionID: String?) -> String? {
        let snapshots = processSnapshots()
        let runningAppsByPID = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { (Int(app.processIdentifier), $0) }
        })
        return ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
            forSessionID: sessionID,
            processSnapshots: snapshots,
            runningAppsByPID: runningAppsByPID
        )
    }

    private func processSnapshots() -> [ProcessSnapshot] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,args="]
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            logger.error("process.snapshot.failed", detail: error.localizedDescription)
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else {
                return nil
            }
            return ProcessSnapshot(pid: pid, ppid: ppid, arguments: String(parts[2]))
        }
    }

    private func runOpenCommand(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("workspace.open.failed", detail: "\(arguments.joined(separator: " ")) \(error.localizedDescription)")
            return false
        }
    }

    private func handleBridgeData(_ data: Data, reply: @escaping (String?) -> Void) {
        do {
            guard try validateBridgeToken(in: data) else {
                logger.error("bridge.token.rejected")
                reply(nil)
                return
            }
            let event = try EventParser.parseBridgeData(data)
            guard sourceEnabled(event.source) else {
                reply(nil)
                return
            }
            ingest(event: event)

            if let approval = EventParser.approvalRequest(for: event) {
                pendingReplies[approval.id] = reply
                pendingEvents[approval.id] = event
                scheduleApprovalTimeout(id: approval.id)
            } else {
                reply(nil)
            }
        } catch {
            logger.error("bridge.parse.failed", detail: error.localizedDescription)
            reply(nil)
        }
    }

    private func validateBridgeToken(in data: Data) throws -> Bool {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let received = object["token"] as? String,
              !received.isEmpty,
              let expected = try? String(contentsOf: AppPaths.bridgeTokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return received == expected
    }

    private func ingest(event: AgentEvent) {
        logger.info("event.ingest", detail: "\(event.source.rawValue) \(event.kind.rawValue)")
        let sessionID = event.threadId ?? event.sessionId ?? "\(event.source.rawValue)-\(event.workspace ?? "default")"
        let previousSession = sessions.first { $0.id == sessionID }
        var session = previousSession ?? AgentSession(
            id: sessionID,
            title: EventParser.title(for: event),
            prompt: EventParser.title(for: event),
            source: event.source,
            workspace: event.workspace ?? "",
            terminal: event.source.displayName,
            updatedAt: event.timestamp,
            status: .idle,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )

        let eventTitle = EventParser.title(for: event)
        if shouldPromoteTitle(current: session.title, candidate: eventTitle, event: event) {
            session.title = eventTitle
        }
        if event.kind == .prompt {
            session.prompt = eventTitle
            session.lastUserMessage = eventTitle
        }
        if let workspace = event.workspace {
            session.workspace = workspace
        }
        if let threadID = event.threadId, !threadID.isEmpty {
            session.threadID = threadID
        }
        if let codexSessionStartSource = event.codexSessionStartSource, !codexSessionStartSource.isEmpty {
            session.codexSessionStartSource = codexSessionStartSource
        }
        session.updatedAt = event.timestamp
        session.status = SessionStateReducer.status(after: session.status, event: event)
        session.activity.append(EventParser.activity(for: event))
        if let transcript = transcriptReader.loadSnapshot(for: event),
           SessionStateReducer.shouldApplyTranscriptContent(transcript, to: event) {
            apply(transcript, to: &session, event: event)
        }
        if let message = assistantMessage(from: event) {
            session.lastAssistantMessage = message
        }

        let approval = EventParser.approvalRequest(for: event)
        if let approval {
            session.approval = approval
            session.status = .waitingApproval
        }

        if event.kind == .subagent {
            let subagentStatus = SessionStatusResolver.isSubagentCompletion(event) ? .done : session.status
            let subagent = SubagentItem(
                id: event.agentName ?? event.id,
                name: event.agentName ?? "Subagent",
                status: subagentStatus,
                detail: EventParser.title(for: event)
            )
            session.subagents.removeAll { $0.id == subagent.id }
            session.subagents.append(subagent)
        }

        upsert(session)

        if approval != nil {
            selectedSessionID = session.id
            if !configurationStore.config.doNotDisturb {
                isExpanded = true
            }
            logger.info("approval.focused", detail: "expanded=\(isExpanded) doNotDisturb=\(configurationStore.config.doNotDisturb)")
            playSound(.approval, key: "approval:\(session.id)", minimumInterval: 1.0)
        } else {
            playEventSound(event: event, previous: previousSession, current: session)
        }
    }

    private func ingest(codexDesktopApproval approval: CodexDesktopApproval) {
        pendingCodexDesktopApprovals[approval.id] = approval
        var session = sessions.first { $0.id == "codex-desktop-\(approval.threadID)" } ?? AgentSession(
            id: "codex-desktop-\(approval.threadID)",
            title: "Codex Desktop 审批",
            prompt: "Codex Desktop",
            source: .codexDesktop,
            workspace: approval.workspace ?? "",
            terminal: "Codex",
            updatedAt: Date(),
            status: .waitingApproval,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
        session.updatedAt = Date()
        session.status = .waitingApproval
        session.workspace = approval.workspace ?? session.workspace
        session.approval = approval.approvalRequest
        session.activity.append(ActivityItem(
            symbol: "hand.raised",
            title: approval.tool,
            detail: approval.detail
        ))
        upsert(session)
        selectedSessionID = session.id
        if !configurationStore.config.doNotDisturb {
            isExpanded = true
        }
        playSound(.approval, key: "approval:\(session.id)", minimumInterval: 1.0)
        logger.info("approval.focused", detail: "expanded=\(isExpanded) doNotDisturb=\(configurationStore.config.doNotDisturb)")
        logger.info("codex.desktop.approval.received", detail: approval.method)
    }

    private func refreshCodexConnectivity() async {
        let client = codexLiveClient
        let result = await Task.detached(priority: .utility) {
            client.initializeProbe()
        }.value
        codexAppServerReachable = result.reachable
        codexAppServerUserAgent = result.userAgent
        codexAppServerThreadListAvailable = result.threadListAvailable
        codexAppServerThreadCount = result.threadCount
        codexIPCSocketPath = codexAppServerLiveClient.codexIPCSocketCandidates(forceDeepScan: true).first?.path
    }

    private func refreshCodexDesktop(force: Bool = false) async {
        guard configurationStore.config.enableCodexDesktop else { return }
        let now = Date()
        if !force,
           let lastCodexDesktopRefreshAt,
           now.timeIntervalSince(lastCodexDesktopRefreshAt) < codexDesktopRefreshInterval {
            return
        }
        guard !isRefreshingCodexDesktop else { return }
        isRefreshingCodexDesktop = true
        defer {
            isRefreshingCodexDesktop = false
            lastCodexDesktopRefreshAt = Date()
        }

        let limit = configurationStore.config.maxVisibleSessions
        let reader = codexStateReader
        let snapshot = await Task.detached(priority: .utility) {
            let records = reader.loadRecentThreads(limit: limit)
            let threadSnapshots = Dictionary(uniqueKeysWithValues: records.map { record in
                (record.id, reader.loadThreadSnapshot(for: record))
            })
            return (records: records, snapshotsByID: threadSnapshots)
        }.value

        let parentThreadIDs = Set(snapshot.records.filter { $0.parentThreadID == nil }.map(\.id))
        for record in snapshot.records {
            if record.parentThreadID != nil {
                continue
            }
            let threadSnapshot = snapshot.snapshotsByID[record.id]
            let activities = threadSnapshot?.activities ?? []
            let existing = sessions.first { $0.id == "codex-desktop-\(record.id)" }
            let childRecords = snapshot.records.filter { $0.parentThreadID == record.id }
            let childSubagents = subagents(
                forParent: record.id,
                records: snapshot.records,
                snapshotsByID: snapshot.snapshotsByID
            )
            let childUpdatedAt = childRecords.map(\.updatedAt).max()
            let displayUpdatedAt = max(record.updatedAt, childUpdatedAt ?? record.updatedAt)
            let parentStatus = codexDesktopStatus(for: record, snapshot: threadSnapshot, existing: existing)
            let session = AgentSession(
                id: "codex-desktop-\(record.id)",
                title: DisplayTextSanitizer.sanitize(record.title.isEmpty ? URL(fileURLWithPath: record.cwd).lastPathComponent : record.title),
                prompt: record.model.isEmpty ? "Codex Desktop" : record.model,
                source: .codexDesktop,
                workspace: record.cwd,
                terminal: "Codex",
                updatedAt: displayUpdatedAt,
                status: desktopStatus(parent: parentStatus, subagents: childSubagents),
                activity: activities,
                approval: existing?.approval,
                question: nil,
                subagents: childSubagents,
                lastAssistantMessage: threadSnapshot?.lastAssistantMessage ?? existing?.lastAssistantMessage,
                lastUserMessage: threadSnapshot?.lastUserMessage ?? existing?.lastUserMessage,
                usage: threadSnapshot?.usage ?? existing?.usage
            )
            if existing != session {
                upsert(session)
                playStatusTransitionSound(previous: existing, current: session)
            }
        }

        let filteredSessions = sessions.filter { session in
            guard session.source == .codexDesktop,
                  session.id.hasPrefix("codex-desktop-") else {
                return true
            }
            if session.approval != nil {
                return true
            }
            let threadID = String(session.id.dropFirst("codex-desktop-".count))
            return parentThreadIDs.contains(threadID)
        }
        if filteredSessions.count != sessions.count {
            sessions = filteredSessions
            if !sessions.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = sessions.first?.id
            }
        }
    }

    private var codexDesktopRefreshInterval: TimeInterval {
        if isExpanded {
            return 2.0
        }
        let now = Date()
        let hasRecentOrActiveDesktop = sessions.contains { session in
            session.source == .codexDesktop &&
                (session.status.isActiveVisual || now.timeIntervalSince(session.updatedAt) < 45)
        }
        return hasRecentOrActiveDesktop ? 2.5 : 8.0
    }

    private func subagents(
        forParent parentID: String,
        records: [CodexThreadRecord],
        snapshotsByID: [String: CodexThreadSnapshot]
    ) -> [SubagentItem] {
        records
            .filter { $0.parentThreadID == parentID }
            .sorted { $0.updatedAtMilliseconds > $1.updatedAtMilliseconds }
            .map { record in
                SubagentItem(
                    id: record.id,
                    name: DisplayTextSanitizer.sanitize(record.agentNickname.isEmpty ? "Subagent" : record.agentNickname),
                    status: SessionStatusResolver.codexDesktopStatus(
                        recordUpdatedAt: record.updatedAt,
                        snapshot: snapshotsByID[record.id],
                        hasPendingApproval: false
                    ),
                    detail: DisplayTextSanitizer.sanitize(record.agentRole.isEmpty ? record.title : record.agentRole)
                )
            }
    }

    private func codexDesktopStatus(
        for record: CodexThreadRecord,
        snapshot: CodexThreadSnapshot?,
        existing: AgentSession?
    ) -> SessionStatus {
        SessionStatusResolver.codexDesktopStatus(
            recordUpdatedAt: record.updatedAt,
            snapshot: snapshot,
            hasPendingApproval: existing?.approval != nil
        )
    }

    private func desktopStatus(parent status: SessionStatus, subagents: [SubagentItem]) -> SessionStatus {
        if status == .waitingApproval || status == .failed {
            return status
        }
        if subagents.contains(where: { $0.status == .runningTool }) {
            return .runningTool
        }
        if subagents.contains(where: { $0.status.isActiveVisual }) {
            return .thinking
        }
        return status
    }

    private func upsert(_ session: AgentSession) {
        let session = SessionMemoryPolicy.compact(session)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        let deduped = SessionDeduper.compact(sessions, selectedSessionID: selectedSessionID)
        sessions = deduped.sessions.map(SessionMemoryPolicy.compact)
        selectedSessionID = deduped.selectedSessionID
        sessions.sort { $0.updatedAt > $1.updatedAt }
        sessions = Array(sessions.prefix(configuredVisibleSessionLimit))
        selectedSessionID = selectedSessionID ?? sessions.first?.id
    }

    private func handleConfigurationChanged() {
        sessions.removeAll { !sourceEnabled($0.source) }
        sessions = Array(sessions.prefix(configuredVisibleSessionLimit))
        if !sessions.contains(where: { $0.id == selectedSessionID }) {
            selectedSessionID = sessions.first?.id
        }
        if configurationStore.config.enableCodexDesktop {
            codexAppServerLiveClient.start()
            startCodexDesktopRefreshTimer()
            Task { await refreshCodexDesktop(force: true) }
        } else {
            codexAppServerLiveClient.stop()
            stopCodexDesktopRefreshTimer()
            codexDesktopApprovalConnected = false
        }
        refreshHealthChecks()
    }

    private func startCodexDesktopRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshCodexDesktop()
            }
        }
    }

    private func stopCodexDesktopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startVisibilityTimer() {
        guard visibilityTimer == nil else { return }
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshVisibleSessionAging()
            }
        }
    }

    private func refreshVisibleSessionAging() {
        guard !sessions.isEmpty else { return }
        let visible = DashboardSessionPolicy.visibleSessions(from: sessions, limit: configuredVisibleSessionLimit)
        if let selectedSessionID,
           !visible.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = visible.first?.id
        }
        sessionVisibilityRefreshToken = sessionVisibilityRefreshToken == Int.max
            ? 0
            : sessionVisibilityRefreshToken + 1
    }

    private var configuredVisibleSessionLimit: Int {
        DashboardSessionPolicy.configuredVisibleSessionLimit(configurationStore.config.maxVisibleSessions)
    }

    private func sourceEnabled(_ source: AgentSource) -> Bool {
        switch source {
        case .claudeCode:
            return configurationStore.config.enableClaude
        case .codexCli:
            return configurationStore.config.enableCodexCLI
        case .codexDesktop:
            return configurationStore.config.enableCodexDesktop
        case .unknown:
            return true
        }
    }

    private func apply(_ transcript: AgentTranscriptSnapshot, to session: inout AgentSession, event: AgentEvent) {
        if let message = transcript.lastUserMessage, !message.isEmpty {
            session.lastUserMessage = message
            session.prompt = message
            if shouldPromoteTitle(current: session.title, candidate: message, eventKind: .prompt, source: session.source) {
                session.title = message
            }
        }
        if let message = transcript.lastAssistantMessage, !message.isEmpty {
            session.lastAssistantMessage = message
        }
        if let usage = transcript.usage {
            session.usage = usage
        }
        if !transcript.activities.isEmpty {
            session.activity.append(contentsOf: transcript.activities)
            session.activity.sort { $0.date < $1.date }
        }
        if SessionStateReducer.shouldApplyTranscriptCompletion(transcript, to: event),
           session.approval == nil,
           session.status != .waitingApproval {
            session.status = .done
        }
    }

    private func shouldPromoteTitle(current: String, candidate: String, event: AgentEvent) -> Bool {
        shouldPromoteTitle(current: current, candidate: candidate, eventKind: event.kind, source: event.source)
    }

    private func shouldPromoteTitle(
        current: String,
        candidate: String,
        eventKind: AgentEventKind,
        source: AgentSource
    ) -> Bool {
        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLowInformationTitle(cleaned, source: source) else {
            return false
        }
        if eventKind == .prompt {
            return true
        }
        return isLowInformationTitle(current, source: source)
    }

    private func isLowInformationTitle(_ title: String, source: AgentSource) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        return trimmed.isEmpty
            || lowercased == source.displayName.lowercased()
            || lowercased == source.shortName.lowercased()
            || lowercased == ".claude"
            || lowercased == ".codex"
            || lowercased == "claude"
            || lowercased == "codex"
            || lowercased == "default"
            || lowercased.hasPrefix("gpt-")
    }

    func playSoundPreview(_ kind: RetroSoundKind) {
        guard configurationStore.config.enableSounds else {
            lastError = "声音已关闭"
            return
        }
        RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
        lastError = nil
    }

    func playAllSoundPreviews() {
        guard configurationStore.config.enableSounds else {
            lastError = "声音已关闭"
            return
        }
        lastError = nil
        Task { @MainActor in
            let kinds: [RetroSoundKind] = [
                .taskStarted,
                .toolTick,
                .taskCompleted,
                .taskFailed,
                .approval
            ]
            for kind in kinds {
                RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
                try? await Task.sleep(nanoseconds: 360_000_000)
            }
        }
    }

    private func playEventSound(event: AgentEvent, previous: AgentSession?, current: AgentSession) {
        playStatusTransitionSound(previous: previous, current: current)

        switch event.kind {
        case .tool, .subagent:
            playSound(.toolTick, key: "tool:\(current.id)", minimumInterval: 0.85)
        case .prompt, .session:
            if current.status.isActiveVisual {
                playSound(.taskStarted, key: "start:\(current.id)", minimumInterval: 2.0)
            }
        case .approval:
            playSound(.approval, key: "approval:\(current.id)", minimumInterval: 1.0)
        case .notification, .status:
            break
        }
    }

    private func playStatusTransitionSound(previous: AgentSession?, current: AgentSession) {
        guard let previous,
              previous.status != current.status else {
            return
        }

        switch current.status {
        case .thinking, .runningTool:
            if !previous.status.isActiveVisual {
                playSound(.taskStarted, key: "start:\(current.id)", minimumInterval: 2.0)
            }
        case .done:
            playSound(.taskCompleted, key: "done:\(current.id)", minimumInterval: 4.0)
        case .failed:
            playSound(.taskFailed, key: "failed:\(current.id)", minimumInterval: 4.0)
        case .waitingApproval, .waitingQuestion:
            playSound(.approval, key: "approval:\(current.id)", minimumInterval: 1.0)
        case .idle:
            break
        }
    }

    private func playSound(_ kind: RetroSoundKind, key: String, minimumInterval: TimeInterval) {
        guard configurationStore.config.enableSounds,
              !configurationStore.config.doNotDisturb else {
            return
        }
        let now = Date()
        soundCooldowns = SessionMemoryPolicy.compactCooldowns(soundCooldowns, now: now)
        if let lastPlayed = soundCooldowns[key],
           now.timeIntervalSince(lastPlayed) < minimumInterval {
            return
        }
        soundCooldowns[key] = now
        RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
    }

    private func assistantMessage(from event: AgentEvent) -> String? {
        let object = event.payload.objectValue ?? [:]
        let candidates = [
            object["codex_last_assistant_message"]?.stringValue,
            object["last_assistant_message"]?.stringValue,
            object["last_agent_message"]?.stringValue,
            object["assistant_response"]?.stringValue,
            object["message"]?.stringValue
        ]
        return candidates.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return DisplayTextSanitizer.sanitize(String(value.prefix(700)))
        }.first
    }

    private func scheduleApprovalTimeout(id: String) {
        let timeout = ApprovalTimeoutPolicy.timeout(configured: configurationStore.config.approvalTimeoutSeconds)
        logger.info("approval.timeout.scheduled", detail: "\(id) \(timeout)s")
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.expirePendingApproval(id: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func expirePendingApproval(id: String) {
        guard let reply = pendingReplies.removeValue(forKey: id) else { return }
        pendingEvents.removeValue(forKey: id)
        markApprovalTimedOut(id)
        reply(nil)
    }

    private func scheduleCodexDesktopResolveTimeout(id: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard pendingCodexDesktopApprovals[id] != nil else { return }
            guard sessions.contains(where: { $0.approval?.id == id && $0.approval?.isResolving == true }) else {
                return
            }
            markApprovalFailed(id, message: "Codex Desktop 未确认结果，已停止等待", state: .timedOut, expired: true)
        }
    }

    private func markApprovalResolving(_ id: String) {
        for index in sessions.indices where sessions[index].approval?.id == id {
            sessions[index].approval?.isResolving = true
            sessions[index].approval?.isExpired = false
            sessions[index].approval?.resolutionState = .resolving
            sessions[index].approval?.resolutionMessage = "正在返回审批结果"
        }
    }

    private func markApprovalResolved(_ id: String, decision: ApprovalDecision) {
        for index in sessions.indices {
            if sessions[index].approval?.id == id {
                let state = approvalResolutionState(for: decision)
                sessions[index].activity.append(ActivityItem(
                    symbol: approvalResolutionSymbol(for: state),
                    title: state.title,
                    detail: decision.title
                ))
                sessions[index].approval = nil
                sessions[index].status = decision == .cancel ? .failed : .runningTool
                sessions[index] = SessionMemoryPolicy.compact(sessions[index])
            }
        }
        logger.info("approval.resolved.marked", detail: id)
        pendingCodexDesktopApprovals.removeValue(forKey: id)
        pendingCodexDesktopDecisions.removeValue(forKey: id)
    }

    private func markApprovalFailed(
        _ id: String,
        message: String,
        state: ApprovalResolutionState = .sendFailed,
        expired: Bool = false
    ) {
        for index in sessions.indices where sessions[index].approval?.id == id {
            sessions[index].approval?.isResolving = false
            sessions[index].approval?.isExpired = expired
            sessions[index].approval?.resolutionState = state
            sessions[index].approval?.resolutionMessage = message
            sessions[index].status = .waitingApproval
        }
        if expired {
            pendingCodexDesktopApprovals.removeValue(forKey: id)
            pendingCodexDesktopDecisions.removeValue(forKey: id)
        }
    }

    private func markApprovalTimedOut(_ id: String) {
        for index in sessions.indices {
            if sessions[index].approval?.id == id {
                sessions[index].activity.append(ActivityItem(
                    symbol: "clock",
                    title: ApprovalResolutionState.timedOut.title,
                    detail: "未返回自动决策，保留原生流程"
                ))
                sessions[index].approval = nil
                sessions[index].status = .failed
                sessions[index] = SessionMemoryPolicy.compact(sessions[index])
            }
        }
        logger.info("approval.timedOut", detail: id)
        pendingCodexDesktopApprovals.removeValue(forKey: id)
        pendingCodexDesktopDecisions.removeValue(forKey: id)
    }

    private func markCodexDesktopRequestResolved(_ requestKey: String) {
        let approvalID = "codex-desktop-approval-\(requestKey)"
        let decision = pendingCodexDesktopDecisions[approvalID] ?? .accept
        let state = approvalResolutionState(for: decision)
        for index in sessions.indices where sessions[index].approval?.id == approvalID {
            sessions[index].activity.append(ActivityItem(
                symbol: approvalResolutionSymbol(for: state),
                title: state.title,
                detail: "Codex Desktop 已接收结果"
            ))
            sessions[index].approval = nil
            sessions[index].status = decision == .cancel ? .failed : .runningTool
            sessions[index] = SessionMemoryPolicy.compact(sessions[index])
        }
        pendingCodexDesktopApprovals.removeValue(forKey: approvalID)
        pendingCodexDesktopDecisions.removeValue(forKey: approvalID)
        logger.info("codex.desktop.approval.resolved", detail: requestKey)
    }

    private func approvalResolutionState(for decision: ApprovalDecision) -> ApprovalResolutionState {
        switch decision {
        case .accept, .acceptForSession:
            return .accepted
        case .decline:
            return .declined
        case .cancel:
            return .cancelled
        }
    }

    private func approvalResolutionSymbol(for state: ApprovalResolutionState) -> String {
        switch state {
        case .accepted:
            return "checkmark.circle"
        case .declined:
            return "xmark.circle"
        case .cancelled:
            return "stop.circle"
        case .timedOut:
            return "clock"
        case .sendFailed, .disconnected:
            return "exclamationmark.triangle"
        case .pending, .resolving:
            return "hand.raised"
        }
    }

    private func refreshHealthChecks() {
        healthChecks = buildHealthChecks()
    }

    private func buildHealthChecks() -> [HealthCheckItem] {
        let bridgeEnabled = configurationStore.config.enableClaude || configurationStore.config.enableCodexCLI
        let bridgeReady = FileManager.default.isExecutableFile(atPath: AppPaths.bridgeURL.path)
        let socketInspection = inspectBridgeSocket()
        let claudeHookReady = hookFileContainsBridge(AppPaths.claudeSettingsURL)
        let codexHookReady = hookFileContainsBridge(AppPaths.codexHooksURL)
        let claudeRecentEventText = recentEventText(for: .claudeCode)
        let codexRecentEventText = recentEventText(for: .codexCli)

        return [
            BridgeRuntimeHealthPolicy.item(
                bridgeEnabled: bridgeEnabled,
                bridgeExecutable: bridgeReady,
                socket: socketInspection
            ),
            HealthCheckItem(
                id: "claude",
                name: "Claude Code",
                status: configurationStore.config.enableClaude ? (claudeHookReady ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableClaude ? (claudeHookReady ? claudeRecentEventText : "已启用来源，但未发现 Vibelsland hook") : "来源已关闭，不接收 Claude 事件",
                suggestedAction: configurationStore.config.enableClaude ? "安装/修复 Hooks" : "在接收来源中启用"
            ),
            HealthCheckItem(
                id: "codex-cli",
                name: "Codex CLI",
                status: configurationStore.config.enableCodexCLI ? (codexHookReady ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableCodexCLI ? (codexHookReady ? codexRecentEventText : "已启用来源，但未发现 Codex hook") : "来源已关闭，不接收 Codex CLI 事件",
                suggestedAction: configurationStore.config.enableCodexCLI ? "安装/修复 Hooks" : "在接收来源中启用"
            ),
            HealthCheckItem(
                id: "codex-desktop",
                name: "Codex Desktop",
                status: configurationStore.config.enableCodexDesktop ? (codexDesktopApprovalConnected ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableCodexDesktop ? codexDesktopDetail : "来源已关闭，不读取 Codex Desktop 状态",
                suggestedAction: configurationStore.config.enableCodexDesktop ? "重新连接" : "在接收来源中启用"
            )
        ]
    }

    private func inspectBridgeSocket() -> BridgeSocketInspection {
        var statBuffer = stat()
        guard lstat(AppPaths.socketURL.path, &statBuffer) == 0 else {
            return .missing
        }
        let fileType = statBuffer.st_mode & S_IFMT
        return BridgeSocketInspection(
            exists: true,
            isSocket: fileType == S_IFSOCK,
            ownerMatchesCurrentUser: statBuffer.st_uid == getuid(),
            permissions: Int(statBuffer.st_mode & 0o777)
        )
    }

    private var codexDesktopDetail: String {
        if codexDesktopApprovalConnected {
            if let codexDesktopLastConnectedAt {
                return "实时审批已连接，上次连接 \(relativeTime(from: codexDesktopLastConnectedAt))"
            }
            return "实时审批已连接"
        }
        if let codexDesktopLastFailureMessage,
           !codexDesktopLastFailureMessage.isEmpty {
            return "实时审批未连接：\(codexDesktopLastFailureMessage)"
        }
        if let codexIPCSocketPath {
            return "发现 IPC socket，但实时审批未连接：\(URL(fileURLWithPath: codexIPCSocketPath).lastPathComponent)"
        }
        if codexAppServerReachable {
            return "App Server 可用，但未发现 Desktop IPC"
        }
        return "未连接 Codex Desktop 实时通道"
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func hookFileContainsBridge(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return HookConfigMerger.containsBridge(object)
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func recentEventText(for source: AgentSource) -> String {
        guard let recentEvent = sessions.first(where: { session in
            if source == .codexCli {
                return session.source == .codexCli || session.source == .codexDesktop
            }
            return session.source == source
        })?.updatedAt else {
            return "还没有收到事件"
        }
        return "最近事件：\(relativeText(for: recentEvent))"
    }
}
