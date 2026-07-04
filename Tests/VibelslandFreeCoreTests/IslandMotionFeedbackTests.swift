import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct IslandMotionFeedbackTests {
    @Test func testEasedProgressEndpointsAndClamping() {
        for expanded in [true, false] {
            XCTAssertEqual(IslandMotionPolicy.WindowTransition.easedProgress(0, expanded: expanded), 0, "Easing starts at 0")
            XCTAssertEqual(IslandMotionPolicy.WindowTransition.easedProgress(1, expanded: expanded), 1, "Easing ends at 1")
            XCTAssertEqual(IslandMotionPolicy.WindowTransition.easedProgress(-0.5, expanded: expanded), 0, "Progress clamps below 0")
            XCTAssertEqual(IslandMotionPolicy.WindowTransition.easedProgress(1.5, expanded: expanded), 1, "Progress clamps above 1")
        }
    }

    @Test func testEasedProgressIsMonotonic() {
        for expanded in [true, false] {
            var previous = -0.001
            for step in 0...20 {
                let value = IslandMotionPolicy.WindowTransition.easedProgress(Double(step) / 20, expanded: expanded)
                XCTAssertTrue(value >= previous, "Easing must be monotonic (expanded=\(expanded), step=\(step))")
                previous = value
            }
        }
    }

    @Test func testExpansionEasingAttacksFasterThanCollapse() {
        // 展开用 ease-out-cubic：前段进度领先，产生「跟手」的快速响应。
        let expansionEarly = IslandMotionPolicy.WindowTransition.easedProgress(0.25, expanded: true)
        let collapseEarly = IslandMotionPolicy.WindowTransition.easedProgress(0.25, expanded: false)
        XCTAssertTrue(
            expansionEarly > collapseEarly,
            "Expansion easing leads at early progress (\(expansionEarly) vs \(collapseEarly))"
        )
        XCTAssertTrue(expansionEarly > 0.5, "Ease-out-cubic passes half distance by a quarter of the time")
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
