import XCTest
@testable import Ping_Island

final class AppLanguageTests: XCTestCase {
    func testSystemLanguagePrefersTraditionalChineseForChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hant"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-TW"]),
            "zh-Hant"
        )
    }

    func testSystemLanguageFallsBackToEnglishForNonChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en-US"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["ja-JP"]),
            "en"
        )
    }

    func testExplicitLanguageSelectionsStayStable() {
        XCTAssertEqual(AppLanguage.traditionalChinese.resolvedLanguageCode(), "zh-Hant")
        XCTAssertEqual(AppLanguage.english.resolvedLanguageCode(), "en")
    }
}
