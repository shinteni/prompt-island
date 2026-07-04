import VibelslandFreeCore
import Foundation


extension SessionStore {
    func handleBridgeData(_ data: Data, reply: @escaping (String?) -> Void) {
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

    func validateBridgeToken(in data: Data) throws -> Bool {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let received = object["token"] as? String,
              !received.isEmpty,
              let expected = try? String(contentsOf: AppPaths.bridgeTokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return received == expected
    }

    func ingest(event: AgentEvent) {
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

        if let approval {
            selectedSessionID = session.id
            if !configurationStore.config.doNotDisturb {
                isExpanded = true
            }
            logger.info("approval.focused", detail: "expanded=\(isExpanded) doNotDisturb=\(configurationStore.config.doNotDisturb)")
            playSound(.approval, key: "approval:\(session.id)", minimumInterval: 1.0)
            notifyApprovalIfNeeded(approval)
        } else {
            playEventSound(event: event, previous: previousSession, current: session)
        }
    }

    func ingest(codexDesktopApproval approval: CodexDesktopApproval) {
        pendingCodexDesktopApprovals[approval.id] = approval
        let approvalSessionTitle = AppText.pick(
            configurationStore.config.language,
            english: "Codex Desktop approval",
            japanese: "Codex Desktop 承認",
            chinese: "Codex Desktop 审批"
        )
        var session = sessions.first { $0.id == "codex-desktop-\(approval.threadID)" } ?? AgentSession(
            id: "codex-desktop-\(approval.threadID)",
            title: approvalSessionTitle,
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
        session.title = approvalSessionTitle
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
        notifyApprovalIfNeeded(approval.approvalRequest)
        logger.info("approval.focused", detail: "expanded=\(isExpanded) doNotDisturb=\(configurationStore.config.doNotDisturb)")
        logger.info("codex.desktop.approval.received", detail: approval.method)
    }

    func refreshCodexConnectivity() async {
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

    func refreshCodexDesktop(force: Bool = false) async {
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

    var codexDesktopRefreshInterval: TimeInterval {
        CodexRefreshCadencePolicy.interval(sessions: sessions, isExpanded: isExpanded)
    }

    func subagents(
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

    func codexDesktopStatus(
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

    func desktopStatus(parent status: SessionStatus, subagents: [SubagentItem]) -> SessionStatus {
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

    func upsert(_ session: AgentSession) {
        let session = SessionMemoryPolicy.compact(session)
        recordStatsTransition(previous: sessions.first { $0.id == session.id }, current: session)
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

    /// 只记录状态转移与增量，upsert 的重复回放（如 Codex 刷新重建会话）不会重复计数。
    func recordStatsTransition(previous: AgentSession?, current: AgentSession) {
        let delta = UsageStatsPolicy.usageDelta(previous: previous?.usage, current: current.usage)
        let started = previous == nil
        let completed = previous?.status != .done && current.status == .done
        let failed = previous?.status != .failed && current.status == .failed
        let approvalReceived = current.approval != nil && previous?.approval?.id != current.approval?.id
        guard started || completed || failed || approvalReceived || delta.tokens > 0 || delta.costUSD > 0 else {
            return
        }
        statsStore.record { day in
            if started {
                day.recordSessionStarted(source: current.source)
            }
            if completed {
                day.sessionsCompleted += 1
            }
            if failed {
                day.sessionsFailed += 1
            }
            if approvalReceived {
                day.approvalsReceived += 1
            }
            day.tokens += delta.tokens
            day.estimatedCostUSD += delta.costUSD
        }
    }

    func handleConfigurationChanged() {
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
        if configurationStore.config.enableApprovalNotifications {
            // 覆盖两种情况：开关刚打开（首次激活+请求授权）、语言切换（动作按钮标题跟随语言）。
            approvalNotificationCenter.activate(language: configurationStore.config.language)
        }
        refreshHealthChecks()
    }

    func startCodexDesktopRefreshTimer() {
        guard refreshTimer == nil else { return }
        scheduleNextCodexDesktopRefresh()
    }

    func stopCodexDesktopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// 单发自排程：每次刷新完按当前活跃度决定下一次唤醒，替代固定 1 秒轮询。
    func scheduleNextCodexDesktopRefresh() {
        refreshTimer?.invalidate()
        let interval = CodexRefreshCadencePolicy.interval(sessions: sessions, isExpanded: isExpanded)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshCodexDesktop()
                guard self.refreshTimer != nil else { return }
                self.scheduleNextCodexDesktopRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func startVisibilityTimer() {
        scheduleVisibilityRefresh()
    }

    /// 只在真正需要的时刻唤醒：面板展开时按 15 秒刷新相对时间，折叠时只在
    /// 会话跨可见性边界的精确时刻唤醒；无会话则完全不设定时器。
    func scheduleVisibilityRefresh() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        guard let delay = SessionAgingSchedulePolicy.nextRefreshDelay(
            sessions: sessions,
            isExpanded: isExpanded
        ) else {
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisibleSessionAging()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }

    func refreshVisibleSessionAging() {
        defer { scheduleVisibilityRefresh() }
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

    var configuredVisibleSessionLimit: Int {
        DashboardSessionPolicy.configuredVisibleSessionLimit(configurationStore.config.maxVisibleSessions)
    }

    func sourceEnabled(_ source: AgentSource) -> Bool {
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

    func apply(_ transcript: AgentTranscriptSnapshot, to session: inout AgentSession, event: AgentEvent) {
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

    func shouldPromoteTitle(current: String, candidate: String, event: AgentEvent) -> Bool {
        shouldPromoteTitle(current: current, candidate: candidate, eventKind: event.kind, source: event.source)
    }

    func shouldPromoteTitle(
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

    func isLowInformationTitle(_ title: String, source: AgentSource) -> Bool {
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
}
