import AppKit
import VibelslandFreeCore
import SwiftUI

struct UsageHeaderView: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let usage: UsageSnapshot

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
            if usage.primaryUsedPercent == nil && usage.secondaryUsedPercent == nil {
                Text(AppText.pick(configurationStore.config.language, english: "Turn", japanese: "今回", chinese: "本轮"))
                    .foregroundStyle(GlassText.secondary)
                Text(UsageSnapshot.compactNumber(usage.lastTokens))
                    .foregroundStyle(Color(red: 0.22, green: 0.94, blue: 0.42))
                Text("|")
                    .foregroundStyle(GlassText.faint)
                Text(AppText.pick(configurationStore.config.language, english: "Total", japanese: "合計", chinese: "总计"))
                    .foregroundStyle(GlassText.secondary)
                Text(usage.totalText)
                    .foregroundStyle(GlassText.primary)
            } else {
                RateLimitHeaderPart(
                    label: UsageSnapshot.windowLabel(minutes: usage.primaryWindowMinutes, fallback: "5h"),
                    percent: usage.primaryUsedPercent,
                    resetsAt: usage.primaryResetsAt
                )
                Text("|")
                    .foregroundStyle(GlassText.faint)
                RateLimitHeaderPart(
                    label: UsageSnapshot.windowLabel(minutes: usage.secondaryWindowMinutes, fallback: "7d"),
                    percent: usage.secondaryUsedPercent,
                    resetsAt: usage.secondaryResetsAt
                )
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
    }
}

struct RateLimitHeaderPart: View {
    let label: String
    let percent: Double?
    let resetsAt: Date?

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(GlassText.primary)
            if let percent {
                Text(UsageSnapshot.percent(percent))
                    .foregroundStyle(percent >= 80 ? Color.orange : Color(red: 0.22, green: 0.94, blue: 0.42))
            } else {
                Text("--")
                    .foregroundStyle(GlassText.tertiary)
            }
            if let remaining = UsageSnapshot.remainingText(until: resetsAt) {
                Text(remaining)
                    .foregroundStyle(GlassText.tertiary)
            }
        }
    }
}

struct HealthSummaryStrip: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let items: [HealthCheckItem]

    var body: some View {
        Button {
            NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if needsActionCount > 0 {
                    HealthCountPill(text: needsActionPillText, color: .orange)
                } else {
                    HealthCountPill(text: HealthCheckStatus.normal.title(language: configurationStore.config.language), color: .green)
                }
            }
            .foregroundStyle(GlassText.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                ClearGlassRoundedBackground(
                    cornerRadius: 10,
                    highlighted: needsActionCount > 0,
                    materialOpacity: 0.28
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(AppText.pick(configurationStore.config.language, english: "Open health checks", japanese: "ヘルスチェックを開く", chinese: "打开健康检查"))
    }

    private var normalCount: Int {
        items.filter { $0.status == .normal }.count
    }

    private var needsActionCount: Int {
        items.filter { $0.status == .needsAction }.count
    }

    private var disabledCount: Int {
        items.filter { $0.status == .disabled }.count
    }

    private var summaryText: String {
        guard !items.isEmpty else {
            return AppText.pick(configurationStore.config.language, english: "Health checks have not run yet", japanese: "ヘルスチェックはまだ実行されていません", chinese: "健康检查尚未运行")
        }
        if needsActionCount > 0 {
            return AppText.pick(
                configurationStore.config.language,
                english: "Health checks: \(needsActionCount) need action",
                japanese: "ヘルスチェック：\(needsActionCount) 件の対応が必要",
                chinese: "健康检查：\(needsActionCount) 项需要处理"
            )
        }
        if disabledCount > 0 {
            return AppText.pick(
                configurationStore.config.language,
                english: "Health checks: \(normalCount) OK, \(disabledCount) disabled",
                japanese: "ヘルスチェック：\(normalCount) 件正常、\(disabledCount) 件無効",
                chinese: "健康检查：\(normalCount) 项正常，\(disabledCount) 项未启用"
            )
        }
        return AppText.pick(configurationStore.config.language, english: "Health checks: all OK", japanese: "ヘルスチェック：すべて正常", chinese: "健康检查：全部正常")
    }

    private var needsActionPillText: String {
        AppText.pick(configurationStore.config.language, english: "\(needsActionCount) action", japanese: "\(needsActionCount) 要対応", chinese: "\(needsActionCount) 需处理")
    }

    private var icon: String {
        needsActionCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }
}

struct HealthCountPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(
                ClearGlassCapsuleBackground(
                    highlighted: true,
                    tint: color.opacity(0.10),
                    materialOpacity: 0.36
                )
            )
            .clipShape(Capsule())
    }
}

struct DashboardSessionCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    let session: AgentSession
    let isSelected: Bool
    var isCondensed = false

    var body: some View {
        Button {
            openSession()
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 9) {
                    sessionIcon
                    sessionText
                    Spacer(minLength: 8)
                    sessionMeta
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: session.source == .unknown ? "checkmark.circle" : "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GlassText.control)
                    .frame(width: 23, height: 23)
                    .background(
                        ClearGlassRoundedBackground(cornerRadius: 8, highlighted: false, materialOpacity: 0.26)
                    )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 11)
        .frame(height: isCondensed ? 48 : 62)
        .background(
            ZStack(alignment: .bottomLeading) {
                DashboardRowBackground(highlighted: isSelected || session.approval != nil, tint: cardTint)
                if !store.isIslandTransitioning {
                    StatusGlowBorder(
                        status: session.status,
                        accentColor: session.source.color,
                        cornerRadius: 14,
                        lineWidth: isSelected ? 1.05 : 0.85,
                        glowRadius: 4,
                        intensity: rgbIntensity
                    )
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .help(session.source == .unknown ? AppText.pick(configurationStore.config.language, english: "Select session", japanese: "セッションを選択", chinese: "选中会话") : AppText.pick(configurationStore.config.language, english: "Open \(session.source.displayName)", japanese: "\(session.source.displayName) を開く", chinese: "打开 \(session.source.displayName)"))
        .accessibilityLabel("\(display.title)，\(display.primaryLine)，\(display.secondaryLine ?? "")")
    }

    private func openSession() {
        store.openSession(session)
    }

    private var sessionIcon: some View {
        AgentSourceIconView(source: session.source, size: 30, status: session.status, showsStatus: false)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black.opacity(0.62), lineWidth: 1))
            }
            .frame(width: 30, height: 30)
    }

    private var sessionText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(display.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GlassText.primary)
                .lineLimit(1)
            Text(display.primaryLine)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(GlassText.secondary)
                .lineLimit(1)
            if !isCondensed, let secondaryLine = display.secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(GlassText.tertiary)
                    .lineLimit(1)
            }
            DashboardSignalLine(session: session)
        }
    }

    private var sessionMeta: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(display.statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusTextColor)
                .lineLimit(1)
            Text(display.confidence.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GlassText.faint)
                .lineLimit(1)
            Text(session.ageText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GlassText.faint)
        }
    }

    private var display: SessionDisplaySnapshot {
        SessionDisplaySnapshot(session: session, language: configurationStore.config.language)
    }

    private var cardTint: Color {
        switch session.status {
        case .waitingApproval, .waitingQuestion:
            return Color.orange.opacity(0.08)
        case .runningTool:
            return session.source.color.opacity(0.07)
        default:
            return .clear
        }
    }

    private var rgbIntensity: Double {
        if session.status == .thinking || session.status == .runningTool {
            return 0.68
        }
        if isSelected {
            return 0.28
        }
        return 0.16
    }

    private var statusDotColor: Color {
        switch session.status {
        case .thinking, .runningTool:
            return session.source.color
        case .waitingApproval, .waitingQuestion:
            return .orange
        case .failed:
            return Color(red: 1.0, green: 0.34, blue: 0.22)
        case .done:
            return Color(red: 0.34, green: 0.74, blue: 0.42)
        case .idle:
            return GlassText.faint
        }
    }

    private var statusTextColor: Color {
        switch session.status {
        case .thinking, .runningTool:
            return session.source.color
        case .waitingApproval, .waitingQuestion:
            return .orange
        case .failed:
            return Color(red: 1.0, green: 0.44, blue: 0.32)
        default:
            return GlassText.secondary
        }
    }
}

struct DashboardSignalLine: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let session: AgentSession

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(display.signals.prefix(2).enumerated()), id: \.element.id) { index, item in
                signal(
                    systemImage: item.symbol,
                    text: compact(item.text),
                    color: index == 0 ? session.source.color : GlassText.secondary
                )
            }
        }
        .frame(height: 16)
    }

    private var display: SessionDisplaySnapshot {
        SessionDisplaySnapshot(session: session, language: configurationStore.config.language)
    }

    private func signal(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .frame(height: 15)
        .background(ClearGlassCapsuleBackground(tint: color.opacity(0.065), materialOpacity: 0.30))
        .clipShape(Capsule())
    }

    private func compact(_ text: String) -> String {
        let sanitized = DisplayTextSanitizer.sanitize(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? AppText.pick(configurationStore.config.language, english: "Activity", japanese: "アクティビティ", chinese: "活动") : String(sanitized.prefix(28))
    }
}

struct DashboardEmptyCard: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GlassText.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppText.pick(configurationStore.config.language, english: "Waiting for events", japanese: "イベント待ち", chinese: "等待事件"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassText.primary)
                Text(AppText.pick(configurationStore.config.language, english: "Claude Code or Codex activity appears here.", japanese: "Claude Code または Codex のアクティビティがここに表示されます。", chinese: "Claude Code 或 Codex 活动会显示在这里。"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GlassText.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(DashboardCardBackground(highlighted: true))
    }
}

struct DashboardChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(ClearGlassCapsuleBackground(highlighted: true, tint: color.opacity(0.10), materialOpacity: 0.36))
            .clipShape(Capsule())
    }
}

struct ConfidenceChip: View {
    @EnvironmentObject private var configurationStore: AppConfigurationStore

    let confidence: DisplayConfidence

    var body: some View {
        Text(confidence.title(language: configurationStore.config.language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(ClearGlassCapsuleBackground(tint: color.opacity(0.085), materialOpacity: 0.34))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch confidence {
        case .realtime:
            return .green
        case .event:
            return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .transcript:
            return GlassText.secondary
        case .inferred:
            return .orange
        }
    }
}
