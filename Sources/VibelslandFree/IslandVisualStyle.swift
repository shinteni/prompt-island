import AppKit
import VibelslandFreeCore
import SwiftUI

enum GlassText {
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.68)
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
    var progressRingColors: [NSColor] {
        switch self {
        case .claudeCode:
            return [NSColor(red: 0.98, green: 0.43, blue: 0.20, alpha: 1),
                    NSColor(red: 1.00, green: 0.67, blue: 0.37, alpha: 1)]
        case .codexCli, .codexDesktop:
            return [NSColor(red: 0.34, green: 0.58, blue: 1.00, alpha: 1),
                    NSColor(red: 0.66, green: 0.39, blue: 1.00, alpha: 1)]
        case .unknown:
            return [.lightGray, .gray]
        }
    }

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

// A single material belongs to the window. Cards use static gradient fills.
struct ClearGlassRoundedBackground: View {
    let cornerRadius: CGFloat
    var highlighted = false
    var tint: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(
                colors: [
                    .white.opacity(highlighted ? 0.085 : 0.04),
                    .white.opacity(highlighted ? 0.035 : 0.018)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(highlighted ? 0.13 : 0.065), lineWidth: 0.75)
            }
    }
}

struct ClearGlassCapsuleBackground: View {
    var highlighted = false
    var tint: Color = .clear

    var body: some View {
        Capsule()
            .fill(highlighted ? Color.white.opacity(0.92) : Color.white.opacity(0.065))
            .overlay { Capsule().fill(tint) }
            .overlay { Capsule().strokeBorder(Color.white.opacity(highlighted ? 0 : 0.08), lineWidth: 0.75) }
    }
}

struct DashboardCardBackground: View {
    var highlighted = false
    var tint: Color = .clear

    var body: some View {
        ClearGlassRoundedBackground(
            cornerRadius: 18,
            highlighted: highlighted,
            tint: tint
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
            tint: tint
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(GlassText.control.opacity(configuration.isPressed ? 0.70 : 1.0))
            .frame(width: 28, height: 28)
            .background(
                ClearGlassRoundedBackground(
                    cornerRadius: 9,
                    highlighted: configuration.isPressed,
                    tint: .clear
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
                    tint: Color.white.opacity(configuration.isPressed ? 0.12 : 0.030)
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
                    tint: Color.white.opacity(configuration.isPressed ? 0.13 : 0.050)
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
            tint: ClearGlass.cyanEdge.opacity(0.055)
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
