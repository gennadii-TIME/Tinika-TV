//
//  SupportInfo.swift
//  Lume
//
//  Canonical support / contact links, shared by the iOS Settings list (tappable
//  Link rows) and the tvOS About pane (read-only text plus a scannable QR code,
//  since Apple TV can't open a URL itself). One source of truth so the two
//  surfaces can never drift.
//
//  Modified for Tinika TV: 2026-10-04 — website, privacy and support point at
//  the Tinika-TV repository and GitHub Pages.
//

import Foundation

nonisolated enum SupportInfo {
    static let website = "https://gennadii-time.github.io/Tinika-TV/"
    static let email = "support@tinika.lv"

    /// Public privacy policy. Source of truth in-repo: `docs/PRIVACY.md` (+ `docs/privacy.html`).
    static let privacyPolicy = "https://gennadii-time.github.io/Tinika-TV/privacy.html"

    /// App Store listing placeholders until Tinika TV ships its own listing.
    static let appStore = "https://github.com/gennadii-TIME/Tinika-TV"
    static let appStoreReview = "https://github.com/gennadii-TIME/Tinika-TV"

    /// Scheme-stripped forms for compact on-screen display.
    static let websiteDisplay = "tinika.tv"
    static let appStoreDisplay = "GitHub"

    static var websiteURL: URL? {
        URL(string: website)
    }

    static var privacyPolicyURL: URL? {
        URL(string: privacyPolicy)
    }

    static var emailURL: URL? {
        URL(string: "mailto:\(email)")
    }

    static var appStoreReviewURL: URL? {
        URL(string: appStoreReview)
    }

    /// Marketing version (`CFBundleShortVersionString`, e.g. "2.1.0"), sourced
    /// from the build's `MARKETING_VERSION` rather than a hardcoded string so
    /// the iOS and tvOS About panes always reflect the shipped version.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
