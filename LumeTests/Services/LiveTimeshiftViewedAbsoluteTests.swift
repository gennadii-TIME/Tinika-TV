//
//  LiveTimeshiftViewedAbsoluteTests.swift
//  LumeTests
//
//  Viewed-absolute playhead must reject stale engine samples after a timeshift
//  URL rebuild so the next scrub session does not jump to the live edge.
//

import XCTest
@testable import Lume

final class LiveTimeshiftViewedAbsoluteTests: XCTestCase {
    func testTrustedPlayerTimeMapsArchiveStartPlusOffset() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = now.addingTimeInterval(-3600)
        let media = Self.timeshiftMedia(start: start, end: now)

        XCTAssertTrue(LiveTimeshift.isPlayerTimeTrusted(media: media, playerTime: 20, now: now))
        let viewed = LiveTimeshift.viewedAbsoluteDate(
            media: media,
            playerTime: 20,
            fallback: start,
            now: now
        )
        XCTAssertEqual(viewed.timeIntervalSince1970, start.addingTimeInterval(20).timeIntervalSince1970, accuracy: 0.01)
    }

    func testStalePlayerTimeFallsBackInsteadOfLiveEdge() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = now.addingTimeInterval(-3600)
        let media = Self.timeshiftMedia(start: start, end: now)
        // Leftover sample from before the URL rebuild — hours ahead of the clip.
        let stale: TimeInterval = 10_000
        XCTAssertFalse(LiveTimeshift.isPlayerTimeTrusted(media: media, playerTime: stale, now: now))

        let fallback = start.addingTimeInterval(20)
        let viewed = LiveTimeshift.viewedAbsoluteDate(
            media: media,
            playerTime: stale,
            fallback: fallback,
            now: now
        )
        XCTAssertEqual(viewed, fallback)
        XCTAssertNotEqual(viewed.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    func testRawAbsolutePlaybackDateStillAddsUntrustedOffset() {
        // Document the unsafe path that caused the scrubber jump — callers that
        // need scrub anchoring must use viewedAbsoluteDate instead.
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let start = now.addingTimeInterval(-3600)
        let media = Self.timeshiftMedia(start: start, end: now)
        let raw = LiveTimeshift.absolutePlaybackDate(media: media, playerTime: 10_000, now: now)
        XCTAssertGreaterThan(raw, now)
    }

    private static func timeshiftMedia(start: Date, end: Date) -> PlayableMedia {
        PlayableMedia(
            id: "\(LiveTimeshift.timeshiftIDPrefix)ch-\(Int(start.timeIntervalSince1970))",
            url: URL(string: "https://example.com/index.m3u8")!,
            title: "Test",
            subtitle: nil,
            posterURL: nil,
            kind: .vod,
            startTime: 0,
            contentRef: .live("ch"),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
    }
}
