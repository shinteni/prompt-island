import SwiftUI
import VibelslandFreeCore

enum IslandMotion {
    static let contentCrossfade = Animation.easeInOut(duration: IslandMotionPolicy.ContentTransition.crossfadeDuration)

    /// Reduce Motion 时返回 nil（不做动画，直接切换）。
    static func contentCrossfade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : contentCrossfade
    }

    /// 审批卡片进出场：轻快弹簧，落定不晃。
    static let approvalCardSpring = Animation.spring(response: 0.34, dampingFraction: 0.84)

    static func approvalCardSpring(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : approvalCardSpring
    }

    static let hoverEase = Animation.easeOut(duration: IslandMotionPolicy.InteractionFeedback.hoverDuration)
    static let pressEase = Animation.easeOut(duration: IslandMotionPolicy.InteractionFeedback.pressDuration)

    enum MiniProgressRing {
        static func refreshInterval(for status: SessionStatus) -> TimeInterval {
            IslandMotionPolicy.MiniProgressRing.refreshInterval(for: status)
        }

        static func rotationCycle(for status: SessionStatus) -> TimeInterval {
            IslandMotionPolicy.MiniProgressRing.rotationCycle(for: status)
        }

        static func rotationDegrees(time: TimeInterval, status: SessionStatus) -> Double {
            IslandMotionPolicy.MiniProgressRing.rotationDegrees(time: time, status: status)
        }
    }

    enum BreathingLights {
        static let dotCount = IslandMotionPolicy.BreathingLights.dotCount
        static let dotPhaseStep = IslandMotionPolicy.BreathingLights.dotPhaseStep
        static let dotBaseSize = IslandMotionPolicy.BreathingLights.dotBaseSize
        static let dotPulseSize = IslandMotionPolicy.BreathingLights.dotPulseSize

        static func refreshInterval(for status: SessionStatus) -> TimeInterval {
            IslandMotionPolicy.BreathingLights.refreshInterval(for: status)
        }

        static func shouldAnimate(for status: SessionStatus) -> Bool {
            IslandMotionPolicy.BreathingLights.shouldAnimate(for: status)
        }

        static func pulseSpeed(for status: SessionStatus) -> Double {
            IslandMotionPolicy.BreathingLights.pulseSpeed(for: status)
        }

        static func opacity(for pulse: Double, status: SessionStatus) -> Double {
            IslandMotionPolicy.BreathingLights.opacity(for: pulse, status: status)
        }

        static func shadowOpacity(for pulse: Double, status: SessionStatus) -> Double {
            IslandMotionPolicy.BreathingLights.shadowOpacity(for: pulse, status: status)
        }
    }

    enum CompactLoadingSpinner {
        static let activeShadowOpacity = IslandMotionPolicy.CompactLoadingSpinner.activeShadowOpacity
        static let inactiveShadowOpacity = IslandMotionPolicy.CompactLoadingSpinner.inactiveShadowOpacity
        static let inactiveDotOpacity = IslandMotionPolicy.CompactLoadingSpinner.inactiveDotOpacity
        static let activeStyleOpacity = IslandMotionPolicy.CompactLoadingSpinner.activeStyleOpacity
        static let inactiveStyleOpacity = IslandMotionPolicy.CompactLoadingSpinner.inactiveStyleOpacity

        static func rotationCycle(for status: SessionStatus) -> TimeInterval {
            IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: status)
        }
    }
}
