import AppKit
import VibelslandFreeCore
import SwiftUI

struct ApprovalSummaryCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    let session: AgentSession
    let approval: ApprovalRequest
    @Binding var showsDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.selectedSessionID = session.id
                showsDetail = true
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.10))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GlassText.primary)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(AppText.pick(
                                configurationStore.config.language,
                                english: "\(approval.source.shortName) requests approval",
                                japanese: "\(approval.source.shortName) が承認を要求",
                                chinese: "\(approval.source.shortName) 请求审批"
                            ))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GlassText.primary)
                                .lineLimit(1)
                            Text(createdText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(GlassText.tertiary)
                                .lineLimit(1)
                        }
                        Text(approval.detail.isEmpty ? approval.tool : approval.detail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GlassText.primary)
                            .lineLimit(1)
                        Text(workspaceText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(GlassText.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GlassText.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .islandHoverHighlight(scale: 1.0)
            .help(AppText.pick(configurationStore.config.language, english: "View approval details", japanese: "承認詳細を表示", chinese: "查看审批详情"))

            HStack(spacing: 4) {
                if approval.supports(.accept) {
                    approvalButton(ApprovalDecision.accept.title(language: configurationStore.config.language), .accept, prominent: true)
                }
                if approval.supports(.acceptForSession) {
                    approvalButton(AppText.pick(configurationStore.config.language, english: "Allow session", japanese: "セッションで許可", chinese: "本轮允许"), .acceptForSession)
                }
                if approval.supports(.decline) {
                    approvalButton(ApprovalDecision.decline.title(language: configurationStore.config.language), .decline)
                }
                Spacer(minLength: 4)
                Button(AppText.pick(configurationStore.config.language, english: "Details", japanese: "詳細", chinese: "详情")) {
                    showsDetail = true
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(PressableButtonStyle())
                .islandHoverHighlight(scale: 1.0)
                .foregroundStyle(GlassText.secondary)
                .disabled(approval.isResolving || approval.isExpired)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 88)
        .background(
            ZStack {
                DashboardCardBackground(highlighted: true, tint: Color.yellow.opacity(0.08))
                StatusGlowBorder(
                    status: .waitingApproval,
                    accentColor: .orange,
                    cornerRadius: 18,
                    lineWidth: 1.1,
                    glowRadius: 6,
                    intensity: 0.86
                )
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func approvalButton(_ title: String, _ decision: ApprovalDecision, prominent: Bool = false) -> some View {
        Button {
            store.resolveApproval(approval, decision: decision)
        } label: {
            // 视觉层放在 label 内，按压缩放才会作用于整个胶囊而不是只有文字。
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    ClearGlassCapsuleBackground(
                        highlighted: prominent,
                        tint: prominent ? Color.white.opacity(0.16) : Color.white.opacity(0.030),
                        materialOpacity: prominent ? 0.62 : 0.42
                    )
                )
                .foregroundStyle(prominent ? Color(red: 0.12, green: 0.42, blue: 0.84) : GlassText.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .islandHoverHighlight()
        .disabled(approval.isResolving || approval.isExpired)
    }

    private var workspaceText: String {
        guard let workspace = approval.workspace, !workspace.isEmpty else {
            return approval.tool
        }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }

    private var createdText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppText.locale(for: configurationStore.config.language)
        return formatter.localizedString(for: approval.createdAt, relativeTo: Date())
    }
}

struct ApprovalQueueCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    let sessions: [AgentSession]
    let onShowDetail: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ApprovalQueuePolicy.elementSpacing) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(AppText.pendingApprovals(ApprovalQueuePolicy.count(in: store.sessions), language: configurationStore.config.language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlassText.primary)
                Spacer()
            }
            .frame(height: ApprovalQueuePolicy.headerHeight)

            ForEach(visibleSessions) { session in
                if let approval = session.approval {
                    ApprovalQueueRow(
                        session: session,
                        approval: approval,
                        onShowDetail: { onShowDetail(session) }
                    )
                    .environmentObject(store)
                }
            }

            if overflowCount > 0 {
                Text(AppText.approvalOverflow(overflowCount, language: configurationStore.config.language))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GlassText.tertiary)
                    .frame(height: ApprovalQueuePolicy.overflowFooterHeight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, ApprovalQueuePolicy.cardVerticalPadding)
        .background(
            ZStack {
                DashboardCardBackground(highlighted: true, tint: Color.yellow.opacity(0.08))
                StatusGlowBorder(
                    status: .waitingApproval,
                    accentColor: .orange,
                    cornerRadius: 18,
                    lineWidth: 1.1,
                    glowRadius: 6,
                    intensity: 0.86
                )
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var visibleSessions: [AgentSession] {
        Array(sessions.prefix(ApprovalQueuePolicy.maximumVisibleRows))
    }

    private var overflowCount: Int {
        max(0, sessions.count - ApprovalQueuePolicy.maximumVisibleRows)
    }
}

private struct ApprovalQueueRow: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    let session: AgentSession
    let approval: ApprovalRequest
    let onShowDetail: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onShowDetail) {
                HStack(spacing: 8) {
                    AgentSourceIconView(source: session.source, size: 26, status: .waitingApproval)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(approval.source.shortName) · \(approval.tool)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GlassText.primary)
                            .lineLimit(1)
                        Text(approval.detail.isEmpty ? workspaceText : approval.detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GlassText.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .islandHoverHighlight(scale: 1.0)
            .help(AppText.pick(configurationStore.config.language, english: "View approval details", japanese: "承認詳細を表示", chinese: "查看审批详情"))

            if approval.supports(.accept) {
                queueActionButton(ApprovalDecision.accept.title(language: configurationStore.config.language), .accept, prominent: true)
            }
            if approval.supports(.decline) {
                queueActionButton(ApprovalDecision.decline.title(language: configurationStore.config.language), .decline)
            }
        }
        .frame(height: ApprovalQueuePolicy.rowHeight)
    }

    private func queueActionButton(_ title: String, _ decision: ApprovalDecision, prominent: Bool = false) -> some View {
        Button {
            store.resolveApproval(approval, decision: decision)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    ClearGlassCapsuleBackground(
                        highlighted: prominent,
                        tint: prominent ? Color.white.opacity(0.16) : Color.white.opacity(0.030),
                        materialOpacity: prominent ? 0.62 : 0.42
                    )
                )
                .foregroundStyle(prominent ? Color(red: 0.12, green: 0.42, blue: 0.84) : GlassText.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .islandHoverHighlight()
        .disabled(approval.isResolving || approval.isExpired)
    }

    private var workspaceText: String {
        guard let workspace = approval.workspace, !workspace.isEmpty else {
            return approval.tool
        }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }
}

struct ApprovalDetailCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    let session: AgentSession
    let approval: ApprovalRequest
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(AppText.pick(
                    configurationStore.config.language,
                    english: "\(approval.source.shortName) approval details",
                    japanese: "\(approval.source.shortName) 承認詳細",
                    chinese: "\(approval.source.shortName) 审批详情"
                ), systemImage: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassText.primary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DashboardSmallButtonStyle())
                .help(AppText.pick(configurationStore.config.language, english: "Back to summary", japanese: "概要に戻る", chinese: "返回摘要"))
            }

            HStack(spacing: 6) {
                DetailPill(text: approval.tool, color: .orange)
                DetailPill(text: workspaceText, color: session.source.color)
                DetailPill(text: createdText, color: GlassText.secondary)
            }

            ScrollView(showsIndicators: true) {
                Text(approval.detail.isEmpty ? approval.tool : approval.detail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 58)
            .padding(8)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                decisionButtons
                Spacer(minLength: 4)
            }
        }
        .padding(12)
        .background(DashboardCardBackground(highlighted: true, tint: Color.orange.opacity(0.10)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var decisionButtons: some View {
        if approval.availableDecisions.isEmpty {
                Text(AppText.pick(
                    configurationStore.config.language,
                    english: "This app version cannot recognize this approval request",
                    japanese: "このバージョンではこの承認リクエストを認識できません",
                    chinese: "当前版本无法识别这个审批请求"
                ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GlassText.secondary)
        } else {
            if approval.supports(.accept) {
                approvalButton(.accept, prominent: true)
            }
            if approval.supports(.acceptForSession) {
                approvalButton(.acceptForSession)
            }
            if approval.supports(.decline) {
                approvalButton(.decline)
            }
            if approval.supports(.cancel) {
                approvalButton(.cancel)
            }
        }
    }

    private func approvalButton(_ decision: ApprovalDecision, prominent: Bool = false) -> some View {
        Button {
            store.resolveApproval(approval, decision: decision)
        } label: {
            Text(decision.title(language: configurationStore.config.language))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    ClearGlassCapsuleBackground(
                        highlighted: prominent,
                        tint: prominent ? Color.white.opacity(0.16) : Color.white.opacity(0.030),
                        materialOpacity: prominent ? 0.62 : 0.42
                    )
                )
                .foregroundStyle(prominent ? Color(red: 0.12, green: 0.42, blue: 0.84) : GlassText.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .islandHoverHighlight()
        .disabled(approval.isResolving || approval.isExpired)
    }

    private var workspaceText: String {
        guard let workspace = approval.workspace, !workspace.isEmpty else {
            return AppText.pick(configurationStore.config.language, english: "No folder provided", japanese: "フォルダ未指定", chinese: "未提供目录")
        }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }

    private var createdText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppText.locale(for: configurationStore.config.language)
        return formatter.localizedString(for: approval.createdAt, relativeTo: Date())
    }
}

struct DetailPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(ClearGlassCapsuleBackground(tint: color.opacity(0.10), materialOpacity: 0.34))
            .clipShape(Capsule())
    }
}
