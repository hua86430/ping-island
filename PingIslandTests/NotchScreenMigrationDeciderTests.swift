import CoreGraphics
import Foundation
import XCTest
@testable import Ping_Island

final class NotchScreenMigrationDeciderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testSpecificModeNeverMigrates() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .specificScreen, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(10), dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testCursorOnCurrentScreenDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 1, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testCursorOnNewScreenWithoutPendingBeginsDwell() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .beginDwell(2))
    }

    func testCursorHoppingToYetAnotherScreenRestartsDwell() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 3, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.1), dwell: 0.2
        )
        XCTAssertEqual(action, .beginDwell(3))
    }

    func testPendingScreenBeforeDwellElapsedDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.1), dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testPendingScreenAfterDwellElapsedMigrates() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.25), dwell: 0.2
        )
        XCTAssertEqual(action, .migrate(2))
    }

    func testNilCursorScreenDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: nil, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }
}
