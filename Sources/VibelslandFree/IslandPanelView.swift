import AppKit
import VibelslandFreeCore
import SwiftUI

struct IslandPanelView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    @State private var showingApprovalDetail = false
    @State private var contentPresentationExpanded = false
    @State private var showExpandedContentLayer = false
    @State private var showCompactContentLayer = true
    @State private var contentTransitionID = 0

    var body: some View {
        let radius: CGFloat = store.isExpanded ? 22 : (isIdleMiniPresentation ? IslandMetrics.idleMiniRadius : 21)
        return ZStack {
            islandBackground(radius: radius)
                .allowsHitTesting(false)
                .zIndex(0)

            ZStack {
                if showsExpandedLayer {
                    expandedContent
                        .opacity(contentPresentationExpanded ? 1 : 0)
                        .allowsHitTesting(contentPresentationExpanded)
                }
                if showsCompactLayer {
                    compactContent
                        .opacity(contentPresentationExpanded ? 0 : 1)
                        .allowsHitTesting(!contentPresentationExpanded)
                }
            }
            .animation(IslandMotion.contentCrossfade, value: contentPresentationExpanded)
            .zIndex(1)
        }
        .background(Color.clear)
        .overlay(
            Group {
                if isIdleMiniPresentation {
                    IdleMiniShellOverlay(status: idleMiniStatus, accentColor: idleMiniAccentColor)
                        .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if isCompactTaskPresentation && !store.isIslandTransitioning {
                CompactRGBOuterGlow(cornerRadius: radius)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contextMenu {
            Button(store.isExpanded ? collapseTitle : expandTitle) {
                store.isExpanded.toggle()
            }
            Button(settingsTitle) {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            Button(installHooksTitle) {
                NSApp.sendAction(#selector(AppDelegate.installHooks), to: nil, from: nil)
            }
            Divider()
            Button(restartTitle) {
                NSApp.sendAction(#selector(AppDelegate.restart), to: nil, from: nil)
            }
            Button(quitTitle) {
                NSApp.sendAction(#selector(AppDelegate.quit), to: nil, from: nil)
            }
        }
        .onAppear {
            contentPresentationExpanded = store.isExpanded
            showExpandedContentLayer = store.isExpanded
            showCompactContentLayer = !store.isExpanded
        }
        .onChange(of: store.isExpanded) { _, isExpanded in
            contentTransitionID += 1
            let transitionID = contentTransitionID
            showExpandedContentLayer = true
            showCompactContentLayer = true
            withAnimation(IslandMotion.contentCrossfade) {
                contentPresentationExpanded = isExpanded
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + IslandMotionPolicy.ContentTransition.crossfadeDuration + 0.04
            ) {
                guard contentTransitionID == transitionID else { return }
                showExpandedContentLayer = isExpanded
                showCompactContentLayer = !isExpanded
            }
        }
    }

    private var showsExpandedLayer: Bool {
        showExpandedContentLayer
    }

    private var showsCompactLayer: Bool {
        showCompactContentLayer
    }

    private func islandBackground(radius: CGFloat) -> some View {
        ZStack {
            if isIdleMiniPresentation {
                IdleMiniGlassBackground(accentColor: idleMiniAccentColor)
                    .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
            } else {
                VisualEffectView(
                    material: store.isExpanded ? .underWindowBackground : .popover,
                    blendingMode: .behindWindow,
                    cornerRadius: radius
                )
                .opacity(store.isExpanded ? 0.30 : 0.26)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(islandFill)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(store.isExpanded ? 0.16 : 0.12),
                                Color.white.opacity(0.024),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: store.isExpanded ? 520 : 180
                        )
                    )
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                ClearGlass.cyanEdge.opacity(store.isExpanded ? 0.20 : 0.15),
                                ClearGlass.violetEdge.opacity(0.070),
                                Color.clear
                            ],
                            center: .bottomTrailing,
                            startRadius: 12,
                            endRadius: store.isExpanded ? 360 : 130
                        )
                    )
                    .blendMode(.plusLighter)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(store.isExpanded ? 0.78 : 0.64),
                                ClearGlass.cyanEdge.opacity(0.30),
                                ClearGlass.warmEdge.opacity(0.24),
                                Color.white.opacity(store.isExpanded ? 0.20 : 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: store.isExpanded ? 1.15 : 0.95
                    )
                RoundedRectangle(cornerRadius: radius - 1, style: .continuous)
                    .stroke(Color.white.opacity(store.isExpanded ? 0.34 : 0.22), lineWidth: 0.7)
                    .padding(1.0)
                RoundedRectangle(cornerRadius: radius - 2, style: .continuous)
                    .stroke(ClearGlass.smoke.opacity(store.isExpanded ? 0.14 : 0.10), lineWidth: 1.0)
                    .blendMode(.multiply)
                    .padding(2.0)
                GlassRefractionHighlights(cornerRadius: radius, isExpanded: store.isExpanded)
            }
        }
    }

    private var islandFill: LinearGradient {
        if store.isExpanded {
            return LinearGradient(
                colors: [
                    ClearGlass.smoke.opacity(0.58),
                    Color.black.opacity(0.38),
                    ClearGlass.smoke.opacity(0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                ClearGlass.smoke.opacity(0.52),
                Color.black.opacity(0.34),
                ClearGlass.smoke.opacity(0.42)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var compactContent: some View {
        Group {
            if isIdleMiniMode {
                IdleMiniContent(
                    status: idleMiniStatus,
                    accentColor: idleMiniAccentColor,
                    language: configurationStore.config.language
                )
                    .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
            } else {
                HStack(spacing: 7) {
                    sourceDots
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactSession.map { SessionDisplaySnapshot(session: $0, language: configurationStore.config.language).title } ?? ">_ - island")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GlassText.primary)
                            .lineLimit(1)
                        Text(compactDetail)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(GlassText.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    CompactLoadingSpinner(
                        status: compactSession?.status ?? .idle,
                        color: compactSession?.source.color ?? Color(red: 0.35, green: 0.68, blue: 1.0),
                        nsColor: compactSession?.source.nsColor ?? NSColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1),
                        language: configurationStore.config.language
                    )
                    .frame(width: 18, height: 18)
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !store.shouldSuppressCompactTap() else { return }
            NSApp.activate(ignoringOtherApps: true)
            store.isExpanded = true
        }
    }

    private var isIdleMiniMode: Bool {
        IslandPresentationPolicy.mode(sessions: store.sessions, isExpanded: false) == .idleMini
    }

    private var isIdleMiniPresentation: Bool {
        IslandPresentationPolicy.isIdleMiniPresentation(
            sessions: store.sessions,
            isExpanded: store.isExpanded
        )
    }

    private var isCompactTaskPresentation: Bool {
        !store.isExpanded && !isIdleMiniPresentation
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            dashboardHeader
            if store.healthChecks.contains(where: { $0.status == .needsAction }) {
                HealthSummaryStrip(items: store.healthChecks)
            }

            if showingApprovalDetail,
               let approvalSession = approvalDetailSession,
               let approval = approvalSession.approval {
                ApprovalDetailCard(session: approvalSession, approval: approval) {
                    showingApprovalDetail = false
                }
                .environmentObject(store)
            } else if approvalQueueSessions.count > 1 {
                ApprovalQueueCard(sessions: approvalQueueSessions) { session in
                    store.selectedSessionID = session.id
                    showingApprovalDetail = true
                }
                .environmentObject(store)
            } else if let approvalSession = approvalQueueSessions.first,
                      let approval = approvalSession.approval {
                ApprovalSummaryCard(
                    session: approvalSession,
                    approval: approval,
                    showsDetail: $showingApprovalDetail
                )
                .environmentObject(store)
            }

            if showingApprovalDetail && approvalDetailSession != nil {
                EmptyView()
            } else if dashboardSessions.isEmpty {
                DashboardEmptyCard()
            } else {
                ForEach(dashboardSessions) { session in
                    DashboardSessionCard(
                        session: session,
                        isSelected: session.id == store.selectedSession?.id,
                        isCondensed: shouldCondenseSessions
                    )
                    .environmentObject(store)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onChange(of: showingApprovalDetail) { _, value in
            store.isApprovalDetailVisible = value && approvalDetailSession != nil
        }
        .onChange(of: approvalDetailSession?.approval?.id) {
            showingApprovalDetail = false
            store.isApprovalDetailVisible = false
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 10) {
            sourceDots
            if let usage = dashboardUsage {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    UsageHeaderView(usage: usage)
                }
                .buttonStyle(.plain)
                .help(AppText.pick(configurationStore.config.language, english: "Open usage settings", japanese: "使用量設定を開く", chinese: "查看用量设置"))
            } else {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    Text(statusLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GlassText.primary)
                }
                .buttonStyle(.plain)
                .help(AppText.pick(configurationStore.config.language, english: "Open settings", japanese: "設定を開く", chinese: "打开设置"))
            }
            Spacer()
            Button {
                configurationStore.config.doNotDisturb.toggle()
            } label: {
                Image(systemName: configurationStore.config.doNotDisturb ? "bell.slash.fill" : "bell.fill")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help(configurationStore.config.doNotDisturb ? AppText.pick(configurationStore.config.language, english: "Turn off Do Not Disturb", japanese: "集中モードをオフ", chinese: "关闭勿扰") : AppText.pick(configurationStore.config.language, english: "Turn on Do Not Disturb", japanese: "集中モードをオン", chinese: "开启勿扰"))
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help(settingsTitle)
            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .help(error)
            }
            Button {
                store.isExpanded = false
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help(collapseTitle)
        }
        .frame(height: 24)
    }

    private var sourceDots: some View {
        AgentIconStack(sources: activeSources, statuses: sourceStatuses, isExpanded: store.isExpanded)
    }

    private var compactSession: AgentSession? {
        pendingApprovalSession
            ?? dashboardVisibleSessions.first(where: { $0.status.isActiveVisual })
            ?? visibleSelectedSession
            ?? dashboardVisibleSessions.first
    }

    private var visibleSelectedSession: AgentSession? {
        guard let selected = store.selectedSession,
              DashboardSessionPolicy.isVisible(selected) else {
            return nil
        }
        return selected
    }

    private var compactDetail: String {
        guard let session = compactSession else {
            return AppText.pick(configurationStore.config.language, english: "Waiting for events", japanese: "イベント待ち", chinese: "等待事件")
        }
        if session.approval != nil {
            let queueCount = approvalQueueSessions.count
            if queueCount > 1 {
                return AppText.pendingApprovals(queueCount, language: configurationStore.config.language)
            }
            return AppText.pick(configurationStore.config.language, english: "Waiting approval", japanese: "承認待ち", chinese: "等待审批")
        }
        let display = SessionDisplaySnapshot(session: session, language: configurationStore.config.language)
        return display.primaryLine
    }

    private var activeSources: [AgentSource] {
        var seen = Set<AgentSource>()
        var ordered: [AgentSource] = []
        for source in dashboardVisibleSessions.map(\.source) where !seen.contains(source) {
            seen.insert(source)
            ordered.append(source)
        }
        return ordered
    }

    private var sourceStatuses: [AgentSource: SessionStatus] {
        Dictionary(uniqueKeysWithValues: activeSources.map { source in
            let status = dashboardVisibleSessions.first { $0.source == source }?.status ?? .idle
            return (source, status)
        })
    }

    private var ambientStatus: SessionStatus {
        if isIdleMiniPresentation {
            return .idle
        }
        if let approval = pendingApprovalSession, approval.approval?.isExpired == false {
            return .waitingApproval
        }
        return compactSession?.status ?? .idle
    }

    private var ambientColor: Color {
        if isIdleMiniPresentation {
            return Color(red: 0.54, green: 0.70, blue: 1.0)
        }
        if ambientStatus == .waitingApproval {
            return .orange
        }
        return compactSession?.source.color ?? Color(red: 0.35, green: 0.68, blue: 1.0)
    }

    private var idleMiniStatus: SessionStatus {
        if store.lastError != nil || store.healthChecks.contains(where: { $0.status == .needsAction }) {
            return .failed
        }
        return .idle
    }

    private var idleMiniAccentColor: Color {
        switch idleMiniStatus {
        case .failed:
            return Color(red: 1.00, green: 0.34, blue: 0.25)
        case .waitingApproval, .waitingQuestion:
            return Color.orange
        case .done:
            return Color.green
        case .thinking, .runningTool:
            return Color(red: 0.30, green: 0.72, blue: 1.00)
        case .idle:
            return Color(red: 0.42, green: 0.66, blue: 1.00)
        }
    }

    private var statusLine: String {
        let approvals = store.sessions.filter { session in
            guard let approval = session.approval else { return false }
            return !approval.isExpired
        }.count
        if approvals > 0 {
            return AppText.pendingApprovals(approvals, language: configurationStore.config.language)
        }

        let visibleSessions = dashboardVisibleSessions
        guard !visibleSessions.isEmpty else {
            return AppText.pick(configurationStore.config.language, english: "No activity", japanese: "アクティビティなし", chinese: "暂无活动")
        }

        let activeCount = visibleSessions.filter(\.status.isActiveVisual).count
        if activeCount > 0 {
            return AppText.activeTasks(activeCount, language: configurationStore.config.language)
        }

        return AppText.recentSessions(visibleSessions.count, language: configurationStore.config.language)
    }

    private var expandTitle: String {
        AppText.pick(configurationStore.config.language, english: "Expand island", japanese: "アイランドを展開", chinese: "展开浮岛")
    }

    private var collapseTitle: String {
        AppText.pick(configurationStore.config.language, english: "Collapse island", japanese: "アイランドを折りたたむ", chinese: "收起浮岛")
    }

    private var settingsTitle: String {
        AppText.pick(configurationStore.config.language, english: "Settings", japanese: "設定", chinese: "设置")
    }

    private var installHooksTitle: String {
        AppText.pick(configurationStore.config.language, english: "Install hooks", japanese: "Hooks をインストール", chinese: "安装 Hooks")
    }

    private var restartTitle: String {
        AppText.pick(configurationStore.config.language, english: "Restart app", japanese: "アプリを再起動", chinese: "重启应用")
    }

    private var quitTitle: String {
        AppText.pick(configurationStore.config.language, english: "Quit app", japanese: "アプリを終了", chinese: "退出应用")
    }

    private var pendingApprovalSession: AgentSession? {
        DashboardSessionPolicy.pendingApprovalSession(in: store.sessions)
    }

    private var approvalQueueSessions: [AgentSession] {
        ApprovalQueuePolicy.queue(in: store.sessions)
    }

    /// 详情优先展示用户点选的审批，未点选时退回等待最久的主审批。
    private var approvalDetailSession: AgentSession? {
        if let selected = store.selectedSession,
           let approval = selected.approval,
           !approval.isExpired {
            return selected
        }
        return pendingApprovalSession
    }

    private var dashboardUsage: UsageSnapshot? {
        dashboardVisibleSessions.first { session in
            guard let usage = session.usage else { return false }
            return usage.primaryUsedPercent != nil || usage.secondaryUsedPercent != nil
        }?.usage ?? compactSession?.usage ?? dashboardVisibleSessions.first(where: { $0.usage != nil })?.usage
    }

    private var dashboardSessions: [AgentSession] {
        let queueIDs = Set(approvalQueueSessions.map(\.id))
        let limit = configuredVisibleSessionLimit - (queueIDs.isEmpty ? 0 : 1)
        return DashboardSessionPolicy.visibleSessions(
            from: store.sessions,
            excludingIDs: queueIDs,
            limit: max(0, limit)
        )
    }

    private var dashboardVisibleSessions: [AgentSession] {
        DashboardSessionPolicy.visibleSessions(
            from: store.sessions,
            limit: configuredVisibleSessionLimit
        )
    }

    private var configuredVisibleSessionLimit: Int {
        DashboardSessionPolicy.configuredVisibleSessionLimit(configurationStore.config.maxVisibleSessions)
    }

    private var shouldCondenseSessions: Bool {
        pendingApprovalSession != nil || dashboardSessions.count > 1
    }

    private var sessionColumn: some View {
        ZStack {
            GlassPanelBackground(cornerRadius: 18)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if store.sessions.isEmpty {
                        EmptyStateView()
                            .padding(.top, 36)
                    } else {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session, isSelected: session.id == store.selectedSession?.id)
                                .onTapGesture {
                                    store.selectedSessionID = session.id
                                }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let session = store.selectedSession {
            ZStack {
                GlassPanelBackground(cornerRadius: 18)
                SessionDetailView(session: session)
                    .environmentObject(store)
            }
        } else {
            ZStack {
                GlassPanelBackground(cornerRadius: 18)
                EmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
