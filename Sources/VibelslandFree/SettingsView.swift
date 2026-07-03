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
                        repairMessage: store.lastRepairMessage,
                        items: store.exceptionOnlyHealthChecks,
                        refresh: store.refreshDiagnostics,
                        repairConnections: store.repairConnections,
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
                    language: binding(\.language),
                    launchAtLogin: launchAtLoginBinding,
                    soundsEnabled: binding(\.enableSounds),
                    soundTheme: binding(\.soundTheme),
                    doNotDisturb: binding(\.doNotDisturb),
                    maxVisibleSessions: binding(\.maxVisibleSessions),
                    globalHotKeysEnabled: binding(\.enableGlobalHotKeys),
                    playPreview: store.playSoundPreview,
                    playAllPreviews: store.playAllSoundPreviews
                )

                ApprovalPreferencesSection(
                    approvalTimeoutSeconds: binding(\.approvalTimeoutSeconds),
                    approvalWaitText: approvalWaitText
                )

                MaintenanceSection(
                    allHealthChecks: store.healthChecks,
                    repairMessage: store.lastRepairMessage,
                    refresh: store.refreshDiagnostics,
                    repairConnections: store.repairConnections,
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
                        store.lastError = AppText.pick(
                            configurationStore.config.language,
                            english: "Launch at login could not switch to the requested state. Make sure you are running the packaged .app.",
                            japanese: "ログイン時起動を要求された状態に切り替えられませんでした。パッケージ化された .app を実行しているか確認してください。",
                            chinese: "登录启动未能切换到请求状态，请确认当前运行的是已打包的 .app。"
                        )
                    } else {
                        store.lastError = nil
                    }
                case .failure(let error):
                    configurationStore.config.launchAtLogin = previous
                    store.lastError = AppText.pick(
                        configurationStore.config.language,
                        english: "Launch at login failed: \(error.localizedDescription)",
                        japanese: "ログイン時起動の設定に失敗しました：\(error.localizedDescription)",
                        chinese: "登录启动设置失败：\(error.localizedDescription)"
                    )
                }
            }
        )
    }

    private var approvalWaitText: String {
        let seconds = Int(configurationStore.config.approvalTimeoutSeconds)
        return AppText.approvalWaitText(seconds: seconds, language: configurationStore.config.language)
    }
}

private struct SettingsHeader: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(">_ - island")
                .font(.system(size: 28, weight: .semibold))
            Text(AppText.pick(
                configurationStore.config.language,
                english: "Manage the floating island, event sources, and local approval bridge. Health details stay hidden when everything is normal.",
                japanese: "フローティングアイランド、通知元、ローカル承認接続を管理します。正常時はヘルスチェックの詳細を表示しません。",
                chinese: "管理浮岛显示、提醒来源和本机审批接入。正常状态下不显示健康检查细节。"
            ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

private struct IssueSummarySection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let error: String?
    let repairMessage: String?
    let items: [HealthCheckItem]
    let refresh: () -> Void
    let repairConnections: () -> Void
    let openLogs: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppText.pick(
                            configurationStore.config.language,
                            english: "Needs action",
                            japanese: "対応が必要",
                            chinese: "需要处理"
                        ))
                            .font(.system(size: 16, weight: .semibold))
                        Text(AppText.pick(
                            configurationStore.config.language,
                            english: "These issues can affect event intake or approval responses.",
                            japanese: "これらの問題はイベント受信や承認返送に影響する可能性があります。",
                            chinese: "这些问题可能会影响事件接收或审批回传。"
                        ))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(refreshTitle, action: refresh)
                        .accessibilityLabel(refreshTitle)
                        .accessibilityIdentifier("settings.issue.refresh")
                    Button(repairTitle, action: repairConnections)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(repairTitle)
                        .accessibilityIdentifier("settings.issue.repairHooks")
                }

                if let error {
                    MessageRow(
                        icon: "xmark.octagon.fill",
                        title: AppText.pick(
                            configurationStore.config.language,
                            english: "Latest error",
                            japanese: "最新のエラー",
                            chinese: "最近错误"
                        ),
                        detail: error,
                        color: .red
                    )
                }

                if let repairMessage {
                    MessageRow(
                        icon: "checkmark.circle.fill",
                        title: AppText.pick(
                            configurationStore.config.language,
                            english: "Repair ran",
                            japanese: "修復を実行しました",
                            chinese: "已执行修复"
                        ),
                        detail: repairMessage,
                        color: .green
                    )
                }

                ForEach(items) { item in
                    HealthCheckRow(item: item, prominent: true)
                }

                HStack {
                    Button(openLogsTitle, action: openLogs)
                        .accessibilityLabel(openLogsTitle)
                        .accessibilityIdentifier("settings.issue.openLogs")
                    Spacer()
                }
            }
        }
    }

    private var refreshTitle: String {
        AppText.pick(configurationStore.config.language, english: "Check again", japanese: "再チェック", chinese: "重新检测")
    }

    private var repairTitle: String {
        AppText.pick(configurationStore.config.language, english: "Repair connection", japanese: "接続を修復", chinese: "修复接入")
    }

    private var openLogsTitle: String {
        AppText.pick(configurationStore.config.language, english: "Open logs", japanese: "ログを開く", chinese: "打开日志")
    }
}

private struct ReceiveSourcesSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    @Binding var claudeEnabled: Bool
    @Binding var codexCLIEnabled: Bool
    @Binding var codexDesktopEnabled: Bool
    let claudeHealth: HealthCheckItem?
    let codexCLIHealth: HealthCheckItem?
    let codexDesktopHealth: HealthCheckItem?

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Sources", japanese: "受信元", chinese: "接收来源"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Toggles only control intake and display. They do not uninstall existing hooks.",
                japanese: "切り替えは受信と表示だけを制御します。既存の Hooks は削除しません。",
                chinese: "开关只控制接收和显示，不会卸载已经写入的 Hooks。"
            )
        ) {
            VStack(spacing: 0) {
                SourceToggleRow(
                    title: "Claude Code",
                    subtitle: AppText.pick(
                        configurationStore.config.language,
                        english: "Receive approvals and events through hooks",
                        japanese: "Hooks 経由で承認とイベントを受信",
                        chinese: "通过 Hooks 接收审批和事件"
                    ),
                    health: claudeHealth,
                    systemImage: "sparkles",
                    isOn: $claudeEnabled
                )
                SettingsDivider()
                SourceToggleRow(
                    title: "Codex CLI",
                    subtitle: AppText.pick(
                        configurationStore.config.language,
                        english: "Receive command-line events through hooks",
                        japanese: "Hooks 経由でコマンドラインイベントを受信",
                        chinese: "通过 Hooks 接收命令行事件"
                    ),
                    health: codexCLIHealth,
                    systemImage: "terminal",
                    isOn: $codexCLIEnabled
                )
                SettingsDivider()
                SourceToggleRow(
                    title: "Codex Desktop",
                    subtitle: AppText.pick(
                        configurationStore.config.language,
                        english: "Read local state and receive live approvals",
                        japanese: "ローカル状態を読み取り、リアルタイム承認を受信",
                        chinese: "读取本机状态，并接收实时审批"
                    ),
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
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    @Binding var position: IslandPosition
    @Binding var language: AppLanguage
    @Binding var launchAtLogin: Bool
    @Binding var soundsEnabled: Bool
    @Binding var soundTheme: SoundTheme
    @Binding var doNotDisturb: Bool
    @Binding var maxVisibleSessions: Int
    @Binding var globalHotKeysEnabled: Bool
    let playPreview: (RetroSoundKind) -> Void
    let playAllPreviews: () -> Void

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Island and alerts", japanese: "アイランドと通知", chinese: "浮岛与提醒"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Control island placement, sound, language, and expanded content.",
                japanese: "アイランドの位置、サウンド、言語、展開時の内容を調整します。",
                chinese: "控制浮岛出现位置、声音、语言和展开内容数量。"
            )
        ) {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "globe",
                    title: AppText.pick(configurationStore.config.language, english: "Language", japanese: "言語", chinese: "语言")
                ) {
                    Picker("", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: AppText.pick(configurationStore.config.language, english: "Island position", japanese: "アイランド位置", chinese: "浮岛位置")
                ) {
                    Picker("", selection: $position) {
                        ForEach(IslandPosition.allCases) { position in
                            Text(position.title(language: configurationStore.config.language)).tag(position)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(icon: "power", title: AppText.pick(configurationStore.config.language, english: "Launch at login", japanese: "ログイン時に起動", chinese: "登录时启动")) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(icon: "speaker.wave.2", title: AppText.pick(configurationStore.config.language, english: "Sound", japanese: "サウンド", chinese: "声音")) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $soundsEnabled)
                            .labelsHidden()
                        Picker("", selection: $soundTheme) {
                            ForEach(SoundTheme.allCases) { theme in
                                Text(theme.title(language: configurationStore.config.language)).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 112)
                        .disabled(!soundsEnabled)
                        Menu(AppText.pick(configurationStore.config.language, english: "Preview", japanese: "試聴", chinese: "试听")) {
                            Button(AppText.pick(configurationStore.config.language, english: "Task started", japanese: "タスク開始", chinese: "任务开始")) {
                                playPreview(.taskStarted)
                            }
                            Button(AppText.pick(configurationStore.config.language, english: "Tool call", japanese: "ツール呼び出し", chinese: "工具调用")) {
                                playPreview(.toolTick)
                            }
                            Button(AppText.pick(configurationStore.config.language, english: "Task completed", japanese: "タスク完了", chinese: "任务完成")) {
                                playPreview(.taskCompleted)
                            }
                            Button(AppText.pick(configurationStore.config.language, english: "Task failed", japanese: "タスク失敗", chinese: "任务失败")) {
                                playPreview(.taskFailed)
                            }
                            Button(AppText.pick(configurationStore.config.language, english: "Approval alert", japanese: "承認通知", chinese: "审批提醒")) {
                                playPreview(.approval)
                            }
                            Divider()
                            Button(AppText.pick(configurationStore.config.language, english: "Preview all", japanese: "すべて試聴", chinese: "试听全部"), action: playAllPreviews)
                        }
                        .disabled(!soundsEnabled)
                    }
                }
                SettingsDivider()
                SettingsRow(icon: "moon", title: AppText.pick(configurationStore.config.language, english: "Do not disturb", japanese: "集中モード", chinese: "勿扰")) {
                    Toggle("", isOn: $doNotDisturb)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(icon: "list.bullet.rectangle", title: AppText.pick(configurationStore.config.language, english: "Expanded limit", japanese: "展開時の表示数", chinese: "展开时最多显示")) {
                    Stepper(
                        value: $maxVisibleSessions,
                        in: DashboardSessionPolicy.minimumConfiguredVisibleSessions...DashboardSessionPolicy.maximumVisibleSessions
                    ) {
                        Text(AppText.sessions(maxVisibleSessions, language: configurationStore.config.language))
                            .monospacedDigit()
                    }
                    .frame(width: 150)
                }
                SettingsDivider()
                SettingsRow(icon: "keyboard", title: AppText.pick(configurationStore.config.language, english: "Global hotkeys", japanese: "グローバルショートカット", chinese: "全局快捷键")) {
                    Toggle("", isOn: $globalHotKeysEnabled)
                        .labelsHidden()
                }
                Text(globalHotKeysHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
            }
        }
    }

    private var globalHotKeysHint: String {
        let toggle = GlobalHotKeyAction.toggleIsland.displayShortcut
        let jump = GlobalHotKeyAction.jumpToApproval.displayShortcut
        return AppText.pick(
            configurationStore.config.language,
            english: "\(toggle) expand/collapse island · \(jump) jump to pending approval",
            japanese: "\(toggle) アイランドを展開/折りたたみ · \(jump) 承認待ちへ移動",
            chinese: "\(toggle) 展开/收起浮岛 · \(jump) 跳转待审批"
        )
    }
}

private struct ApprovalPreferencesSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    @Binding var approvalTimeoutSeconds: TimeInterval
    let approvalWaitText: String

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Approvals", japanese: "承認", chinese: "审批"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Only affects how long real approval responses wait.",
                japanese: "実際の承認返送の待機時間だけに影響します。",
                chinese: "只影响真实审批回传的等待时间。"
            )
        ) {
            VStack(spacing: 0) {
                SettingsRow(icon: "checkmark.shield", title: AppText.pick(configurationStore.config.language, english: "Wait time", japanese: "待機時間", chinese: "等待时间")) {
                    Stepper(value: $approvalTimeoutSeconds, in: 60...7200, step: 300) {
                        Text(approvalWaitText)
                            .monospacedDigit()
                    }
                    .frame(width: 170)
                }
                SettingsDivider()
                Text(AppText.pick(
                    configurationStore.config.language,
                    english: "If the app is unavailable, requests fall back immediately. After the app takes over a request, timeout never auto-allows or auto-denies it.",
                    japanese: "アプリが利用できない場合はすぐにフォールバックします。アプリがリクエストを引き受けた後、タイムアウトで自動許可または自動拒否することはありません。",
                    chinese: "应用不可用时会立即回退；应用已接管请求后，超时不会自动允许或拒绝。"
                ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }
}

private struct MaintenanceSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let allHealthChecks: [HealthCheckItem]
    let repairMessage: String?
    let refresh: () -> Void
    let repairConnections: () -> Void
    let openLogs: () -> Void

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Maintenance", japanese: "メンテナンス", chinese: "维护"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "For normal use, check again or repair the connection here.",
                japanese: "通常はここで再チェックまたは接続修復を行います。",
                chinese: "日常只需要在这里重新检测或修复接入。"
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(refreshTitle, action: refresh)
                        .accessibilityLabel(refreshTitle)
                        .accessibilityIdentifier("settings.maintenance.refresh")
                    Button(repairTitle, action: repairConnections)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(repairTitle)
                        .accessibilityIdentifier("settings.maintenance.repairHooks")
                    Button(openLogsTitle, action: openLogs)
                        .accessibilityLabel(openLogsTitle)
                        .accessibilityIdentifier("settings.maintenance.openLogs")
                    Spacer()
                }

                if issueItems.isEmpty {
                    if let repairMessage {
                        MessageRow(
                            icon: "checkmark.circle.fill",
                            title: AppText.pick(
                                configurationStore.config.language,
                                english: "Repair ran",
                                japanese: "修復を実行しました",
                                chinese: "已执行修复"
                            ),
                            detail: repairMessage,
                            color: .green
                        )
                    } else {
                        Text(allHealthChecks.isEmpty ? notRunText : noIssuesText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Show checks that need action", japanese: "対応が必要なチェックを表示", chinese: "查看需要处理的检查")) {
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

    private var refreshTitle: String {
        AppText.pick(configurationStore.config.language, english: "Check again", japanese: "再チェック", chinese: "重新检测")
    }

    private var repairTitle: String {
        AppText.pick(configurationStore.config.language, english: "Repair connection", japanese: "接続を修復", chinese: "修复接入")
    }

    private var openLogsTitle: String {
        AppText.pick(configurationStore.config.language, english: "Open logs", japanese: "ログを開く", chinese: "打开日志")
    }

    private var notRunText: String {
        AppText.pick(configurationStore.config.language, english: "Checks have not run yet.", japanese: "チェックはまだ実行されていません。", chinese: "尚未运行检测。")
    }

    private var noIssuesText: String {
        AppText.pick(configurationStore.config.language, english: "No issues need action.", japanese: "対応が必要な問題はありません。", chinese: "未发现需要处理的问题。")
    }
}

private struct DiagnosticsSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let codexAppServerReachable: Bool
    let codexAppServerThreadListAvailable: Bool
    let codexAppServerThreadCount: Int
    let codexIPCSocketPath: String?
    let codexDesktopApprovalConnected: Bool
    let codexDesktopLastConnectedAt: Date?
    let codexDesktopLastFailureMessage: String?
    let installReport: InstallReport?

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Advanced diagnostics", japanese: "高度な診断", chinese: "高级诊断"),
            subtitle: AppText.pick(configurationStore.config.language, english: "Expand only when troubleshooting.", japanese: "問題調査時だけ展開します。", chinese: "排查问题时再展开。")
        ) {
            DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Show technical diagnostics", japanese: "技術診断を表示", chinese: "显示技术诊断")) {
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Technical connection status", japanese: "技術的な接続状態", chinese: "技术连接状态")) {
                        VStack(spacing: 10) {
                            DiagnosticRow(title: "App Server", value: codexAppServerReachable ? availableText : disconnectedText)
                            DiagnosticRow(
                                title: "thread/list",
                                value: codexAppServerThreadListAvailable ? threadListText : unavailableText
                            )
                            DiagnosticRow(title: "Desktop IPC", value: codexIPCSocketPath ?? notFoundText, monospaced: true)
                            DiagnosticRow(title: liveApprovalTitle, value: codexDesktopApprovalConnected ? connectedText : disconnectedText)
                            DiagnosticRow(title: lastConnectedTitle, value: lastConnectedText)
                            DiagnosticRow(title: latestFailureTitle, value: codexDesktopLastFailureMessage ?? noneText)
                        }
                        .padding(.top, 10)
                    }

                    DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Local paths", japanese: "ローカルパス", chinese: "本机路径")) {
                        VStack(spacing: 10) {
                            PathRow(title: "Bridge", path: AppPaths.bridgeURL.path)
                            PathRow(title: "Socket", path: AppPaths.socketURL.path)
                            PathRow(title: AppText.pick(configurationStore.config.language, english: "Config", japanese: "設定", chinese: "配置"), path: AppPaths.configURL.path)
                            PathRow(title: AppText.pick(configurationStore.config.language, english: "Logs", japanese: "ログ", chinese: "日志"), path: AppPaths.logURL.path)
                        }
                        .padding(.top, 10)
                    }

                    if let installReport {
                        DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Last install", japanese: "最近のインストール", chinese: "最近安装")) {
                            VStack(spacing: 10) {
                                DiagnosticRow(title: "Bridge", value: installReport.bridgeInstalled ? installedText : notInstalledText)
                                DiagnosticRow(title: "Claude", value: installReport.claudeHooksInstalled ? mergedText : disabledText)
                                DiagnosticRow(title: "Codex", value: installReport.codexHooksInstalled ? mergedText : disabledText)
                                if installReport.codexHooksInstalled {
                                    DiagnosticRow(
                                        title: AppText.pick(configurationStore.config.language, english: "Codex hooks flag", japanese: "Codex hooks フラグ", chinese: "Codex hooks 开关"),
                                        value: installReport.codexFeatureFlagEnabled
                                            ? (installReport.codexFeatureFlagChanged ? enabledText : enabledUnchangedText)
                                            : disabledText
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
        guard let codexDesktopLastConnectedAt else {
            return AppText.pick(configurationStore.config.language, english: "Never connected", japanese: "未接続", chinese: "未连接过")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.locale = AppText.locale(for: configurationStore.config.language)
        return formatter.string(from: codexDesktopLastConnectedAt)
    }

    private var availableText: String { AppText.pick(configurationStore.config.language, english: "Available", japanese: "利用可能", chinese: "可用") }
    private var unavailableText: String { AppText.pick(configurationStore.config.language, english: "Unavailable", japanese: "利用不可", chinese: "不可用") }
    private var connectedText: String { AppText.pick(configurationStore.config.language, english: "Connected", japanese: "接続済み", chinese: "已连接") }
    private var disconnectedText: String { AppText.pick(configurationStore.config.language, english: "Disconnected", japanese: "未接続", chinese: "未连接") }
    private var notFoundText: String { AppText.pick(configurationStore.config.language, english: "Not found", japanese: "未検出", chinese: "未发现") }
    private var noneText: String { AppText.pick(configurationStore.config.language, english: "None", japanese: "なし", chinese: "无") }
    private var liveApprovalTitle: String { AppText.pick(configurationStore.config.language, english: "Live approval", japanese: "リアルタイム承認", chinese: "实时审批") }
    private var lastConnectedTitle: String { AppText.pick(configurationStore.config.language, english: "Last connected", japanese: "最終接続", chinese: "最近连接") }
    private var latestFailureTitle: String { AppText.pick(configurationStore.config.language, english: "Latest failure", japanese: "最新の失敗", chinese: "最近失败") }
    private var installedText: String { AppText.pick(configurationStore.config.language, english: "Installed", japanese: "インストール済み", chinese: "已安装") }
    private var notInstalledText: String { AppText.pick(configurationStore.config.language, english: "Not installed", japanese: "未インストール", chinese: "未安装") }
    private var mergedText: String { AppText.pick(configurationStore.config.language, english: "Merged", japanese: "マージ済み", chinese: "已合并") }
    private var disabledText: String { AppText.pick(configurationStore.config.language, english: "Disabled", japanese: "無効", chinese: "未启用") }
    private var enabledText: String { AppText.pick(configurationStore.config.language, english: "Enabled", japanese: "有効", chinese: "已开启") }
    private var enabledUnchangedText: String { AppText.pick(configurationStore.config.language, english: "Enabled, unchanged", japanese: "有効、変更不要", chinese: "已开启，无需修改") }
    private var threadListText: String {
        AppText.pick(
            configurationStore.config.language,
            english: "Available, \(codexAppServerThreadCount) rows",
            japanese: "利用可能、\(codexAppServerThreadCount) 件",
            chinese: "可用，\(codexAppServerThreadCount) 条"
        )
    }
}

private struct AdvancedActionsSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let uninstallHooks: () -> Void
    let restart: () -> Void
    let quit: () -> Void

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "App", japanese: "アプリ", chinese: "应用"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Restart and quit are always available. Actions that rewrite local integrations are grouped separately.",
                japanese: "再起動と終了は直接使用できます。ローカル接続を書き換える操作は別にまとめています。",
                chinese: "重启和退出直接可用；会改写本机接入的操作单独收起。"
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button(restartTitle, action: restart)
                        .accessibilityLabel(restartTitle)
                        .accessibilityIdentifier("settings.app.restart")
                    Button(quitTitle, action: quit)
                        .accessibilityLabel(quitTitle)
                        .accessibilityIdentifier("settings.app.quit")
                    Spacer()
                }

                SettingsDivider()

                DisclosureGroup(AppText.pick(configurationStore.config.language, english: "Danger zone", japanese: "危険な操作", chinese: "危险操作")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button(uninstallTitle, role: .destructive, action: uninstallHooks)
                                .accessibilityLabel(uninstallTitle)
                                .accessibilityIdentifier("settings.danger.uninstallHooks")
                            Spacer()
                        }
                        Text(AppText.pick(
                            configurationStore.config.language,
                            english: "Turning off sources does not remove hooks. Only uninstall here rewrites local Claude and Codex hook files.",
                            japanese: "受信元をオフにしても Hooks は削除されません。ここでのアンインストールだけがローカルの Claude と Codex hook ファイルを書き換えます。",
                            chinese: "关闭接收来源不会移除 Hooks；只有这里的卸载操作会改写本机 Claude 和 Codex hook 文件。"
                        ))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private var restartTitle: String {
        AppText.pick(configurationStore.config.language, english: "Restart app", japanese: "アプリを再起動", chinese: "重启应用")
    }

    private var quitTitle: String {
        AppText.pick(configurationStore.config.language, english: "Quit app", japanese: "アプリを終了", chinese: "退出应用")
    }

    private var uninstallTitle: String {
        AppText.pick(configurationStore.config.language, english: "Uninstall hooks", japanese: "Hooks をアンインストール", chinese: "卸载 Hooks")
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
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let status: HealthCheckStatus

    var body: some View {
        Text(status.title(language: configurationStore.config.language))
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
