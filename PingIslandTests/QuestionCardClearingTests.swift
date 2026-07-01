import XCTest
@testable import Ping_Island

@MainActor
final class QuestionCardClearingTests: XCTestCase {

    private func questionIntervention(id: String, metadata: [String: String]) -> SessionIntervention {
        SessionIntervention(
            id: id,
            kind: .question,
            title: "q",
            message: "q",
            options: [],
            questions: [],
            supportsSessionScope: false,
            metadata: metadata
        )
    }

    private func postToolUse(tool: String, toolUseId: String?) -> HookEvent {
        HookEvent(
            sessionId: "s1",
            cwd: "/tmp/project",
            event: "PostToolUse",
            status: "active",
            provider: .claude,
            clientInfo: SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code"),
            pid: nil,
            tty: nil,
            tool: tool,
            toolInput: nil,
            toolUseId: toolUseId,
            notificationType: nil,
            message: nil
        )
    }

    // hasResolvableToolUseId
    func testHasResolvableToolUseIdTrueWhenMetadataIdPresent() {
        XCTAssertTrue(questionIntervention(id: "x", metadata: ["tool_use_id": "tu_1"]).hasResolvableToolUseId)
        XCTAssertTrue(questionIntervention(id: "x", metadata: ["originalToolUseId": "tu_1"]).hasResolvableToolUseId)
        XCTAssertTrue(questionIntervention(id: "x", metadata: ["toolUseId": "tu_1"]).hasResolvableToolUseId)
    }

    func testHasResolvableToolUseIdFalseWhenNoIdMetadata() {
        XCTAssertFalse(questionIntervention(id: "notif-1", metadata: [:]).hasResolvableToolUseId)
        XCTAssertFalse(questionIntervention(id: "notif-1", metadata: ["tool_use_id": ""]).hasResolvableToolUseId)
    }

    // isQuestionToolPostToolUse
    func testMatchingIdClears() {
        let iv = questionIntervention(id: "x", metadata: ["tool_use_id": "tu_1"])
        XCTAssertTrue(SessionStore.shared.isQuestionToolPostToolUse(postToolUse(tool: "AskUserQuestion", toolUseId: "tu_1"), matching: iv))
    }

    func testDifferentIdDoesNotClear() {
        let iv = questionIntervention(id: "x", metadata: ["tool_use_id": "tu_1"])
        XCTAssertFalse(SessionStore.shared.isQuestionToolPostToolUse(postToolUse(tool: "AskUserQuestion", toolUseId: "tu_OTHER"), matching: iv))
    }

    func testIdlessInterventionClearsOnAskUserQuestionPostToolUse() {
        let iv = questionIntervention(id: "notif-1", metadata: [:])
        XCTAssertTrue(SessionStore.shared.isQuestionToolPostToolUse(postToolUse(tool: "AskUserQuestion", toolUseId: "tu_1"), matching: iv))
    }

    func testNonQuestionToolDoesNotClear() {
        let iv = questionIntervention(id: "notif-1", metadata: [:])
        XCTAssertFalse(SessionStore.shared.isQuestionToolPostToolUse(postToolUse(tool: "Bash", toolUseId: "tu_1"), matching: iv))
    }

    func testPostToolUseWithoutIdClears() {
        let iv = questionIntervention(id: "x", metadata: ["tool_use_id": "tu_1"])
        XCTAssertTrue(SessionStore.shared.isQuestionToolPostToolUse(postToolUse(tool: "AskUserQuestion", toolUseId: nil), matching: iv))
    }
}
