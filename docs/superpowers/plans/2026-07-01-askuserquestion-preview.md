# AskUserQuestion non-blocking preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in setting that makes Claude `AskUserQuestion` non-blocking — Claude Code renders its native picker in the terminal while the Island shows a read-only preview instead of hijacking the answer.

**Architecture:** A new `claudeQuestionPreviewOnly` flag flows Settings → `BridgeRuntimeConfigWriter` → `BridgeRuntimeConfig` → `HookPayloadMapper`, mirroring the existing `routePromptsToTerminal` flag. When on, the mapper marks a Claude AskUserQuestion envelope non-blocking (`expectsResponse=false`) but keeps the question intervention and sets `suppress_in_app_prompt`, so the Island renders it via the existing `suppressInAppPromptControls` notify-only path.

**Tech Stack:** Swift, XCTest. Shared logic + mapper tests in `Prototype/Tests`; app settings tests in `PingIslandTests`.

## Global Constraints

- Scoped to `provider == .claude` and an intervention of `InterventionKind.question` (AskUserQuestion). Approvals (`.approval`) and non-Claude providers are unaffected.
- Default OFF. Flag off = current behavior (Island answers, terminal blocks).
- The `BridgeRuntimeConfig` JSON schema in `IslandShared` and the `BridgeRuntimeConfigWriter` payload must stay in sync (both gain the same key `claudeQuestionPreviewOnly`).
- Localization keys stay Simplified (project convention); add the toggle's zh-Hant + en values.
- Commit style: ticket-less Conventional Commits.
- Feasibility gate: before building the Settings UI, verify live that a non-blocking hook return makes Claude Code render its native AskUserQuestion picker (Task 2, Step 6).

---

### Task 1: Runtime-config flag round-trip

**Files:**
- Modify: `Prototype/Sources/IslandShared/BridgeRuntimeConfig.swift`
- Modify: `PingIsland/Services/Hooks/BridgeRuntimeConfigWriter.swift`
- Test: `Prototype/Tests/IslandTests/BridgeRuntimeConfigTests.swift` (create)

**Interfaces:**
- Produces: `BridgeRuntimeConfig.claudeQuestionPreviewOnly: Bool` (default false; JSON key `claudeQuestionPreviewOnly`); `BridgeRuntimeConfigSnapshot.claudeQuestionPreviewOnly: Bool` written under the same key.

- [ ] **Step 1: Write the failing test**

Create `Prototype/Tests/IslandTests/BridgeRuntimeConfigTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Prototype --filter BridgeRuntimeConfigTests`
Expected: FAIL to compile — `claudeQuestionPreviewOnly` does not exist.

- [ ] **Step 3: Add the field to `BridgeRuntimeConfig`**

In `Prototype/Sources/IslandShared/BridgeRuntimeConfig.swift`:

Add the stored property + init parameter:

```swift
public struct BridgeRuntimeConfig: Sendable, Equatable {
    public var routePromptsToTerminal: Bool
    public var claudeQuestionPreviewOnly: Bool
    public var debugLogPolicy: BridgeDebugLogPolicy

    public init(
        routePromptsToTerminal: Bool = false,
        claudeQuestionPreviewOnly: Bool = false,
        debugLogPolicy: BridgeDebugLogPolicy = .default
    ) {
        self.routePromptsToTerminal = routePromptsToTerminal
        self.claudeQuestionPreviewOnly = claudeQuestionPreviewOnly
        self.debugLogPolicy = debugLogPolicy
    }
```

In `load(from:)`, read the key and pass it:

```swift
        let route = (json["routePromptsToTerminal"] as? Bool) ?? false
        let previewOnly = (json["claudeQuestionPreviewOnly"] as? Bool) ?? false
        return BridgeRuntimeConfig(
            routePromptsToTerminal: route,
            claudeQuestionPreviewOnly: previewOnly,
            debugLogPolicy: BridgeDebugLogPolicy(jsonObject: json)
        )
```

In `jsonObject`, serialize it:

```swift
    public var jsonObject: [String: Any] {
        var object = debugLogPolicy.jsonObject
        object["routePromptsToTerminal"] = routePromptsToTerminal
        object["claudeQuestionPreviewOnly"] = claudeQuestionPreviewOnly
        return object
    }
```

- [ ] **Step 4: Add the field to the writer snapshot + payload**

In `PingIsland/Services/Hooks/BridgeRuntimeConfigWriter.swift`, add the key to `payloadData`:

```swift
        let payload: [String: Any] = [
            "routePromptsToTerminal": config.routePromptsToTerminal,
            "claudeQuestionPreviewOnly": config.claudeQuestionPreviewOnly,
            "debugLoggingEnabled": config.debugLoggingEnabled,
            "debugLogRetentionDays": config.debugLogRetentionDays,
            "debugLogMaxDirectoryMegabytes": config.debugLogMaxDirectoryMegabytes
        ]
```

Add the stored property + init parameter to `BridgeRuntimeConfigSnapshot`:

```swift
    let routePromptsToTerminal: Bool
    let claudeQuestionPreviewOnly: Bool
    let debugLoggingEnabled: Bool
    let debugLogRetentionDays: Int
    let debugLogMaxDirectoryMegabytes: Int

    init(
        routePromptsToTerminal: Bool,
        claudeQuestionPreviewOnly: Bool = false,
        debugLoggingEnabled: Bool = Self.defaultDebugLoggingEnabled,
        debugLogRetentionDays: Int = Self.defaultDebugLogRetentionDays,
        debugLogMaxDirectoryMegabytes: Int = Self.defaultDebugLogMaxDirectoryMegabytes
    ) {
        self.routePromptsToTerminal = routePromptsToTerminal
        self.claudeQuestionPreviewOnly = claudeQuestionPreviewOnly
        self.debugLoggingEnabled = debugLoggingEnabled
        self.debugLogRetentionDays = Self.clampedDebugLogRetentionDays(debugLogRetentionDays)
        self.debugLogMaxDirectoryMegabytes = Self.clampedDebugLogMaxDirectoryMegabytes(debugLogMaxDirectoryMegabytes)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Prototype --filter BridgeRuntimeConfigTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Prototype/Sources/IslandShared/BridgeRuntimeConfig.swift PingIsland/Services/Hooks/BridgeRuntimeConfigWriter.swift Prototype/Tests/IslandTests/BridgeRuntimeConfigTests.swift
git commit -m "feat: add claudeQuestionPreviewOnly to bridge runtime config"
```

---

### Task 2: Mapper gate + live feasibility check

**Files:**
- Modify: `Prototype/Sources/IslandShared/HookPayloadMapper.swift` (`makeEnvelope`, lines ~41-68)
- Test: `Prototype/Tests/IslandTests/HookPayloadMapperTests.swift` (append)

**Interfaces:**
- Consumes: `BridgeRuntimeConfig.claudeQuestionPreviewOnly` (Task 1); `InterventionKind.question` (`Models.swift:87`).

- [ ] **Step 1: Write the failing test**

Append to `Prototype/Tests/IslandTests/HookPayloadMapperTests.swift`. (Mirror the arguments/stdin an existing AskUserQuestion test in this file uses — reuse its helper for building a Claude `AskUserQuestion` `stdinData`/`arguments`; the assertions below are the new behavior.)

```swift
    func testClaudeQuestionPreviewOnlyMakesQuestionNonBlockingButKeepsPreview() {
        let envelope = HookPayloadMapper.makeEnvelope(
            source: .claude,
            arguments: claudeAskUserQuestionArguments(),
            environment: [:],
            stdinData: claudeAskUserQuestionStdin(),
            runtimeConfig: BridgeRuntimeConfig(claudeQuestionPreviewOnly: true)
        )
        XCTAssertEqual(envelope.intervention?.kind, .question)   // preview preserved
        XCTAssertFalse(envelope.expectsResponse)                 // not blocking
        XCTAssertEqual(envelope.metadata["suppress_in_app_prompt"], "true")
    }

    func testClaudeQuestionStillBlocksWhenPreviewOnlyDisabled() {
        let envelope = HookPayloadMapper.makeEnvelope(
            source: .claude,
            arguments: claudeAskUserQuestionArguments(),
            environment: [:],
            stdinData: claudeAskUserQuestionStdin(),
            runtimeConfig: BridgeRuntimeConfig(claudeQuestionPreviewOnly: false)
        )
        XCTAssertEqual(envelope.intervention?.kind, .question)
        XCTAssertTrue(envelope.expectsResponse)
        XCTAssertNil(envelope.metadata["suppress_in_app_prompt"])
    }
```

If the file has no reusable `claudeAskUserQuestion*` helpers, add them next to the test using the exact same stdin/arguments shape as the existing AskUserQuestion mapping test in this file (do not invent a new payload shape).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Prototype --filter HookPayloadMapperTests`
Expected: FAIL — `testClaudeQuestionPreviewOnly...` fails because `expectsResponse` is still true and `suppress_in_app_prompt` is not set.

- [ ] **Step 3: Add the gate in `makeEnvelope`**

In `HookPayloadMapper.swift`, right after `detectedIntervention` is computed (after the closing `)` of the `detectIntervention(...)` call, ~line 48), insert:

```swift
        let isClaudePreviewQuestion = runtimeConfig.claudeQuestionPreviewOnly
            && source == .claude
            && detectedIntervention?.kind == .question
        if isClaudePreviewQuestion {
            // Non-blocking preview: keep the intervention for a read-only Island
            // card, but let Claude Code render its native picker in the terminal.
            metadata["suppress_in_app_prompt"] = "true"
        }
```

Then replace the existing `expectsResponse` assignment (the `runtimeConfig.routePromptsToTerminal ? false : detectExpectsResponse(...)` ternary, ~lines 61-68) with:

```swift
        let expectsResponse: Bool
        if runtimeConfig.routePromptsToTerminal || isClaudePreviewQuestion {
            expectsResponse = false
        } else {
            expectsResponse = detectExpectsResponse(
                eventType: eventType,
                payload: payload,
                clientKind: clientKind,
                intervention: intervention
            )
        }
```

Leave the `intervention` binding as-is (`runtimeConfig.routePromptsToTerminal ? nil : detectedIntervention`): for the preview case `routePromptsToTerminal` is unrelated, so the question intervention is preserved for the Island preview.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Prototype --filter HookPayloadMapperTests`
Expected: PASS (both new tests + existing mapper tests).

- [ ] **Step 5: Commit**

```bash
git add Prototype/Sources/IslandShared/HookPayloadMapper.swift Prototype/Tests/IslandTests/HookPayloadMapperTests.swift
git commit -m "feat: map Claude AskUserQuestion to non-blocking preview when enabled"
```

- [ ] **Step 6: Live feasibility gate (manual, before building UI)**

Rebuild the bridge/app so the new mapper is live, then manually enable the flag without the Settings UI:
1. Edit `~/.ping-island/bridge-config.json` and add `"claudeQuestionPreviewOnly": true`.
2. In a terminal, run `claude` and drive it to an `AskUserQuestion`.
3. Confirm: the terminal renders Claude Code's native question picker (not blocked), and the Island shows a read-only preview (question + options, no submit button).

If the terminal does NOT render the native picker (Claude hangs or shows nothing), STOP and report — the non-blocking premise is wrong and the design must change before proceeding. Revert the manual edit afterward.

---

### Task 3: Settings field + snapshot wiring

**Files:**
- Modify: `PingIsland/Core/Settings.swift` (Keys ~457; `@Published` ~946; `bridgeRuntimeConfigSnapshot` ~1034; init load ~1558)
- Test: `PingIslandTests/AppSettingsPersistenceTests.swift` (append)

**Interfaces:**
- Consumes: `BridgeRuntimeConfigSnapshot.claudeQuestionPreviewOnly` (Task 1).
- Produces: `AppSettings.claudeQuestionPreviewOnly: Bool` (persisted, default false; included in `bridgeRuntimeConfigSnapshot`).

- [ ] **Step 1: Write the failing test**

Append to `PingIslandTests/AppSettingsPersistenceTests.swift` (match the file's existing pattern for constructing an `AppSettings` with a scratch `UserDefaults`):

```swift
    func testClaudeQuestionPreviewOnlyPersistsAndReachesSnapshot() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
        settings.claudeQuestionPreviewOnly = true

        XCTAssertTrue(defaults.bool(forKey: "claudeQuestionPreviewOnly"))
        XCTAssertTrue(settings.bridgeRuntimeConfigSnapshot.claudeQuestionPreviewOnly)

        let reloaded = AppSettings(defaults: defaults, bridgeRuntimeConfigWriter: { _ in })
        XCTAssertTrue(reloaded.claudeQuestionPreviewOnly)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AppSettingsPersistenceTests` (prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)
Expected: FAIL to compile — `claudeQuestionPreviewOnly` does not exist.

- [ ] **Step 3: Add the key**

In `Settings.swift`, in the `Keys` enum (near line 457):

```swift
        static let claudeQuestionPreviewOnly = "claudeQuestionPreviewOnly"
```

- [ ] **Step 4: Add the published property**

After the `routePromptsToTerminal` published property (~line 953), add:

```swift
    @Published var claudeQuestionPreviewOnly: Bool {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(claudeQuestionPreviewOnly, forKey: Keys.claudeQuestionPreviewOnly)
            recordTelemetrySettingChange(key: Keys.claudeQuestionPreviewOnly, value: claudeQuestionPreviewOnly.description)
            writeEffectiveBridgeRuntimeConfig()
        }
    }
```

- [ ] **Step 5: Include it in the snapshot**

In `bridgeRuntimeConfigSnapshot` (~line 1034):

```swift
    var bridgeRuntimeConfigSnapshot: BridgeRuntimeConfigSnapshot {
        BridgeRuntimeConfigSnapshot(
            routePromptsToTerminal: effectiveRoutePromptsToTerminal,
            claudeQuestionPreviewOnly: claudeQuestionPreviewOnly,
            debugLoggingEnabled: hookDebugLoggingEnabled,
            debugLogRetentionDays: hookDebugLogRetentionDays,
            debugLogMaxDirectoryMegabytes: hookDebugLogMaxDirectoryMegabytes
        )
    }
```

- [ ] **Step 6: Load it in init**

In `init`, next to where `_routePromptsToTerminal` is initialized (~line 1564):

```swift
        _claudeQuestionPreviewOnly = Published(initialValue: Self.boolValue(
            from: defaults,
            key: Keys.claudeQuestionPreviewOnly,
            exists: persistedKeys.contains(Keys.claudeQuestionPreviewOnly),
            default: false
        ))
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AppSettingsPersistenceTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add PingIsland/Core/Settings.swift PingIslandTests/AppSettingsPersistenceTests.swift
git commit -m "feat: add claudeQuestionPreviewOnly setting wired to bridge config"
```

---

### Task 4: Settings toggle + localization + docs + full verification

**Files:**
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift` (integration "审批与提问" section ~3155)
- Modify: `PingIsland/Resources/en.lproj/Localizable.strings`, `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add the toggle**

In `SettingsWindowView.swift`, inside the `SettingsSectionCard(title: "审批与提问")`, after the `routePromptsToTerminal` toggle + its `SettingsLineDivider()` (~line 3160), add:

```swift
                SettingsToggleLine(
                    title: "Claude 问题留在终端",
                    subtitle: "开启后 Claude 的 AskUserQuestion 会在终端里回答，Island 只显示只读预览，不再拦截作答。",
                    isOn: $settings.claudeQuestionPreviewOnly
                )
                SettingsLineDivider()
```

- [ ] **Step 2: Add localization values (keys stay Simplified)**

Append to `PingIsland/Resources/en.lproj/Localizable.strings`:

```
"Claude 问题留在终端" = "Keep Claude questions in the terminal";
"开启后 Claude 的 AskUserQuestion 会在终端里回答，Island 只显示只读预览，不再拦截作答。" = "When on, Claude's AskUserQuestion is answered in the terminal and the Island shows a read-only preview instead of intercepting the answer.";
```

Append to `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`:

```
"Claude 问题留在终端" = "Claude 問題留在終端";
"开启后 Claude 的 AskUserQuestion 会在终端里回答，Island 只显示只读预览，不再拦截作答。" = "開啟後 Claude 的 AskUserQuestion 會在終端裡回答，Island 只顯示唯讀預覽，不再攔截作答。";
```

- [ ] **Step 3: Update AGENTS.md**

Under the change-routing bullet about hook payload shape / intervention semantics, add a sub-bullet:

```markdown
  - `claudeQuestionPreviewOnly` (Settings → `BridgeRuntimeConfigWriter` → `BridgeRuntimeConfig` → `HookPayloadMapper`): when on, a Claude `AskUserQuestion` (`InterventionKind.question`) is made non-blocking (`expectsResponse=false`) with `suppress_in_app_prompt` set, so Claude Code renders its native picker in the terminal and the Island shows a read-only preview via `suppressInAppPromptControls`. Approvals and non-Claude providers are unaffected. Default off.
```

- [ ] **Step 4: Full build + test suites**

Run: `swift test --package-path Prototype --filter "BridgeRuntimeConfigTests|HookPayloadMapperTests"`
Expected: PASS.
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual verification (jack-loop)**

Launch the built app. In Settings, toggle "Claude 問題留在終端" ON. Run `claude` in a terminal, trigger an `AskUserQuestion`: confirm the terminal shows the native picker, the Island shows a read-only preview (no submit), answering in the terminal proceeds, and the preview clears. Toggle OFF and confirm the old Island-answer behavior returns.

- [ ] **Step 6: Commit**

```bash
git add PingIsland/UI/Views/SettingsWindowView.swift PingIsland/Resources/en.lproj/Localizable.strings PingIsland/Resources/zh-Hant.lproj/Localizable.strings AGENTS.md
git commit -m "feat: add Settings toggle for Claude AskUserQuestion preview"
```

---

## Self-Review

**Spec coverage:**
- Runtime-config flag (Settings→writer→config→mapper) → Tasks 1 + 3.
- Mapper gate (claude + question → non-blocking + keep intervention + suppress_in_app_prompt) → Task 2.
- Island read-only preview → reuses existing `suppressInAppPromptControls` (no new UI); driven by `suppress_in_app_prompt` set in Task 2.
- Settings GUI toggle, default off → Tasks 3 + 4.
- Feasibility gate → Task 2 Step 6 (before UI).
- Approvals / non-Claude unaffected → mapper gate condition + Task 2 second test.
- Localization keys stay Simplified + zh-Hant/en values → Task 4 Step 2.

**Placeholder scan:** Test helpers in Task 2 Step 1 are explicitly tied to the existing AskUserQuestion mapping test's payload shape rather than invented; every other step has concrete code/commands.

**Type consistency:** `claudeQuestionPreviewOnly` used identically across `BridgeRuntimeConfig`, `BridgeRuntimeConfigSnapshot`, `AppSettings`, and the mapper. `InterventionKind.question`, `SettingsToggleLine(title:subtitle:isOn:)`, and `bridgeRuntimeConfigSnapshot` match the current codebase.

## Success criteria

- Toggle ON: Claude AskUserQuestion renders natively in the terminal, Island shows a non-blocking read-only preview, terminal never blocks on the Island.
- Toggle OFF (default): current behavior unchanged.
- Approvals + non-Claude providers unchanged.
- New unit tests + full `PingIslandTests` + Prototype mapper/config tests pass; app builds.
