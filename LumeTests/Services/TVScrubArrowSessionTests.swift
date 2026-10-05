import XCTest
@testable import Lume

final class TVScrubArrowSessionTests: XCTestCase {
    func testShortPressEmitsSingleStep() {
        var session = TVScrubArrowSession()
        XCTAssertEqual(session.begin(.right, at: 0), .armed)
        XCTAssertEqual(session.tick(at: 0.1), .ignore)
        XCTAssertEqual(session.end(at: 0.2), .shortStep(.right))
        XCTAssertFalse(session.isPressActive)
    }

    func testHoldRateRampsFromTenToSixtyOverThreeSeconds() {
        XCTAssertEqual(TVScrubArrowSession.holdRate(holdElapsed: 0), 10, accuracy: 0.0001)
        XCTAssertEqual(TVScrubArrowSession.holdRate(holdElapsed: 1.5), 35, accuracy: 0.0001)
        XCTAssertEqual(TVScrubArrowSession.holdRate(holdElapsed: 3), 60, accuracy: 0.0001)
        XCTAssertEqual(TVScrubArrowSession.holdRate(holdElapsed: 10), 60, accuracy: 0.0001)
    }

    func testHoldStartsAtTenAndRampsDuringTicks() {
        var session = TVScrubArrowSession()
        XCTAssertEqual(session.begin(.right, at: 0), .armed)
        XCTAssertEqual(session.tick(at: 0.25), .holdStarted(.right))

        // First tick just after hold start — still near 10×.
        if case let .holdTick(_, videoDelta) = session.tick(at: 0.35) {
            // holdElapsed ≈ 0.10 → rate ≈ 10 + 50*(0.10/3) ≈ 11.667
            let expectedRate = TVScrubArrowSession.holdRate(holdElapsed: 0.10)
            XCTAssertEqual(videoDelta, 0.10 * expectedRate, accuracy: 0.001)
            XCTAssertEqual(expectedRate, 10 + 50 * (0.10 / 3), accuracy: 0.0001)
        } else {
            XCTFail("expected holdTick near start rate")
        }

        // After full ramp (≥ 3 s of hold) rate is flat 60×.
        _ = session.tick(at: 0.25 + 3.0)
        if case let .holdTick(_, videoDelta) = session.tick(at: 0.25 + 3.0 + 0.05) {
            XCTAssertEqual(videoDelta, 0.05 * 60, accuracy: 0.001)
        } else {
            XCTFail("expected holdTick at max rate")
        }
    }

    func testReleaseStopsHoldImmediately() {
        var session = TVScrubArrowSession()
        _ = session.begin(.right, at: 0)
        _ = session.tick(at: 0.25)
        XCTAssertTrue(session.isHolding)
        XCTAssertEqual(session.end(at: 0.26), .holdEnded(.right))
        XCTAssertEqual(session.tick(at: 0.30), .ignore)
        XCTAssertFalse(session.isHolding)
    }

    func testDirectionChangeRestartsAcceleration() {
        var session = TVScrubArrowSession()
        _ = session.begin(.left, at: 0)
        _ = session.tick(at: 0.25)
        // Ramp for ~2 s of hold time.
        _ = session.tick(at: 2.25)
        if case let .holdTick(_, videoDelta) = session.tick(at: 2.30) {
            let rate = abs(videoDelta) / 0.05
            XCTAssertGreaterThan(rate, 40, "should have ramped well above start rate")
        } else {
            XCTFail("expected holdTick before direction change")
        }

        XCTAssertEqual(session.begin(.right, at: 2.40), .replaced(previous: .left))
        XCTAssertFalse(session.isHolding)
        XCTAssertNil(session.holdStartedAt)

        // New direction must wait for threshold again, then restart at 10×.
        XCTAssertEqual(session.tick(at: 2.50), .ignore)
        XCTAssertEqual(session.tick(at: 2.65), .holdStarted(.right))
        if case let .holdTick(_, videoDelta) = session.tick(at: 2.75) {
            let expectedRate = TVScrubArrowSession.holdRate(holdElapsed: 0.10)
            XCTAssertEqual(videoDelta, 0.10 * expectedRate, accuracy: 0.001)
            XCTAssertLessThan(expectedRate, 15)
        } else {
            XCTFail("expected holdTick at restarted start rate")
        }
    }

    func testMissingReleaseWatchdogForceEnds() {
        var session = TVScrubArrowSession()
        _ = session.begin(.right, at: 0)
        _ = session.tick(at: 0.25)
        let forceAt = TVScrubArrowSession.missingReleaseWatchdog
        XCTAssertEqual(session.tick(at: forceAt), .forceEnd(.right))
        XCTAssertFalse(session.isPressActive)
    }

    func testCancelDuringArmDoesNotShortStep() {
        var session = TVScrubArrowSession()
        _ = session.begin(.left, at: 0)
        XCTAssertEqual(session.cancel(), .ignore)
    }

    func testCancelDuringHoldEndsHold() {
        var session = TVScrubArrowSession()
        _ = session.begin(.left, at: 0)
        _ = session.tick(at: 0.25)
        XCTAssertEqual(session.cancel(), .holdEnded(.left))
    }
}
