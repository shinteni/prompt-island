import AppKit
import VibelslandFreeCore
import Foundation


extension SessionStore {
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
            lastError = AppText.pick(
                configurationStore.config.language,
                english: "Could not open logs: \(error.localizedDescription)",
                japanese: "ログを開けません：\(error.localizedDescription)",
                chinese: "无法打开日志：\(error.localizedDescription)"
            )
            logger.error("store.logs.open.failed", detail: error.localizedDescription)
        }
    }

    func focusCodexDesktop() {
        focusApplication(for: .codexDesktop)
    }

    func openSession(_ session: AgentSession) {
        logger.info("session.open.request", detail: "\(session.id) \(session.source.rawValue)")
        selectedSessionID = session.id
        switch SessionOpenPolicy.action(for: session, language: configurationStore.config.language) {
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
            lastError = AppText.pick(configurationStore.config.language, english: "Could not determine which app to open", japanese: "開くアプリを判定できません", chinese: "无法确定要打开的应用")
            return
        }
        focusApplication(
            bundleID: bundleID,
            displayName: source.shortName,
            fallbackPaths: source.fallbackApplicationPath.map { [$0] } ?? []
        )
    }

    func focusApplication(bundleID: String, displayName: String, fallbackPaths: [String]) {
        if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            application.unhide()
        }

        if runOpenCommand(arguments: CodexOpenCommandPolicy.focusArguments(bundleID: bundleID)) {
            confirmApplicationFocused(bundleID: bundleID, errorMessage: cannotOpenText(displayName))
            return
        }

        let fallbackURL = fallbackPaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? fallbackURL else {
            lastError = AppText.pick(configurationStore.config.language, english: "Could not find \(displayName)", japanese: "\(displayName) が見つかりません", chinese: "无法找到 \(displayName) 应用")
            return
        }

        if runOpenCommand(arguments: [url.path]) {
            confirmApplicationFocused(bundleID: bundleID, errorMessage: cannotOpenText(displayName))
        } else {
            lastError = cannotOpenText(displayName)
        }
    }

    func confirmApplicationFocused(bundleID: String, errorMessage: String) {
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

    func openCodexThread(
        _ threadID: String,
        expectedSessionID: String,
        logNamespace: String,
        errorMessage: String
    ) {
        guard let bundleID = AgentSource.codexDesktop.applicationBundleIdentifier else {
            lastError = AppText.pick(configurationStore.config.language, english: "Could not determine which Codex app to open", japanese: "開く Codex アプリを判定できません", chinese: "无法确定要打开的 Codex 应用")
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

    func verifyCodexOpen(
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
                        self.lastError = AppText.pick(
                            self.configurationStore.config.language,
                            english: "Codex opened, but the target thread was not confirmed",
                            japanese: "Codex は開きましたが、対象の会話を確認できませんでした",
                            chinese: "已打开 Codex，但未确认目标对话"
                        )
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

    func focusClaudeCodeTerminal(sessionID: String?) {
        if let bundleID = terminalBundleIdentifierForRunningClaude(sessionID: sessionID) {
            logger.info("session.open.claude.cli.terminal", detail: "\(sessionID ?? "unknown") \(bundleID)")
            focusApplication(bundleID: bundleID, displayName: AppText.pick(configurationStore.config.language, english: "Claude CLI terminal", japanese: "Claude CLI ターミナル", chinese: "Claude CLI 终端"), fallbackPaths: [])
            return
        }

        lastError = AppText.pick(configurationStore.config.language, english: "No running Claude CLI terminal was found", japanese: "実行中の Claude CLI ターミナルが見つかりません", chinese: "没有找到正在运行的 Claude CLI 终端")
        logger.error("session.open.claude.cli.terminal.notFound", detail: sessionID ?? "unknown")
    }

    private func cannotOpenText(_ displayName: String) -> String {
        AppText.pick(configurationStore.config.language, english: "Could not open \(displayName)", japanese: "\(displayName) を開けません", chinese: "无法打开 \(displayName)")
    }

    func terminalBundleIdentifierForRunningClaude(sessionID: String?) -> String? {
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

    func processSnapshots() -> [ProcessSnapshot] {
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

    func runOpenCommand(arguments: [String]) -> Bool {
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
}
