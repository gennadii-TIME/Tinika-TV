//
//  AppInterfaceLanguage.swift
//  Lume
//
//  In-app interface language. Default is English (not the system language).
//  Persisted across launches and applied before UI loads so String Catalog
//  lookups, SwiftUI Text, and Bundle.localizedString agree.
//

import Foundation
import ObjectiveC
import SwiftUI

/// Supported Tinika TV / Lume interface languages (String Catalog locales).
nonisolated enum AppInterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case portuguese = "pt"
    case russian = "ru"
    case chineseSimplified = "zh-Hans"

    static let storageKey = "app.interfaceLanguage"
    static let defaultValue: AppInterfaceLanguage = .english

    var id: String { rawValue }

    /// BCP-47 code used for `Locale` / `AppleLanguages`.
    var localeIdentifier: String { rawValue }

    /// Locale for `String(format:locale:)` and SwiftUI environment pinning.
    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Language name in that language (picker labels — not translated via catalog).
    var nativeDisplayName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .french: "Français"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .portuguese: "Português"
        case .russian: "Русский"
        case .chineseSimplified: "简体中文"
        }
    }

    static func resolve(_ raw: String?) -> AppInterfaceLanguage {
        guard let raw, let value = AppInterfaceLanguage(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    /// Stored choice, or English when unset / unknown.
    static var current: AppInterfaceLanguage {
        resolve(UserDefaults.standard.string(forKey: storageKey))
    }

    /// Persist and apply immediately (Bundle + AppleLanguages). Call from `LumeApp.init`
    /// before any localized UI is built, and again when the user picks a language.
    static func set(_ language: AppInterfaceLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        apply(language)
    }

    /// Apply without rewriting storage (launch path).
    static func applyStored() {
        apply(current)
    }

    /// Resolve a String Catalog key with the in-app language.
    /// Prefer this over bare `String(localized:)` for values shown outside
    /// `Text(LocalizedStringKey)` — `String(localized:)` does not reliably go
    /// through `Bundle.main.localizedString` (and thus our language override).
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// Resolve a `LocalizedStringResource` with the in-app locale pinned.
    static func localized(_ resource: LocalizedStringResource) -> String {
        var pinned = resource
        pinned.locale = current.locale
        return String(localized: pinned)
    }

    /// `String(format:)` using the in-app catalog translation of `key`.
    static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: current.locale, arguments: arguments)
    }

    private static func apply(_ language: AppInterfaceLanguage) {
        // Prefer the in-app choice over the system / Settings per-app language.
        UserDefaults.standard.set([language.localeIdentifier], forKey: "AppleLanguages")
        Bundle.setAppLanguage(language.localeIdentifier)
    }
}

// MARK: - Bundle override

private var appLanguageBundleKey: UInt8 = 0

extension Bundle {
    /// Points `Bundle.main` localized lookups at the chosen `.lproj` (String Catalog
    /// builds still emit per-language resources the runtime can load).
    fileprivate static func setAppLanguage(_ languageCode: String) {
        object_setClass(Bundle.main, AppLanguageBundle.self)
        let path = Bundle.main.path(forResource: languageCode, ofType: "lproj")
        objc_setAssociatedObject(
            Bundle.main,
            &appLanguageBundleKey,
            path,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

/// Forwards `localizedString` to the active language `.lproj`. The app build
/// recompiles `Localizable.xcstrings` into every language folder
/// (`Scripts/compile-localizable.sh`) so in-app language switching sees the
/// full catalog — not Xcode's incomplete incremental `.strings`.
private final class AppLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        if let path = objc_getAssociatedObject(self, &appLanguageBundleKey) as? String,
           let languageBundle = Bundle(path: path)
        {
            // Sentinel distinguishes "missing key" from a translation that
            // equals the English source (Premium, OK, …).
            let sentinel = "\u{FFFF}.\(key)"
            let localized = languageBundle.localizedString(
                forKey: key, value: sentinel, table: tableName
            )
            if localized != sentinel {
                return localized
            }
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - SwiftUI

extension View {
    /// Pins SwiftUI's locale to the in-app language and rebuilds on change so
    /// `Text("…")` / `LocalizedStringKey` refresh without a process relaunch.
    func appInterfaceLanguage(_ language: AppInterfaceLanguage) -> some View {
        environment(\.locale, Locale(identifier: language.localeIdentifier))
            .id(language.rawValue)
    }
}
