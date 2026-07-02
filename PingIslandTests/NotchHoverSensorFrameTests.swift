import CoreGraphics
import XCTest
@testable import Ping_Island

final class NotchHoverSensorFrameTests: XCTestCase {
    private let closed = CGRect(x: 620, y: 810, width: 200, height: 40)
    private let reveal = CGRect(x: 560, y: 800, width: 320, height: 60)

    private func rect(det: Bool = false, sup: Bool = false, rev: Bool = false) -> CGRect? {
        NotchHoverSensorFrame.rect(isDetached: det, isSuppressedHidden: sup,
            isFullscreenReveal: rev, closedTriggerRect: closed, fullscreenRevealRect: reveal)
    }

    func testNormalUsesClosedTriggerRect() { XCTAssertEqual(rect(), closed) }
    func testDetachedHasNoSensor() { XCTAssertNil(rect(det: true)) }
    func testSuppressedHiddenHasNoSensor() { XCTAssertNil(rect(sup: true)) }
    func testFullscreenRevealUsesRevealRect() { XCTAssertEqual(rect(rev: true), reveal) }
    func testDetachedWinsOverReveal() { XCTAssertNil(rect(det: true, rev: true)) }
    func testSuppressedWinsOverReveal() { XCTAssertNil(rect(sup: true, rev: true)) }
}
