import AppKit
import VibelslandFreeCore
import SwiftUI

enum GlassText {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.70)
    static let tertiary = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.38)
    static let control = Color.white.opacity(0.76)
}

enum ClearGlass {
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
    static let windowScale: CGFloat = IslandPresentationPolicy.windowScale
}

extension AgentSource {
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

/// 胶囊/卡片操作的按压反馈：轻微缩放 + 变淡。Reduce Motion 时不缩放，只保留不透明度变化。
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = IslandMotionPolicy.InteractionFeedback.pressedScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed
                    ? IslandMotionPolicy.InteractionFeedback.pressedScale(pressedScale, reduceMotion: reduceMotion)
                    : 1
            )
            .opacity(configuration.isPressed ? IslandMotionPolicy.InteractionFeedback.pressedOpacity : 1)
            .animation(IslandMotion.pressEase, value: configuration.isPressed)
    }
}

/// 悬停高亮：轻微放大 + 提亮 + 小手光标，让可点元素在悬停时有明确的可点感。
/// Reduce Motion 时跳过缩放，保留提亮与光标。
///
/// 不用 SwiftUI 的 .onHover：它的 tracking area 只在应用激活时生效，而浮岛是
/// 常驻辅助面板，用户悬停时应用几乎总是非激活的。这里用 .activeAlways 的
/// 显式 NSTrackingArea（与浮岛离开自动收起相同的机制）保证任何状态都有反馈。
struct IslandHoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    var scale: CGFloat = IslandMotionPolicy.InteractionFeedback.hoverScale
    var usesPointingHand = true

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering && !reduceMotion ? scale : 1)
            .brightness(isHovering ? IslandMotionPolicy.InteractionFeedback.hoverBrightness : 0)
            .animation(IslandMotion.hoverEase, value: isHovering)
            .overlay(
                AlwaysOnHoverView(usesPointingHand: usesPointingHand) { hovering in
                    isHovering = hovering
                }
            )
            .onDisappear {
                if isHovering {
                    if usesPointingHand {
                        NSCursor.arrow.set()
                    }
                    isHovering = false
                }
            }
    }
}

/// 应用非激活时也能收到进出事件的悬停探测层；对点击完全透明。
private struct AlwaysOnHoverView: NSViewRepresentable {
    let usesPointingHand: Bool
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.usesPointingHand = usesPointingHand
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.usesPointingHand = usesPointingHand
        view.onHoverChanged = onHoverChanged
    }

    final class TrackingView: NSView {
        var usesPointingHand = true
        var onHoverChanged: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        // 悬停探测不拦截任何鼠标事件，点击照常落到下面的按钮/手势上。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
            if usesPointingHand {
                NSCursor.pointingHand.set()
            }
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
            if usesPointingHand {
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func islandHoverHighlight(
        scale: CGFloat = IslandMotionPolicy.InteractionFeedback.hoverScale,
        usesPointingHand: Bool = true
    ) -> some View {
        modifier(IslandHoverHighlight(scale: scale, usesPointingHand: usesPointingHand))
    }
}

struct DashboardIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(
                configuration.isPressed
                    ? IslandMotionPolicy.InteractionFeedback.pressedScale(reduceMotion: reduceMotion)
                    : 1
            )
            .animation(IslandMotion.pressEase, value: configuration.isPressed)
    }
}

struct DashboardSmallButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(
                configuration.isPressed
                    ? IslandMotionPolicy.InteractionFeedback.pressedScale(reduceMotion: reduceMotion)
                    : 1
            )
            .animation(IslandMotion.pressEase, value: configuration.isPressed)
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
