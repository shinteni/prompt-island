import AppKit
import VibelslandFreeCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader()

                if hasVisibleIssues {
                    IssueSummarySection(
                        error: store.lastError,
                        items: store.exceptionOnlyHealthChecks,
                        refresh: store.refreshDiagnostics,
                        repairHooks: store.installSelectedHooks,
                        openLogs: store.openLogs
                    )
                }

                ReceiveSourcesSection(
                    claudeEnabled: binding(\.enableClaude),
                    codexCLIEnabled: binding(\.enableCodexCLI),
                    codexDesktopEnabled: binding(\.enableCodexDesktop),
                    claudeHealth: healthItem("claude"),
                    codexCLIHealth: healthItem("codex-cli"),
                    codexDesktopHealth: healthItem("codex-desktop")
                )

                IslandPreferencesSection(
                    position: binding(\.islandPosition),
                    launchAtLogin: launchAtLoginBinding,
                    soundsEnabled: binding(\.enableSounds),
                    soundTheme: binding(\.soundTheme),
                    doNotDisturb: binding(\.doNotDisturb),
                    maxVisibleSessions: binding(\.maxVisibleSessions),
                    playPreview: store.playSoundPreview,
                    playAllPreviews: store.playAllSoundPreviews
                )

                ApprovalPreferencesSection(
                    approvalTimeoutSeconds: binding(\.approvalTimeoutSeconds),
                    approvalWaitText: approvalWaitText
                )

                MaintenanceSection(
                    allHealthChecks: store.healthChecks,
                    refresh: store.refreshDiagnostics,
                    repairHooks: store.installSelectedHooks,
                    openLogs: store.openLogs
                )

                DiagnosticsSection(
                    codexAppServerReachable: store.codexAppServerReachable,
                    codexAppServerThreadListAvailable: store.codexAppServerThreadListAvailable,
                    codexAppServerThreadCount: store.codexAppServerThreadCount,
                    codexIPCSocketPath: store.codexIPCSocketPath,
                    codexDesktopApprovalConnected: store.codexDesktopApprovalConnected,
                    codexDesktopLastConnectedAt: store.codexDesktopLastConnectedAt,
                    codexDesktopLastFailureMessage: store.codexDesktopLastFailureMessage,
                    installReport: store.installReport
                )

                AdvancedActionsSection(
                    uninstallHooks: store.uninstallHooks,
                    restart: {
                        NSApp.sendAction(#selector(AppDelegate.restart), to: nil, from: nil)
                    },
                    quit: {
                        NSApp.sendAction(#selector(AppDelegate.quit), to: nil, from: nil)
                    }
                )
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 820, minHeight: 680)
        .onAppear {
            NotificationCenter.default.post(name: .vibelslandSettingsDidAppear, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .vibelslandSettingsDidDisappear, object: nil)
        }
    }

    private var hasVisibleIssues: Bool {
        store.lastError != nil || !store.exceptionOnlyHealthChecks.isEmpty
    }

    private func healthItem(_ id: String) -> HealthCheckItem? {
        store.healthChecks.first { $0.id == id }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { configurationStore.config[keyPath: keyPath] },
            set: { configurationStore.config[keyPath: keyPath] = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LaunchAtLoginController.isEnabled },
            set: { value in
                let previous = configurationStore.config.launchAtLogin
                switch LaunchAtLoginController.setEnabled(value) {
                case .success(let actual):
                    configurationStore.config.launchAtLogin = actual
                    if actual != value {
                        store.lastError = "登录启动未能切换到请求状态，请确认当前运行的是已打包的 .app。"
                    } else {
                        store.lastError = nil
                    }
                case .failure(let error):
                    configurationStore.config.launchAtLogin = previous
                    store.lastError = "登录启动设置失败：\(error.localizedDescription)"
                }
            }
        )
    }

    private var approvalWaitText: String {
        let seconds = Int(configurationStore.config.approvalTimeoutSeconds)
        if seconds < 3600 {
            return "\(max(1, seconds / 60)) 分钟"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if minutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }
}

private struct SettingsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Vibelsland Free")
                .font(.system(size: 28, weight: .semibold))
            Text("管理浮岛显示、提醒来源和本机审批接入。正常状态下不显示健康检查细节。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

private struct IssueSummarySection: View {
    let error: String?
    let items: [HealthCheckItem]
    let refresh: () -> Void
    let repairHooks: () -> Void
    let openLogs: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("需要处理")
                            .font(.system(size: 16, weight: .semibold))
                        Text("这些问题可能会影响事件接收或审批回传。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新检测", action: refresh)
                        .accessibilityLabel("重新检测")
                        .accessibilityIdentifier("settings.issue.refresh")
                    Button("修复 Hooks", action: repairHooks)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("修复 Hooks")
                        .accessibilityIdentifier("settings.issue.repairHooks")
                }

                if let error {
                    MessageRow(
                        icon: "xmark.octagon.fill",
                        title: "最近错误",
                        detail: error,
                        color: .red
                    )
                }

                ForEach(items) { item in
                    HealthCheckRow(item: item, prominent: true)
                }

                HStack {
                    Button("打开日志", action: openLogs)
                        .accessibilityLabel("打开日志")
                        .accessibilityIdentifier("settings.issue.openLogs")
                    Spacer()
                }
            }
        }
    }
}

private struct ReceiveSourcesSection: View {
    @Binding var claudeEnabled: Bool
    @Binding var codexCLIEnabled: Bool
    @Binding var codexDesktopEnabled: Bool
    let claudeHealth: HealthCheckItem?
    let codexCLIHealth: HealthCheckItem?
    let codexDesktopHealth: HealthCheckItem?

    var body: some View {
        SettingsCard(title: "接收来源", subtitle: "开关只控制接收和显示，不会卸载已经写入的 Hooks。") {
            VStack(spacing: 0) {
                SourceToggleRow(
                    title: "Claude Code",
                    subtitle: "通过 Hooks 接收审批和事件",
                    health: claudeHealth,
                    systemImage: "sparkles",
                    isOn: $claudeEnabled
                )
                SettingsDivider()
                SourceToggleRow(
                    title: "Codex CLI",
                    subtitle: "通过 Hooks 接收命令行事件",
                    health: codexCLIHealth,
                    systemImage: "terminal",
                    isOn: $codexCLIEnabled
                )
                SettingsDivider()
                SourceToggleRow(
                    title: "Codex Desktop",
                    subtitle: "读取本机状态，并接收实时审批",
                    health: codexDesktopHealth,
                    systemImage: "macwindow",
                    isOn: $codexDesktopEnabled
                )
            }
        }
    }
}

private struct SourceToggleRow: View {
    let title: String
    let subtitle: String
    let health: HealthCheckItem?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    if let health, health.status == .needsAction {
                        StatusPill(status: health.status)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if let health, health.status == .needsAction {
                    Text(health.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

private struct IslandPreferencesSection: View {
    @Binding var position: IslandPosition
    @Binding var launchAtLogin: Bool
    @Binding var soundsEnabled: Bool
    @Binding var soundTheme: SoundTheme
    @Binding var doNotDisturb: Bool
    @Binding var maxVisibleSessions: Int
    let playPreview: (RetroSoundKind) -> Void
    let playAllPreviews: () -> Void

    var body: some View {
        SettingsCard(title: "浮岛与提醒", subtitle: "控制浮岛出现位置、声音和展开内容数量。") {
            VStack(spacing: 0) {
                SettingsRow(icon: "rectangle.inset.filled.and.person.filled", title: "浮岛位置") {
                    Picker("", selection: $position) {
                        ForEach(IslandPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(icon: "power", title: "登录时启动") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(icon: "speaker.wave.2", title: "声音") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $soundsEnabled)
                            .labelsHidden()
                        Picker("", selection: $soundTheme) {
                            ForEach(SoundTheme.allCases) { theme in
                                Text(theme.title).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 112)
                        .disabled(!soundsEnabled)
                        Menu("试听") {
                            Button("任务开始") {
                                playPreview(.taskStarted)
                            }
                            Button("工具调用") {
                                playPreview(.toolTick)
                            }
                            Button("任务完成") {
                                playPreview(.taskCompleted)
                            }
                            Button("任务失败") {
                                playPreview(.taskFailed)
                            }
                            Button("审批提醒") {
                                playPreview(.approval)
                            }
                            Divider()
                            Button("试听全部", action: playAllPreviews)
                        }
                        .disabled(!soundsEnabled)
                    }
                }
                SettingsDivider()
                SettingsRow(icon: "moon", title: "勿扰") {
                    Toggle("", isOn: $doNotDisturb)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(icon: "list.bullet.rectangle", title: "展开时最多显示") {
                    Stepper(
                        value: $maxVisibleSessions,
                        in: DashboardSessionPolicy.minimumConfiguredVisibleSessions...DashboardSessionPolicy.maximumVisibleSessions
                    ) {
                        Text("\(maxVisibleSessions) 个会话")
                            .monospacedDigit()
                    }
                    .frame(width: 150)
                }
            }
        }
    }
}

private struct ApprovalPreferencesSection: View {
    @Binding var approvalTimeoutSeconds: TimeInterval
    let approvalWaitText: String

    var body: some View {
        SettingsCard(title: "审批", subtitle: "只影响真实审批回传的等待时间。") {
            VStack(spacing: 0) {
                SettingsRow(icon: "checkmark.shield", title: "等待时间") {
                    Stepper(value: $approvalTimeoutSeconds, in: 60...7200, step: 300) {
                        Text(approvalWaitText)
                            .monospacedDigit()
                    }
                    .frame(width: 170)
                }
                SettingsDivider()
                Text("应用不可用时会立即回退；应用已接管请求后，超时不会自动允许或拒绝。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }
}

private struct MaintenanceSection: View {
    let allHealthChecks: [HealthCheckItem]
    let refresh: () -> Void
    let repairHooks: () -> Void
    let openLogs: () -> Void

    var body: some View {
        SettingsCard(title: "维护", subtitle: "日常只需要在这里重新检测或修复接入。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button("重新检测", action: refresh)
                        .accessibilityLabel("重新检测")
                        .accessibilityIdentifier("settings.maintenance.refresh")
                    Button("安装/修复 Hooks", action: repairHooks)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("安装/修复 Hooks")
                        .accessibilityIdentifier("settings.maintenance.repairHooks")
                    Button("打开日志", action: openLogs)
                        .accessibilityLabel("打开日志")
                        .accessibilityIdentifier("settings.maintenance.openLogs")
                    Spacer()
                }

                if issueItems.isEmpty {
                    Text(allHealthChecks.isEmpty ? "尚未运行检测。" : "未发现需要处理的问题。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    DisclosureGroup("查看需要处理的检查") {
                        VStack(spacing: 10) {
                            ForEach(issueItems) { item in
                                HealthCheckRow(item: item, prominent: false)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private var issueItems: [HealthCheckItem] {
        allHealthChecks.filter { $0.status == .needsAction }
    }
}

private struct DiagnosticsSection: View {
    let codexAppServerReachable: Bool
    let codexAppServerThreadListAvailable: Bool
    let codexAppServerThreadCount: Int
    let codexIPCSocketPath: String?
    let codexDesktopApprovalConnected: Bool
    let codexDesktopLastConnectedAt: Date?
    let codexDesktopLastFailureMessage: String?
    let installReport: InstallReport?

    var body: some View {
        SettingsCard(title: "高级诊断", subtitle: "排查问题时再展开。") {
            DisclosureGroup("显示技术诊断") {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("技术连接状态") {
                        VStack(spacing: 10) {
                            DiagnosticRow(title: "App Server", value: codexAppServerReachable ? "可用" : "未连接")
                            DiagnosticRow(
                                title: "thread/list",
                                value: codexAppServerThreadListAvailable ? "可用，\(codexAppServerThreadCount) 条" : "不可用"
                            )
                            DiagnosticRow(title: "Desktop IPC", value: codexIPCSocketPath ?? "未发现", monospaced: true)
                            DiagnosticRow(title: "实时审批", value: codexDesktopApprovalConnected ? "已连接" : "未连接")
                            DiagnosticRow(title: "最近连接", value: lastConnectedText)
                            DiagnosticRow(title: "最近失败", value: codexDesktopLastFailureMessage ?? "无")
                        }
                        .padding(.top, 10)
                    }

                    DisclosureGroup("本机路径") {
                        VStack(spacing: 10) {
                            PathRow(title: "Bridge", path: AppPaths.bridgeURL.path)
                            PathRow(title: "Socket", path: AppPaths.socketURL.path)
                            PathRow(title: "配置", path: AppPaths.configURL.path)
                            PathRow(title: "日志", path: AppPaths.logURL.path)
                        }
                        .padding(.top, 10)
                    }

                    if let installReport {
                        DisclosureGroup("最近安装") {
                            VStack(spacing: 10) {
                                DiagnosticRow(title: "Bridge", value: installReport.bridgeInstalled ? "已安装" : "未安装")
                                DiagnosticRow(title: "Claude", value: installReport.claudeHooksInstalled ? "已合并" : "未启用")
                                DiagnosticRow(title: "Codex", value: installReport.codexHooksInstalled ? "已合并" : "未启用")
                                if installReport.codexHooksInstalled {
                                    DiagnosticRow(
                                        title: "Codex hooks 开关",
                                        value: installReport.codexFeatureFlagEnabled
                                            ? (installReport.codexFeatureFlagChanged ? "已开启" : "已开启，无需修改")
                                            : "未开启"
                                    )
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var lastConnectedText: String {
        guard let codexDesktopLastConnectedAt else { return "未连接过" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: codexDesktopLastConnectedAt)
    }
}

private struct AdvancedActionsSection: View {
    let uninstallHooks: () -> Void
    let restart: () -> Void
    let quit: () -> Void

    var body: some View {
        SettingsCard(title: "应用", subtitle: "重启和退出直接可用；会改写本机接入的操作单独收起。") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button("重启应用", action: restart)
                        .accessibilityLabel("重启应用")
                        .accessibilityIdentifier("settings.app.restart")
                    Button("退出应用", action: quit)
                        .accessibilityLabel("退出应用")
                        .accessibilityIdentifier("settings.app.quit")
                    Spacer()
                }

                SettingsDivider()

                DisclosureGroup("危险操作") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button("卸载 Hooks", role: .destructive, action: uninstallHooks)
                                .accessibilityLabel("卸载 Hooks")
                                .accessibilityIdentifier("settings.danger.uninstallHooks")
                            Spacer()
                        }
                        Text("关闭接收来源不会移除 Hooks；只有这里的卸载操作会改写本机 Claude 和 Codex hook 文件。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            accessory
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 36)
    }
}

private struct MessageRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

private struct HealthCheckRow: View {
    let item: HealthCheckItem
    let prominent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 15 : 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: prominent ? 13 : 12, weight: .semibold))
                    StatusPill(status: item.status)
                }
                Text(item.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.status == .needsAction {
                    Text(item.suggestedAction)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }

    private var icon: String {
        switch item.status {
        case .normal: "checkmark.circle"
        case .needsAction: "exclamationmark.triangle.fill"
        case .disabled: "minus.circle"
        }
    }

    private var color: Color {
        switch item.status {
        case .normal: .green
        case .needsAction: .orange
        case .disabled: .secondary
        }
    }
}

private struct StatusPill: View {
    let status: HealthCheckStatus

    var body: some View {
        Text(status.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .normal: .secondary
        case .needsAction: .orange
        case .disabled: .secondary
        }
    }
}

private struct DiagnosticRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

private struct PathRow: View {
    let title: String
    let path: String

    var body: some View {
        DiagnosticRow(title: title, value: path, monospaced: true)
    }
}
