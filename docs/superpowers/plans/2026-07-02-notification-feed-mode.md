# Notification feed mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in toggle that turns the opened Island's session list into an iPhone-style unread feed: only sessions with new activity show, tapping a row focuses its terminal and clears it, a top-right Clear All empties the feed, and the collapsed island shows an unread count.

**Architecture:** A per-session in-memory `lastSeenAt` timestamp on `SessionState` (derived `hasUnread = lastActivity > lastSeenAt`), mutated only through the `SessionStore` actor. A persisted `notificationFeedMode` toggle gates: (a) `IslandOpenedContentView`'s `.sessionList` route swapping `SessionListView` for a new `NotificationFeedView`, (b) a one-line exemption in `SessionMonitor.filteredVisibleSessions` so unread sessions ignore the 30-minute idle hide, (c) an unread-count badge on the collapsed notch.

**Tech Stack:** Swift, SwiftUI, XCTest (`PingIslandTests`, `@testable import Ping_Island`).

## Global Constraints

- Toggle key/name is exactly `notificationFeedMode`, default `false`. Toggle OFF must be pixel-identical to today (no behavior change anywhere).
- "Clear" ALWAYS means mark-as-seen. Never archive, never end, never remove a session from the store. A cleared session reappears in the feed on new activity.
- `lastSeenAt` is in-memory only (NOT persisted). Its default value is `Date()` at `SessionState` creation, which makes launch-restored sessions start seen (feed starts empty) with zero special launch code.
- Every site in `SessionStore` that constructs a `SessionState(...)` while carrying fields over from an existing session MUST pass `lastSeenAt: existing.lastSeenAt` — the reconstruction sites are at SessionStore.swift lines ~284, ~334, ~4384, ~4455, ~4501 (verify each; a missed site silently marks the session seen).
- All `lastSeenAt` mutation goes through the `SessionStore` actor (`markSessionSeen`, `markAllSessionsSeen`). No view mutates state directly.
- Feed rows: only `hasUnread == true`, sorted `lastActivity` descending.
- SourceKit editor diagnostics ("No such module 'XCTest'", "Cannot find X in scope") are known false positives in this repo; the xcodebuild result is authoritative.
- Localization convention: Simplified-Chinese literal is the lookup key in Swift; add matching entries to BOTH `PingIsland/Resources/zh-Hant.lproj/Localizable.strings` (Traditional value, correct characters — 終端機/顯示/點一下) and `PingIsland/Resources/en.lproj/Localizable.strings` (English value).
- Commit style: ticket-less Conventional Commits on branch `main`. Commit ticket-less; do NOT ask about a Jira ticket.
- Test command template: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:<TARGET>`

---

### Task 1: Unread model (`lastSeenAt` / `hasUnread` / mark-seen)

**Files:**
- Modify: `PingIsland/Models/SessionState.swift` (field near line 108 `var lastActivity: Date`; init param near line 151; assignment near line 184; derived var near the other derived helpers ~line 191)
- Modify: `PingIsland/Services/State/SessionStore.swift` (thread `lastSeenAt` through the `SessionState(` reconstruction sites at ~284, ~334, ~4384, ~4455, ~4501; add `markSessionSeen` / `markAllSessionsSeen`)
- Modify: `PingIsland/Services/Session/SessionMonitor.swift` (forwarding methods, mirroring how `archiveSession(sessionId:)` forwards to the store)
- Test: `PingIslandTests/NotificationFeedTests.swift` (create)

**Interfaces:**
- Produces: `SessionState.lastSeenAt: Date` (stored, default `Date()`), `SessionState.hasUnread: Bool` (derived), `SessionStore.markSessionSeen(sessionId: String)`, `SessionStore.markAllSessionsSeen()`, and `SessionMonitor.markSessionSeen(sessionId:)` / `SessionMonitor.markAllSessionsSeen()` (main-actor forwarders). Tasks 3 and 4 consume all of these.

- [ ] **Step 1: Write the failing tests**

Create `PingIslandTests/NotificationFeedTests.swift`. IMPORTANT: `SessionState`'s memberwise init has many parameters with defaults — READ the real init (PingIsland/Models/SessionState.swift, init starts near line 117) and existing test fixtures (`rg "SessionState(" PingIslandTests Prototype/Tests` for examples) and construct sessions by passing ONLY the required parameters plus the ones under test. Do not invent parameter names. The test logic must be exactly:

```swift
import XCTest
@testable import Ping_Island

final class NotificationFeedTests: XCTestCase {

    // Build a minimal SessionState. Fill the required init parameters from the
    // real initializer; set only sessionId/cwd/provider-style essentials plus
    // the two dates under test.
    private func makeSession(
        id: String = "s1",
        lastActivity: Date,
        lastSeenAt: Date
    ) -> SessionState {
        // ... construct with the real memberwise init, passing
        // lastActivity: lastActivity, lastSeenAt: lastSeenAt ...
    }

    func testHasUnreadTruthTable() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        // activity after seen → unread
        XCTAssertTrue(makeSession(lastActivity: base.addingTimeInterval(10), lastSeenAt: base).hasUnread)
        // seen at same instant as activity → read
        XCTAssertFalse(makeSession(lastActivity: base, lastSeenAt: base).hasUnread)
        // seen after activity → read
        XCTAssertFalse(makeSession(lastActivity: base, lastSeenAt: base.addingTimeInterval(10)).hasUnread)
    }

    func testDefaultLastSeenAtMakesFreshSessionRead() {
        // A session created "now" with lastActivity defaulting to now must not
        // be unread at creation (feed starts empty on launch).
        // Construct with the init's DEFAULTS for both dates (pass neither).
        // Then assert hasUnread == false.
    }

    func testMarkSessionSeenClearsUnread() async {
        // Drive through the real store: insert a session whose lastActivity is
        // newer than lastSeenAt (unread), call markSessionSeen, read it back,
        // assert hasUnread == false. Use SessionStore.shared only if the store
        // exposes a test seam; otherwise test the mutation semantics at the
        // SessionState level: verify that setting lastSeenAt = Date() on a
        // session whose lastActivity is in the past flips hasUnread to false.
        var session = makeSession(lastActivity: Date(timeIntervalSinceNow: -60), lastSeenAt: Date(timeIntervalSinceNow: -120))
        XCTAssertTrue(session.hasUnread)
        session.lastSeenAt = Date()
        XCTAssertFalse(session.hasUnread)
    }
}
```

(If `SessionStore` offers no clean test seam for actor-level insert/read, keep `testMarkSessionSeenClearsUnread` at the SessionState level as shown — the actor methods are one-line mutations and the reconstruction threading is covered by Step 4's checklist.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`
Expected: FAIL to compile (`lastSeenAt` / `hasUnread` not members of `SessionState`).

- [ ] **Step 3: Add the stored field + derived property**

In `PingIsland/Models/SessionState.swift`:

Next to `var lastActivity: Date` (line ~108) add:

```swift
    /// When the user last "saw" this session (notification-feed read marker).
    /// In-memory only: defaults to creation time, so sessions restored at app
    /// launch start read and the notification feed starts empty.
    var lastSeenAt: Date
```

In the memberwise init parameter list, next to `lastActivity: Date = Date()` (line ~151) add:

```swift
        lastSeenAt: Date = Date(),
```

Next to `self.lastActivity = lastActivity` (line ~184) add:

```swift
        self.lastSeenAt = lastSeenAt
```

Near the other derived helpers (e.g. below `needsPromptNotification`, ~line 202) add:

```swift
    /// True when the session has activity the user has not seen yet.
    nonisolated var hasUnread: Bool {
        lastActivity > lastSeenAt
    }
```

- [ ] **Step 4: Thread `lastSeenAt` through SessionStore reconstruction sites**

In `PingIsland/Services/State/SessionStore.swift`, inspect EVERY `SessionState(` construction (grep `= SessionState(`; currently lines ~284, ~334, ~4384, ~4455, ~4501). For each site that copies fields from an existing session (a local named `existing`, `session`, or similar whose values are being carried into the new instance), add `lastSeenAt: existing.lastSeenAt` (using that site's actual variable name). Sites that create a genuinely NEW session from an event (no prior state carried over) keep the default. Record in your report which sites you changed and which you left on the default, with one line of justification each.

- [ ] **Step 5: Add the actor mutations + monitor forwarders**

In `PingIsland/Services/State/SessionStore.swift` (inside `actor SessionStore`, near the other simple mutation methods):

```swift
    func markSessionSeen(sessionId: String) {
        let resolvedSessionId = resolveCodexSessionAlias(sessionId)
        guard var session = sessions[resolvedSessionId] else { return }
        session.lastSeenAt = Date()
        sessions[resolvedSessionId] = session
        // Propagate exactly the way archiveSession does after mutating
        // `sessions` (same publish/notify call at the end of that method).
    }

    func markAllSessionsSeen() {
        let now = Date()
        for (id, var session) in sessions {
            session.lastSeenAt = now
            sessions[id] = session
        }
        // Same publish/notify as above.
    }
```

READ `archiveSession(sessionId:)` to the end and copy the exact publish/notify call it uses after mutating `sessions` (do not invent a name; reuse whatever that method calls). If `archiveSession` is `private` and reached through a public wrapper or `process(...)` action, expose `markSessionSeen`/`markAllSessionsSeen` the same way that wrapper pattern does.

In `PingIsland/Services/Session/SessionMonitor.swift`, add main-actor forwarders mirroring the existing `archiveSession(sessionId:)` forwarder (same Task/await shape):

```swift
    func markSessionSeen(sessionId: String) {
        Task { await SessionStore.shared.markSessionSeen(sessionId: sessionId) }
    }

    func markAllSessionsSeen() {
        Task { await SessionStore.shared.markAllSessionsSeen() }
    }
```

(Match the actual forwarder style used by the existing monitor methods — if they are `async` and `await` directly, do the same.)

- [ ] **Step 6: Run the new tests + build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add PingIsland/Models/SessionState.swift PingIsland/Services/State/SessionStore.swift PingIsland/Services/Session/SessionMonitor.swift PingIslandTests/NotificationFeedTests.swift
git commit -m "feat: per-session unread model (lastSeenAt/hasUnread/markSeen)"
```

---

### Task 2: `notificationFeedMode` setting + Settings UI

**Files:**
- Modify: `PingIsland/Core/Settings.swift` (key in `enum AppSettingsDefaultKeys` ~line 12; `@Published` var near `terminalHandlesAskUserQuestion` ~line 956; bootstrap init near `_terminalHandlesAskUserQuestion` ~line 1577; static accessor in `enum AppSettings` ~line 1657)
- Modify: `PingIsland/UI/Views/SettingsWindowView.swift` (one `SettingsToggleLine`)
- Modify: `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`, `PingIsland/Resources/en.lproj/Localizable.strings`
- Test: `PingIslandTests/NotificationFeedTests.swift` (add one persistence test)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `AppSettingsStore.notificationFeedMode: Bool` (default false), static `AppSettings.notificationFeedMode: Bool` (get/set forwarder). Tasks 3 and 4 read these.

- [ ] **Step 1: Write the failing test**

Add to `PingIslandTests/NotificationFeedTests.swift` (isolated-suite pattern, identical to `AskUserQuestionExclusionTests.testSettingDefaultsToFalseAndPersists`):

```swift
    @MainActor
    func testNotificationFeedModeDefaultsToFalseAndPersists() {
        let key = AppSettingsDefaultKeys.notificationFeedMode
        let suiteName = "test-\(key)-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: suite, bridgeRuntimeConfigWriter: { _ in })

        XCTAssertFalse(store.notificationFeedMode)
        store.notificationFeedMode = true
        XCTAssertTrue(suite.bool(forKey: key))
        store.notificationFeedMode = false
        XCTAssertFalse(suite.bool(forKey: key))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests/testNotificationFeedModeDefaultsToFalseAndPersists`
Expected: FAIL to compile (`notificationFeedMode` missing).

- [ ] **Step 3: Add the setting (four parts)**

In `PingIsland/Core/Settings.swift`:

1. In `enum AppSettingsDefaultKeys` (~line 12):
```swift
    static let notificationFeedMode = "notificationFeedMode"
```

2. In `AppSettingsStore`, next to `terminalHandlesAskUserQuestion` (~line 956) — pure persistence, NO bridge-config write, NO hook reinstall:
```swift
    @Published var notificationFeedMode: Bool {
        didSet {
            guard !isBootstrapping else { return }
            defaults.set(notificationFeedMode, forKey: AppSettingsDefaultKeys.notificationFeedMode)
            recordTelemetrySettingChange(
                key: AppSettingsDefaultKeys.notificationFeedMode,
                value: notificationFeedMode.description
            )
        }
    }
```

3. In the init, next to `_terminalHandlesAskUserQuestion = Published(...)` (~line 1577):
```swift
        _notificationFeedMode = Published(initialValue: Self.boolValue(
            from: defaults,
            key: AppSettingsDefaultKeys.notificationFeedMode,
            exists: persistedKeys.contains(AppSettingsDefaultKeys.notificationFeedMode),
            default: false
        ))
```

4. In `enum AppSettings` (~line 1657), next to the other static forwarders (`soundEnabled` etc.):
```swift
    static var notificationFeedMode: Bool {
        get { shared.notificationFeedMode }
        set { shared.notificationFeedMode = newValue }
    }
```

- [ ] **Step 4: Add the Settings toggle + localization**

In `PingIsland/UI/Views/SettingsWindowView.swift`, add a `SettingsToggleLine` in a fitting section of the notch/appearance-related settings (near where the session-list / notch behavior toggles live; if none is clearly better, put it in the section holding `routePromptsToTerminal` at ~line 3155, after that card's rows, with a `SettingsLineDivider()`):

```swift
SettingsLineDivider()

SettingsToggleLine(
    title: "通知中心模式",
    subtitle: "开启后展开的岛只显示有新动态的 session（未读），点一下跳到终端并清除该通知；右上角可清除全部。关闭则显示全部 session。",
    isOn: $settings.notificationFeedMode
)
```

Add to `PingIsland/Resources/zh-Hant.lproj/Localizable.strings`:
```
"通知中心模式" = "通知中心模式";
"开启后展开的岛只显示有新动态的 session（未读），点一下跳到终端并清除该通知；右上角可清除全部。关闭则显示全部 session。" = "開啟後展開的島只顯示有新動態的 session（未讀），點一下跳到終端機並清除該通知；右上角可清除全部。關閉則顯示全部 session。";
```

Add to `PingIsland/Resources/en.lproj/Localizable.strings`:
```
"通知中心模式" = "Notification center mode";
"开启后展开的岛只显示有新动态的 session（未读），点一下跳到终端并清除该通知；右上角可清除全部。关闭则显示全部 session。" = "When on, the expanded island lists only sessions with new activity (unread); click one to jump to its terminal and clear it, or use Clear All in the top-right. When off, all sessions are listed.";
```

- [ ] **Step 5: Run test + build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add PingIsland/Core/Settings.swift PingIsland/UI/Views/SettingsWindowView.swift PingIsland/Resources/zh-Hant.lproj/Localizable.strings PingIsland/Resources/en.lproj/Localizable.strings PingIslandTests/NotificationFeedTests.swift
git commit -m "feat: add notificationFeedMode setting and toggle"
```

---

### Task 3: `NotificationFeedView` + route switch + idle-hide exemption

**Files:**
- Create: `PingIsland/UI/Views/NotificationFeedView.swift`
- Modify: `PingIsland/UI/Views/IslandOpenedContentView.swift` (the `.sessionList` case, lines ~42-48)
- Modify: `PingIsland/Services/Session/SessionMonitor.swift` (`filteredVisibleSessions`, line ~838: one-line exemption)
- Test: `PingIslandTests/NotificationFeedTests.swift` (feed filter/sort tests)

**Interfaces:**
- Consumes: `SessionState.hasUnread`, `SessionMonitor.markSessionSeen(sessionId:)`, `SessionMonitor.markAllSessionsSeen()` (Task 1); `AppSettings.notificationFeedMode` (Task 2); existing `SessionLauncher.shared.activate(_:)`, `NotchViewModel.notchClose()`.
- Produces: `NotificationFeedView(sessionMonitor:viewModel:)` SwiftUI view; `NotificationFeedView.feedSessions(from:) -> [SessionState]` (nonisolated static, unit-tested).

- [ ] **Step 1: Write the failing tests**

Add to `PingIslandTests/NotificationFeedTests.swift`:

```swift
    func testFeedSessionsOnlyUnreadNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let unreadOld = makeSession(id: "old", lastActivity: base.addingTimeInterval(10), lastSeenAt: base)
        let unreadNew = makeSession(id: "new", lastActivity: base.addingTimeInterval(100), lastSeenAt: base)
        let read = makeSession(id: "read", lastActivity: base, lastSeenAt: base.addingTimeInterval(1))

        let feed = NotificationFeedView.feedSessions(from: [read, unreadOld, unreadNew])
        XCTAssertEqual(feed.map(\.sessionId), ["new", "old"])
    }

    func testFeedIncludesUnreadOlderThanThirtyMinutes() {
        // Unread exempt from the 30-minute idle hide: an unread session whose
        // lastActivity is 45 minutes old must still be in the feed.
        let old = Date(timeIntervalSinceNow: -45 * 60)
        let stale = makeSession(id: "stale", lastActivity: old, lastSeenAt: old.addingTimeInterval(-1))
        XCTAssertEqual(NotificationFeedView.feedSessions(from: [stale]).map(\.sessionId), ["stale"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`
Expected: FAIL to compile (`NotificationFeedView` missing).

- [ ] **Step 3: Create `NotificationFeedView`**

Create `PingIsland/UI/Views/NotificationFeedView.swift`. Row visuals: reuse the existing list's look by composing the same building blocks the session list rows use (client mascot via `MascotView`, session display name, project/folder line, relative timestamp) — READ `SessionListView`'s `InstanceRow` for the exact fonts/colors/spacing and mirror a lightweight version; do NOT reuse `InstanceRow` itself (its click behaviors and action cluster don't apply). Structure:

```swift
import SwiftUI

struct NotificationFeedView: View {
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    /// Pure feed selection: unread only, newest activity first.
    nonisolated static func feedSessions(from sessions: [SessionState]) -> [SessionState] {
        sessions
            .filter(\.hasUnread)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    private var feed: [SessionState] {
        Self.feedSessions(from: sessionMonitor.instances)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(appLocalized: "新通知")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if !feed.isEmpty {
                    Button(appLocalized: "清除全部") {
                        sessionMonitor.markAllSessionsSeen()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if feed.isEmpty {
                Text(appLocalized: "没有新通知")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(feed) { session in
                            NotificationFeedRow(session: session) {
                                open(session)
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func open(_ session: SessionState) {
        viewModel.notchClose()
        sessionMonitor.markSessionSeen(sessionId: session.sessionId)
        Task {
            _ = await SessionLauncher.shared.activate(session)
        }
    }
}
```

`NotificationFeedRow`: a `Button(action:)` (Buttons capture clicks reliably in the notch; `.onTapGesture` does not — this repo learned that in 0.24.10/0.24.11) whose label mirrors the session-list row style (mascot + name + folder + preview + relative time). Copy the concrete fonts/colors from `InstanceRow` while writing it. If `Text(appLocalized:)` is not an existing initializer in this codebase, use the same localization call the neighboring views use (`AppLocalization.string(...)` — grep one usage and match it). Add the three new strings to BOTH Localizable.strings files:

zh-Hant: `"新通知" = "新通知";` `"清除全部" = "清除全部";` `"没有新通知" = "沒有新通知";`
en: `"新通知" = "Notifications";` `"清除全部" = "Clear All";` `"没有新通知" = "No new notifications";`

- [ ] **Step 4: Switch the `.sessionList` route**

In `PingIsland/UI/Views/IslandOpenedContentView.swift`, replace the `.sessionList` case (lines ~42-48):

```swift
        case .sessionList:
            if settings.notificationFeedMode {
                NotificationFeedView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel
                )
            } else {
                SessionListView(
                    sessionMonitor: sessionMonitor,
                    viewModel: viewModel,
                    enableKeyboardNavigation: surface == .docked,
                    highlightedSessionStableID: highlightedSessionStableID
                )
            }
```

(`settings` is already an `@ObservedObject` on this view — `AppSettings.shared` at line 6.)

- [ ] **Step 5: Idle-hide exemption for unread in feed mode**

In `PingIsland/Services/Session/SessionMonitor.swift`, `filteredVisibleSessions` (line ~838), change the primary filter:

```swift
        let feedMode = AppSettings.notificationFeedMode
        let primaryVisibleSessions = sessions.filter {
            (!$0.shouldHideFromPrimaryUI || (feedMode && $0.hasUnread))
                && $0.shouldDisplaySubagent(in: visibilityMode)
        }
```

(Everything else in the method stays byte-identical. `SessionMonitor` is `@MainActor`, so reading `AppSettings` is legal — same as the existing `AppSettings.subagentVisibilityMode` read one line above.)

- [ ] **Step 6: Run tests + build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`
Expected: PASS (6 tests).
Then: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PingIsland/UI/Views/NotificationFeedView.swift PingIsland/UI/Views/IslandOpenedContentView.swift PingIsland/Services/Session/SessionMonitor.swift PingIsland/Resources/zh-Hant.lproj/Localizable.strings PingIsland/Resources/en.lproj/Localizable.strings PingIslandTests/NotificationFeedTests.swift
git commit -m "feat: notification feed view with clear-all and tap-to-focus-and-clear"
```

---

### Task 4: Collapsed-island unread count badge

**Files:**
- Modify: `PingIsland/UI/Views/NotchView.swift` (closed-state `headerRow`, ~line 644; the closed HStack that shows the mascot)

**Interfaces:**
- Consumes: `SessionState.hasUnread` (Task 1), `AppSettings.notificationFeedMode` (Task 2), `sessionMonitor.instances` (already available in `NotchView`, see the attention pick at line ~208).

- [ ] **Step 1: Add the badge**

In `PingIsland/UI/Views/NotchView.swift`, add a computed count near the other session-derived helpers (e.g. near the attention session pick at ~line 208):

```swift
    private var unreadFeedCount: Int {
        guard AppSettings.shared.notificationFeedMode else { return 0 }
        return sessionMonitor.instances.filter(\.hasUnread).count
    }
```

In `headerRow`'s closed layout (the `HStack(spacing: 0)` branch that shows `MascotView` when `viewModel.status != .opened`, ~line 655), add a small numeric badge displayed only when `viewModel.status != .opened && unreadFeedCount > 0`, styled consistently with the closed notch (small capsule, ~10pt semibold, subtle background). Place it on the trailing side of the closed content, next to any existing status affordance — READ the closed HStack fully first and pick the slot that does not collide with the existing badge/spinner logic:

```swift
                    if viewModel.status != .opened && unreadFeedCount > 0 {
                        Text("\(unreadFeedCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
```

Toggle OFF (or zero unread) → `unreadFeedCount == 0` → no badge, closed notch pixel-identical to today.

- [ ] **Step 2: Build + visual sanity**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PingIsland/UI/Views/NotchView.swift
git commit -m "feat: unread count badge on collapsed island in feed mode"
```

---

### Task 5: Full suite + docs

**Files:**
- Modify: `AGENTS.md` (one line), `TODO.md`

- [ ] **Step 1: Full app test suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Document**

`AGENTS.md`: one line in the Change Routing section near the session-list / idle-visibility rules: when `notificationFeedMode` is on, the opened Island's `.sessionList` route renders `NotificationFeedView` (unread-only via `SessionState.hasUnread`/`lastSeenAt`, exempt from the 30-minute idle hide), tap = focus terminal + `markSessionSeen`, Clear All = `markAllSessionsSeen`, and the collapsed island shows an unread count; trace `SessionState`, `SessionStore`, `SessionMonitor.filteredVisibleSessions`, `IslandOpenedContentView`, and `NotificationFeedView` together.

`TODO.md`: mark the notification-feed item done with the commit range.

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md TODO.md
git commit -m "docs: note notification feed mode routing"
```

---

## Self-Review

**Spec coverage:** toggle default off → Task 2; unread model + relaunch-empty (default `lastSeenAt = Date()`) → Task 1; feed unread-only newest-first + 30-min exemption + Clear All + tap-focus-and-clear + empty state → Task 3; collapsed badge → Task 4; toggle-off parity → Tasks 3/4 gating (`notificationFeedMode` guards every new path); testing list in spec → Tasks 1-3 tests; docs → Task 5.

**Placeholder scan:** `makeSession` body and one publish-call name are deliberate read-the-real-init/method directives with exact anchors (memberwise init ~40 params; inventing names would be worse) — each names the precise source to copy from. No TBDs.

**Type consistency:** `lastSeenAt: Date`, `hasUnread`, `markSessionSeen(sessionId:)`, `markAllSessionsSeen()`, `notificationFeedMode`, `NotificationFeedView.feedSessions(from:)` consistent across tasks.

## Success criteria

- Toggle OFF: behavior identical to today (all suites green, no visual change).
- Toggle ON: feed shows only unread (newest first, incl. >30-min-old unread); tap row → terminal focused + row gone; Clear All empties feed; badge shows unread count on collapsed island; cleared session reappears on new activity; relaunch starts empty.
