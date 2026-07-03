import XCTest

final class PingIslandUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsWindowLaunchesInUITestMode() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PING_ISLAND_UI_TEST_MODE"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["settings.sidebar.general"].waitForExistence(timeout: 5))
        // Assert on the detail identifier rather than a localized label: the shipped
        // locale is zh-Hant, so the general toggle renders as "登入時打開", not the
        // simplified source key. The identifier is locale-independent.
        XCTAssertTrue(app.descendants(matching: .any)["settings.detail.general"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsSidebarCanSwitchToAboutPage() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PING_ISLAND_UI_TEST_MODE"] = "1"
        app.launch()

        // The identifier lands on several nested elements (row content + List cell
        // wrapper + sidebar ScrollView). firstMatch resolves to the ScrollView, which
        // has no hit point, so pick the first hittable match to tap.
        let aboutMatches = app.descendants(matching: .any).matching(identifier: "settings.sidebar.about")
        XCTAssertTrue(aboutMatches.firstMatch.waitForExistence(timeout: 5))
        let aboutButton = aboutMatches.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? aboutMatches.firstMatch
        aboutButton.tap()

        // Locale-independent: verify the detail router switched to the about page.
        XCTAssertTrue(app.descendants(matching: .any)["settings.detail.about"].waitForExistence(timeout: 5))
    }
}
