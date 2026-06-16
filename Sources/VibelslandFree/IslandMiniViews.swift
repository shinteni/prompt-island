import AppKit
import VibelslandFreeCore
import SwiftUI

struct IdleMiniContent: View {
    let status: SessionStatus
    let accentColor: Color
    let language: AppLanguage

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
        .accessibilityLabel(">_ - island \(status.displayName(language: language))")
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
    let language: AppLanguage

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
        .accessibilityLabel(status.isActiveVisual ? loadingText : status.displayName(language: language))
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

    private var loadingText: String {
        AppText.pick(language, english: "Loading", japanese: "読み込み中", chinese: "加载中")
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
