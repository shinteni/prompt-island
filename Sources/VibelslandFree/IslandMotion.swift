import SwiftUI
import VibelslandFreeCore

enum IslandMotion {
    static let expansionSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let contentCrossfade = Animation.easeInOut(duration: IslandMotionPolicy.ContentTransition.crossfadeDuration)

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
