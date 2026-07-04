import XCTest
@testable import Ping_Island

final class StatusBarMenuBuilderTests: XCTestCase {
    private func actions(_ items: [StatusMenuItem]) -> [StatusMenuAction] {
        items.compactMap {
            if case .action(let action) = $0.kind { return action }
            return nil
        }
    }

    func testMenuOrderAndKinds() {
        let items = StatusBarMenuBuilder.menu(
            surfaceMode: .notch,
            shortVersion: "1.2.3",
            buildNumber: "99",
            includeCheckForUpdates: true
        )

        XCTAssertEqual(items.count, 7)

        XCTAssertEqual(items[0].kind, .action(.openSettings))
        XCTAssertEqual(items[0].titleKey, "打开设置")

        guard case .submenu(let children) = items[1].kind else {
            return XCTFail("expected submenu at index 1")
        }
        XCTAssertEqual(items[1].titleKey, "展示模式")
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].kind, .action(.setSurfaceMode(.notch)))
        XCTAssertEqual(children[0].titleKey, "刘海屏方式")
        XCTAssertEqual(children[1].kind, .action(.setSurfaceMode(.floatingPet)))
        XCTAssertEqual(children[1].titleKey, "独立悬浮宠物")

        XCTAssertEqual(items[2].kind, .separator)

        XCTAssertEqual(items[3].kind, .info)
        XCTAssertEqual(items[3].literalTitle, "Ping Island v1.2.3 (build 99)")

        XCTAssertEqual(items[4].kind, .action(.checkForUpdates))
        XCTAssertEqual(items[4].titleKey, "检查更新")

        XCTAssertEqual(items[5].kind, .separator)

        XCTAssertEqual(items[6].kind, .action(.quit))
        XCTAssertEqual(items[6].titleKey, "退出 Ping Island")
    }

    func testCheckmarkFollowsNotchMode() {
        let items = StatusBarMenuBuilder.menu(
            surfaceMode: .notch,
            shortVersion: "1.0.0",
            buildNumber: "1",
            includeCheckForUpdates: true
        )
        guard case .submenu(let children) = items[1].kind else {
            return XCTFail("expected submenu")
        }
        XCTAssertTrue(children[0].isChecked)  // 停靠瀏海
        XCTAssertFalse(children[1].isChecked) // 獨立懸浮寵物
    }

    func testCheckmarkFollowsFloatingPetMode() {
        let items = StatusBarMenuBuilder.menu(
            surfaceMode: .floatingPet,
            shortVersion: "1.0.0",
            buildNumber: "1",
            includeCheckForUpdates: true
        )
        guard case .submenu(let children) = items[1].kind else {
            return XCTFail("expected submenu")
        }
        XCTAssertFalse(children[0].isChecked)
        XCTAssertTrue(children[1].isChecked)
    }

    func testAppStoreBranchExcludesCheckForUpdates() {
        let items = StatusBarMenuBuilder.menu(
            surfaceMode: .notch,
            shortVersion: "1.0.0",
            buildNumber: "1",
            includeCheckForUpdates: false
        )
        XCTAssertFalse(actions(items).contains(.checkForUpdates))
        XCTAssertEqual(items.count, 6)
        // Trailing block collapses to a single separator then quit.
        XCTAssertEqual(items[4].kind, .separator)
        XCTAssertEqual(items[5].kind, .action(.quit))
    }

    func testVersionDisplayStringFormat() {
        XCTAssertEqual(
            StatusBarMenuBuilder.versionDisplayString(shortVersion: "0.25.9", buildNumber: "82"),
            "Ping Island v0.25.9 (build 82)"
        )
    }
}
