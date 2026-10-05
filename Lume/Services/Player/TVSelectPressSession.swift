//
//  TVSelectPressSession.swift
//  Lume
//
//  Resolves short vs long Select on the hidden-OSD catcher so a recognised
//  long-press cannot also deliver show-controls / Pause-Play, and so the mute
//  menu does not receive focus (and key-repeat activation) until Select ends.
//

import Foundation

/// Pure press-session state for tvOS Select long-press vs tap.
///
/// Physical sequence we must handle:
/// 1. Select down → arm session
/// 2a. Up before long threshold → short Select (show OSD)
/// 2b. Held past threshold → long Select (open mute menu) once; ignore short
/// 3. Select up after long → allow focus into the menu (no activation during hold)
struct TVSelectPressSession: Equatable, Sendable {
    /// Long-press was recognised for this physical press; short Select is suppressed.
    private(set) var longPressRecognised = false
    /// Mute menu is visible but must not take button focus until Select is released.
    private(set) var awaitFocusUntilRelease = false
    /// Select is currently down (began without a matching end).
    private(set) var isSelectDown = false

    enum ShortSelectDecision: Equatable, Sendable {
        case showControls
        case ignore
    }

    enum LongSelectDecision: Equatable, Sendable {
        case openMuteMenu
        case ignore
    }

    enum ReleaseDecision: Equatable, Sendable {
        /// Hand focus to the mute menu now that Select is up.
        case focusMuteMenu
        case ignore
    }

    mutating func beginSelect() {
        // Held Select can deliver repeated pressesBegan; never re-arm mid-hold
        // or a later long-press recognition / release focus hand-off is lost.
        guard !isSelectDown else { return }
        isSelectDown = true
        longPressRecognised = false
        awaitFocusUntilRelease = false
    }

    /// Long-press threshold reached while Select is still down.
    ///
    /// `pressesBegan` can miss the UIView when SwiftUI briefly owns focus; the
    /// long-press recogniser is still authoritative, so arm the session here.
    mutating func recogniseLongPress() -> LongSelectDecision {
        guard !longPressRecognised else { return .ignore }
        isSelectDown = true
        longPressRecognised = true
        awaitFocusUntilRelease = true
        return .openMuteMenu
    }

    /// Tap / short Select (only valid when long-press did not win).
    mutating func shortSelect() -> ShortSelectDecision {
        if longPressRecognised { return .ignore }
        return .showControls
    }

    /// Select released.
    mutating func endSelect() -> ReleaseDecision {
        let shouldFocus = longPressRecognised && awaitFocusUntilRelease
        isSelectDown = false
        longPressRecognised = false
        awaitFocusUntilRelease = false
        return shouldFocus ? .focusMuteMenu : .ignore
    }

    /// Menu closed or stream swapped — drop any in-flight press bookkeeping.
    mutating func reset() {
        self = TVSelectPressSession()
    }
}
