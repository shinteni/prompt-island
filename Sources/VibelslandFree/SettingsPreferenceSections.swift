import AppKit
import VibelslandFreeCore
import SwiftUI

struct IslandPreferencesSection: View {
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

struct ApprovalPreferencesSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    @Binding var approvalTimeoutSeconds: TimeInterval
    @Binding var approvalNotificationsEnabled: Bool
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
                SettingsRow(icon: "bell.badge", title: AppText.pick(configurationStore.config.language, english: "System notifications", japanese: "システム通知", chinese: "系统通知")) {
                    Toggle("", isOn: $approvalNotificationsEnabled)
                        .labelsHidden()
                }
                Text(AppText.pick(
                    configurationStore.config.language,
                    english: "Posts a notification with Allow/Decline actions when an approval arrives, so requests are not missed while you are away. Respects Do Not Disturb. Requires macOS notification permission on first use.",
                    japanese: "承認リクエスト到着時に許可/拒否アクション付きの通知を送り、離席中の見逃しを防ぎます。集中モード中は送信しません。初回は macOS の通知許可が必要です。",
                    chinese: "审批到达时发送带允许/拒绝按钮的系统通知，人不在电脑前也不会错过；勿扰模式下不发送。首次使用需授予 macOS 通知权限。"
                ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                SettingsDivider()
                    .padding(.top, 8)
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

struct StatsSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    @ObservedObject var statsStore: UsageStatsStore

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Statistics", japanese: "統計", chinese: "统计"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Aggregate counters kept only on this Mac — no prompts, commands, or session content. Last 30 days.",
                japanese: "この Mac にのみ保存される集計カウンターです。プロンプトや会話内容は含まれません。直近 30 日分。",
                chinese: "仅保存在本机的聚合计数，不含任何提示词、命令或会话内容；保留最近 30 天。"
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statsRow(
                    label: AppText.pick(configurationStore.config.language, english: "Today", japanese: "今日", chinese: "今日"),
                    stats: statsStore.todayStats()
                )
                SettingsDivider()
                statsRow(
                    label: AppText.pick(configurationStore.config.language, english: "Last 7 days", japanese: "直近 7 日", chinese: "近 7 天"),
                    stats: statsStore.weekStats()
                )
                tokenBars
                HStack {
                    Spacer()
                    Button(AppText.pick(configurationStore.config.language, english: "Clear statistics", japanese: "統計を消去", chinese: "清除统计")) {
                        statsStore.clearAll()
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
        }
    }

    private func statsRow(label: String, stats: DailyStats) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 76, alignment: .leading)
            statMetric(
                AppText.pick(configurationStore.config.language, english: "Sessions", japanese: "セッション", chinese: "会话"),
                "\(stats.sessionsStartedTotal)"
            )
            statMetric(
                AppText.pick(configurationStore.config.language, english: "Done", japanese: "完了", chinese: "完成"),
                "\(stats.sessionsCompleted)"
            )
            statMetric(
                AppText.pick(configurationStore.config.language, english: "Approvals", japanese: "承認", chinese: "审批"),
                approvalSummary(stats)
            )
            statMetric("Token", UsageSnapshot.compactNumber(stats.tokens))
            if stats.estimatedCostUSD > 0 {
                statMetric(
                    AppText.pick(configurationStore.config.language, english: "Est.", japanese: "概算", chinese: "估算"),
                    UsageSnapshot.costText(stats.estimatedCostUSD)
                )
            }
            Spacer()
        }
    }

    private func approvalSummary(_ stats: DailyStats) -> String {
        guard stats.approvalsReceived > 0 else { return "0" }
        return "\(stats.approvalsReceived) (✓\(stats.approvalsAccepted) ✕\(stats.approvalsDeclined))"
    }

    private func statMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var tokenBars: some View {
        let days = statsStore.recentDays()
        let maxTokens = max(1, days.map(\.stats.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(AppText.pick(configurationStore.config.language, english: "Tokens per day", japanese: "日別トークン", chinese: "每日 Token"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.key) { day in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(day.stats.tokens > 0 ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25))
                            .frame(width: 26, height: max(3, CGFloat(day.stats.tokens) / CGFloat(maxTokens) * 44))
                            .help("\(day.key): \(UsageSnapshot.compactNumber(day.stats.tokens))")
                        Text(String(day.key.suffix(2)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .frame(height: 62, alignment: .bottom)
        }
    }
}

struct UpdateSection: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    @Binding var autoCheckUpdates: Bool
    let state: UpdateCheckState
    let checkAndUpdate: () -> Void
    let installUpdate: (RemoteRelease) -> Void

    var body: some View {
        SettingsCard(
            title: AppText.pick(configurationStore.config.language, english: "Updates", japanese: "アップデート", chinese: "更新"),
            subtitle: AppText.pick(
                configurationStore.config.language,
                english: "Contacts GitHub only when you ask. One-click update downloads the release, verifies its SHA-256 against the published checksum, then installs and relaunches.",
                japanese: "GitHub への接続は明示的な操作時のみ。ワンクリック更新はリリースをダウンロードし、公開チェックサムと SHA-256 を照合してからインストール・再起動します。",
                chinese: "只在你主动操作时访问 GitHub。一键更新会下载发布包、对照公开校验和验证 SHA-256，然后安装并自动重启。"
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(AppText.pick(configurationStore.config.language, english: "Current version", japanese: "現在のバージョン", chinese: "当前版本") + " \(UpdateChecker.currentVersion)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle(AppText.pick(configurationStore.config.language, english: "Check at launch", japanese: "起動時に確認", chinese: "启动时自动检查"), isOn: $autoCheckUpdates)
                        .font(.system(size: 12, weight: .medium))
                    Button(checkTitle, action: checkAndUpdate)
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isBusy)
                        .accessibilityIdentifier("settings.updates.check")
                }
                statusRow
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            MessageRow(
                icon: "arrow.triangle.2.circlepath",
                title: AppText.pick(configurationStore.config.language, english: "Checking…", japanese: "確認中…", chinese: "正在检查…"),
                detail: "",
                color: .gray
            )
        case .upToDate(let current):
            MessageRow(
                icon: "checkmark.circle.fill",
                title: AppText.pick(configurationStore.config.language, english: "Up to date", japanese: "最新です", chinese: "已是最新版本"),
                detail: current,
                color: .green
            )
        case .available(let release):
            HStack(spacing: 10) {
                MessageRow(
                    icon: "sparkles",
                    title: AppText.pick(configurationStore.config.language, english: "New version \(release.version)", japanese: "新しいバージョン \(release.version)", chinese: "发现新版本 \(release.version)"),
                    detail: "",
                    color: .blue
                )
                if release.supportsSelfUpdate {
                    Button(AppText.pick(configurationStore.config.language, english: "Update now", japanese: "今すぐ更新", chinese: "立即更新")) {
                        installUpdate(release)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(AppText.pick(configurationStore.config.language, english: "Release page", japanese: "リリースページ", chinese: "发布页")) {
                    NSWorkspace.shared.open(release.pageURL)
                }
            }
        case .updating(let stage, let release):
            MessageRow(
                icon: "arrow.down.circle",
                title: stageText(stage, version: release.version),
                detail: AppText.pick(configurationStore.config.language, english: "Do not quit the app", japanese: "アプリを終了しないでください", chinese: "请勿退出应用"),
                color: .blue
            )
        case .updateFailed(let message, let release):
            HStack(spacing: 10) {
                MessageRow(
                    icon: "exclamationmark.triangle",
                    title: AppText.pick(configurationStore.config.language, english: "Update failed", japanese: "更新に失敗しました", chinese: "更新失败"),
                    detail: message,
                    color: .orange
                )
                Button(AppText.pick(configurationStore.config.language, english: "Release page", japanese: "リリースページ", chinese: "前往发布页")) {
                    NSWorkspace.shared.open(release.pageURL)
                }
            }
        case .failed(let message):
            MessageRow(
                icon: "exclamationmark.triangle",
                title: AppText.pick(configurationStore.config.language, english: "Check failed", japanese: "確認に失敗しました", chinese: "检查失败"),
                detail: message,
                color: .orange
            )
        }
    }

    private func stageText(_ stage: UpdateStage, version: String) -> String {
        switch stage {
        case .downloading:
            AppText.pick(configurationStore.config.language, english: "Downloading \(version)…", japanese: "\(version) をダウンロード中…", chinese: "正在下载 \(version)…")
        case .verifying:
            AppText.pick(configurationStore.config.language, english: "Verifying SHA-256…", japanese: "SHA-256 を検証中…", chinese: "正在校验 SHA-256…")
        case .installing:
            AppText.pick(configurationStore.config.language, english: "Installing…", japanese: "インストール中…", chinese: "正在安装…")
        case .restarting:
            AppText.pick(configurationStore.config.language, english: "Restarting…", japanese: "再起動中…", chinese: "正在重启…")
        }
    }

    private var checkTitle: String {
        AppText.pick(configurationStore.config.language, english: "Check & update", japanese: "確認して更新", chinese: "检查并更新")
    }
}
