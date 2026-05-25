import Foundation

package enum CodexDesktopApprovalKind: String, Equatable {
    case commandExecution
    case fileChange
    case permissions
    case legacyExec
    case legacyPatch
}

package enum CodexDesktopApprovalResponseError: Error, Equatable {
    case unsupportedDecision
    case disconnected
    case encodeFailed
    case writeFailed(String)

    package var userMessage: String {
        switch self {
        case .unsupportedDecision:
            return "当前请求不支持这个审批选项"
        case .disconnected:
            return "Codex Desktop 实时连接已断开"
        case .encodeFailed:
            return "审批结果编码失败"
        case .writeFailed(let detail):
            return "审批结果发送失败：\(detail)"
        }
    }
}

package struct CodexDesktopApproval: Equatable {
    package var id: String
    package var requestID: JSONValue
    package var method: String
    package var kind: CodexDesktopApprovalKind
    package var threadID: String
    package var turnID: String?
    package var itemID: String?
    package var workspace: String?
    package var tool: String
    package var detail: String
    package var requestedPermissions: JSONValue?
    package var availableDecisions: [ApprovalDecision]

    package var approvalRequest: ApprovalRequest {
        ApprovalRequest(
            id: id,
            source: .codexDesktop,
            title: "Codex Desktop 请求审批",
            detail: detail,
            tool: tool,
            workspace: workspace,
            availableDecisions: availableDecisions,
            suggestedSessionAllow: availableDecisions.contains(.acceptForSession),
            supportsCancel: availableDecisions.contains(.cancel),
            createdAt: Date()
        )
    }
}

package final class CodexAppServerLiveClient: @unchecked Sendable {
    package typealias ApprovalHandler = @MainActor (CodexDesktopApproval) -> Void
    package typealias ResolvedHandler = @MainActor (String) -> Void
    package typealias StatusHandler = @MainActor (Bool, String?, Date?, String?) -> Void
    package typealias ResponseHandler = @MainActor (Result<Void, CodexDesktopApprovalResponseError>) -> Void
    package typealias ThreadLoadedHandler = @MainActor (Bool) -> Void

    private let logger: AppLogger
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "free.vibelsland.codex-appserver-live")

    private var shouldRun = false
    private var process: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var stdoutBuffer = Data()
    private var nextRequestID = 100
    private var socketPath: String?
    private var cachedSocketURL: URL?
    private var lastDeepSocketScanAt: Date?
    private var reconnectAttempt = 0
    private var pendingThreadLoadedChecks: [Int: (threadID: String, completion: ThreadLoadedHandler)] = [:]
    private let deepSocketScanInterval: TimeInterval = 60

    package var onApproval: ApprovalHandler?
    package var onResolved: ResolvedHandler?
    package var onStatusChanged: StatusHandler?
    package var lastConnectedAt: Date?
    package var lastFailureMessage: String?

    package init(logger: AppLogger = .shared, fileManager: FileManager = .default) {
        self.logger = logger
        self.fileManager = fileManager
    }

    package func start() {
        queue.async { [weak self] in
            guard let self, !self.shouldRun else { return }
            self.shouldRun = true
            self.startLocked()
        }
    }

    package func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            self.stopLocked()
        }
    }

    package func retryNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = true
            guard self.process == nil else { return }
            self.startLocked()
        }
    }

    package func respond(
        to approval: CodexDesktopApproval,
        decision: ApprovalDecision,
        completion: ResponseHandler? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let result = Self.responseResult(for: approval, decision: decision) else {
                self.logger.error("codex.desktop.approval.unsupported", detail: "\(approval.method) \(decision.rawValue)")
                self.publishResponse(.failure(.unsupportedDecision), completion)
                return
            }
            let response: [String: Any] = [
                "id": Self.jsonObject(from: approval.requestID) ?? approval.id,
                "result": result
            ]
            let writeResult = self.writeJSONObject(response)
            self.publishResponse(writeResult, completion)
        }
    }

    package func checkThreadLoaded(
        _ threadID: String,
        timeout: TimeInterval = 1.4,
        completion: @escaping ThreadLoadedHandler
    ) {
        queue.async { [weak self] in
            guard let self,
                  self.process?.isRunning == true else {
                self?.publishThreadLoaded(false, completion)
                return
            }

            let requestID = self.nextRequestID
            self.nextRequestID += 1
            self.pendingThreadLoadedChecks[requestID] = (threadID, completion)
            let writeResult = self.writeJSONObject([
                "id": requestID,
                "method": "thread/loaded/list",
                "params": ["limit": 50]
            ])
            if case .failure = writeResult {
                self.pendingThreadLoadedChecks.removeValue(forKey: requestID)
                self.publishThreadLoaded(false, completion)
                return
            }

            self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self,
                      let pending = self.pendingThreadLoadedChecks.removeValue(forKey: requestID) else {
                    return
                }
                self.logger.error("codex.desktop.thread.loaded.timeout", detail: pending.threadID)
                self.publishThreadLoaded(false, pending.completion)
            }
        }
    }

    package func codexIPCSocketCandidates(forceDeepScan: Bool = false) -> [URL] {
        let uid = getuid()
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["VIBELSLAND_CODEX_IPC_SOCKET"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let cachedSocketURL {
            candidates.append(cachedSocketURL)
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        candidates.append(
            tempURL
                .appendingPathComponent("codex-ipc", isDirectory: true)
                .appendingPathComponent("ipc-\(uid).sock")
        )

        let now = Date()
        let shouldDeepScan = forceDeepScan
            || lastDeepSocketScanAt == nil
            || now.timeIntervalSince(lastDeepSocketScanAt ?? .distantPast) >= deepSocketScanInterval
        if shouldDeepScan {
            lastDeepSocketScanAt = now
            let foldersURL = URL(fileURLWithPath: "/var/folders", isDirectory: true)
            if let enumerator = fileManager.enumerator(
                at: foldersURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                let suffix = "/T/codex-ipc/ipc-\(uid).sock"
                for case let url as URL in enumerator where url.path.hasSuffix(suffix) {
                    candidates.append(url)
                }
            }
        }

        var seen = Set<String>()
        let existing = candidates.filter { url in
            guard fileManager.fileExists(atPath: url.path),
                  seen.insert(url.path).inserted else {
                return false
            }
            return true
        }
        cachedSocketURL = existing.first
        return existing
    }

    private func startLocked() {
        guard shouldRun, process == nil else { return }
        guard let codexPath = findCodexExecutable() else {
            lastFailureMessage = "找不到 Codex CLI 可执行文件"
            publishStatus(false, nil)
            logger.error("codex.desktop.live.missing.codex")
            scheduleReconnect()
            return
        }
        guard let socketURL = codexIPCSocketCandidates().first else {
            lastFailureMessage = "未发现 Codex Desktop IPC socket"
            publishStatus(false, nil)
            logger.error("codex.desktop.live.missing.socket")
            scheduleReconnect()
            return
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "proxy", "--sock", socketURL.path]
        process.environment = CodexExecutableResolver.processEnvironment(forExecutablePath: codexPath)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let client = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            client.queue.async { [weak client] in
                client?.handleStdout(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !detail.isEmpty {
                self?.queue.async { [weak self] in
                    self?.lastFailureMessage = detail
                }
                self?.logger.error("codex.desktop.live.stderr", detail: detail)
            }
        }
        process.terminationHandler = { [weak self] _ in
            guard let client = self else { return }
            client.queue.async { [weak client] in
                client?.handleTermination()
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdin = stdin
            self.stdout = stdout
            self.stderr = stderr
            self.socketPath = socketURL.path
            self.cachedSocketURL = socketURL
            self.lastConnectedAt = Date()
            self.lastFailureMessage = nil
            self.reconnectAttempt = 0
            self.stdoutBuffer.removeAll()
            publishStatus(true, socketURL.path)
            sendInitialize()
            logger.info("codex.desktop.live.connected", detail: socketURL.path)
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            lastFailureMessage = error.localizedDescription
            publishStatus(false, nil)
            logger.error("codex.desktop.live.start.failed", detail: error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func stopLocked() {
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        try? stdin?.fileHandleForWriting.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        socketPath = nil
        stdoutBuffer.removeAll()
        failPendingThreadLoadedChecks()
        publishStatus(false, nil)
    }

    private func handleTermination() {
        process = nil
        stdin = nil
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        stdout = nil
        stderr = nil
        socketPath = nil
        stdoutBuffer.removeAll()
        failPendingThreadLoadedChecks()
        if shouldRun {
            if lastFailureMessage?.isEmpty != false {
                lastFailureMessage = "Codex Desktop 实时审批连接已断开"
            }
        }
        publishStatus(false, nil)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldRun else { return }
        reconnectAttempt += 1
        let delay = reconnectDelay(for: reconnectAttempt)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startLocked()
        }
    }

    private func reconnectDelay(for attempt: Int) -> TimeInterval {
        min(30, pow(2.0, Double(min(max(attempt - 1, 0), 4))) * 2.0)
    }

    private func sendInitialize() {
        let id = nextRequestID
        nextRequestID += 1
        _ = writeJSONObject([
            "id": id,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "prompt-island", "version": "2"],
                "capabilities": [:]
            ]
        ])
        _ = writeJSONObject(["method": "initialized"])
    }

    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }
            handleMessage(object)
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        if let id = Self.integerID(from: message["id"]),
           let pending = pendingThreadLoadedChecks.removeValue(forKey: id) {
            let loaded = Self.loadedThreadIDs(from: message).contains(pending.threadID)
            logger.info("codex.desktop.thread.loaded.check", detail: "\(pending.threadID) \(loaded)")
            publishThreadLoaded(loaded, pending.completion)
            return
        }

        guard let method = message["method"] as? String else {
            return
        }

        if let approval = Self.approval(from: message) {
            Task { @MainActor [onApproval] in
                onApproval?(approval)
            }
            return
        }

        if method == "serverRequest/resolved",
           let params = message["params"] as? [String: Any],
           let requestID = params["requestId"] {
            let key = Self.requestKey(JSONValue(any: requestID))
            Task { @MainActor [onResolved] in
                onResolved?(key)
            }
            return
        }

        if message["id"] != nil {
            _ = writeJSONObject([
                "id": message["id"] ?? NSNull(),
                "error": [
                    "code": -32601,
                    "message": ">_ - island does not handle \(method)"
                ]
            ])
        }
    }

    private func failPendingThreadLoadedChecks() {
        let pending = Array(pendingThreadLoadedChecks.values)
        pendingThreadLoadedChecks.removeAll()
        for item in pending {
            publishThreadLoaded(false, item.completion)
        }
    }

    private func writeJSONObject(_ object: [String: Any]) -> Result<Void, CodexDesktopApprovalResponseError> {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8),
              let output = (line + "\n").data(using: .utf8) else {
            logger.error("codex.desktop.live.encode.failed")
            return .failure(.encodeFailed)
        }
        guard let writer = stdin?.fileHandleForWriting else {
            logger.error("codex.desktop.live.disconnected")
            return .failure(.disconnected)
        }
        do {
            try writer.write(contentsOf: output)
            return .success(())
        } catch {
            logger.error("codex.desktop.live.write.failed", detail: error.localizedDescription)
            handleTermination()
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    private func publishResponse(
        _ result: Result<Void, CodexDesktopApprovalResponseError>,
        _ completion: ResponseHandler?
    ) {
        guard let completion else { return }
        Task { @MainActor in
            completion(result)
        }
    }

    private func publishThreadLoaded(_ loaded: Bool, _ completion: @escaping ThreadLoadedHandler) {
        Task { @MainActor in
            completion(loaded)
        }
    }

    private func publishStatus(_ connected: Bool, _ path: String?) {
        let lastConnectedAt = lastConnectedAt
        let lastFailureMessage = lastFailureMessage
        Task { @MainActor [onStatusChanged] in
            onStatusChanged?(connected, path, lastConnectedAt, lastFailureMessage)
        }
    }

    private func findCodexExecutable() -> String? {
        CodexExecutableResolver.executablePath()
    }
}

package extension CodexAppServerLiveClient {
    static func loadedThreadIDs(from message: [String: Any]) -> [String] {
        guard let result = message["result"] as? [String: Any],
              let data = result["data"] as? [Any] else {
            return []
        }
        return data.compactMap { $0 as? String }
    }

    static func integerID(from value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    static func approval(from message: [String: Any]) -> CodexDesktopApproval? {
        guard let method = message["method"] as? String,
              let requestID = message["id"],
              let params = message["params"] as? [String: Any] else {
            return nil
        }

        let requestJSONID = JSONValue(any: requestID)
        let id = "codex-desktop-approval-\(requestKey(requestJSONID))"
        let threadID = string(params["threadId"]) ?? string(params["conversationId"]) ?? ""
        let turnID = string(params["turnId"])
        let itemID = string(params["itemId"]) ?? string(params["callId"])
        let cwd = string(params["cwd"])
        let modernDecisions = availableDecisions(in: params, default: [.accept, .acceptForSession, .decline, .cancel])

        switch method {
        case "item/commandExecution/requestApproval":
            return CodexDesktopApproval(
                id: id,
                requestID: requestJSONID,
                method: method,
                kind: .commandExecution,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                workspace: cwd,
                tool: "命令执行",
                detail: string(params["command"]) ?? string(params["reason"]) ?? "Codex 请求执行命令",
                requestedPermissions: JSONValue(any: params["additionalPermissions"]),
                availableDecisions: modernDecisions
            )
        case "item/fileChange/requestApproval":
            return CodexDesktopApproval(
                id: id,
                requestID: requestJSONID,
                method: method,
                kind: .fileChange,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                workspace: cwd,
                tool: "文件修改",
                detail: string(params["reason"]) ?? string(params["grantRoot"]) ?? "Codex 请求修改文件",
                requestedPermissions: nil,
                availableDecisions: modernDecisions
            )
        case "item/permissions/requestApproval":
            return CodexDesktopApproval(
                id: id,
                requestID: requestJSONID,
                method: method,
                kind: .permissions,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                workspace: cwd,
                tool: "权限请求",
                detail: string(params["reason"]) ?? JSONValue(any: params["permissions"]).flattenedText(limit: 240),
                requestedPermissions: JSONValue(any: params["permissions"]),
                availableDecisions: modernDecisions
            )
        case "execCommandApproval":
            let command = (params["command"] as? [Any])?.compactMap { string($0) }.joined(separator: " ")
            return CodexDesktopApproval(
                id: id,
                requestID: requestJSONID,
                method: method,
                kind: .legacyExec,
                threadID: threadID,
                turnID: turnID,
                itemID: itemID,
                workspace: cwd,
                tool: "命令执行",
                detail: command ?? string(params["reason"]) ?? "Codex 请求执行命令",
                requestedPermissions: nil,
                availableDecisions: [.accept, .acceptForSession, .decline, .cancel]
            )
        case "applyPatchApproval":
            let fileChanges = (params["fileChanges"] as? [String: Any])?.keys.sorted().joined(separator: ", ")
            return CodexDesktopApproval(
                id: id,
                requestID: requestJSONID,
                method: method,
                kind: .legacyPatch,
                threadID: threadID,
                turnID: nil,
                itemID: itemID,
                workspace: nil,
                tool: "文件修改",
                detail: string(params["reason"]) ?? fileChanges ?? "Codex 请求应用修改",
                requestedPermissions: nil,
                availableDecisions: [.accept, .acceptForSession, .decline, .cancel]
            )
        default:
            return nil
        }
    }

    static func responseResult(for approval: CodexDesktopApproval, decision: ApprovalDecision) -> [String: Any]? {
        guard approval.availableDecisions.contains(decision) else { return nil }
        switch approval.kind {
        case .commandExecution, .fileChange:
            return ["decision": decision.rawValue]
        case .permissions:
            switch decision {
            case .accept, .acceptForSession:
                var permissions: [String: Any] = [:]
                if let object = approval.requestedPermissions.flatMap(jsonObject) as? [String: Any] {
                    permissions = object
                }
                return [
                    "permissions": permissions,
                    "scope": decision == .acceptForSession ? "session" : "turn",
                    "strictAutoReview": false
                ]
            case .decline, .cancel:
                return [
                    "permissions": [:],
                    "scope": "turn",
                    "strictAutoReview": false
                ]
            }
        case .legacyExec, .legacyPatch:
            let legacyDecision: String
            switch decision {
            case .accept: legacyDecision = "approved"
            case .acceptForSession: legacyDecision = "approved_for_session"
            case .decline: legacyDecision = "denied"
            case .cancel: legacyDecision = "abort"
            }
            return ["decision": legacyDecision]
        }
    }

    static func requestKey(_ value: JSONValue) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number): return String(Int(number))
        case .bool(let bool): return String(bool)
        case .object, .array, .null:
            return value.flattenedText(limit: 80)
        }
    }

    private static func availableDecisions(in params: [String: Any], default defaultDecisions: [ApprovalDecision]) -> [ApprovalDecision] {
        if params.keys.contains("availableDecisions") {
            return approvalDecisions(params["availableDecisions"])
        }
        if params.keys.contains("available_decisions") {
            return approvalDecisions(params["available_decisions"])
        }
        return defaultDecisions
    }

    private static func approvalDecisions(_ value: Any?) -> [ApprovalDecision] {
        guard let array = value as? [Any] else { return [] }
        var seen = Set<ApprovalDecision>()
        return array.compactMap { item -> ApprovalDecision? in
            if let string = item as? String {
                let decision = ApprovalDecision(rawValue: string)
                if let decision, seen.insert(decision).inserted {
                    return decision
                }
            }
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value.isEmpty ? nil : value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func jsonObject(from value: JSONValue?) -> Any? {
        switch value {
        case .string(let string): string
        case .number(let double): double
        case .bool(let bool): bool
        case .object(let object): object.mapValues { jsonObject(from: $0) ?? NSNull() }
        case .array(let array): array.map { jsonObject(from: $0) ?? NSNull() }
        case .null, nil: nil
        }
    }
}
