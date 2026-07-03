import XCTest
@testable import Ping_Island

final class SettingsCategoryTests: XCTestCase {
    func testVisibleCategoriesHideLabsWhenLocked() {
        let categories = SettingsCategory.visibleCategories(labsUnlocked: false)
        XCTAssertFalse(categories.contains(.labs))
        XCTAssertEqual(categories, SettingsCategory.allCases.filter { $0 != .labs })
    }

    func testVisibleCategoriesKeepDeclaredOrderWhenUnlocked() {
        XCTAssertEqual(
            SettingsCategory.visibleCategories(labsUnlocked: true),
            SettingsCategory.allCases
        )
    }
}
