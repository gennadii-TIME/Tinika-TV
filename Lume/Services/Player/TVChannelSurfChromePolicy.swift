//
//  TVChannelSurfChromePolicy.swift
//  Lume
//
//  When ↑/↓ channel surfing may raise the player OSD. Kept pure so hosts and
//  unit tests share one rule: a successful clean-screen surf must not open the
//  scrub chrome.
//

import Foundation

/// Chrome side-effects after a vertical live-channel surf attempt.
enum TVChannelSurfChromePolicy: Equatable, Sendable {
    /// Successful ↑/↓ never raises player chrome. Surfing is meant to work with
    /// the OSD hidden; an already-visible OSD refreshes its hide timer on the
    /// overlay / host path instead.
    static func shouldShowControlsAfterSuccessfulVerticalSurf() -> Bool {
        false
    }

    /// Nowhere to surf — summon controls so the press is not a silent no-op.
    static func shouldShowControlsWhenVerticalSurfUnavailable() -> Bool {
        true
    }
}
