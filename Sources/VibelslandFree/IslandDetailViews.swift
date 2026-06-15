import AppKit
import VibelslandFreeCore
import SwiftUI

struct SessionRow: View {
    let session: AgentSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            AgentSourceIconView(source: session.source, size: 36, status: session.status)
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(display.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(display.primaryLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(session.ageText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            ClearGlassRoundedBackground(
                cornerRadius: 16,
                highlighted: isSelected,
                tint: isSelected ? Color.white.opacity(0.12) : .clear,
                materialOpacity: isSelected ? 0.72 : 0.46
            )
        )
    }

    private var display: SessionDisplaySnapshot {
        SessionDisplaySnapshot(session: session)
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var store: SessionStore
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(display.title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Text(display.secondaryLine ?? session.workspace)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(status: session.status, color: session.source.color)
            }

            if let usage = session.usage {
                UsageStrip(usage: usage)
            }

            if let message = session.lastAssistantMessage, !message.isEmpty {
                AssistantMessageCard(message: message)
            }

            if let approval = session.approval {
                ApprovalPanel(approval: approval)
                    .environmentObject(store)
            }

            if session.subagents.contains(where: { $0.status.isActiveVisual }) {
                SubagentSummaryView(subagents: session.subagents)
            }

            Text("活动")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)

            if session.activity.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 22, weight: .medium))
                    Text("暂无可展示活动")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(session.activity.reversed()) { item in
                            ActivityRow(item: item)
                        }
                    }
                    .padding(.top, 4)
                }
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.isExpanded = false
                        }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var display: SessionDisplaySnapshot {
        SessionDisplaySnapshot(session: session)
    }
}

struct UsageStrip: View {
    let usage: UsageSnapshot

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                UsageMetric(title: "本轮", value: UsageSnapshot.compactNumber(usage.lastTokens))
                UsageMetric(title: "总计", value: usage.totalText)
                if usage.contextWindow > 0 {
                    UsageMetric(title: "上下文", value: UsageSnapshot.compactNumber(usage.contextWindow))
                }
                if let primary = usage.primaryUsedPercent {
                    UsageMetric(title: "5h", value: UsageSnapshot.percent(primary), accent: primary >= 80)
                }
                if let secondary = usage.secondaryUsedPercent {
                    UsageMetric(title: "7d", value: UsageSnapshot.percent(secondary), accent: secondary >= 80)
                }
                if let plan = usage.planType, !plan.isEmpty {
                    UsageMetric(title: "计划", value: plan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UsageMetric: View {
    let title: String
    let value: String
    var accent = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(accent ? Color.orange : Color.primary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            ClearGlassCapsuleBackground(
                highlighted: accent,
                tint: accent ? Color.orange.opacity(0.10) : Color.white.opacity(0.040),
                materialOpacity: 0.40
            )
        )
        .clipShape(Capsule())
    }
}

struct AssistantMessageCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("最新回复", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClearGlassRoundedBackground(cornerRadius: 10, highlighted: true, materialOpacity: 0.30))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SubagentSummaryView: View {
    let subagents: [SubagentItem]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2")
            Text("运行 \(activeCount) 个子智能体")
            if doneCount > 0 {
                Text("完成 \(doneCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            ClearGlassCapsuleBackground(
                highlighted: true,
                tint: Color.white.opacity(0.050),
                materialOpacity: 0.40
            )
        )
        .clipShape(Capsule())
    }

    private var doneCount: Int {
        subagents.filter { $0.status == .done }.count
    }

    private var activeCount: Int {
        subagents.filter { $0.status.isActiveVisual }.count
    }
}

struct ApprovalPanel: View {
    @EnvironmentObject private var store: SessionStore
    let approval: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.yellow)
                Text(approval.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text(approval.detail.isEmpty ? approval.tool : approval.detail)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if approval.availableDecisions.isEmpty {
                    Text("当前版本无法识别这个审批请求")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if approval.supports(.accept) {
                    Button(ApprovalDecision.accept.title) {
                        store.resolveApproval(approval, decision: .accept)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(approval.isResolving || approval.isExpired)
                }

                if approval.supports(.acceptForSession) {
                    Button(ApprovalDecision.acceptForSession.title) {
                        store.resolveApproval(approval, decision: .acceptForSession)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(approval.isResolving || approval.isExpired)
                }

                Spacer()

                if approval.supports(.decline) {
                    Button(ApprovalDecision.decline.title) {
                        store.resolveApproval(approval, decision: .decline)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(approval.isResolving || approval.isExpired)
                }

                if approval.supports(.cancel) {
                    Button(ApprovalDecision.cancel.title) {
                        store.resolveApproval(approval, decision: .cancel)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(approval.isResolving || approval.isExpired)
                }
            }
            .buttonStyle(.bordered)

            if let message = approval.resolutionMessage {
                Label(message, systemImage: resolutionIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            ClearGlassRoundedBackground(
                cornerRadius: 8,
                highlighted: true,
                tint: Color.yellow.opacity(0.10),
                materialOpacity: 0.32
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resolutionIcon: String {
        if approval.isResolving {
            return "arrow.triangle.2.circlepath"
        }
        if approval.isExpired {
            return "clock"
        }
        return "exclamationmark.triangle"
    }
}

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ClearGlassRoundedBackground(cornerRadius: 12, highlighted: true, materialOpacity: 0.28)
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: SessionStatus
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            PixelBlinker(color: color, isActive: status.isActiveVisual)
                .frame(width: 12, height: 12)
            Text(status.displayName)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(ClearGlassCapsuleBackground(highlighted: true, tint: color.opacity(0.12), materialOpacity: 0.28))
        .foregroundStyle(color)
        .overlay(
            ZStack {
                StatusGlowBorder(
                    status: status,
                    accentColor: color,
                    cornerRadius: 18,
                    lineWidth: 1,
                    glowRadius: 4,
                    intensity: 0.72
                )
            }
        )
        .clipShape(Capsule())
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("等待事件")
                .font(.system(size: 13, weight: .semibold))
            Text("启动 Claude Code 或 Codex 后会自动显示。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
    }
}
