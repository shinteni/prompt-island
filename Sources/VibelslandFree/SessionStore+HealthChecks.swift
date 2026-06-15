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

    func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale.current
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
        formatter.locale = Locale.current
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func recentEventText(for source: AgentSource) -> String {
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
