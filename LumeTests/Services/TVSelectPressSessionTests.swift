import XCTest
@testable import Lume

final class TVSelectPressSessionTests: XCTestCase {
    func testShortSelectShowsControls() {
        var session = TVSelectPressSession()
        session.beginSelect()
        XCTAssertEqual(session.shortSelect(), .showControls)
        XCTAssertEqual(session.endSelect(), .ignore)
    }

    func testLongPressOpensMenuOnceAndSuppressesShortSelect() {
        var session = TVSelectPressSession()
        session.beginSelect()
        XCTAssertEqual(session.recogniseLongPress(), .openMuteMenu)
        // Key-repeat / second long recognition while still down must be ignored.
        XCTAssertEqual(session.recogniseLongPress(), .ignore)
        XCTAssertEqual(session.shortSelect(), .ignore)
        XCTAssertEqual(session.endSelect(), .focusMuteMenu)
    }

    func testShortSelectAfterLongPressEndIsFresh() {
        var session = TVSelectPressSession()
        session.beginSelect()
        XCTAssertEqual(session.recogniseLongPress(), .openMuteMenu)
        XCTAssertEqual(session.endSelect(), .focusMuteMenu)

        session.beginSelect()
        XCTAssertEqual(session.shortSelect(), .showControls)
    }

    func testReleaseWithoutLongDoesNotFocusMenu() {
        var session = TVSelectPressSession()
        session.beginSelect()
        XCTAssertEqual(session.endSelect(), .ignore)
    }

    func testResetClearsArmedLongPress() {
        var session = TVSelectPressSession()
        session.beginSelect()
        _ = session.recogniseLongPress()
        session.reset()
        XCTAssertEqual(session.shortSelect(), .showControls)
    }

    func testRepeatedBeginSelectDuringHoldDoesNotClearLongPress() {
        var session = TVSelectPressSession()
        session.beginSelect()
        XCTAssertEqual(session.recogniseLongPress(), .openMuteMenu)
        // Physical remotes can re-deliver pressesBegan while Select stays down.
        session.beginSelect()
        XCTAssertEqual(session.recogniseLongPress(), .ignore)
        XCTAssertEqual(session.shortSelect(), .ignore)
        XCTAssertEqual(session.endSelect(), .focusMuteMenu)
    }

    func testFailedLongThenShortMatchesUIKitOrder() {
        var session = TVSelectPressSession()
        session.beginSelect()
        // Long-press recogniser fails; tap fires while Select may already be up
        // or still ending — short Select must win either way.
        XCTAssertEqual(session.shortSelect(), .showControls)
        XCTAssertEqual(session.endSelect(), .ignore)
    }

    func testLongPressWorksWhenPressesBeganWasMissed() {
        var session = TVSelectPressSession()
        // Gesture can fire without pressesBegan when SwiftUI briefly owns focus.
        XCTAssertEqual(session.recogniseLongPress(), .openMuteMenu)
        XCTAssertEqual(session.shortSelect(), .ignore)
        XCTAssertEqual(session.endSelect(), .focusMuteMenu)
    }
}
