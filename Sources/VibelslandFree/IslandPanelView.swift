import AppKit
import VibelslandFreeCore
import SwiftUI

struct IslandPanelView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var configurationStore: AppConfigurationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingApprovalDetail = false
    @State private var contentPresentationExpanded = false
    @State private var showExpandedContentLayer = false
    @State private var showCompactContentLayer = true
    @State private var contentTransitionID = 0

    var body: some View {
        // 窗口是设计尺寸的 0.8 倍；内容按设计尺寸布局后整体缩放，
        // 字体与间距等比缩小、版式不变（与 IslandWindow.targetFrame 配对）。
        GeometryReader { proxy in
            islandContent
                .frame(
                    width: proxy.size.width / IslandMetrics.windowScale,
                    height: proxy.size.height / IslandMetrics.windowScale
                )
                .scaleEffect(IslandMetrics.windowScale, anchor: .topLeading)
        }
    }

    private var islandContent: some View {
        let radius: CGFloat = store.isExpanded ? 22 : (dockEdge != nil ? IslandDockingPolicy.tabSize.height / 2 : (isIdleMiniPresentation ? IslandMetrics.idleMiniRadius : 21))
        return ZStack {
            islandBackground(radius: radius)
                .allowsHitTesting(false)
                .zIndex(0)

            ZStack {
                if showsExpandedLayer {
                    // 交叉淡化叠加细微缩放：展开内容从 0.98 生长到位，读作形变而非替换。
                    expandedContent
                        .frame(width: 620)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(contentPresentationExpanded ? 1 : 0)
                        .scaleEffect(
                            reduceMotion || contentPresentationExpanded
                                ? 1
                                : IslandMotionPolicy.ContentTransition.expandedLayerInitialScale,
                            anchor: .top
                        )
                        .allowsHitTesting(contentPresentationExpanded)
                }
                if showsCompactLayer {
                    compactContent
                        .frame(width: dockEdge != nil ? IslandDockingPolicy.tabSize.width : (isIdleMiniPresentation ? IslandMetrics.idleMiniDiameter : IslandPresentationPolicy.compactTaskSize.width))
                        .opacity(contentPresentationExpanded ? 0 : 1)
                        .scaleEffect(
                            !reduceMotion && contentPresentationExpanded
                                ? IslandMotionPolicy.ContentTransition.compactLayerLiftedScale
                                : 1
                        )
                        .allowsHitTesting(!contentPresentationExpanded)
                }
            }
            .animation(IslandMotion.contentCrossfade(reduceMotion: reduceMotion), value: contentPresentationExpanded)
            .zIndex(1)
        }
        .background(Color.clear)
        .clipShape(panelShape(radius: radius))
        .preferredColorScheme(.dark)
        .contentShape(panelShape(radius: radius))
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
            if reduceMotion {
                contentPresentationExpanded = isExpanded
                showExpandedContentLayer = isExpanded
                showCompactContentLayer = !isExpanded
                return
            }
            let transitionID = contentTransitionID
            showExpandedContentLayer = true
            showCompactContentLayer = true
            withAnimation(IslandMotion.contentCrossfade(reduceMotion: reduceMotion)) {
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
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: dockEdge == nil ? radius : 0)
            panelShape(radius: radius)
                .fill(Color(red: 0.075, green: 0.080, blue: 0.095).opacity(0.94))
            panelShape(radius: radius)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.33, blue: 0.55).opacity(0.24),
                        .white.opacity(0.018),
                        Color(red: 0.32, green: 0.20, blue: 0.43).opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            panelShape(radius: radius)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
        }
    }

    private var dockEdge: IslandDockEdge? {
        configurationStore.config.islandDockPlacement?.edge
    }

    private func panelShape(radius: CGFloat) -> IslandPanelShape {
        IslandPanelShape(edge: dockEdge, expanded: store.isExpanded, cornerRadius: radius)
    }

    private var statusSpinner: some View {
        CompactLoadingSpinner(
            status: compactSession?.status ?? .idle,
            source: compactSession?.source ?? store.selectedSession?.source ?? .unknown,
            language: configurationStore.config.language
        )
    }

    private var compactContent: some View {
        Group {
            if dockEdge != nil {
                ZStack {
                    statusSpinner.frame(width: 22, height: 22)
                }
                .frame(width: IslandDockingPolicy.tabSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dockEdge == .left ? .trailing : .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\((compactSession?.source ?? store.selectedSession?.source ?? .unknown).shortName) · \((compactSession?.status ?? .idle).displayName(language: configurationStore.config.language))")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { store.isExpanded = true }
            } else if isIdleMiniMode {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GlassText.primary)
                    .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
            } else {
                HStack(spacing: 10) {
                    sourceDots
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactSession.map { SessionDisplaySnapshot(session: $0, language: configurationStore.config.language).title } ?? ">_ - island")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(GlassText.primary)
                            .lineLimit(1)
                        Text(compactDetail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(GlassText.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    statusSpinner
                    .frame(width: 18, height: 18)
                }
                .padding(.horizontal, 13)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .islandHoverHighlight(scale: 1.01)
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
        VStack(alignment: .leading, spacing: 8) {
            dashboardHeader
            if store.healthChecks.contains(where: { $0.status == .needsAction }) {
                HealthSummaryStrip(items: store.healthChecks)
            }

            // 审批区的摘要/队列/详情三态切换用轻弹簧 + 缩放过渡，新审批到达时卡片「生长」出现。
            Group {
                if showingApprovalDetail,
                   let approvalSession = approvalDetailSession,
                   let approval = approvalSession.approval {
                    ApprovalDetailCard(session: approvalSession, approval: approval) {
                        showingApprovalDetail = false
                    }
                    .environmentObject(store)
                    .transition(approvalCardTransition)
                } else if approvalQueueSessions.count > 1 {
                    ApprovalQueueCard(sessions: approvalQueueSessions) { session in
                        store.selectedSessionID = session.id
                        showingApprovalDetail = true
                    }
                    .environmentObject(store)
                    .transition(approvalCardTransition)
                } else if let approvalSession = approvalQueueSessions.first,
                          let approval = approvalSession.approval {
                    ApprovalSummaryCard(
                        session: approvalSession,
                        approval: approval,
                        showsDetail: $showingApprovalDetail
                    )
                    .environmentObject(store)
                    .transition(approvalCardTransition)
                }
            }
            .animation(
                IslandMotion.approvalCardSpring(reduceMotion: reduceMotion),
                value: approvalAreaSignature
            )

            if showingApprovalDetail && approvalDetailSession != nil {
                EmptyView()
            } else if dashboardSessions.isEmpty {
                if approvalQueueSessions.isEmpty {
                    DashboardEmptyCard()
                }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: showingApprovalDetail) { _, value in
            store.isApprovalDetailVisible = value && approvalDetailSession != nil
        }
        .onChange(of: approvalDetailSession?.approval?.id) {
            showingApprovalDetail = false
            store.isApprovalDetailVisible = false
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 8) {
            Text(">_")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(GlassText.tertiary)
                .help(AppText.pick(configurationStore.config.language, english: "Drag to move the island", japanese: "ドラッグして移動", chinese: "拖动以移动浮岛"))
            if let usage = dashboardUsage {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    UsageHeaderView(usage: usage)
                }
                .buttonStyle(.plain)
                .islandHoverHighlight(scale: 1.0)
                .help(AppText.pick(configurationStore.config.language, english: "Open usage settings", japanese: "使用量設定を開く", chinese: "查看用量设置"))
            } else {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    Text(statusLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GlassText.secondary)
                }
                .buttonStyle(.plain)
                .islandHoverHighlight(scale: 1.0)
                .help(AppText.pick(configurationStore.config.language, english: "Open settings", japanese: "設定を開く", chinese: "打开设置"))
            }
            Spacer()
            Button {
                configurationStore.config.doNotDisturb.toggle()
            } label: {
                Image(systemName: configurationStore.config.doNotDisturb ? "bell.slash" : "bell")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help(configurationStore.config.doNotDisturb ? AppText.pick(configurationStore.config.language, english: "Turn off Do Not Disturb", japanese: "集中モードをオフ", chinese: "关闭勿扰") : AppText.pick(configurationStore.config.language, english: "Turn on Do Not Disturb", japanese: "集中モードをオン", chinese: "开启勿扰"))
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
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
        .frame(height: 32)
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

    private var approvalCardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    /// 审批区状态签名：详情开关 + 队列成员变化都触发弹簧过渡。
    private var approvalAreaSignature: String {
        "\(showingApprovalDetail)|\(approvalQueueSessions.map(\.id).joined(separator: ","))"
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

struct IslandPanelShape: InsettableShape {
    let edge: IslandDockEdge?
    let expanded: Bool
    let cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        guard let dockEdge = edge, !expanded else {
            let radius = max(0, cornerRadius - insetAmount)
            return UnevenRoundedRectangle(
                topLeadingRadius: edge == .left ? 0 : radius,
                bottomLeadingRadius: edge == .left ? 0 : radius,
                bottomTrailingRadius: edge == .right ? 0 : radius,
                topTrailingRadius: edge == .right ? 0 : radius,
                style: edge == nil ? .continuous : .circular
            ).path(in: rect)
        }

        let radius = rect.height / 2
        let centerX = rect.minX + radius
        let arc = radius * 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addCurve(to: CGPoint(x: centerX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY),
            control2: CGPoint(x: centerX + radius * 0.8, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: centerX - arc, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.midY - arc))
        path.addCurve(to: CGPoint(x: centerX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.midY + arc),
            control2: CGPoint(x: centerX - arc, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: centerX + radius * 0.8, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
        path.closeSubpath()
        return dockEdge == .right ? path : path.applying(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        )
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
