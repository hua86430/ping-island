import AppKit
import XCTest
@testable import Ping_Island

@MainActor
final class NotchWindowControllerFrameTests: XCTestCase {
    func testDockedFrameForPrimaryScreenPinsFullWidthToTop() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        XCTAssertEqual(frame, NSRect(x: 0, y: 900 - 750, width: 1440, height: 750))
    }

    func testDockedFrameForOffsetExternalScreenUsesItsOrigin() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        )
        XCTAssertEqual(frame, NSRect(x: 1440, y: 1440 - 750, width: 2560, height: 750))
    }
}
