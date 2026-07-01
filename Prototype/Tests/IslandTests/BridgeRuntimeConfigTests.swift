import XCTest
@testable import IslandShared

final class BridgeRuntimeConfigTests: XCTestCase {
    func testDefaultClaudeQuestionPreviewOnlyIsFalse() {
        XCTAssertFalse(BridgeRuntimeConfig.default.claudeQuestionPreviewOnly)
    }

    func testJSONRoundTripPreservesClaudeQuestionPreviewOnly() throws {
        let config = BridgeRuntimeConfig(routePromptsToTerminal: true, claudeQuestionPreviewOnly: true)
        let data = try JSONSerialization.data(withJSONObject: config.jsonObject)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brc-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = BridgeRuntimeConfig.load(from: url)
        XCTAssertTrue(loaded.claudeQuestionPreviewOnly)
        XCTAssertTrue(loaded.routePromptsToTerminal)
    }

    func testMissingKeyLoadsFalse() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brc-\(UUID().uuidString).json")
        try Data("{\"routePromptsToTerminal\":true}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(BridgeRuntimeConfig.load(from: url).claudeQuestionPreviewOnly)
    }
}
