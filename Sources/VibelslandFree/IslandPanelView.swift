import AppKit
import VibelslandFreeCore
import SwiftUI

private enum GlassText {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.70)
    static let tertiary = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.38)
    static let control = Color.white.opacity(0.76)
}

private enum ClearGlass {
    static let topHighlight = Color.white.opacity(0.64)
    static let innerShade = Color.black.opacity(0.030)
    static let cyanEdge = Color(red: 0.50, green: 0.95, blue: 1.0)
    static let warmEdge = Color(red: 1.0, green: 0.66, blue: 0.36)
    static let violetEdge = Color(red: 0.72, green: 0.62, blue: 1.0)
    static let smoke = Color(red: 0.13, green: 0.18, blue: 0.20)
}

enum IslandMetrics {
    static let idleMiniDiameter: CGFloat = IslandPresentationPolicy.idleMiniDiameter
    static let idleMiniRadius: CGFloat = idleMiniDiameter / 2
}

private extension AgentSource {
    var nsColor: NSColor {
        switch self {
        case .claudeCode:
            return NSColor(red: 0.86, green: 0.42, blue: 0.24, alpha: 1)
        case .codexCli:
            return NSColor(red: 0.20, green: 0.72, blue: 0.42, alpha: 1)
        case .codexDesktop:
            return NSColor(red: 0.34, green: 0.60, blue: 0.92, alpha: 1)
        case .unknown:
            return .tertiaryLabelColor
        }
    }
}

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
            Button(store.isExpanded ? "收起浮岛" : "展开浮岛") {
                store.isExpanded.toggle()
            }
            Button("设置") {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }
            Button("安装 Hooks") {
                NSApp.sendAction(#selector(AppDelegate.installHooks), to: nil, from: nil)
            }
            Divider()
            Button("重启应用") {
                NSApp.sendAction(#selector(AppDelegate.restart), to: nil, from: nil)
            }
            Button("退出应用") {
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
                IdleMiniContent(status: idleMiniStatus, accentColor: idleMiniAccentColor)
                    .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
            } else {
                HStack(spacing: 7) {
                    sourceDots
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactSession.map { SessionDisplaySnapshot(session: $0).title } ?? ">_ - island")
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
                        nsColor: compactSession?.source.nsColor ?? NSColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1)
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

            if let approvalSession = pendingApprovalSession,
               let approval = approvalSession.approval {
                if showingApprovalDetail {
                    ApprovalDetailCard(session: approvalSession, approval: approval) {
                        showingApprovalDetail = false
                    }
                    .environmentObject(store)
                } else {
                    ApprovalSummaryCard(
                        session: approvalSession,
                        approval: approval,
                        showsDetail: $showingApprovalDetail
                    )
                    .environmentObject(store)
                }
            }

            if showingApprovalDetail && pendingApprovalSession != nil {
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
            store.isApprovalDetailVisible = value && pendingApprovalSession != nil
        }
        .onChange(of: pendingApprovalSession?.approval?.id) {
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
                .help("查看用量设置")
            } else {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                } label: {
                    Text(statusLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GlassText.primary)
                }
                .buttonStyle(.plain)
                .help("打开设置")
            }
            Spacer()
            Button {
                configurationStore.config.doNotDisturb.toggle()
            } label: {
                Image(systemName: configurationStore.config.doNotDisturb ? "bell.slash.fill" : "bell.fill")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help(configurationStore.config.doNotDisturb ? "关闭勿扰" : "开启勿扰")
            Button {
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(DashboardIconButtonStyle())
            .help("设置")
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
            .help("收起")
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
            return "等待事件"
        }
        if session.approval != nil {
            return "等待审批"
        }
        let display = SessionDisplaySnapshot(session: session)
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
            return "\(approvals) 个审批等待处理"
        }

        let visibleSessions = dashboardVisibleSessions
        guard !visibleSessions.isEmpty else {
            return "暂无活动"
        }

        let activeCount = visibleSessions.filter(\.status.isActiveVisual).count
        if activeCount > 0 {
            return "\(activeCount) 个任务进行中"
        }

        return "\(visibleSessions.count) 个最近会话"
    }

    private var pendingApprovalSession: AgentSession? {
        DashboardSessionPolicy.pendingApprovalSession(in: store.sessions)
    }

    private var dashboardUsage: UsageSnapshot? {
        dashboardVisibleSessions.first { session in
            guard let usage = session.usage else { return false }
            return usage.primaryUsedPercent != nil || usage.secondaryUsedPercent != nil
        }?.usage ?? compactSession?.usage ?? dashboardVisibleSessions.first(where: { $0.usage != nil })?.usage
    }

    private var dashboardSessions: [AgentSession] {
        let approvalID = pendingApprovalSession?.id
        let limit = configuredVisibleSessionLimit - (pendingApprovalSession == nil ? 0 : 1)
        return DashboardSessionPolicy.visibleSessions(
            from: store.sessions,
            excluding: approvalID,
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

struct IdleMiniContent: View {
    let status: SessionStatus
    let accentColor: Color

    var body: some View {
        ZStack {
            MiniBreathingLights(status: status, accentColor: accentColor)
                .frame(width: IslandMetrics.idleMiniDiameter, height: IslandMetrics.idleMiniDiameter)
            MiniStatusProgressRing(status: status, accentColor: accentColor)
                .padding(1.6)
            VibelslandLineMark()
                .frame(width: 21, height: 18)
                .shadow(color: Color.white.opacity(0.36), radius: 1.2, y: 0.5)
        }
        .accessibilityLabel(">_ - island \(status.displayName)")
    }
}

struct VibelslandLineMark: View {
    var body: some View {
        ZStack {
            VibelslandMarkShape()
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                .blur(radius: 0.65)
            VibelslandMarkShape()
                .stroke(Color.black.opacity(0.78), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        }
    }
}

struct VibelslandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.22, y: height * 0.22))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.50))
        path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.78))

        path.move(to: CGPoint(x: width * 0.56, y: height * 0.65))
        path.addLine(to: CGPoint(x: width * 0.72, y: height * 0.65))

        path.move(to: CGPoint(x: width * 0.80, y: height * 0.65))
        path.addLine(to: CGPoint(x: width * 0.90, y: height * 0.65))

        return path
    }
}

struct IdleMiniGlassBackground: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                cornerRadius: IslandMetrics.idleMiniRadius
            )
            .opacity(0.18)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            accentColor.opacity(0.10),
                            Color.white.opacity(0.035)
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 32
                    )
                )
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.clear,
                            Color.black.opacity(0.026)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                .padding(0.4)
        }
        .shadow(color: accentColor.opacity(0.13), radius: 7, y: 3)
        .shadow(color: Color.black.opacity(0.030), radius: 2, y: 1)
    }
}

struct IdleMiniShellOverlay: View {
    let status: SessionStatus
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.52), lineWidth: 0.8)
            Circle()
                .stroke(accentColor.opacity(status.isActiveVisual ? 0.38 : 0.20), lineWidth: 0.8)
                .padding(3.2)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

struct MiniStatusProgressRing: View {
    let status: SessionStatus
    let accentColor: Color

    var body: some View {
        if status.isActiveVisual {
            TimelineView(.periodic(from: .now, by: IslandMotion.MiniProgressRing.refreshInterval(for: status))) { context in
                ring(rotation: IslandMotion.MiniProgressRing.rotationDegrees(
                    time: context.date.timeIntervalSinceReferenceDate,
                    status: status
                ) - 90)
            }
            .allowsHitTesting(false)
        } else {
            ring(rotation: -90)
                .allowsHitTesting(false)
        }
    }

    private func ring(rotation: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 2.3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringStyle, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .shadow(color: accentColor.opacity(shadowOpacity), radius: 2.6)
            if status == .idle {
                Circle()
                    .trim(from: 0.03, to: 0.11)
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .rotationEffect(.degrees(-42))
            }
        }
    }

    private var progress: CGFloat {
        switch status {
        case .idle:
            return 0.72
        case .thinking:
            return 0.64
        case .runningTool:
            return 0.78
        case .waitingApproval, .waitingQuestion:
            return 0.62
        case .done, .failed:
            return 0.96
        }
    }

    private var shadowOpacity: Double {
        switch status {
        case .idle:
            return 0.20
        case .failed, .waitingApproval, .waitingQuestion:
            return 0.36
        case .thinking, .runningTool:
            return 0.42
        case .done:
            return 0.30
        }
    }

    private var ringStyle: AnyShapeStyle {
        switch status {
        case .thinking, .runningTool:
            return AnyShapeStyle(
                AngularGradient(
                    colors: [
                        Color(red: 0.32, green: 0.62, blue: 1.00),
                        Color(red: 0.25, green: 0.98, blue: 0.58),
                        Color(red: 0.98, green: 0.78, blue: 0.26),
                        Color(red: 0.78, green: 0.34, blue: 1.00),
                        Color(red: 0.32, green: 0.62, blue: 1.00)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                )
            )
        case .waitingApproval, .waitingQuestion:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.orange, Color.yellow.opacity(0.78), Color.orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .done:
            return AnyShapeStyle(Color.green.opacity(0.92))
        case .failed:
            return AnyShapeStyle(Color(red: 1.00, green: 0.30, blue: 0.20).opacity(0.92))
        case .idle:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [accentColor.opacity(0.92), Color(red: 0.64, green: 0.82, blue: 1.00).opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

struct MiniBreathingLights: View {
    let status: SessionStatus
    let accentColor: Color

    var body: some View {
        if IslandMotion.BreathingLights.shouldAnimate(for: status) {
            TimelineView(.animation(minimumInterval: IslandMotion.BreathingLights.refreshInterval(for: status))) { context in
                lights(time: context.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
        } else {
            lights(time: 0)
                .allowsHitTesting(false)
        }
    }

    private func lights(time: TimeInterval) -> some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2 - 3.5

            ZStack {
                ForEach(0..<IslandMotion.BreathingLights.dotCount, id: \.self) { index in
                    let phase = Double(index) * IslandMotion.BreathingLights.dotPhaseStep
                    let pulse = (sin(time * IslandMotion.BreathingLights.pulseSpeed(for: status) + phase) + 1) / 2
                    let angle = (Double(index) / Double(IslandMotion.BreathingLights.dotCount)) * .pi * 2 - .pi / 2
                    let dotSize = IslandMotion.BreathingLights.dotBaseSize + CGFloat(pulse) * IslandMotion.BreathingLights.dotPulseSize

                    Circle()
                        .fill(lightColor(index: index).opacity(IslandMotion.BreathingLights.opacity(for: pulse, status: status)))
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: lightColor(index: index).opacity(IslandMotion.BreathingLights.shadowOpacity(for: pulse, status: status)), radius: 2.4)
                        .position(
                            x: center.x + CGFloat(cos(angle)) * radius,
                            y: center.y + CGFloat(sin(angle)) * radius
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func lightColor(index: Int) -> Color {
        switch status {
        case .thinking, .runningTool:
            let palette = [
                Color(red: 0.32, green: 0.62, blue: 1.00),
                Color(red: 0.24, green: 0.95, blue: 0.54),
                Color(red: 0.98, green: 0.78, blue: 0.25),
                Color(red: 0.92, green: 0.26, blue: 0.38),
                Color(red: 0.72, green: 0.34, blue: 1.00)
            ]
            return palette[index % palette.count]
        case .waitingApproval, .waitingQuestion:
            return index.isMultiple(of: 2) ? Color.orange : Color.yellow.opacity(0.86)
        case .done:
            return Color.green
        case .failed:
            return Color(red: 1.00, green: 0.30, blue: 0.20)
        case .idle:
            return accentColor
        }
    }
}

struct CompactLoadingSpinner: View {
    let status: SessionStatus
    let color: Color
    let nsColor: NSColor

    var body: some View {
        Group {
            if status.isActiveVisual {
                CoreAnimationLoadingSpinner(
                    color: spinnerNSColor,
                    trimEnd: trimEnd,
                    cycle: IslandMotion.CompactLoadingSpinner.rotationCycle(for: status)
                )
            } else {
                spinner(rotation: -90)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(status.isActiveVisual ? "加载中" : status.displayName)
    }

    private func spinner(rotation: Double) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(spinnerStyle, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .shadow(
                    color: statusColor.opacity(status.isActiveVisual ? IslandMotion.CompactLoadingSpinner.activeShadowOpacity : IslandMotion.CompactLoadingSpinner.inactiveShadowOpacity),
                    radius: 2.2
                )
            if !status.isActiveVisual {
                Circle()
                    .fill(statusColor.opacity(IslandMotion.CompactLoadingSpinner.inactiveDotOpacity))
                    .frame(width: 4.4, height: 4.4)
            }
        }
    }

    private var trimEnd: CGFloat {
        switch status {
        case .thinking:
            return 0.70
        case .runningTool:
            return 0.78
        case .waitingApproval, .waitingQuestion:
            return 0.66
        case .done, .failed:
            return 0.92
        case .idle:
            return 0.58
        }
    }

    private var statusColor: Color {
        switch status {
        case .done:
            return Color.green
        case .failed:
            return Color(red: 1.00, green: 0.30, blue: 0.20)
        case .waitingApproval, .waitingQuestion:
            return Color.orange
        case .thinking, .runningTool:
            return color
        case .idle:
            return Color.black.opacity(0.42)
        }
    }

    private var spinnerStyle: AnyShapeStyle {
        switch status {
        case .thinking, .runningTool, .waitingApproval, .waitingQuestion:
            return AnyShapeStyle(statusColor.opacity(IslandMotion.CompactLoadingSpinner.activeStyleOpacity))
        default:
            return AnyShapeStyle(
                statusColor.opacity(
                    status.isActiveVisual
                    ? IslandMotion.CompactLoadingSpinner.activeStyleOpacity
                    : IslandMotion.CompactLoadingSpinner.inactiveStyleOpacity
                )
            )
        }
    }

    private var spinnerNSColor: NSColor {
        switch status {
        case .done:
            return .systemGreen
        case .failed:
            return .systemRed
        case .waitingApproval, .waitingQuestion:
            return .systemOrange
        case .thinking, .runningTool:
            return nsColor
        case .idle:
            return .tertiaryLabelColor
        }
    }
}

private struct CoreAnimationLoadingSpinner: NSViewRepresentable {
    let color: NSColor
    let trimEnd: CGFloat
    let cycle: TimeInterval

    func makeNSView(context: Context) -> CoreAnimationLoadingSpinnerView {
        CoreAnimationLoadingSpinnerView()
    }

    func updateNSView(_ view: CoreAnimationLoadingSpinnerView, context: Context) {
        view.configure(color: color, trimEnd: trimEnd, cycle: cycle)
    }
}

private final class CoreAnimationLoadingSpinnerView: NSView {
    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()
    private var currentTrimEnd: CGFloat?
    private var currentCycle: TimeInterval?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        [trackLayer, arcLayer].forEach { shapeLayer in
            shapeLayer.fillColor = NSColor.clear.cgColor
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            shapeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(shapeLayer)
        }
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.20).cgColor
        trackLayer.strokeEnd = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updatePath()
    }

    func configure(color: NSColor, trimEnd: CGFloat, cycle: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arcLayer.strokeColor = color.withAlphaComponent(0.90).cgColor
        arcLayer.strokeEnd = trimEnd
        currentTrimEnd = trimEnd
        CATransaction.commit()

        if currentCycle != cycle {
            restartAnimation(cycle: cycle)
            currentCycle = cycle
        }
        updatePath()
    }

    private func updatePath() {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let lineWidth: CGFloat = 2.2
        let rect = CGRect(
            x: (bounds.width - side) / 2 + lineWidth / 2,
            y: (bounds.height - side) / 2 + lineWidth / 2,
            width: side - lineWidth,
            height: side - lineWidth
        )
        let path = CGPath(ellipseIn: rect, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [trackLayer, arcLayer].forEach { shapeLayer in
            shapeLayer.frame = bounds
            shapeLayer.path = path
            shapeLayer.lineWidth = lineWidth
        }
        CATransaction.commit()
    }

    private func restartAnimation(cycle: TimeInterval) {
        arcLayer.removeAnimation(forKey: "rotation")
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = -CGFloat.pi / 2
        animation.toValue = CGFloat.pi * 1.5
        animation.duration = cycle
        animation.repeatCount = .greatestFiniteMagnitude
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        arcLayer.add(animation, forKey: "rotation")
    }
}

struct UsageHeaderView: View {
    let usage: UsageSnapshot

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
            if usage.primaryUsedPercent == nil && usage.secondaryUsedPercent == nil {
                Text("本轮")
                    .foregroundStyle(GlassText.secondary)
                Text(UsageSnapshot.compactNumber(usage.lastTokens))
                    .foregroundStyle(Color(red: 0.22, green: 0.94, blue: 0.42))
                Text("|")
                    .foregroundStyle(GlassText.faint)
                Text("总计")
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
                    HealthCountPill(text: "\(needsActionCount) 需处理", color: .orange)
                } else {
                    HealthCountPill(text: "正常", color: .green)
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
        .help("打开健康检查")
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
        guard !items.isEmpty else { return "健康检查尚未运行" }
        if needsActionCount > 0 {
            return "健康检查：\(needsActionCount) 项需要处理"
        }
        if disabledCount > 0 {
            return "健康检查：\(normalCount) 项正常，\(disabledCount) 项未启用"
        }
        return "健康检查：全部正常"
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
        .help(session.source == .unknown ? "选中会话" : "打开 \(session.source.displayName)")
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
        SessionDisplaySnapshot(session: session)
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
        SessionDisplaySnapshot(session: session)
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
        return sanitized.isEmpty ? "活动" : String(sanitized.prefix(28))
    }
}

struct ApprovalSummaryCard: View {
    @EnvironmentObject private var store: SessionStore
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
                            Text("\(approval.source.shortName) 请求审批")
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
            .help("查看审批详情")

            HStack(spacing: 4) {
                if approval.supports(.accept) {
                    approvalButton(ApprovalDecision.accept.title, .accept, prominent: true)
                }
                if approval.supports(.acceptForSession) {
                    approvalButton("本轮允许", .acceptForSession)
                }
                if approval.supports(.decline) {
                    approvalButton(ApprovalDecision.decline.title, .decline)
                }
                Spacer(minLength: 4)
                Button("详情") {
                    showsDetail = true
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
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
        Button(title) {
            store.resolveApproval(approval, decision: decision)
        }
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
        .buttonStyle(.plain)
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
        formatter.locale = Locale.current
        return formatter.localizedString(for: approval.createdAt, relativeTo: Date())
    }
}

struct ApprovalDetailCard: View {
    @EnvironmentObject private var store: SessionStore
    let session: AgentSession
    let approval: ApprovalRequest
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("\(approval.source.shortName) 审批详情", systemImage: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassText.primary)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DashboardSmallButtonStyle())
                .help("返回摘要")
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
                Text("当前版本无法识别这个审批请求")
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
        Button(decision.title) {
            store.resolveApproval(approval, decision: decision)
        }
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
        .buttonStyle(.plain)
        .disabled(approval.isResolving || approval.isExpired)
    }

    private var workspaceText: String {
        guard let workspace = approval.workspace, !workspace.isEmpty else {
            return "未提供目录"
        }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }

    private var createdText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale.current
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

struct DashboardEmptyCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GlassText.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("等待事件")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassText.primary)
                Text("Claude Code 或 Codex 活动会显示在这里。")
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
    let confidence: DisplayConfidence

    var body: some View {
        Text(confidence.title)
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

struct GlassRefractionHighlights: View {
    let cornerRadius: CGFloat
    let isExpanded: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .stroke(ClearGlass.cyanEdge.opacity(isExpanded ? 0.20 : 0.16), lineWidth: 0.7)
                .offset(x: 0.8, y: 0.8)
                .blendMode(.plusLighter)
            shape
                .stroke(ClearGlass.warmEdge.opacity(isExpanded ? 0.18 : 0.14), lineWidth: 0.7)
                .offset(x: -0.8, y: -0.8)
                .blendMode(.plusLighter)
            VStack(spacing: 0) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isExpanded ? 0.58 : 0.42),
                                Color.white.opacity(0.16),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: isExpanded ? 3.0 : 2.0)
                    .padding(.horizontal, isExpanded ? 58 : 34)
                    .padding(.top, 1.4)
                Spacer(minLength: 0)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                ClearGlass.warmEdge.opacity(isExpanded ? 0.20 : 0.16),
                                ClearGlass.cyanEdge.opacity(isExpanded ? 0.28 : 0.20),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2.2)
                    .padding(.horizontal, isExpanded ? 84 : 42)
                    .padding(.bottom, 1.2)
            }
        }
        .mask(shape)
        .allowsHitTesting(false)
    }
}

struct CompactRGBOuterGlow: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .stroke(rgbGradient, lineWidth: 4.2)
                .blur(radius: 3.2)
                .opacity(0.46)
            shape
                .stroke(rgbGradient, lineWidth: 1.35)
                .opacity(0.88)
            shape
                .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
                .padding(1.2)
        }
        .allowsHitTesting(false)
    }

    private var rgbGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.26, green: 0.62, blue: 1.00),
                Color(red: 0.17, green: 0.95, blue: 0.48),
                Color(red: 0.96, green: 0.86, blue: 0.26),
                Color(red: 1.00, green: 0.45, blue: 0.24),
                Color(red: 0.74, green: 0.34, blue: 1.00),
                Color(red: 0.26, green: 0.62, blue: 1.00)
            ],
            center: .center,
            startAngle: .degrees(12),
            endAngle: .degrees(372)
        )
    }
}

struct ClearGlassRoundedBackground: View {
    let cornerRadius: CGFloat
    var highlighted = false
    var tint: Color = .clear
    var materialOpacity: Double = 0.38

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlighted ? 0.12 : 0.080),
                            ClearGlass.smoke.opacity(highlighted ? 0.30 : 0.22),
                            Color.black.opacity(highlighted ? 0.22 : 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            ClearGlass.topHighlight.opacity(highlighted ? 0.42 : 0.26),
                            Color.white.opacity(0.018),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            ClearGlass.cyanEdge.opacity(highlighted ? 0.16 : 0.090),
                            ClearGlass.violetEdge.opacity(0.034),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 8,
                        endRadius: 150
                    )
                )
                .blendMode(.plusLighter)
            shape
                .fill(tint)
                .blendMode(.plusLighter)
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlighted ? 0.42 : 0.28),
                            ClearGlass.cyanEdge.opacity(highlighted ? 0.24 : 0.16),
                            ClearGlass.warmEdge.opacity(highlighted ? 0.18 : 0.10),
                            Color.white.opacity(highlighted ? 0.13 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: highlighted ? 1.0 : 0.85
                )
            shape
                .stroke(Color.white.opacity(highlighted ? 0.16 : 0.10), lineWidth: 0.55)
                .padding(1)
        }
    }
}

struct ClearGlassCapsuleBackground: View {
    var highlighted = false
    var tint: Color = .clear
    var materialOpacity: Double = 0.32

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(materialOpacity)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlighted ? 0.12 : 0.070),
                            ClearGlass.smoke.opacity(highlighted ? 0.26 : 0.18),
                            Color.black.opacity(highlighted ? 0.18 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Capsule()
                .fill(tint)
                .blendMode(.plusLighter)
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlighted ? 0.36 : 0.24),
                            ClearGlass.cyanEdge.opacity(highlighted ? 0.16 : 0.10),
                            ClearGlass.warmEdge.opacity(highlighted ? 0.14 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }
}

struct DashboardCardBackground: View {
    var highlighted = false
    var tint: Color = .clear

    var body: some View {
        ClearGlassRoundedBackground(
            cornerRadius: 18,
            highlighted: highlighted,
            tint: tint,
            materialOpacity: highlighted ? 0.42 : 0.30
        )
    }
}

struct DashboardRowBackground: View {
    var highlighted = false
    var tint: Color = .clear

    var body: some View {
        ClearGlassRoundedBackground(
            cornerRadius: 14,
            highlighted: highlighted,
            tint: tint,
            materialOpacity: highlighted ? 0.38 : 0.28
        )
    }
}

struct DashboardIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(GlassText.control.opacity(configuration.isPressed ? 0.70 : 1.0))
            .frame(width: 28, height: 28)
            .background(
                ClearGlassRoundedBackground(
                    cornerRadius: 9,
                    highlighted: true,
                    tint: Color.white.opacity(configuration.isPressed ? 0.12 : 0.035),
                    materialOpacity: configuration.isPressed ? 0.48 : 0.34
                )
            )
    }
}

struct DashboardSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(GlassText.control.opacity(configuration.isPressed ? 0.68 : 1.0))
            .frame(width: 23, height: 23)
            .background(
                ClearGlassRoundedBackground(
                    cornerRadius: 8,
                    highlighted: true,
                    tint: Color.white.opacity(configuration.isPressed ? 0.12 : 0.030),
                    materialOpacity: configuration.isPressed ? 0.48 : 0.32
                )
            )
    }
}

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

struct IslandIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(
                ClearGlassRoundedBackground(
                    cornerRadius: 14,
                    highlighted: true,
                    tint: Color.white.opacity(configuration.isPressed ? 0.13 : 0.050),
                    materialOpacity: configuration.isPressed ? 0.48 : 0.32
                )
            )
    }
}

struct GlassPanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        ClearGlassRoundedBackground(
            cornerRadius: cornerRadius,
            highlighted: true,
            tint: ClearGlass.cyanEdge.opacity(0.055),
            materialOpacity: 0.30
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.layer?.masksToBounds = true
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.cornerRadius = cornerRadius
    }
}
