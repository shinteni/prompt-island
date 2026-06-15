import VibelslandFreeCore
import Foundation


extension SessionStore {
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

    func scheduleApprovalTimeout(id: String) {
        let timeout = ApprovalTimeoutPolicy.timeout(configured: configurationStore.config.approvalTimeoutSeconds)
        logger.info("approval.timeout.scheduled", detail: "\(id) \(timeout)s")
        let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.expirePendingApproval(id: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func expirePendingApproval(id: String) {
        guard let reply = pendingReplies.removeValue(forKey: id) else { return }
        pendingEvents.removeValue(forKey: id)
        markApprovalTimedOut(id)
        reply(nil)
    }

    func scheduleCodexDesktopResolveTimeout(id: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard pendingCodexDesktopApprovals[id] != nil else { return }
            guard sessions.contains(where: { $0.approval?.id == id && $0.approval?.isResolving == true }) else {
                return
            }
            markApprovalFailed(id, message: "Codex Desktop 未确认结果，已停止等待", state: .timedOut, expired: true)
        }
    }

    func markApprovalResolving(_ id: String) {
        for index in sessions.indices where sessions[index].approval?.id == id {
            sessions[index].approval?.isResolving = true
            sessions[index].approval?.isExpired = false
            sessions[index].approval?.resolutionState = .resolving
            sessions[index].approval?.resolutionMessage = "正在返回审批结果"
        }
    }

    func markApprovalResolved(_ id: String, decision: ApprovalDecision) {
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

    func markApprovalFailed(
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

    func markApprovalTimedOut(_ id: String) {
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

    func markCodexDesktopRequestResolved(_ requestKey: String) {
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

    func approvalResolutionState(for decision: ApprovalDecision) -> ApprovalResolutionState {
        switch decision {
        case .accept, .acceptForSession:
            return .accepted
        case .decline:
            return .declined
        case .cancel:
            return .cancelled
        }
    }

    func approvalResolutionSymbol(for state: ApprovalResolutionState) -> String {
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
}
