import AppKit
import QuartzCore
import VibelslandFreeCore

@MainActor
final class LaunchIntroWindow: NSPanel {
    private weak var store: SessionStore?
    private let onComplete: () -> Void
    private let introView: BlackPillIntroView
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var didPlaySound = false
    private var didComplete = false
    private let duration: CFTimeInterval = 2.20

    /// 阴影 blur 18 + 偏移 5，四周留足边距，避免图层阴影被窗口裁剪。
    private static let shadowMargin: CGFloat = 48

    init(finalFrame: NSRect, store: SessionStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
        let screenFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        // 目标药丸尺寸与旧实现一致的钳制规则。
        let targetSize = CGSize(
            width: min(max(finalFrame.width, 220), screenFrame.width - 64),
            height: min(max(finalFrame.height, 42), 66)
        )
        // 旧实现开整屏窗口每帧 CPU 重绘；现在窗口只包住药丸+阴影边距，
        // backing store 缩小两个数量级。
        let windowSize = CGSize(
            width: targetSize.width + Self.shadowMargin * 2,
            height: targetSize.height + Self.shadowMargin * 2
        )
        let introFrame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
        introView = BlackPillIntroView(targetSize: targetSize)

        super.init(
            contentRect: introFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        title = "Vibelsland Launch Intro"
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        introView.frame = NSRect(origin: .zero, size: introFrame.size)
        introView.autoresizingMask = [.width, .height]
        contentView = introView
    }

    func start() {
        displayLink?.invalidate()
        didPlaySound = false
        didComplete = false
        // 首次播放的波形生成与音频引擎初始化提前完成，动画中途不再卡顿。
        if let store,
           store.configurationStore.config.enableSounds,
           !store.configurationStore.config.doNotDisturb {
            RetroSoundPlayer.shared.prepare(.launch, theme: store.configurationStore.config.soundTheme)
        }
        startedAt = CACurrentMediaTime()
        alphaValue = 1
        introView.progress = 0.001
        orderFrontRegardless()
        displayIfNeeded()

        // 跟随显示器刷新率、无并发跳板的直接回调，替代旧的 60Hz Timer + Task。
        let link = introView.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard !didComplete else { return }
        let elapsed = CACurrentMediaTime() - startedAt
        if elapsed >= 0.42, !didPlaySound {
            didPlaySound = true
            playLaunchSound()
        }

        let rawProgress = min(max(elapsed / duration, 0), 1)
        introView.progress = CGFloat(rawProgress)
        if rawProgress >= 1 {
            finish()
        }
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        displayLink?.invalidate()
        displayLink = nil
        orderOut(nil)
        onComplete()
    }

    private func playLaunchSound() {
        guard let store,
              store.configurationStore.config.enableSounds,
              !store.configurationStore.config.doNotDisturb else { return }
        RetroSoundPlayer.shared.play(.launch, theme: store.configurationStore.config.soundTheme)
    }
}

/// 药丸开场：GPU 合成的 Core Animation 图层，替代旧的整屏 CPU draw(_:)。
/// 阴影由带 shadowPath 的容器层渲染，渐变在子层内圆角裁剪，每帧只改
/// 图层几何属性（禁用隐式动画），不再触发位图重绘。
private final class BlackPillIntroView: NSView {
    var progress: CGFloat = 0 {
        didSet {
            render()
        }
    }

    private let targetSize: CGSize
    private let pillContainer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let highlightLayer = CAShapeLayer()

    override var isOpaque: Bool { false }

    init(targetSize: CGSize) {
        self.targetSize = targetSize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        pillContainer.shadowColor = NSColor.black.cgColor
        pillContainer.shadowRadius = 18
        pillContainer.shadowOffset = CGSize(width: 0, height: -5)
        pillContainer.shadowOpacity = 0

        // 与旧 NSGradient(angle: -90) 相同：颜色从上往下。
        gradientLayer.colors = [
            NSColor(calibratedRed: 0.015, green: 0.017, blue: 0.020, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.065, green: 0.070, blue: 0.078, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.010, green: 0.012, blue: 0.014, alpha: 1).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.masksToBounds = true

        highlightLayer.fillColor = nil
        highlightLayer.strokeColor = NSColor.white.cgColor
        highlightLayer.lineWidth = 2.4
        highlightLayer.lineCap = .round
        highlightLayer.opacity = 0

        pillContainer.addSublayer(gradientLayer)
        gradientLayer.addSublayer(highlightLayer)
        layer?.addSublayer(pillContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func render() {
        let p = min(max(progress, 0), 1)
        let grow = easeInOutCubic(min(p / 0.72, 1))
        let fade = p > 0.88 ? 1 - smoothStep(min(max((p - 0.88) / 0.12, 0), 1)) : 1
        let alpha = max(0, fade)

        let startDiameter: CGFloat = 8
        let width = startDiameter + (targetSize.width - startDiameter) * grow
        let height = startDiameter + (targetSize.height - startDiameter) * grow
        let rect = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        pillContainer.frame = rect
        pillContainer.shadowOpacity = Float(0.28 * alpha)
        pillContainer.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: rect.size),
            cornerWidth: height / 2,
            cornerHeight: height / 2,
            transform: nil
        )
        pillContainer.opacity = Float(alpha)

        gradientLayer.frame = CGRect(origin: .zero, size: rect.size)
        gradientLayer.cornerRadius = height / 2

        if grow > 0.34 {
            let highlightAlpha = min((grow - 0.34) / 0.34, 1) * 0.18
            let highlightRect = CGRect(origin: .zero, size: rect.size)
                .insetBy(dx: rect.width * 0.18, dy: rect.height * 0.28)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: highlightRect.minX, y: highlightRect.midY + 2))
            path.addCurve(
                to: CGPoint(x: highlightRect.maxX, y: highlightRect.midY + 2),
                control1: CGPoint(x: highlightRect.minX + highlightRect.width * 0.34, y: highlightRect.maxY),
                control2: CGPoint(x: highlightRect.minX + highlightRect.width * 0.64, y: highlightRect.minY)
            )
            highlightLayer.frame = CGRect(origin: .zero, size: rect.size)
            highlightLayer.path = path
            highlightLayer.opacity = Float(highlightAlpha)
        } else {
            highlightLayer.opacity = 0
        }

        CATransaction.commit()
    }

    private func easeInOutCubic(_ value: CGFloat) -> CGFloat {
        let x = min(max(value, 0), 1)
        if x < 0.5 {
            return 4 * x * x * x
        }
        return 1 - pow(-2 * x + 2, 3) / 2
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
