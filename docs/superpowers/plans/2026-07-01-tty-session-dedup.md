# Terminal-scoped session dedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scope Claude session dedup by terminal identity so two sessions in the same cwd but different terminals each keep their own notch row, while a relaunch in the same terminal still collapses to one.

**Architecture:** Add one `terminalDedupIdentity` computed property to `SessionState`, reused by the two dedup paths that currently key on `provider:cwd` only: the UI-layer filter `SessionMonitor.deduplicateSameProjectClaudeSessions` and the store-layer `SessionStore.endOrphanedSessions`.

**Tech Stack:** Swift, SwiftUI, XCTest, xcodebuild. Tests live in the `PingIslandTests` target (`@testable import Ping_Island`).

## Global Constraints

- Only `.claude` provider sessions are affected; Codex/OpenCode/Qoder dedup paths are untouched.
- The existing pid liveness / execution-evidence / needsManualAttention guards in `endOrphanedSessions` are preserved; do not remove them.
- Terminal-identity normalization: trim whitespace, empty-after-trim is absent, lowercase.
- Commit style: ticket-less Conventional Commits.
- Work happens on branch `feat/tty-session-dedup`.

---

### Task 1: `terminalDedupIdentity` on SessionState

**Files:**
- Modify: `PingIsland/Models/SessionState.swift` (add computed property just above `private nonisolated var hookSurfaceIdentityTokens`, around line 1237)
- Test: `PingIslandTests/SessionTerminalDedupTests.swift` (create)

**Interfaces:**
- Produces: `SessionState.terminalDedupIdentity: String?` — nonisolated, internal. Returns a normalized scalar identifying the terminal surface, or `nil` when no terminal identity is available.

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/SessionTerminalDedupTests.swift`:

```swift
import XCTest
@testable import Ping_Island

final class SessionTerminalDedupTests: XCTestCase {

    private func makeSession(
        sessionId: String = "s1",
        cwd: String = "/tmp/project",
        tty: String? = nil,
        clientInfo: SessionClientInfo? = nil,
        lastActivity: Date = Date()
    ) -> SessionState {
        SessionState(
            sessionId: sessionId,
            cwd: cwd,
            provider: .claude,
            clientInfo: clientInfo,
            tty: tty,
            lastActivity: lastActivity
        )
    }

    // MARK: - terminalDedupIdentity

    func testIdentityPrefersTmuxPaneOverEverything() {
        let info = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude_code",
            name: "Claude Code",
            terminalSessionIdentifier: "term-1",
            iTermSessionIdentifier: "iterm-1",
            tmuxPaneIdentifier: "%3"
        )
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: info).terminalDedupIdentity, "pane:%3")
    }

    func testIdentityFallsBackThroughPriority() {
        let iterm = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", iTermSessionIdentifier: "ITERM-1")
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: iterm).terminalDedupIdentity, "iterm:iterm-1")

        let term = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", terminalSessionIdentifier: "Term-2")
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: term).terminalDedupIdentity, "term:term-2")
    }

    func testIdentityTtyFallbackAndLowercasing() {
        XCTAssertEqual(makeSession(tty: "TTYS004").terminalDedupIdentity, "tty:ttys004")
    }

    func testIdentityTtyFallbackPrefixesRemoteHost() {
        let info = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", remoteHost: "BuildBox")
        XCTAssertEqual(makeSession(tty: "ttys004", clientInfo: info).terminalDedupIdentity, "tty:buildbox:ttys004")
    }

    func testIdentityIsNilWhenNoTerminalInfo() {
        XCTAssertNil(makeSession(tty: nil).terminalDedupIdentity)
        XCTAssertNil(makeSession(tty: "   ").terminalDedupIdentity)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionTerminalDedupTests`
Expected: FAIL to compile with "value of type 'SessionState' has no member 'terminalDedupIdentity'".

- [ ] **Step 3: Write minimal implementation**

In `PingIsland/Models/SessionState.swift`, add immediately above `private nonisolated var hookSurfaceIdentityTokens: Set<String> {`:

```swift
    /// Stable identifier for the terminal surface this session runs in. Used to
    /// keep two concurrent Claude sessions in the same cwd but different
    /// terminals from collapsing into one row, while still collapsing a relaunch
    /// in the same terminal. Returns nil when no terminal identity is available;
    /// callers fall back to sessionId.
    nonisolated var terminalDedupIdentity: String? {
        func normalized(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            return trimmed.lowercased()
        }
        if let pane = normalized(clientInfo.tmuxPaneIdentifier) { return "pane:\(pane)" }
        if let iterm = normalized(clientInfo.iTermSessionIdentifier) { return "iterm:\(iterm)" }
        if let term = normalized(clientInfo.terminalSessionIdentifier) { return "term:\(term)" }
        if let tty = normalized(tty) {
            if let host = normalized(clientInfo.remoteHost) { return "tty:\(host):\(tty)" }
            return "tty:\(tty)"
        }
        return nil
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionTerminalDedupTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Models/SessionState.swift PingIslandTests/SessionTerminalDedupTests.swift
git commit -m "feat: add terminalDedupIdentity to SessionState"
```

---

### Task 2: Terminal-scope the UI dedup key

**Files:**
- Modify: `PingIsland/Services/Session/SessionMonitor.swift` (function signature ~line 859, key line ~869, callsite ~843)
- Test: `PingIslandTests/SessionTerminalDedupTests.swift` (append)

**Interfaces:**
- Consumes: `SessionState.terminalDedupIdentity` (Task 1)
- Produces: `SessionMonitor.deduplicateSameProjectClaudeSessions(from: [SessionState]) -> [SessionState]` — now `nonisolated static`, callable from tests.

- [ ] **Step 1: Write the failing test**

Append to `PingIslandTests/SessionTerminalDedupTests.swift` (inside the class):

```swift
    // MARK: - deduplicateSameProjectClaudeSessions

    func testDifferentTerminalsSameCwdStaySeparate() {
        let a = makeSession(sessionId: "a", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 100))
        let b = makeSession(sessionId: "b", tty: "ttys002", lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [a, b])
        XCTAssertEqual(Set(result.map(\.sessionId)), ["a", "b"])
    }

    func testSameTerminalSameCwdCollapsesToMostRecent() {
        let old = makeSession(sessionId: "old", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 100))
        let new = makeSession(sessionId: "new", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [old, new])
        XCTAssertEqual(result.map(\.sessionId), ["new"])
    }

    func testNoTerminalIdentitySessionsStaySeparate() {
        let a = makeSession(sessionId: "a", tty: nil, lastActivity: Date(timeIntervalSince1970: 100))
        let b = makeSession(sessionId: "b", tty: nil, lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [a, b])
        XCTAssertEqual(Set(result.map(\.sessionId)), ["a", "b"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionTerminalDedupTests`
Expected: FAIL to compile with "deduplicateSameProjectClaudeSessions is inaccessible due to 'private' protection level" (private instance method, not callable as static).

- [ ] **Step 3: Change the function to nonisolated static**

In `PingIsland/Services/Session/SessionMonitor.swift`, change the signature (~line 859) from:

```swift
    private func deduplicateSameProjectClaudeSessions(
        from sessions: [SessionState]
    ) -> [SessionState] {
```

to:

```swift
    nonisolated static func deduplicateSameProjectClaudeSessions(
        from sessions: [SessionState]
    ) -> [SessionState] {
```

- [ ] **Step 4: Update the dedup key**

In the same function, change (~line 869):

```swift
            let key = "\(session.provider.rawValue):\(cwd)"
```

to:

```swift
            let terminal = session.terminalDedupIdentity ?? "session:\(session.sessionId)"
            let key = "\(session.provider.rawValue):\(cwd):\(terminal)"
```

- [ ] **Step 5: Update the callsite**

In `filteredVisibleSessions` (~line 843), change:

```swift
        let dedupedSessions = deduplicateSameProjectClaudeSessions(from: primaryVisibleSessions)
```

to:

```swift
        let dedupedSessions = Self.deduplicateSameProjectClaudeSessions(from: primaryVisibleSessions)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionTerminalDedupTests`
Expected: PASS (8 tests).

- [ ] **Step 7: Commit**

```bash
git add PingIsland/Services/Session/SessionMonitor.swift PingIslandTests/SessionTerminalDedupTests.swift
git commit -m "feat: scope UI session dedup by terminal identity"
```

---

### Task 3: Terminal-scope the store-level orphan removal

**Files:**
- Modify: `PingIsland/Services/State/SessionStore.swift` (function `endOrphanedSessions`, add guard after the `existing.cwd == cwd` guard ~line 2538)
- Test: `PingIslandTests/SessionStoreTerminalOrphanTests.swift` (create)

**Interfaces:**
- Consumes: `SessionState.terminalDedupIdentity` (Task 1); `SessionStore.shared.process(.hookReceived(HookEvent))` and `SessionStore.shared.session(for:)` (existing public API).

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/SessionStoreTerminalOrphanTests.swift`:

```swift
import Foundation
import XCTest
@testable import Ping_Island

/// Verifies endOrphanedSessions only removes a relaunch orphan from the SAME
/// terminal surface, so two concurrent Claude sessions in the same cwd but
/// different terminals both survive.
final class SessionStoreTerminalOrphanTests: XCTestCase {

    func testDifferentTerminalSameCwdSessionsBothSurvive() async {
        let cwd = "/tmp/ttydedup-\(UUID().uuidString)"
        let idA = "orphanA-\(UUID().uuidString)"
        let idB = "orphanB-\(UUID().uuidString)"
        let store = SessionStore.shared

        // Session A in terminal ttys101, no live pid so the pid guard cannot
        // save it — only the terminal-identity guard should.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idA, cwd: cwd, tty: "ttys101")))
        XCTAssertNotNil(await store.session(for: idA))

        // Session B arrives in a DIFFERENT terminal (ttys102), same cwd. This
        // triggers endOrphanedSessions against A.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idB, cwd: cwd, tty: "ttys102")))

        XCTAssertNotNil(await store.session(for: idA),
                        "Different-terminal session must NOT be removed as an orphan")
        XCTAssertNotNil(await store.session(for: idB))

        await store.process(.sessionArchived(sessionId: idA))
        await store.process(.sessionArchived(sessionId: idB))
    }

    func testSameTerminalRelaunchOrphanIsRemoved() async {
        let cwd = "/tmp/ttydedup-\(UUID().uuidString)"
        let idOld = "relaunchOld-\(UUID().uuidString)"
        let idNew = "relaunchNew-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(makeClaudeEvent(sessionId: idOld, cwd: cwd, tty: "ttys201")))
        XCTAssertNotNil(await store.session(for: idOld))

        // Relaunch in the SAME terminal (ttys201): old session is an orphan.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idNew, cwd: cwd, tty: "ttys201")))

        XCTAssertNil(await store.session(for: idOld),
                     "Same-terminal relaunch orphan must be removed")
        XCTAssertNotNil(await store.session(for: idNew))

        await store.process(.sessionArchived(sessionId: idNew))
    }

    // MARK: - Helpers

    private func makeClaudeEvent(
        sessionId: String,
        cwd: String,
        tty: String
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: "UserPromptSubmit",
            status: "processing",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .claudeCode,
                profileID: "claude_code",
                name: "Claude Code",
                bundleIdentifier: "com.anthropic.claudecode"
            ),
            pid: nil,
            tty: tty,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionStoreTerminalOrphanTests`
Expected: `testDifferentTerminalSameCwdSessionsBothSurvive` FAILS — session A is removed as an orphan (pid nil defeats the existing pid guard). `testSameTerminalRelaunchOrphanIsRemoved` passes.

- [ ] **Step 3: Add the same-terminal guard**

In `PingIsland/Services/State/SessionStore.swift`, in `endOrphanedSessions`, immediately after the existing line `guard existing.cwd == cwd else { continue }` (~line 2538), insert:

```swift
            // Only clean up a relaunch orphan from the SAME terminal surface.
            // Two Claude instances in the same cwd but different terminals are
            // legitimate concurrent sessions and must not remove each other.
            guard let terminalIdentity = session.terminalDedupIdentity,
                  existing.terminalDedupIdentity == terminalIdentity else { continue }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/SessionStoreTerminalOrphanTests`
Expected: PASS (2 tests).

Implementation note: test assertions call `await store.session(for:)` into a `let` binding first, then pass the binding to `XCTAssertNil`/`XCTAssertNotNil`, rather than `await`-ing inside the assert's autoclosure argument — Swift 6.1.2 strict concurrency rejects the latter.

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Services/State/SessionStore.swift PingIslandTests/SessionStoreTerminalOrphanTests.swift
git commit -m "fix: only archive same-terminal relaunch orphans"
```

---

### Task 4: Docs + full verification

**Files:**
- Modify: `AGENTS.md` (session-lifecycle / primary-list rules section)

- [ ] **Step 1: Update AGENTS.md**

In `AGENTS.md`, under the change-routing bullet about session lifecycle (the bullet starting "If you change session lifecycle or transitions, start in `SessionStore`"), add a sub-bullet:

```markdown
  - Claude session dedup is scoped by terminal identity (`SessionState.terminalDedupIdentity`: tmux pane / iTerm / terminal-session id, falling back to tty, then sessionId). Two Claude sessions in the same cwd but different terminals stay as separate rows; a relaunch in the same terminal collapses. Both `SessionMonitor.deduplicateSameProjectClaudeSessions` and `SessionStore.endOrphanedSessions` must use this same identity so UI hiding and store removal agree.
```

- [ ] **Step 2: Run the full PingIslandTests suite**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: PASS (whole suite, including the 3 new/appended files).

- [ ] **Step 3: Build the app**

Run: `xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification (jack-loop)**

1. Launch the built app.
2. Open two Ghostty tabs in the same folder, run `claude` in each.
3. Confirm the notch shows TWO rows for that folder, each focusable to its own tab.
4. In one tab, Ctrl-C and re-run `claude`; confirm that tab stays a single row (relaunch collapse).

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs: note terminal-scoped session dedup in AGENTS.md"
```

---

## Self-Review

**Spec coverage:**
- `terminalDedupIdentity` data contract → Task 1.
- Change 1 (UI dedup key) → Task 2.
- Change 2 (endOrphanedSessions guard) → Task 3.
- Edge cases (different terminals, relaunch, no-identity) → Tasks 2 and 3 tests.
- Testing section → Tasks 1-3 tests + Task 4 full suite + manual jack-loop.
- File change list → all files covered across Tasks 1-4.
- Out of scope (pid guard kept, other providers untouched) → honored; no task touches them.

**Placeholder scan:** No TBD/TODO; every code and command step is concrete.

**Type consistency:** `terminalDedupIdentity` returns `String?` and is used identically in Tasks 2 and 3. `deduplicateSameProjectClaudeSessions(from:)` signature is consistent between the definition (Task 2 Step 3) and the test callsite (Task 2 Step 1). `HookEvent` / `SessionClientInfo` / `SessionState` initializers match the real signatures in the codebase.

## Success criteria

- Two Claude sessions in the same cwd but different terminals render as two rows.
- Same-terminal relaunch collapses to one row.
- No-terminal-identity sessions are never hidden by dedup.
- New unit tests pass; full `PingIslandTests` suite passes; app builds.
