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
                    approvalNotificationsEnabled: binding(\.enableApprovalNotifications),
                    approvalWaitText: approvalWaitText
                )

                MaintenanceSection(
                    allHealthChecks: store.healthChecks,
                    repairMessage: store.lastRepairMessage,
                    refresh: store.refreshDiagnostics,
                    repairConnections: store.repairConnections,
                    openLogs: store.openLogs
                )

                UpdateSection(
                    autoCheckUpdates: binding(\.autoCheckUpdates),
                    state: store.updateCheckState,
                    check: store.checkForUpdates
                )

                StatsSection(statsStore: store.statsStore)

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

