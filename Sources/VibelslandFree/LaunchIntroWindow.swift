import AppKit
import VibelslandFreeCore

@MainActor
final class LaunchIntroWindow: NSPanel {
    private weak var store: SessionStore?
    private let onComplete: () -> Void
    private let introView: BlackPillIntroView
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0
    private var didPlaySound = false
    private var didComplete = false
    private let duration: CFTimeInterval = 2.20

    init(finalFrame: NSRect, store: SessionStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
        let introFrame = Self.introFrame(for: finalFrame)
        introView = BlackPillIntroView(
            targetFrame: Self.localTargetFrame(finalFrame, in: introFrame)
        )

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
        timer?.invalidate()
        didPlaySound = false
        didComplete = false
        startedAt = CACurrentMediaTime()
        alphaValue = 1
        introView.progress = 0.001
        orderFrontRegardless()
        displayIfNeeded()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
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
        timer?.invalidate()
        timer = nil
        orderOut(nil)
        onComplete()
    }

    private func playLaunchSound() {
        guard let store,
              store.configurationStore.config.enableSounds,
              !store.configurationStore.config.doNotDisturb else { return }
        RetroSoundPlayer.shared.play(.launch, theme: store.configurationStore.config.soundTheme)
    }

    private static func introFrame(for finalFrame: NSRect) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        return screenFrame
    }

    private static func localTargetFrame(_ finalFrame: NSRect, in introFrame: NSRect) -> NSRect {
        NSRect(
            x: finalFrame.minX - introFrame.minX,
            y: finalFrame.minY - introFrame.minY,
            width: finalFrame.width,
            height: finalFrame.height
        )
    }
}

private final class BlackPillIntroView: NSView {
    var progress: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    private let targetFrame: NSRect

    override var isOpaque: Bool { false }

    init(targetFrame: NSRect) {
        self.targetFrame = targetFrame
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let p = min(max(progress, 0), 1)
        let grow = easeInOutCubic(min(p / 0.72, 1))
        let fade = p > 0.88 ? 1 - smoothStep(min(max((p - 0.88) / 0.12, 0), 1)) : 1
        let alpha = max(0, fade)
        guard alpha > 0 else { return }

        let startDiameter: CGFloat = 8
        let targetWidth = min(max(targetFrame.width, 220), bounds.width - 64)
        let targetHeight = min(max(targetFrame.height, 42), 66)
        let width = startDiameter + (targetWidth - startDiameter) * grow
        let height = startDiameter + (targetHeight - startDiameter) * grow
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )

        context.saveGState()
        context.setAlpha(alpha)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28 * alpha)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()

        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        pillGradient.draw(in: path, angle: -90)

        if grow > 0.34 {
            let highlightAlpha = min((grow - 0.34) / 0.34, 1) * 0.18 * alpha
            let highlightRect = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.28)
            let highlight = NSBezierPath()
            highlight.move(to: CGPoint(x: highlightRect.minX, y: highlightRect.midY + 2))
            highlight.curve(
                to: CGPoint(x: highlightRect.maxX, y: highlightRect.midY + 2),
                controlPoint1: CGPoint(x: highlightRect.minX + highlightRect.width * 0.34, y: highlightRect.maxY),
                controlPoint2: CGPoint(x: highlightRect.minX + highlightRect.width * 0.64, y: highlightRect.minY)
            )
            NSColor.white.withAlphaComponent(highlightAlpha).setStroke()
            highlight.lineWidth = 2.4
            highlight.stroke()
        }
        context.restoreGState()
    }

    private var pillGradient: NSGradient {
        NSGradient(colors: [
            NSColor(calibratedRed: 0.015, green: 0.017, blue: 0.020, alpha: 1),
            NSColor(calibratedRed: 0.065, green: 0.070, blue: 0.078, alpha: 1),
            NSColor(calibratedRed: 0.010, green: 0.012, blue: 0.014, alpha: 1)
        ]) ?? NSGradient(starting: .black, ending: .darkGray)!
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
