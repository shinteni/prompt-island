import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct IslandMotionFeedbackTests {
    @Test func springSettlesAtItsTarget() {
        let motion = IslandMotionPolicy.WindowTransition.self
        #expect(motion.sample(start: 10, target: 100, elapsed: 0, duration: 0.32).value == 10)
        #expect(motion.sample(start: 10, target: 100, elapsed: 0.32, duration: 0.32).value == 100)
        #expect(motion.sample(start: 10, target: 100, elapsed: 0, duration: 0).value == 100)
    }

    @Test func springFromRestDoesNotOvershoot() {
        for target in [100.0, -100.0] {
            var previous = 0.0
            for step in 0...32 {
                let value = IslandMotionPolicy.WindowTransition.sample(start: 0, target: target,
                    elapsed: Double(step) / 100, duration: 0.32).value
                #expect(abs(value) >= abs(previous))
                #expect(abs(value) <= abs(target))
                previous = value
            }
        }
    }

    @Test func reversingMidFlightPreservesPositionAndVelocity() {
        let motion = IslandMotionPolicy.WindowTransition.self
        let before = motion.sample(start: 240, target: 496, elapsed: 0.08, duration: 0.32)
        let reversed = motion.sample(start: before.value, target: 240, velocity: before.velocity,
                                     elapsed: 0, duration: 0.42)
        #expect(abs(reversed.value - before.value) < 0.0001)
        #expect(abs(reversed.velocity - before.velocity) < 0.0001)
        #expect(motion.sample(start: before.value, target: 240, velocity: before.velocity,
                              elapsed: 0.42, duration: 0.42).value == 240)
    }

    @Test func testReduceMotionCollapsesDurationsToZero() {
        XCTAssertEqual(
            IslandMotionPolicy.WindowTransition.duration(expanded: true, reduceMotion: true),
            0,
            "Reduce Motion skips the expansion animation"
        )
        XCTAssertEqual(
            IslandMotionPolicy.WindowTransition.duration(expanded: false, reduceMotion: true),
            0,
            "Reduce Motion skips the collapse animation"
        )
        XCTAssertEqual(
            IslandMotionPolicy.WindowTransition.duration(expanded: true, reduceMotion: false),
            IslandMotionPolicy.WindowTransition.expansionDuration,
            "Normal mode keeps the expansion duration"
        )
        XCTAssertEqual(
            IslandMotionPolicy.ContentTransition.crossfadeDuration(reduceMotion: true),
            0,
            "Reduce Motion skips the content crossfade"
        )
    }

    @Test func testInteractionFeedbackConstantsAreSane() {
        let feedback = IslandMotionPolicy.InteractionFeedback.self
        XCTAssertTrue(feedback.pressedScale < 1, "Pressed state shrinks slightly")
        XCTAssertTrue(feedback.cardPressedScale < 1, "Card pressed state shrinks slightly")
        XCTAssertTrue(feedback.hoverScale > 1, "Hover state grows slightly")
        XCTAssertTrue(feedback.hoverScale < 1.05, "Hover growth stays subtle")
        XCTAssertTrue(feedback.pressedScale > 0.9, "Pressed shrink stays subtle")

        XCTAssertEqual(feedback.hoverScale(reduceMotion: true), 1, "Reduce Motion removes hover scaling")
        XCTAssertEqual(feedback.pressedScale(reduceMotion: true), 1, "Reduce Motion removes press scaling")
        XCTAssertEqual(
            feedback.pressedScale(reduceMotion: false),
            feedback.pressedScale,
            "Normal mode keeps the press scale"
        )
    }

    @Test func testContentDepthScalesStayNearIdentity() {
        let content = IslandMotionPolicy.ContentTransition.self
        XCTAssertTrue(content.expandedLayerInitialScale < 1, "Expanded layer grows in from slightly below 1")
        XCTAssertTrue(content.expandedLayerInitialScale > 0.95, "Depth scale stays subtle")
        XCTAssertTrue(content.compactLayerLiftedScale > 1, "Compact layer lifts slightly past 1")
        XCTAssertTrue(content.compactLayerLiftedScale < 1.06, "Lift scale stays subtle")
    }
}
