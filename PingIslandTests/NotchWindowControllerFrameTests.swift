import AppKit
import XCTest
@testable import Ping_Island

@MainActor
final class NotchWindowControllerFrameTests: XCTestCase {
    private var w: CGFloat { NotchWindowController.panelWindowWidth }

    // MARK: - Docked (opened/popping) frame: centered, narrow, full height

    func testDockedFrameForPrimaryScreenIsCenteredNarrowFullHeight() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        XCTAssertEqual(frame, NSRect(x: 720 - w / 2, y: 900 - 750, width: w, height: 750))
    }

    func testDockedFrameForOffsetExternalScreenCentersOnThatScreen() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        )
        let midX: CGFloat = 1440 + 2560 / 2
        XCTAssertEqual(frame, NSRect(x: midX - w / 2, y: 1440 - 750, width: w, height: 750))
    }

    // MARK: - Closed strip frame: centered, narrow, closedHeight + slack

    func testClosedFrameIsCenteredNarrowStripOfClosedHeightPlusSlack() {
        let closedHeight: CGFloat = 38
        let frame = NotchWindowController.closedWindowFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            closedHeight: closedHeight
        )
        let h = closedHeight + NotchWindowController.closedFrameSlack
        XCTAssertEqual(frame, NSRect(x: 720 - w / 2, y: 900 - h, width: w, height: h))
        XCTAssertLessThan(frame.height, NotchWindowController.windowHeight)
        XCTAssertLessThan(frame.width, 1440) // no longer spans the display
    }

    func testClosedFrameForOffsetExternalScreenCentersOnThatScreen() {
        let closedHeight: CGFloat = 24
        let frame = NotchWindowController.closedWindowFrame(
            screenFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            closedHeight: closedHeight
        )
        let midX: CGFloat = 1440 + 2560 / 2
        let h = closedHeight + NotchWindowController.closedFrameSlack
        XCTAssertEqual(frame, NSRect(x: midX - w / 2, y: 1440 - h, width: w, height: h))
    }

    // MARK: - Status-driven target frame resolver

    func testTargetFrameClosedIsTheClosedStrip() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let closedHeight: CGFloat = 38
        XCTAssertEqual(
            NotchWindowController.targetWindowFrame(status: .closed, screenFrame: screen, closedHeight: closedHeight),
            NotchWindowController.closedWindowFrame(screenFrame: screen, closedHeight: closedHeight)
        )
    }

    func testTargetFrameOpenedAndPoppingAreTheFullDockedCanvas() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let closedHeight: CGFloat = 38
        let docked = NotchWindowController.dockedWindowFrame(screenFrame: screen)
        XCTAssertEqual(
            NotchWindowController.targetWindowFrame(status: .opened, screenFrame: screen, closedHeight: closedHeight),
            docked
        )
        XCTAssertEqual(
            NotchWindowController.targetWindowFrame(status: .popping, screenFrame: screen, closedHeight: closedHeight),
            docked
        )
    }

    func testTargetFrameWidthIsConstantHeightByStatusOriginCentersOnScreen() {
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let b = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        let closedHeight: CGFloat = 38

        let closedA = NotchWindowController.targetWindowFrame(status: .closed, screenFrame: a, closedHeight: closedHeight)
        let closedB = NotchWindowController.targetWindowFrame(status: .closed, screenFrame: b, closedHeight: closedHeight)
        XCTAssertEqual(closedA.width, w)                 // width constant, not screen-derived
        XCTAssertEqual(closedB.width, w)
        XCTAssertEqual(closedA.height, closedB.height)   // height only by status
        XCTAssertEqual(closedB.origin.x, (1440 + 2560 / 2) - w / 2) // centered on that screen

        let openedB = NotchWindowController.targetWindowFrame(status: .opened, screenFrame: b, closedHeight: closedHeight)
        XCTAssertEqual(openedB.width, w)
        XCTAssertEqual(openedB.height, NotchWindowController.windowHeight)
        XCTAssertNotEqual(openedB.height, closedB.height)
    }

    // MARK: - Hit-test rect derives from live window width/height (not screen/750)

    func testHitTestRectCentersOnWindowWidthAndDerivesYFromWindowHeight() {
        let opened = CGSize(width: 400, height: 120)
        let closed = CGSize(width: 200, height: 38)
        let winW: CGFloat = 700
        let winH: CGFloat = 158

        let openedRect = NotchViewController.panelHitRect(
            status: .opened, openedSize: opened, closedSize: closed,
            windowWidth: winW, windowHeight: winH
        )
        // Centered within the window, top-pinned to the live window height.
        XCTAssertEqual(openedRect.midX, winW / 2, accuracy: 0.5)
        XCTAssertEqual(openedRect.maxY, winH, accuracy: 0.5)
        XCTAssertEqual(openedRect.origin.y, winH - opened.height, accuracy: 0.5)

        let closedRect = NotchViewController.panelHitRect(
            status: .closed, openedSize: opened, closedSize: closed,
            windowWidth: winW, windowHeight: winH
        )
        XCTAssertEqual(closedRect.maxY, winH + 5, accuracy: 0.5) // closed adds +5 top padding
    }
}
