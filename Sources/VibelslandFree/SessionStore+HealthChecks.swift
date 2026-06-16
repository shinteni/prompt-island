import VibelslandFreeCore
import Darwin
import Foundation


extension SessionStore {
    func refreshHealthChecks() {
        healthChecks = buildHealthChecks()
    }

    func buildHealthChecks() -> [HealthCheckItem] {
        let bridgeEnabled = configurationStore.config.enableClaude || configurationStore.config.enableCodexCLI
        let bridgeReady = FileManager.default.isExecutableFile(atPath: AppPaths.bridgeURL.path)
        let socketInspection = inspectBridgeSocket()
        let claudeHookReady = hookFileContainsBridge(AppPaths.claudeSettingsURL)
        let codexHookReady = hookFileContainsBridge(AppPaths.codexHooksURL)
        let claudeRecentEventText = recentEventText(for: .claudeCode)
        let codexRecentEventText = recentEventText(for: .codexCli)
        let language = configurationStore.config.language

        return [
            BridgeRuntimeHealthPolicy.item(
                bridgeEnabled: bridgeEnabled,
                bridgeExecutable: bridgeReady,
                socket: socketInspection,
                language: language
            ),
            HealthCheckItem(
                id: "claude",
                name: "Claude Code",
                status: configurationStore.config.enableClaude ? (claudeHookReady ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableClaude ? (claudeHookReady ? claudeRecentEventText : missingVibelslandHookText(language)) : sourceDisabledText("Claude", language: language),
                suggestedAction: configurationStore.config.enableClaude ? repairHooksText(language) : enableInSourcesText(language)
            ),
            HealthCheckItem(
                id: "codex-cli",
                name: "Codex CLI",
                status: configurationStore.config.enableCodexCLI ? (codexHookReady ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableCodexCLI ? (codexHookReady ? codexRecentEventText : missingCodexHookText(language)) : sourceDisabledText("Codex CLI", language: language),
                suggestedAction: configurationStore.config.enableCodexCLI ? repairHooksText(language) : enableInSourcesText(language)
            ),
            HealthCheckItem(
                id: "codex-desktop",
                name: "Codex Desktop",
                status: configurationStore.config.enableCodexDesktop ? (codexDesktopApprovalConnected ? .normal : .needsAction) : .disabled,
                detail: configurationStore.config.enableCodexDesktop ? codexDesktopDetail : codexDesktopDisabledText(language),
                suggestedAction: configurationStore.config.enableCodexDesktop ? reconnectText(language) : enableInSourcesText(language)
            )
        ]
    }

    func inspectBridgeSocket() -> BridgeSocketInspection {
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

    var codexDesktopDetail: String {
        if codexDesktopApprovalConnected {
            if let codexDesktopLastConnectedAt {
                return AppText.pick(
                    configurationStore.config.language,
                    english: "Live approvals connected, last connected \(relativeTime(from: codexDesktopLastConnectedAt))",
                    japanese: "リアルタイム承認は接続済み、最終接続 \(relativeTime(from: codexDesktopLastConnectedAt))",
                    chinese: "实时审批已连接，上次连接 \(relativeTime(from: codexDesktopLastConnectedAt))"
                )
            }
            return AppText.pick(configurationStore.config.language, english: "Live approvals connected", japanese: "リアルタイム承認は接続済み", chinese: "实时审批已连接")
        }
        if let codexDesktopLastFailureMessage,
           !codexDesktopLastFailureMessage.isEmpty {
            return AppText.pick(
                configurationStore.config.language,
                english: "Live approvals not connected: \(codexDesktopLastFailureMessage)",
                japanese: "リアルタイム承認は未接続：\(codexDesktopLastFailureMessage)",
                chinese: "实时审批未连接：\(codexDesktopLastFailureMessage)"
            )
        }
        if let codexIPCSocketPath {
            return AppText.pick(
                configurationStore.config.language,
                english: "IPC socket found, but live approvals are not connected: \(URL(fileURLWithPath: codexIPCSocketPath).lastPathComponent)",
                japanese: "IPC socket は見つかりましたが、リアルタイム承認は未接続です：\(URL(fileURLWithPath: codexIPCSocketPath).lastPathComponent)",
                chinese: "发现 IPC socket，但实时审批未连接：\(URL(fileURLWithPath: codexIPCSocketPath).lastPathComponent)"
            )
        }
        if codexAppServerReachable {
            return AppText.pick(configurationStore.config.language, english: "App Server is available, but Desktop IPC was not found", japanese: "App Server は利用可能ですが Desktop IPC が見つかりません", chinese: "App Server 可用，但未发现 Desktop IPC")
        }
        return AppText.pick(configurationStore.config.language, english: "Codex Desktop live channel is not connected", japanese: "Codex Desktop のリアルタイムチャネルは未接続です", chinese: "未连接 Codex Desktop 实时通道")
    }

    func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppText.locale(for: configurationStore.config.language)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func hookFileContainsBridge(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return HookConfigMerger.containsBridge(object)
    }

    func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppText.locale(for: configurationStore.config.language)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func recentEventText(for source: AgentSource) -> String {
        guard let recentEvent = sessions.first(where: { session in
            if source == .codexCli {
                return session.source == .codexCli || session.source == .codexDesktop
            }
            return session.source == source
        })?.updatedAt else {
            return AppText.pick(configurationStore.config.language, english: "No events received yet", japanese: "まだイベントを受信していません", chinese: "还没有收到事件")
        }
        return AppText.pick(
            configurationStore.config.language,
            english: "Latest event: \(relativeText(for: recentEvent))",
            japanese: "最新イベント：\(relativeText(for: recentEvent))",
            chinese: "最近事件：\(relativeText(for: recentEvent))"
        )
    }

    private func missingVibelslandHookText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Source is enabled, but Vibelsland hook was not found", japanese: "受信元は有効ですが Vibelsland hook が見つかりません", chinese: "已启用来源，但未发现 Vibelsland hook")
    }

    private func missingCodexHookText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Source is enabled, but Codex hook was not found", japanese: "受信元は有効ですが Codex hook が見つかりません", chinese: "已启用来源，但未发现 Codex hook")
    }

    private func sourceDisabledText(_ source: String, language: AppLanguage) -> String {
        AppText.pick(language, english: "Source is off. \(source) events are not received.", japanese: "受信元はオフです。\(source) イベントは受信しません。", chinese: "来源已关闭，不接收 \(source) 事件")
    }

    private func codexDesktopDisabledText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Source is off. Codex Desktop state is not read.", japanese: "受信元はオフです。Codex Desktop 状態は読み取りません。", chinese: "来源已关闭，不读取 Codex Desktop 状态")
    }

    private func repairHooksText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Install or repair hooks", japanese: "Hooks をインストールまたは修復", chinese: "安装/修复 Hooks")
    }

    private func enableInSourcesText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Enable in Sources", japanese: "受信元で有効化", chinese: "在接收来源中启用")
    }

    private func reconnectText(_ language: AppLanguage) -> String {
        AppText.pick(language, english: "Reconnect", japanese: "再接続", chinese: "重新连接")
    }
}
