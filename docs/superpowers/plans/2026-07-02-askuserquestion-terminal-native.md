# AskUserQuestion terminal-native (full hook exclusion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in setting that stops PingIsland from intercepting Claude Code's AskUserQuestion, so Claude renders its native terminal picker and the island shows nothing for the question.

**Architecture:** All changes live at the hook-install layer plus one setting and its UI. When the setting is on, `HookInstaller` rewrites the Claude Code profile's `PreToolUse` and `PermissionRequest` matchers from `"*"` to a regex that excludes `AskUserQuestion`/`AskFollowupQuestion`, so no bridge envelope is generated for those tools. No `SessionStore` change and no app-side intervention drop.

**Tech Stack:** Swift, XCTest (`PingIslandTests`, `@testable import Ping_Island`), Claude Code `~/.claude/settings.json` JSON hooks.

## Global Constraints

- Setting defaults to `false` (off). Off = today's behavior, byte for byte.
- Scope is the Claude Code hook profile only: `profile.id == "claude-hooks"`. No other client's hooks change.
- Exclusion regex matches every tool name except exactly `AskUserQuestion` and `AskFollowupQuestion`: `^(?!(?:AskUserQuestion|AskFollowupQuestion)$).+$` (validated in node against Bash/Edit/Read/Write/Task → match, the two question tools → excluded).
- Only `PreToolUse` and `PermissionRequest` matchers are rewritten. `PostToolUse` stays `.matcher("*")`.
- No app-side intervention drop: excluding at the matcher is the whole mechanism. Dropping an intervention while a pre-toggle session's blocking `PreToolUse` still waits would hang Claude on that hook.
- Takes effect on the next Claude session (Claude reads `settings.json` at session start). The Settings UI must say so.
- The persisted defaults key is shared between `AppSettingsStore` and `HookInstaller` via `AppSettingsDefaultKeys` (no duplicated string literal).
- Commit style: ticket-less Conventional Commits. Branch `main`. Commit ticket-less; do NOT ask about a Jira ticket.

---

### Task 1: Live fail-fast gate (manual, controller-run — NOT a dispatched subagent task)

This task verifies the one external unknown before any Swift is written: does Claude Code's matcher engine accept the negative-lookahead regex and actually stop firing the `PreToolUse` hook for `AskUserQuestion`. Prior manual exclusion attempts did not take effect (PreToolUse kept firing in `~/.ping-island-debug/claude-hooks/20260701.jsonl`); cause unknown. If this gate fails, adjust the approach (see Fallback) before proceeding.

**Files:** none (edits the live `~/.claude/settings.json`, reversibly).

- [ ] **Step 1: Back up the live settings**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-askuq
```

- [ ] **Step 2: Rewrite only the two matchers**

In `~/.claude/settings.json`, under `hooks`, change the `PreToolUse` and `PermissionRequest` entries' `"matcher": "*"` to `"matcher": "^(?!(?:AskUserQuestion|AskFollowupQuestion)$).+$"`. Leave the `command`, `type`, `timeout`, and every other event (`PostToolUse`, `Notification`, `Stop`, `SessionStart`, etc.) untouched. Confirm the file still parses:

```bash
python3 -c "import json;json.load(open('$HOME/.claude/settings.json'));print('ok')"
```
Expected: `ok`

- [ ] **Step 3: Restart a Claude session and trigger a question**

Start a fresh Claude Code session (the edit only applies to new sessions), then have it call AskUserQuestion (e.g. ask it a question that makes it use the tool).

- [ ] **Step 4: Verify the outcome**

Confirm both:
1. Claude renders its native terminal picker for the question (the island does NOT pop a question card).
2. No `PreToolUse` envelope for AskUserQuestion arrives. Check the bridge log for a recent AskUserQuestion PreToolUse:

```bash
grep -c '"tool_name": *"AskUserQuestion"' ~/.ping-island-debug/claude-hooks/$(date -u +%Y%m%d).jsonl 2>/dev/null || echo 0
```
Compare against events after the restart time; the picker rendering (outcome 1) is the primary signal.

- [ ] **Step 5: Restore the backup**

```bash
mv ~/.claude/settings.json.bak-askuq ~/.claude/settings.json
```

**Gate:** If the native picker rendered, the mechanism is confirmed — proceed to Task 2 as written. **Fallback** (if the regex was rejected or PreToolUse still fired): replace the exclusion regex in every later task with an explicit allow-list matcher built from the specific tool names Claude reports in the bridge log (join them with `|`, e.g. `^(?:Bash|Edit|Read|Write|Task|...)$`), and record the discovered tool list in the progress ledger. The rest of the plan structure is unchanged.

---

### Task 2: Matcher exclusion in the hook installer

**Files:**
- Modify: `PingIsland/Core/Settings.swift` (add the shared defaults key to `AppSettingsDefaultKeys`, enum at line 12)
- Modify: `PingIsland/Services/Hooks/HookInstaller.swift` (add exclusion helper + read the key in `effectiveEvents`, line 821)
- Test: `PingIslandTests/AskUserQuestionExclusionTests.swift` (create)

**Interfaces:**
- Produces: `AppSettingsDefaultKeys.terminalHandlesAskUserQuestion: String` (= `"terminalHandlesAskUserQuestion"`), consumed by Task 3.
- Produces: `HookInstaller.askUserQuestionExclusionMatcher: String` and `HookInstaller.applyingAskUserQuestionTerminalExclusion(to:enabled:profileID:) -> [HookInstallEventDescriptor]` (internal static, nonisolated), tested here.
- Consumes: `HookInstallEventDescriptor(name:templates:timeout:)`, `HookInstallEntryTemplate.matcher(String)` / `.plain` / `.direct` (all in `PingIsland/Models/ClientProfile.swift`).

- [ ] **Step 1: Write the failing tests**

Create `PingIslandTests/AskUserQuestionExclusionTests.swift`:

```swift
import XCTest
@testable import Ping_Island

final class AskUserQuestionExclusionTests: XCTestCase {

    private func descriptor(_ name: String, _ templates: [HookInstallEntryTemplate], timeout: Int? = nil) -> HookInstallEventDescriptor {
        HookInstallEventDescriptor(name: name, templates: templates, timeout: timeout)
    }

    // Pure helper: scope + rewrite behavior
    func testExclusionRewritesClaudePreAndPermissionMatchers() {
        let events = [
            descriptor("PreToolUse", [.matcher("*")]),
            descriptor("PostToolUse", [.matcher("*")]),
            descriptor("PermissionRequest", [.matcher("*")], timeout: 86_400),
            descriptor("Stop", [.plain]),
        ]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: true, profileID: "claude-hooks")
        func matcher(_ name: String) -> String? {
            guard let e = out.first(where: { $0.name == name }), case .matcher(let m) = e.templates.first else { return nil }
            return m
        }
        XCTAssertEqual(matcher("PreToolUse"), HookInstaller.askUserQuestionExclusionMatcher)
        XCTAssertEqual(matcher("PermissionRequest"), HookInstaller.askUserQuestionExclusionMatcher)
        XCTAssertEqual(matcher("PostToolUse"), "*") // untouched
        // Stop stays .plain; PermissionRequest keeps its timeout
        let perm = try? XCTUnwrap(out.first { $0.name == "PermissionRequest" })
        XCTAssertEqual(perm??.timeout, 86_400)
        if let stop = out.first(where: { $0.name == "Stop" }) {
            if case .plain = stop.templates.first {} else { XCTFail("Stop template changed") }
        }
    }

    func testExclusionDisabledLeavesMatchersUntouched() {
        let events = [descriptor("PreToolUse", [.matcher("*")])]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: false, profileID: "claude-hooks")
        if case .matcher(let m) = out[0].templates.first { XCTAssertEqual(m, "*") } else { XCTFail() }
    }

    func testExclusionScopedToClaudeProfileOnly() {
        let events = [descriptor("PreToolUse", [.matcher("*")])]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: true, profileID: "codex-hooks")
        if case .matcher(let m) = out[0].templates.first { XCTAssertEqual(m, "*") } else { XCTFail() }
    }

    // Regex behavior
    func testExclusionMatcherRegexExcludesOnlyQuestionTools() throws {
        let re = try NSRegularExpression(pattern: HookInstaller.askUserQuestionExclusionMatcher)
        func matches(_ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        XCTAssertFalse(matches("AskUserQuestion"))
        XCTAssertFalse(matches("AskFollowupQuestion"))
        for t in ["Bash", "Edit", "Read", "Write", "Task"] { XCTAssertTrue(matches(t), t) }
    }

    // Real emitted settings.json via the public install path
    func testTemporarySettingsFileExcludesQuestionToolsWhenEnabled() throws {
        let key = AppSettingsDefaultKeys.terminalHandlesAskUserQuestion
        let had = UserDefaults.standard.object(forKey: key) != nil
        let prev = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { had ? UserDefaults.standard.set(prev, forKey: key) : UserDefaults.standard.removeObject(forKey: key) }

        let url = try XCTUnwrap(HookInstaller.createTemporarySettingsFile(for: "claude-hooks"))
        defer { HookInstaller.removeTemporarySettingsFile(at: url) }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.first?["matcher"] as? String, HookInstaller.askUserQuestionExclusionMatcher)
        let perm = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(perm.first?["matcher"] as? String, HookInstaller.askUserQuestionExclusionMatcher)
        let post = try XCTUnwrap(hooks["PostToolUse"] as? [[String: Any]])
        XCTAssertEqual(post.first?["matcher"] as? String, "*")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AskUserQuestionExclusionTests`
Expected: FAIL to compile (`applyingAskUserQuestionTerminalExclusion`, `askUserQuestionExclusionMatcher`, `AppSettingsDefaultKeys.terminalHandlesAskUserQuestion` missing).

- [ ] **Step 3: Add the shared defaults key**

In `PingIsland/Core/Settings.swift`, inside `enum AppSettingsDefaultKeys` (line 12), add:

```swift
    static let terminalHandlesAskUserQuestion = "terminalHandlesAskUserQuestion"
```

- [ ] **Step 4: Add the exclusion helper + matcher constant**

In `PingIsland/Services/Hooks/HookInstaller.swift`, add these to the `HookInstaller` struct (near `effectiveEvents`, ~line 821):

```swift
    /// Matches every tool name except AskUserQuestion / AskFollowupQuestion.
    /// Used to exclude Claude's question tools from the intervention-producing
    /// hooks so Claude renders its native terminal picker instead.
    static let askUserQuestionExclusionMatcher = "^(?!(?:AskUserQuestion|AskFollowupQuestion)$).+$"

    /// When enabled for the Claude Code profile, rewrites the PreToolUse and
    /// PermissionRequest tool matchers to exclude the question tools. Other
    /// events, other profiles, and the disabled case are returned untouched.
    static func applyingAskUserQuestionTerminalExclusion(
        to events: [HookInstallEventDescriptor],
        enabled: Bool,
        profileID: String
    ) -> [HookInstallEventDescriptor] {
        guard enabled, profileID == "claude-hooks" else { return events }
        let rewritten: Set<String> = ["PreToolUse", "PermissionRequest"]
        return events.map { event in
            guard rewritten.contains(event.name) else { return event }
            let templates = event.templates.map { template -> HookInstallEntryTemplate in
                if case .matcher = template { return .matcher(askUserQuestionExclusionMatcher) }
                return template
            }
            return HookInstallEventDescriptor(name: event.name, templates: templates, timeout: event.timeout)
        }
    }
```

- [ ] **Step 5: Wire the helper into `effectiveEvents`**

In `PingIsland/Services/Hooks/HookInstaller.swift`, replace `effectiveEvents(for:)` (currently at line 821):

```swift
    private static func effectiveEvents(for profile: ManagedHookClientProfile) -> [HookInstallEventDescriptor] {
        let base = profile.supportsEventSelection
            ? loadSelection(for: profile).filteredEvents(for: profile)
            : profile.events
        return applyingAskUserQuestionTerminalExclusion(
            to: base,
            enabled: UserDefaults.standard.bool(forKey: AppSettingsDefaultKeys.terminalHandlesAskUserQuestion),
            profileID: profile.id
        )
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AskUserQuestionExclusionTests`
Expected: PASS (5 tests).

- [ ] **Step 7: Commit**

```bash
git add PingIsland/Core/Settings.swift PingIsland/Services/Hooks/HookInstaller.swift PingIslandTests/AskUserQuestionExclusionTests.swift
git commit -m "feat: exclude AskUserQuestion from Claude hooks when terminal-native is on"
```

---

### Task 3: Persisted setting on `AppSettingsStore`

**Files:**
- Modify: `PingIsland/Core/Settings.swift` (`final class AppSettingsStore` at line 388: add the published property + its bootstrap init)
- Test: `PingIslandTests/AskUserQuestionExclusionTests.swift` (add a setting-persistence test)

**Interfaces:**
- Consumes: `AppSettingsDefaultKeys.terminalHandlesAskUserQuestion` (Task 2).
- Produces: `AppSettingsStore.shared.terminalHandlesAskUserQuestion: Bool` (default `false`), consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Add to `PingIslandTests/AskUserQuestionExclusionTests.swift`:

```swift
    func testSettingDefaultsToFalseAndPersists() {
        let key = AppSettingsDefaultKeys.terminalHandlesAskUserQuestion
        let had = UserDefaults.standard.object(forKey: key) != nil
        let prev = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { had ? UserDefaults.standard.set(prev, forKey: key) : UserDefaults.standard.removeObject(forKey: key) }

        // Property exists and mirrors the persisted default (false when unset).
        XCTAssertFalse(AppSettingsStore.shared.terminalHandlesAskUserQuestion)
        AppSettingsStore.shared.terminalHandlesAskUserQuestion = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        AppSettingsStore.shared.terminalHandlesAskUserQuestion = false
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AskUserQuestionExclusionTests/testSettingDefaultsToFalseAndPersists`
Expected: FAIL to compile (`terminalHandlesAskUserQuestion` not a member of `AppSettingsStore`).

- [ ] **Step 3: Add the published property**

In `PingIsland/Core/Settings.swift`, add to `AppSettingsStore`, next to `routePromptsToTerminal` (~line 946):

```swift
    @Published var terminalHandlesAskUserQuestion: Bool {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(terminalHandlesAskUserQuestion, forKey: AppSettingsDefaultKeys.terminalHandlesAskUserQuestion)
            recordTelemetrySettingChange(
                key: AppSettingsDefaultKeys.terminalHandlesAskUserQuestion,
                value: terminalHandlesAskUserQuestion.description
            )
        }
    }
```

(No hook reinstall here — the model stays pure persistence. The reinstall side effect is wired in the UI in Task 4, mirroring how the existing settings views own reinstall.)

- [ ] **Step 4: Add the bootstrap initializer**

In `PingIsland/Core/Settings.swift`, in the `AppSettingsStore` init where the other `_x = Published(initialValue:)` lines live (near line 1564 for `_routePromptsToTerminal`), add:

```swift
        _terminalHandlesAskUserQuestion = Published(initialValue: Self.boolValue(
            from: defaults,
            key: AppSettingsDefaultKeys.terminalHandlesAskUserQuestion,
            exists: persistedKeys.contains(AppSettingsDefaultKeys.terminalHandlesAskUserQuestion),
            default: false
        ))
```

- [ ] **Step 5: Run test to verify it passes**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/AskUserQuestionExclusionTests/testSettingDefaultsToFalseAndPersists`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add PingIsland/Core/Settings.swift PingIslandTests/AskUserQuestionExclusionTests.swift
git commit -m "feat: add terminalHandlesAskUserQuestion setting"
```

---

### Task 4: Settings UI toggle + reinstall on change

**Files:**
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift` (add a Toggle bound to the setting + `.onChange` that reinstalls the Claude hooks; the view model's `reinstallHooks(for:)` at line 433 already handles Developer ID vs App Store)

**Interfaces:**
- Consumes: `AppSettingsStore.shared.terminalHandlesAskUserQuestion` (Task 3); `ClientProfileRegistry.managedHookProfile(id:)`, `HookInstaller.isInstalled(_:)`, and the view model's `reinstallHooks(for:)`.

This task is UI wiring with no unit test (the reinstall path is exercised by the existing settings flow and by Task 1's live check). Verify by building and by manual toggle.

- [ ] **Step 1: Add the toggle to the hooks/integration settings section**

In `PingIsland/UI/Views/SettingsWindowView.swift`, in the section that already shows hook/prompt-routing settings (near the `routePromptsToTerminal` UI), add a toggle bound to `settings.terminalHandlesAskUserQuestion`. Match the surrounding toggles' exact style and the file's settings singleton reference (`AppSettingsStore.shared`). Use a label and caption such as:

```swift
Toggle(AppLocalization.string("讓終端處理 Claude 的提問"), isOn: $settings.terminalHandlesAskUserQuestion)
Text(AppLocalization.string("開啟後，Claude 的 AskUserQuestion 由終端原生選單處理，靈動島不再顯示該提問。下一個 Claude session 生效。"))
    .font(.caption)
    .foregroundStyle(.secondary)
```

Add both localization keys to `PingIsland/Resources/zh-Hant.lproj/Localizable.strings` and `PingIsland/Resources/en.lproj/Localizable.strings` (Traditional Chinese value for zh-Hant; an English value for en), following the existing entries' format.

- [ ] **Step 2: Reinstall Claude hooks when the toggle changes**

Attach an `.onChange` to the enclosing view (mirror the existing `.onChange(of: settings.soundThemeMode)` usage in this file) that reinstalls the Claude hooks only when they are currently installed, so the new matcher is written to `~/.claude/settings.json`:

```swift
.onChange(of: settings.terminalHandlesAskUserQuestion) { _, _ in
    if let profile = ClientProfileRegistry.managedHookProfile(id: "claude-hooks"),
       HookInstaller.isInstalled(profile) {
        viewModel.reinstallHooks(for: profile)
    }
}
```

Use the actual view-model instance name in this view (the one that owns `reinstallHooks(for:)`, `reinstallingHookProfileID`). If the toggle and the reinstall method live on the same view model, call it directly.

- [ ] **Step 3: Build**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual check**

Launch the app, open Settings, toggle the new switch on. Confirm `~/.claude/settings.json` now has the exclusion regex on `PreToolUse` and `PermissionRequest` and `"*"` elsewhere:

```bash
python3 -c "import json;h=json.load(open('$HOME/.claude/settings.json'))['hooks'];print('Pre',h['PreToolUse'][0]['matcher']);print('Perm',h['PermissionRequest'][0]['matcher']);print('Post',h['PostToolUse'][0]['matcher'])"
```
Expected: `Pre` and `Perm` show the regex; `Post` shows `*`. Toggle off → all three back to `*`.

- [ ] **Step 5: Commit**

```bash
git add PingIsland/UI/Views/SettingsWindowView.swift PingIsland/Resources/zh-Hant.lproj/Localizable.strings PingIsland/Resources/en.lproj/Localizable.strings
git commit -m "feat: settings toggle for terminal-native AskUserQuestion"
```

---

### Task 5: Full suite + AGENTS.md note

**Files:**
- Modify: `AGENTS.md` (one line under the AskUserQuestion / hook-matcher area, if a natural anchor exists)

- [ ] **Step 1: Run the full app test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Document the behavior**

Add one line to `AGENTS.md` near the Claude hook / matcher notes: the Claude Code profile's `PreToolUse` + `PermissionRequest` matchers exclude `AskUserQuestion`/`AskFollowupQuestion` when `AppSettingsDefaultKeys.terminalHandlesAskUserQuestion` is set, so Claude renders its native terminal picker; the switch reinstalls hooks and takes effect on the next Claude session.

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: note terminal-native AskUserQuestion hook exclusion"
```

---

## Self-Review

**Spec coverage:**
- Setting, default off → Task 3.
- Matcher exclusion (Pre + PermissionRequest, Claude only, PostToolUse untouched) → Task 2.
- Reinstall on toggle → Task 4 Step 2.
- Settings UI + "next Claude session" note → Task 4 Step 1.
- Risk / fail-fast live check + whitelist fallback → Task 1.
- Scope guard (Claude only) → Task 2 helper + `testExclusionScopedToClaudeProfileOnly`.
- Tests (matcher on/off, scope, emitted JSON, persistence) → Task 2 + Task 3.
- No app-side drop → honored by construction (no SessionStore/SessionEvent change in any task).

**Placeholder scan:** No TBD/TODO. Task 1 is intentionally manual (live external behavior, not unit-testable); its fallback is concrete. Task 4 has no unit test by design (UI wiring) with a manual verification step.

**Type consistency:** `applyingAskUserQuestionTerminalExclusion(to:enabled:profileID:)`, `askUserQuestionExclusionMatcher`, `AppSettingsDefaultKeys.terminalHandlesAskUserQuestion`, `AppSettingsStore.terminalHandlesAskUserQuestion`, `HookInstallEventDescriptor(name:templates:timeout:)`, `HookInstallEntryTemplate.matcher`, profile id `"claude-hooks"` — consistent across tasks and verified against the codebase.

## Success criteria

- Setting off (default) → Claude hooks identical to today; all existing tests pass.
- Setting on + fresh Claude session → native terminal picker renders, island shows no question card.
- Toggling rewrites `~/.claude/settings.json` (Pre/PermissionRequest regex, PostToolUse `*`), preserving other events and clients.
- New tests pass; app builds; full `PingIslandTests` green.
