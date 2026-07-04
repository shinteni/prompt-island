import CoreGraphics
import Foundation

package enum IslandMotionPolicy {
    package enum MiniProgressRing {
        package static func refreshInterval(for status: SessionStatus) -> TimeInterval {
            status.isActiveVisual ? (1.0 / 60.0) : 1.0
        }

        package static func rotationCycle(for status: SessionStatus) -> TimeInterval {
            status == .runningTool ? 3.4 : 4.2
        }

        package static func rotationDegrees(time: TimeInterval, status: SessionStatus) -> Double {
            guard status.isActiveVisual else { return 0 }
            let cycle = rotationCycle(for: status)
            return (time.truncatingRemainder(dividingBy: cycle) / cycle) * 360
        }
    }

    package enum BreathingLights {
        package static let dotCount = 12
        package static let dotPhaseStep = 0.72
        package static let dotBaseSize: CGFloat = 1.7
        package static let dotPulseSize: CGFloat = 1.25

        package static func refreshInterval(for status: SessionStatus) -> TimeInterval {
            status.isActiveVisual ? (1.0 / 30.0) : 0.35
        }

        package static func shouldAnimate(for status: SessionStatus) -> Bool {
            status.isActiveVisual
        }

        package static func pulseSpeed(for status: SessionStatus) -> Double {
            switch status {
            case .idle:
                return 1.45
            case .thinking, .runningTool:
                return 3.20
            case .waitingApproval, .waitingQuestion:
                return 2.65
            case .done:
                return 1.15
            case .failed:
                return 2.35
            }
        }

        package static func opacity(for pulse: Double, status: SessionStatus) -> Double {
            switch status {
            case .idle:
                return 0.18 + pulse * 0.34
            case .done:
                return 0.22 + pulse * 0.36
            case .failed, .waitingApproval, .waitingQuestion:
                return 0.30 + pulse * 0.48
            case .thinking, .runningTool:
                return 0.26 + pulse * 0.50
            }
        }

        package static func shadowOpacity(for pulse: Double, status: SessionStatus) -> Double {
            switch status {
            case .idle:
                return 0.08 + pulse * 0.20
            case .done:
                return 0.14 + pulse * 0.22
            case .failed, .waitingApproval, .waitingQuestion:
                return 0.22 + pulse * 0.34
            case .thinking, .runningTool:
                return 0.20 + pulse * 0.36
            }
        }
    }

    package enum CompactLoadingSpinner {
        package static let activeShadowOpacity = 0.16
        package static let inactiveShadowOpacity = 0.14
        package static let inactiveDotOpacity = 0.82
        package static let activeStyleOpacity = 0.90
        package static let inactiveStyleOpacity = 0.72

        package static func rotationCycle(for status: SessionStatus) -> TimeInterval {
            switch status {
            case .runningTool:
                return 4.2
            case .thinking:
                return 4.8
            case .waitingApproval, .waitingQuestion:
                return 5.2
            default:
                return 4.6
            }
        }
    }

    package enum WindowTransition {
        package static let expansionDuration: TimeInterval = 0.32
        package static let collapseDuration: TimeInterval = 0.42
        package static let resetPadding: TimeInterval = 0.10

        package static func duration(expanded: Bool) -> TimeInterval {
            expanded ? expansionDuration : collapseDuration
        }

        /// 尊重系统「减弱动态效果」：直接落到目标帧，不做过渡。
        package static func duration(expanded: Bool, reduceMotion: Bool) -> TimeInterval {
            reduceMotion ? 0 : duration(expanded: expanded)
        }

        package static func resetDelay(expanded: Bool) -> UInt64 {
            UInt64((duration(expanded: expanded) + resetPadding) * 1_000_000_000)
        }

        /// 帧动画缓动。展开用 ease-out-cubic：起步快（跟手感），落定柔和；
        /// 收起保留 smoothstep 的对称节奏，避免收起显得急促。
        package static func easedProgress(_ progress: Double, expanded: Bool) -> Double {
            let t = min(max(progress, 0), 1)
            if expanded {
                let inverse = 1 - t
                return 1 - inverse * inverse * inverse
            }
            return t * t * (3 - 2 * t)
        }
    }

    package enum ContentTransition {
        package static let crossfadeDuration: TimeInterval = 0.18
        /// 交叉淡化时给两层内容一点纵深缩放，让展开/收起读作「形变」而非「替换」。
        package static let expandedLayerInitialScale: CGFloat = 0.98
        package static let compactLayerLiftedScale: CGFloat = 1.03

        package static func crossfadeDuration(reduceMotion: Bool) -> TimeInterval {
            reduceMotion ? 0 : crossfadeDuration
        }
    }

    package enum InteractionFeedback {
        package static let hoverScale: CGFloat = 1.015
        package static let pressedScale: CGFloat = 0.97
        package static let cardPressedScale: CGFloat = 0.985
        package static let hoverBrightness: Double = 0.05
        package static let pressedOpacity: Double = 0.86
        package static let hoverDuration: TimeInterval = 0.12
        package static let pressDuration: TimeInterval = 0.10

        /// Reduce Motion 下不做几何缩放，只保留亮度/不透明度反馈。
        package static func hoverScale(reduceMotion: Bool) -> CGFloat {
            reduceMotion ? 1 : hoverScale
        }

        package static func pressedScale(_ scale: CGFloat = pressedScale, reduceMotion: Bool) -> CGFloat {
            reduceMotion ? 1 : scale
        }
    }
}
