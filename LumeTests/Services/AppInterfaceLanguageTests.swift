import XCTest
@testable import Lume

final class AppInterfaceLanguageTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var previousLanguage: String?
    private var previousAppleLanguages: [String]?

    override func setUp() {
        super.setUp()
        previousLanguage = defaults.string(forKey: AppInterfaceLanguage.storageKey)
        previousAppleLanguages = defaults.stringArray(forKey: "AppleLanguages")
        defaults.removeObject(forKey: AppInterfaceLanguage.storageKey)
    }

    override func tearDown() {
        if let previousLanguage {
            defaults.set(previousLanguage, forKey: AppInterfaceLanguage.storageKey)
        } else {
            defaults.removeObject(forKey: AppInterfaceLanguage.storageKey)
        }
        if let previousAppleLanguages {
            defaults.set(previousAppleLanguages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        AppInterfaceLanguage.applyStored()
        super.tearDown()
    }

    func testDefaultIsEnglishWhenUnset() {
        defaults.removeObject(forKey: AppInterfaceLanguage.storageKey)
        XCTAssertEqual(AppInterfaceLanguage.current, .english)
        XCTAssertEqual(AppInterfaceLanguage.resolve(nil), .english)
        XCTAssertEqual(AppInterfaceLanguage.resolve("nope"), .english)
    }

    func testSetPersistsAndUpdatesAppleLanguages() {
        AppInterfaceLanguage.set(.russian)
        XCTAssertEqual(
            defaults.string(forKey: AppInterfaceLanguage.storageKey),
            AppInterfaceLanguage.russian.rawValue
        )
        XCTAssertEqual(AppInterfaceLanguage.current, .russian)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ru"])

        AppInterfaceLanguage.set(.english)
        XCTAssertEqual(AppInterfaceLanguage.current, .english)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
    }

    func testAllTenCatalogLanguagesAreSelectable() {
        let codes = Set(AppInterfaceLanguage.allCases.map(\.rawValue))
        XCTAssertEqual(
            codes,
            Set(["en", "de", "es", "fr", "it", "ja", "ko", "pt", "ru", "zh-Hans"])
        )
    }

    /// Brand stays "Premium" in every language (not translated).
    func testPremiumBrandStaysPremiumInAllLanguages() {
        for language in AppInterfaceLanguage.allCases {
            AppInterfaceLanguage.set(language)
            let resolved = AppInterfaceLanguage.localized("Premium")
            XCTAssertEqual(resolved, "Premium", "\(language.rawValue) changed Premium")
        }
    }

    /// Main-menu + settings strings must resolve via the in-app language
    /// (not system locale, not English verbatim).
    func testRussianMainMenuSubtitlesMatchCatalog() {
        AppInterfaceLanguage.set(.russian)
        let viaBundle = AppInterfaceLanguage.localized("Groups, list and program guide")
        XCTAssertEqual(viaBundle, "Группы, список и программа передач", "bundle=\(viaBundle)")
        XCTAssertEqual(
            AppInterfaceLanguage.localized("View Channels"),
            "Просмотр каналов"
        )
        XCTAssertEqual(AppInterfaceLanguage.localized("Settings"), "Настройки")
        XCTAssertEqual(AppInterfaceLanguage.localized("Language"), "Язык")
        XCTAssertEqual(AppInterfaceLanguage.localized("Automatic"), "Автоматически")
        XCTAssertEqual(AppInterfaceLanguage.localized("On"), "Вкл.")
        XCTAssertEqual(AppInterfaceLanguage.localized("Off"), "Выкл.")
    }

    func testSettingsAndMainMenuKeysResolveForAllLanguages() {
        let keys = [
            "View Channels",
            "Groups, list and program guide",
            "Channel Sorting",
            "Profiles and channel order",
            "Update Channel List",
            "Fetch the latest playlist",
            "Update Program Guide",
            "Program guide updated",
            "Settings",
            "Language",
            "Interface",
            "Playlists",
            "Profiles",
            "Player",
            "About",
            "TV Guide",
            "Full version purchased",
            "30 days free",
            "Automatic",
            "On",
            "Off",
            "Never",
            "Buy Forever",
            "Content",
            "Integrations",
            "Storage"
        ]

        // Catalog intentionally keeps the English spelling in some languages.
        let allowedSameAsEnglish: [AppInterfaceLanguage: Set<String>] = [
            .german: ["Playlists", "Player", "Premium"],
            .french: ["Interface", "Playlists", "Premium"],
            .italian: ["Premium"],
            .portuguese: ["Interface", "Playlists", "Player", "Premium"],
            .spanish: ["Premium"],
            .japanese: ["Premium"],
            .korean: ["Premium"],
            .russian: ["Premium"],
            .chineseSimplified: ["Premium"]
        ]

        for language in AppInterfaceLanguage.allCases {
            AppInterfaceLanguage.set(language)
            let allowSame = allowedSameAsEnglish[language] ?? []
            for key in keys {
                let resolved = AppInterfaceLanguage.localized(key)
                if language == .english {
                    XCTAssertFalse(resolved.isEmpty, "empty en for \(key)")
                    // English source keys that are missing from en.lproj still
                    // resolve to themselves via the Bundle fallback.
                    XCTAssertEqual(resolved, key, "en changed \(key) → \(resolved)")
                } else if allowSame.contains(key) || key == "Premium" {
                    // Same-as-English is OK for shared loanwords / brands.
                    XCTAssertFalse(resolved.isEmpty, "\(language) empty for \(key)")
                } else {
                    XCTAssertNotEqual(
                        resolved, key,
                        "\(language.rawValue) still English for \(key)"
                    )
                }
            }
        }
    }

    func testLocalizedFormatUsesAppLanguage() {
        AppInterfaceLanguage.set(.russian)
        let formatted = AppInterfaceLanguage.localizedFormat("%lld seconds", Int64(5))
        XCTAssertTrue(
            formatted.contains("5"),
            "expected 5 in \(formatted)"
        )
        XCTAssertNotEqual(formatted, "5 seconds")
    }
}
