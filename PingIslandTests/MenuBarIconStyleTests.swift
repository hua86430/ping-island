import XCTest
@testable import Ping_Island

final class MenuBarIconStyleTests: XCTestCase {
    func testAllCasesHaveStableRawValues() {
        XCTAssertEqual(
            MenuBarIconStyle.allCases.map(\.rawValue),
            ["notchDots", "notchDotsHollow", "codeSpark", "commandBubble", "cursorSpark"]
        )
    }

    func testDefaultIsNotchDots() {
        XCTAssertEqual(MenuBarIconStyle.default, .notchDots)
    }

    func testRawValueRoundTrips() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(MenuBarIconStyle(rawValue: style.rawValue), style)
        }
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(MenuBarIconStyle(rawValue: "bogus"))
    }

    func testTitleKeysAreDistinctAndNonEmpty() {
        let keys = MenuBarIconStyle.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertFalse(keys.contains(where: \.isEmpty))
    }

    @MainActor
    func testTemplateImageIsTemplateAndSized() {
        let image = MenuBarIconStyle.codeSpark.templateImage(pointSize: 18)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 18, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 18, accuracy: 0.5)
    }
}
