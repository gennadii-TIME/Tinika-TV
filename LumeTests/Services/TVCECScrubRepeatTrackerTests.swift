import XCTest
@testable import Lume

final class TVCECScrubRepeatTrackerTests: XCTestCase {
    func testFirstPulseIsShortStep() {
        var tracker = TVCECScrubRepeatTracker()
        XCTAssertEqual(tracker.notePulse(.right, at: 0), .shortStep(.right))
        XCTAssertFalse(tracker.isHolding)
        XCTAssertTrue(tracker.isTracking)
    }

    func testSecondPulseWithinPromoteGapStartsHold() {
        var tracker = TVCECScrubRepeatTracker()
        XCTAssertEqual(tracker.notePulse(.right, at: 0), .shortStep(.right))
        XCTAssertEqual(
            tracker.notePulse(.right, at: 0.30),
            .startHold(.right)
        )
        XCTAssertTrue(tracker.isHolding)
        XCTAssertEqual(
            tracker.notePulse(.right, at: 0.50),
            .continueHold(.right)
        )
    }

    func testPulseDedupeCollapsesTwins() {
        var tracker = TVCECScrubRepeatTracker()
        XCTAssertEqual(tracker.notePulse(.left, at: 1.0), .shortStep(.left))
        XCTAssertEqual(tracker.notePulse(.left, at: 1.05), .ignore)
        XCTAssertEqual(tracker.notePulse(.left, at: 1.20), .startHold(.left))
    }

    func testSilenceWhileArmedDoesNotEndHold() {
        var tracker = TVCECScrubRepeatTracker()
        _ = tracker.notePulse(.right, at: 0)
        XCTAssertEqual(tracker.noteSilence(at: 0.5), .ignore)
        XCTAssertFalse(tracker.isTracking)
    }

    func testSilenceWhileHoldingEndsHold() {
        var tracker = TVCECScrubRepeatTracker()
        _ = tracker.notePulse(.right, at: 0)
        _ = tracker.notePulse(.right, at: 0.3)
        XCTAssertEqual(tracker.noteSilence(at: 0.8), .holdEnded(.right))
        XCTAssertFalse(tracker.isHolding)
        XCTAssertFalse(tracker.isTracking)
    }

    func testOppositePulseWhileArmedRestartsShortStep() {
        var tracker = TVCECScrubRepeatTracker()
        XCTAssertEqual(tracker.notePulse(.right, at: 0), .shortStep(.right))
        XCTAssertEqual(tracker.notePulse(.left, at: 0.2), .shortStep(.left))
        XCTAssertFalse(tracker.isHolding)
    }

    func testLateSecondPulseIsFreshShortStep() {
        var tracker = TVCECScrubRepeatTracker()
        XCTAssertEqual(tracker.notePulse(.right, at: 0), .shortStep(.right))
        // Beyond promoteGap and after armed silence would have cleared — still
        // armed here because silence wasn't noted; treat as fresh tap.
        let late = TVCECScrubRepeatTracker.promoteGap + 0.1
        XCTAssertEqual(tracker.notePulse(.right, at: late), .shortStep(.right))
        XCTAssertFalse(tracker.isHolding)
    }

    func testExternalPulseDedupesTrailingTwin() {
        var tracker = TVCECScrubRepeatTracker()
        tracker.noteExternalPulse(.right, at: 2.0)
        XCTAssertEqual(tracker.notePulse(.right, at: 2.05), .ignore)
        XCTAssertEqual(tracker.notePulse(.right, at: 2.20), .shortStep(.right))
    }

    func testCancelClearsHoldWithoutDecision() {
        var tracker = TVCECScrubRepeatTracker()
        _ = tracker.notePulse(.left, at: 0)
        _ = tracker.notePulse(.left, at: 0.25)
        tracker.cancel()
        XCTAssertFalse(tracker.isTracking)
        XCTAssertEqual(tracker.noteSilence(at: 1), .ignore)
    }
}
