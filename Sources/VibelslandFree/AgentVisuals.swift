import AppKit
import VibelslandFreeCore
import SwiftUI

struct AgentSourceIconView: View {
    let source: AgentSource
    var size: CGFloat
    var status: SessionStatus? = nil
    var showsStatus = true
    var contentPaddingRatio: CGFloat = 0.08
    var iconBackgroundOpacity: Double = 0.08
    var strokeOpacity: Double = 0.20
    var shadowOpacity: Double = 0.22
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 3
    var imageScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            iconBody
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                )
                .shadow(color: source.color.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)

            if showsStatus, let status {
                StatusPixelBadge(status: status, color: source.color)
                    .offset(x: size * 0.10, y: size * 0.10)
            }
        }
        .accessibilityLabel(source.displayName)
    }

    @ViewBuilder
    private var iconBody: some View {
        if let image = AgentAppIconProvider.shared.icon(for: source) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * contentPaddingRatio)
                .background(Color.white.opacity(iconBackgroundOpacity))
                .scaleEffect(imageScale)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            source.color.opacity(0.92),
                            source.color.opacity(0.44)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: source == .unknown ? "sparkles" : "app.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                )
        }
    }
}

struct AgentIconStack: View {
    let sources: [AgentSource]
    let statuses: [AgentSource: SessionStatus]
    var isExpanded: Bool

    var body: some View {
        HStack(spacing: isExpanded ? -5 : -6) {
            ForEach(Array(sources.prefix(3)), id: \.self) { source in
                AgentSourceIconView(
                    source: source,
                    size: isExpanded ? 23 : 18,
                    status: statuses[source],
                    showsStatus: false
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 6 : 5, style: .continuous)
                        .stroke(.black.opacity(0.34), lineWidth: 1)
                )
            }
        }
    }
}

struct StatusPixelBadge: View {
    let status: SessionStatus
    let color: Color

    var body: some View {
        PixelBlinker(color: badgeColor, isActive: status.isActiveVisual)
            .frame(width: 11, height: 11)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            )
    }

    private var badgeColor: Color {
        switch status {
        case .done:
            return .green
        case .failed:
            return .red
        case .waitingApproval, .waitingQuestion:
            return .orange
        case .runningTool, .thinking:
            return color
        case .idle:
            return .gray
        }
    }
}

struct PixelBlinker: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        if isActive {
            TimelineView(.animation(minimumInterval: 0.28)) { context in
                pixels(pulse: (sin(context.date.timeIntervalSinceReferenceDate * 5.2) + 1) / 2)
            }
        } else {
            pixels(pulse: 0.35)
        }
    }

    private func pixels(pulse: Double) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<2, id: \.self) { column in
                VStack(spacing: 1.5) {
                    ForEach(0..<2, id: \.self) { row in
                        Rectangle()
                            .fill(color.opacity(opacity(row: row, column: column, pulse: pulse)))
                    }
                }
            }
        }
        .padding(2)
    }

    private func opacity(row: Int, column: Int, pulse: Double) -> Double {
        guard isActive else { return 0.62 }
        let offset = Double(row + column) * 0.18
        return min(1.0, 0.38 + pulse * 0.56 + offset)
    }
}

struct PixelActivityStrip: View {
    let status: SessionStatus
    let color: Color
    var density: Int = 22
    var recentActivityDate: Date?
    var activityRate = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let recentPulse = recentPulse(at: context.date)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<density, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color.opacity(pixelOpacity(index: index, time: time, recentPulse: recentPulse)))
                        .frame(width: pixelWidth(index: index), height: pixelHeight(index: index, time: time, recentPulse: recentPulse))
                }
            }
            .drawingGroup()
        }
        .opacity(status == .idle ? 0.18 : 0.88)
    }

    private func pixelHeight(index: Int, time: TimeInterval, recentPulse: Double) -> CGFloat {
        if !status.isActiveVisual {
            return index % 4 == 0 ? 8 : 4
        }
        let wave = sin(time * speed + Double(index) * 0.72)
        let beat = sin(time * beatSpeed + Double(index + activityRate) * 1.15)
        let stepped = Int((wave + 1) * 2.5)
        let beatBoost = max(0, beat) * recentPulse * 8
        return CGFloat(4 + stepped * 3) + beatBoost
    }

    private func pixelWidth(index: Int) -> CGFloat {
        index % 5 == 0 ? 4 : 3
    }

    private func pixelOpacity(index: Int, time: TimeInterval, recentPulse: Double) -> Double {
        if status == .done {
            return index % 3 == 0 ? 0.36 : 0.18
        }
        if status == .failed {
            return index % 2 == 0 ? 0.72 : 0.28
        }
        if !status.isActiveVisual {
            return 0.24
        }
        let wave = (sin(time * speed + Double(index) * 0.6) + 1) / 2
        let activityFlash = ((index + activityRate) % 5 == 0 ? recentPulse * 0.34 : 0)
        return min(0.92, 0.16 + wave * 0.56 + activityFlash)
    }

    private var speed: Double {
        let boost = min(Double(activityRate), 8) * 0.42
        switch status {
        case .waitingApproval, .waitingQuestion:
            return 6.0
        case .runningTool:
            return 8.5 + boost
        case .thinking:
            return 4.2 + boost * 0.45
        default:
            return 1.0
        }
    }

    private var beatSpeed: Double {
        10.0 + min(Double(activityRate), 8) * 1.1
    }

    private func recentPulse(at date: Date) -> Double {
        guard let recentActivityDate else { return 0 }
        let elapsed = date.timeIntervalSince(recentActivityDate)
        guard elapsed >= 0, elapsed < 2.0 else { return 0 }
        return 1 - elapsed / 2.0
    }
}

struct PixelAmbientField: View {
    let color: Color
    let status: SessionStatus

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 0.32)) { context in
                let columns = max(1, Int(proxy.size.width / 18))
                let rows = max(1, Int(proxy.size.height / 16))
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<(columns * rows), id: \.self) { index in
                        let column = index % columns
                        let row = index / columns
                        Rectangle()
                            .fill(color.opacity(dotOpacity(index: index, time: time)))
                            .frame(width: 3, height: 3)
                            .position(
                                x: CGFloat(column) * 18 + 8,
                                y: CGFloat(row) * 16 + 8
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(status.isActiveVisual ? 0.28 : 0.12)
    }

    private func dotOpacity(index: Int, time: TimeInterval) -> Double {
        let base = status.isActiveVisual ? 0.16 : 0.08
        let phase = sin(time * 2.4 + Double(index % 7) * 0.8)
        return max(0, base + phase * 0.12)
    }
}

struct StatusGlowBorder: View {
    let status: SessionStatus
    let accentColor: Color
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.2
    var glowRadius: CGFloat = 7
    var intensity: Double = 1.0

    var body: some View {
        ZStack {
            stroke(width: lineWidth + 2.2)
                .blur(radius: glowRadius)
                .opacity(glowOpacity)
            stroke(width: lineWidth)
                .opacity(strokeOpacity)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func stroke(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch status {
        case .thinking, .runningTool:
            shape.strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.28, green: 0.62, blue: 1.00),
                        Color(red: 0.18, green: 0.96, blue: 0.42),
                        Color(red: 1.00, green: 0.86, blue: 0.28),
                        Color(red: 1.00, green: 0.22, blue: 0.34),
                        Color(red: 0.70, green: 0.36, blue: 1.00),
                        Color(red: 0.28, green: 0.62, blue: 1.00)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: width
            )
        case .waitingApproval, .waitingQuestion:
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.98),
                        Color.yellow.opacity(0.72),
                        Color.orange.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: width
            )
        case .done:
            shape.strokeBorder(Color.green.opacity(0.82), lineWidth: width)
        case .failed:
            shape.strokeBorder(Color.orange.opacity(0.90), lineWidth: width)
        case .idle:
            shape.strokeBorder(accentColor.opacity(0.28), lineWidth: width)
        }
    }

    private var glowOpacity: Double {
        switch status {
        case .thinking, .runningTool:
            return 0.22 * intensity
        case .waitingApproval, .waitingQuestion:
            return 0.30 * intensity
        case .done:
            return 0.24 * intensity
        case .failed:
            return 0.30 * intensity
        case .idle:
            return 0.06 * intensity
        }
    }

    private var strokeOpacity: Double {
        switch status {
        case .thinking, .runningTool:
            return 0.74 * intensity
        case .waitingApproval, .waitingQuestion:
            return 0.74 * intensity
        case .done:
            return 0.72 * intensity
        case .failed:
            return 0.76 * intensity
        case .idle:
            return 0.24 * intensity
        }
    }
}

struct EdgeSweepHighlight: View {
    let status: SessionStatus
    let color: Color
    let cornerRadius: CGFloat
    let startedAt: Date?
    var duration: TimeInterval = 1.15
    var lineWidth: CGFloat = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { context in
            if let progress = progress(at: context.date) {
                sweep(progress: progress)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sweep(progress: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let start = max(0, progress - 0.10)
        let end = min(1, progress + 0.22)
        ZStack {
            shape
                .trim(from: start, to: end)
                .stroke(
                    sweepGradient,
                    style: StrokeStyle(lineWidth: lineWidth + 3, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: 3)
                .opacity(0.24 * (1 - progress))
            shape
                .trim(from: start, to: end)
                .stroke(
                    sweepGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .opacity(0.82 * (1 - progress * 0.35))
        }
    }

    private var sweepGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.92),
                color.opacity(0.88),
                Color.white.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func progress(at date: Date) -> Double? {
        guard status.isActiveVisual, let startedAt else { return nil }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0, elapsed <= duration else { return nil }
        return elapsed / duration
    }
}

struct TerminalPulseRing: View {
    let status: SessionStatus
    let color: Color
    let cornerRadius: CGFloat
    let finishedAt: Date?
    var duration: TimeInterval = 1.25
    @State private var progress = 1.0
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if visible {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(pulseColor.opacity(0.72 * (1 - progress)), lineWidth: 2)
                    .blur(radius: 0.4 + progress * 3)
                    .scaleEffect(1 + progress * 0.065)
                    .opacity(1 - progress)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
        .onAppear(perform: restart)
        .onChange(of: status) { _, _ in
            restart()
        }
        .onChange(of: finishedAt) { _, _ in
            restart()
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private var pulseColor: Color {
        switch status {
        case .done:
            return .green
        case .failed:
            return .orange
        default:
            return color
        }
    }

    private func restart() {
        hideTask?.cancel()
        guard status == .done || status == .failed,
              let finishedAt,
              Date().timeIntervalSince(finishedAt) <= duration else {
            visible = false
            progress = 1
            return
        }
        progress = 0
        visible = true
        withAnimation(.linear(duration: duration)) {
            progress = 1
        }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                visible = false
                progress = 1
            }
        }
    }
}

@MainActor
private final class AgentAppIconProvider {
    static let shared = AgentAppIconProvider()
    private var cache: [AgentSource: NSImage] = [:]

    func icon(for source: AgentSource) -> NSImage? {
        if let cached = cache[source] {
            return cached
        }

        guard let url = applicationURL(for: source) else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        cache[source] = image
        return image
    }

    private func applicationURL(for source: AgentSource) -> URL? {
        if let bundleID = source.applicationBundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        if let path = source.fallbackApplicationPath,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
