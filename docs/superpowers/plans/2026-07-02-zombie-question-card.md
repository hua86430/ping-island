# Clear stuck AskUserQuestion cards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear a resolved AskUserQuestion notch card even when the intervention carries no `tool_use_id` to match against, without wrongly clearing a different concurrent question that does carry an id.

**Architecture:** Add `SessionIntervention.hasResolvableToolUseId`, then extend `SessionStore.isQuestionToolPostToolUse` so an AskUserQuestion `PostToolUse` clears the current question when the id matches OR the intervention has no resolvable tool-use-id at all.

**Tech Stack:** Swift, XCTest (`PingIslandTests`, `@testable import Ping_Island`).

## Global Constraints

- Strict id matching is preserved when the intervention carries a real tool-use-id (concurrent-question safety); the relaxed clear only applies when the intervention has no resolvable id.
- No behavior change for PreToolUse/PermissionRequest-origin cards (they carry the id and match as before).
- Commit style: ticket-less Conventional Commits. Branch `main`.

---

### Task 1: Clear id-less AskUserQuestion cards on PostToolUse

**Files:**
- Modify: `PingIsland/Models/SessionProvider.swift` (add `hasResolvableToolUseId` right after `matchesResolvedToolUseId`, ~line 1109)
- Modify: `PingIsland/Services/State/SessionStore.swift` (`isQuestionToolPostToolUse`: make it testable + add the branch)
- Test: `PingIslandTests/QuestionCardClearingTests.swift` (create)

**Interfaces:**
- Produces: `SessionIntervention.hasResolvableToolUseId: Bool` (nonisolated); `SessionStore.isQuestionToolPostToolUse(_:matching:) -> Bool` becomes `nonisolated` + internal (drop `private`) so it is unit-testable.

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/QuestionCardClearingTests.swift`. Construct fixtures with the real initializers — READ `SessionIntervention` (struct at `PingIsland/Models/SessionProvider.swift:958`; stored fields `id, kind, title, message, options, questions, supportsSessionScope, metadata`) and the `HookEvent` initializer (see any existing test, e.g. `PingIslandTests/SessionStoreLivenessSweepTests.swift`, for the exact argument list) and match them exactly — do not invent parameter names.

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/QuestionCardClearingTests`
Expected: FAIL to compile (`hasResolvableToolUseId` missing; `isQuestionToolPostToolUse` inaccessible/private). After making it accessible, `testIdlessInterventionClearsOnAskUserQuestionPostToolUse` fails (currently returns false).

- [ ] **Step 3: Add `hasResolvableToolUseId`**

In `PingIsland/Models/SessionProvider.swift`, immediately after `matchesResolvedToolUseId(_:)` (ends ~line 1109), add:

```swift
    /// True when the intervention carries a real tool-use-id we can match a
    /// PostToolUse against. Notification-origin (and suppress-path) questions
    /// have none, so a matching-tool PostToolUse cannot be id-correlated to them.
    nonisolated var hasResolvableToolUseId: Bool {
        [metadata["originalToolUseId"], metadata["toolUseId"], metadata["tool_use_id"]]
            .contains { ($0?.isEmpty == false) }
    }
```

- [ ] **Step 4: Make `isQuestionToolPostToolUse` testable + add the clear branch**

In `PingIsland/Services/State/SessionStore.swift`, change the signature from `private func` to `nonisolated func` (drop `private`, add `nonisolated`) and add the id-less clear branch. The full method becomes:

```swift
    nonisolated func isQuestionToolPostToolUse(
        _ event: HookEvent,
        matching intervention: SessionIntervention?
    ) -> Bool {
        guard event.event == "PostToolUse" else { return false }
        let normalizedTool = event.tool?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard normalizedTool == "askuserquestion" || normalizedTool == "askfollowupquestion" else {
            return false
        }
        guard let toolUseId = event.toolUseId else {
            return true
        }
        if intervention?.matchesResolvedToolUseId(toolUseId) == true {
            return true
        }
        // The intervention carries no tool_use_id to disambiguate against (e.g.
        // a Notification-origin question); a completed AskUserQuestion means this
        // question is done, so clear it instead of leaving a stuck card.
        return intervention?.hasResolvableToolUseId == false
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/QuestionCardClearingTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Full suite + build (no regression)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PingIsland/Models/SessionProvider.swift PingIsland/Services/State/SessionStore.swift PingIslandTests/QuestionCardClearingTests.swift
git commit -m "fix: clear stuck AskUserQuestion cards with no tool_use_id"
```

---

## Self-Review

**Spec coverage:**
- `hasResolvableToolUseId` (metadata-only, id not counted) → Step 3.
- Relaxed clear for id-less interventions + preserved strict match → Step 4.
- Behavior table (match / different-id / id-less / no-event-id / non-question) → tests in Step 1.
- Concurrent-question safety (real id → strict) → `testDifferentIdDoesNotClear`.

**Placeholder scan:** No TBD; test fixtures reference the real `SessionIntervention`/`HookEvent` initializers with an explicit instruction to match them (the one soft spot — the implementer confirms the exact init argument list from the struct + an existing test).

**Type consistency:** `hasResolvableToolUseId`, `isQuestionToolPostToolUse(_:matching:)`, `matchesResolvedToolUseId(_:)`, and `SessionIntervention` fields match the current codebase.

## Success criteria

- A resolved AskUserQuestion clears its card even when it had no `tool_use_id`.
- A concurrent question with its own id is not wrongly cleared.
- No change to PreToolUse/PermissionRequest-origin clearing.
- New tests + full `PingIslandTests` pass; app builds.
