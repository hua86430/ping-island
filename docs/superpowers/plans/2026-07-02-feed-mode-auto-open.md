# Feed mode auto-open decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In notification feed mode, the island auto-opens only for actionable attention (stays) or as a 5-second self-closing banner; a bare new session never pops it; session mode is byte-identical to today.

**Architecture:** Two surgical changes in `NotchView`: (1) gate the new-pending-session auto-open (`handlePendingSessionsChange`) behind a pure decision function that, in feed mode, requires `needsPromptNotification`; (2) a feed-banner dismissal timer mirroring the existing completion-notification timer (5 s, hover cancels, hover-exit closes, same close guards), armed when a `.notification`-opened panel is left showing the feed. Hover plumbing rides the same pattern as the completion card's.

**Tech Stack:** Swift, SwiftUI, XCTest (`PingIslandTests`).

## Global Constraints

- Session mode (toggle off): every trigger byte-identical to today. Every new behavior is gated on `AppSettings.notificationFeedMode` (views/NotchView may read `AppSettings.shared.notificationFeedMode` — main-actor).
- Attention opens (`needsPromptNotification`) never get a timer: they stay until handled/gesture.
- The completion-card flow's own 5 s timer, queue chaining, and hover semantics are UNTOUCHED.
- Banner timer duration = 5 seconds, same as the completion flow (shared literal is fine; do not add a setting).
- Timer close guard identical to the completion one: only `notchClose()` when `viewModel.status == .opened && viewModel.openReason == .notification && !hasPendingPermission && !hasHumanIntervention`.
- `previousPendingIds` bookkeeping in `handlePendingSessionsChange` must update on every call (all early-return paths already do; keep it that way).
- SourceKit editor diagnostics ("No such module", "Cannot find X in scope") are known build-graph false positives; xcodebuild is authoritative.
- Commit ticket-less Conventional Commits on `main`; do NOT ask about a Jira ticket.
- Test command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotificationFeedTests`

---

### Task 1: Gate the new-pending-session auto-open

**Files:**
- Modify: `PingIsland/UI/Views/NotchView.swift` (`handlePendingSessionsChange`, ~line 1020)
- Test: `PingIslandTests/NotificationFeedTests.swift` (append; reuse the existing `makeSession` helper — it already supports `lastNotifiableActivityAt`)

**Interfaces:**
- Produces: `NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending:feedMode:) -> Bool` (nonisolated static, new enum in NotchView.swift or a small new file `PingIsland/Core/NotchAutoOpenPolicy.swift` — prefer the new file; it will also host Task 2's predicate).

- [ ] **Step 1: Write the failing tests**

Append to `PingIslandTests/NotificationFeedTests.swift`. To make a session `needsPromptNotification`, construct it with a `.question` intervention — READ how existing tests build `SessionIntervention` (e.g. `PingIslandTests/QuestionCardClearingTests.swift` has a `questionIntervention` fixture; copy its construction) and pass `intervention:` through `SessionState`'s memberwise init (the `makeSession` helper may need an optional `intervention:` parameter added — extend it, do not fork it). A bare prompt-ready session is `makeSession(...)` with `phase: .waitingForInput` and no intervention (extend the helper with `phase:` defaulting to `.idle` if needed).

```swift
    func testAutoOpenPolicyForNewPendingSessions() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let bareReady = makeSession(id: "ready", lastActivity: base, lastSeenAt: base, phase: .waitingForInput)
        let question = makeSession(id: "q", lastActivity: base, lastSeenAt: base, phase: .waitingForInput, intervention: questionIntervention())

        // Session mode: any new pending opens (today's behavior).
        XCTAssertTrue(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady], feedMode: false))
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [], feedMode: false))

        // Feed mode: bare prompt-ready must NOT open; actionable attention must.
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady], feedMode: true))
        XCTAssertTrue(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady, question], feedMode: true))
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [], feedMode: true))
    }
```

- [ ] **Step 2: Run to verify it fails** (compile error: `NotchAutoOpenPolicy` missing). Command per Global Constraints.

- [ ] **Step 3: Create the policy**

Create `PingIsland/Core/NotchAutoOpenPolicy.swift`:

```swift
import Foundation

/// Pure decision logic for WHEN the docked notch may auto-open, so the
/// feed-mode rules are unit-testable apart from the SwiftUI observers.
enum NotchAutoOpenPolicy {
    /// New pending (needsAttention) sessions appeared. Session mode opens for
    /// any of them (legacy behavior). Feed mode opens only when at least one
    /// actually needs the user to act (question/approval); a bare prompt-ready
    /// session stays silent.
    nonisolated static func shouldAutoOpenForNewPendingSessions(
        newPending: [SessionState],
        feedMode: Bool
    ) -> Bool {
        guard feedMode else { return !newPending.isEmpty }
        return newPending.contains { $0.needsPromptNotification }
    }
}
```

- [ ] **Step 4: Wire it into `handlePendingSessionsChange`**

In `PingIsland/UI/Views/NotchView.swift` (~line 1020), the current open condition is:

```swift
        if !newPendingIds.isEmpty &&
           viewModel.status == .closed &&
           !shouldSuppressAutoOpen {
            viewModel.notchOpen(reason: .notification)
        }
```

Replace with:

```swift
        let newPendingSessions = sessions.filter { newPendingIds.contains($0.stableId) }
        if NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(
            newPending: newPendingSessions,
            feedMode: AppSettings.shared.notificationFeedMode
        ),
           viewModel.status == .closed,
           !shouldSuppressAutoOpen {
            viewModel.notchOpen(reason: .notification)
        }
```

(Everything else in the method — the suppression early-returns and the unconditional `previousPendingIds = currentIds` — stays byte-identical.)

- [ ] **Step 5: Run tests to verify pass**, then full Debug build (`... build` must end `** BUILD SUCCEEDED **`).

- [ ] **Step 6: Commit**

```bash
git add PingIsland/Core/NotchAutoOpenPolicy.swift PingIsland/UI/Views/NotchView.swift PingIslandTests/NotificationFeedTests.swift
git commit -m "feat: feed mode ignores bare new-session pops, opens only for actionable attention"
```

---

### Task 2: Feed banner auto-close timer

**Files:**
- Modify: `PingIsland/Core/NotchAutoOpenPolicy.swift` (add the arming predicate)
- Modify: `PingIsland/UI/Views/NotchView.swift` (timer state + schedule/cancel/hover/close + arming call sites)
- Modify: `PingIsland/UI/Views/NotificationFeedView.swift` (top-level `.onHover` callback param)
- Modify: `PingIsland/UI/Views/IslandOpenedContentView.swift` (plumb the hover callback to the feed view)
- Test: `PingIslandTests/NotificationFeedTests.swift`

**Interfaces:**
- Consumes: `NotchAutoOpenPolicy` (Task 1); the existing completion machinery as the pattern (schedule at NotchView.swift:1377-1387, hover at :1408-1425, close guard at :1446-1452 — read them before writing).
- Produces: `NotchAutoOpenPolicy.shouldArmFeedBannerDismissal(feedMode:isOpened:openedByNotification:hasAttentionSession:hasActiveCompletionCard:isChatContent:unreadCount:) -> Bool`; `NotificationFeedView.onHoverChanged: (Bool) -> Void` (default `{ _ in }`); `IslandOpenedContentView.onFeedHoverChanged: (Bool) -> Void` (default `{ _ in }`).

- [ ] **Step 1: Write the failing predicate tests**

```swift
    func testFeedBannerArmingPredicate() {
        func arm(feed: Bool = true, opened: Bool = true, byNotification: Bool = true,
                 attention: Bool = false, completionCard: Bool = false, chat: Bool = false,
                 unread: Int = 1) -> Bool {
            NotchAutoOpenPolicy.shouldArmFeedBannerDismissal(
                feedMode: feed, isOpened: opened, openedByNotification: byNotification,
                hasAttentionSession: attention, hasActiveCompletionCard: completionCard,
                isChatContent: chat, unreadCount: unread
            )
        }
        XCTAssertTrue(arm())                                  // notification-opened feed with unread → arm
        XCTAssertFalse(arm(feed: false))                      // session mode never arms
        XCTAssertFalse(arm(opened: false))                    // closed panel
        XCTAssertFalse(arm(byNotification: false))            // hover/click-opened = manual control
        XCTAssertFalse(arm(attention: true))                  // attention card stays
        XCTAssertFalse(arm(completionCard: true))             // completion card has its own timer
        XCTAssertFalse(arm(chat: true))                       // chat stays
        XCTAssertFalse(arm(unread: 0))                        // nothing to preview
    }
```

- [ ] **Step 2: Run to verify it fails** (predicate missing).

- [ ] **Step 3: Add the predicate**

Append to `NotchAutoOpenPolicy`:

```swift
    /// A `.notification`-opened panel is sitting on the FEED route (not an
    /// attention card, not the completion card, not chat). Such a panel is a
    /// transient banner: it must self-dismiss after the banner interval.
    nonisolated static func shouldArmFeedBannerDismissal(
        feedMode: Bool,
        isOpened: Bool,
        openedByNotification: Bool,
        hasAttentionSession: Bool,
        hasActiveCompletionCard: Bool,
        isChatContent: Bool,
        unreadCount: Int
    ) -> Bool {
        feedMode
            && isOpened
            && openedByNotification
            && !hasAttentionSession
            && !hasActiveCompletionCard
            && !isChatContent
            && unreadCount > 0
    }
```

- [ ] **Step 4: Timer machinery in `NotchView`**

Mirror the completion pattern exactly (READ NotchView.swift:1377-1462 first). Add state next to `completionNotificationDismissWorkItem`:

```swift
    @State private var feedBannerDismissWorkItem: DispatchWorkItem?
    @State private var shouldDismissFeedBannerOnHoverExit = false
```

Add the functions (place beside the completion ones):

```swift
    private var hasResolvedAttentionSession: Bool {
        IslandExpandedRouteResolver.highestPriorityAttentionSession(
            from: sessionMonitor.instances
        ) != nil
    }

    private func armFeedBannerDismissalIfNeeded() {
        let isChat: Bool
        if case .chat = viewModel.contentType { isChat = true } else { isChat = false }
        guard NotchAutoOpenPolicy.shouldArmFeedBannerDismissal(
            feedMode: AppSettings.shared.notificationFeedMode,
            isOpened: viewModel.status == .opened,
            openedByNotification: viewModel.openReason == .notification,
            hasAttentionSession: hasResolvedAttentionSession,
            hasActiveCompletionCard: activeCompletionNotification != nil,
            isChatContent: isChat,
            unreadCount: unreadFeedCount
        ) else { return }
        scheduleFeedBannerDismissal()
    }

    private func scheduleFeedBannerDismissal() {
        feedBannerDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [self] in
            dismissFeedBannerIfStillPassive()
        }
        feedBannerDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func dismissFeedBannerIfStillPassive() {
        feedBannerDismissWorkItem = nil
        shouldDismissFeedBannerOnHoverExit = false
        if viewModel.status == .opened,
           viewModel.openReason == .notification,
           !hasPendingPermission,
           !hasHumanIntervention {
            viewModel.notchClose()
        }
    }

    private func handleFeedBannerHover(_ isHovering: Bool) {
        guard AppSettings.shared.notificationFeedMode,
              viewModel.openReason == .notification else { return }
        if isHovering {
            shouldDismissFeedBannerOnHoverExit = feedBannerDismissWorkItem != nil
            feedBannerDismissWorkItem?.cancel()
            feedBannerDismissWorkItem = nil
            return
        }
        guard shouldDismissFeedBannerOnHoverExit else { return }
        shouldDismissFeedBannerOnHoverExit = false
        dismissFeedBannerIfStillPassive()
    }
```

`IslandExpandedRouteResolver.highestPriorityAttentionSession` exists (IslandExpandedRoute.swift:89) — check its exact signature/visibility and adapt the call (if it is private, replicate its one-line filter: sessions with `needsPromptNotification`, highest `attentionRequestedAt ?? lastActivity` — copy the real body). `unreadFeedCount` and `hasPendingPermission`/`hasHumanIntervention` already exist in NotchView.

Arming call sites (all three):
1. End of `handlePendingSessionsChange` right after the `viewModel.notchOpen(reason: .notification)` call added in Task 1 (a feed-mode open for attention won't arm — predicate rejects `hasAttentionSession`; this covers unforeseen feed-route landings).
2. End of `dismissActiveCompletionNotification(closePanel:advanceQueue:)` (after the existing body): when the panel was intentionally left open (`!closePanel` case or guards blocked the close), call `armFeedBannerDismissalIfNeeded()` so completion fall-throughs self-close in feed mode.
3. Cancellation safety: in whatever place the notch transitions away from `.notification` control — add `feedBannerDismissWorkItem?.cancel(); feedBannerDismissWorkItem = nil` alongside the existing `completionNotificationDismissWorkItem` cancellations (grep `completionNotificationDismissWorkItem?.cancel()` in NotchView and mirror at the sites that cancel due to user interaction/open-reason change, NOT inside the completion flow's own scheduling).

- [ ] **Step 5: Hover plumbing**

`NotificationFeedView`: add `var onHoverChanged: (Bool) -> Void = { _ in }` and attach `.onHover(perform: onHoverChanged)` to the view's top-level `ScrollView` (after `.scrollBounceBehavior`).
`IslandOpenedContentView`: add `var onFeedHoverChanged: (Bool) -> Void = { _ in }` and pass it as `onHoverChanged:` at BOTH `NotificationFeedView(...)` call sites (`.sessionList` and `.hoverDashboard` branches).
`NotchView.contentView` (the `IslandOpenedContentView(...)` construction, ~line 820): pass `onFeedHoverChanged: handleFeedBannerHover`. Other construction sites (grep `IslandOpenedContentView(`; DetachedIslandWindowController has one) compile unchanged thanks to the default value — leave them.

- [ ] **Step 6: Run tests + full Debug build.** Expected: NotificationFeedTests all pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PingIsland/Core/NotchAutoOpenPolicy.swift PingIsland/UI/Views/NotchView.swift PingIsland/UI/Views/NotificationFeedView.swift PingIsland/UI/Views/IslandOpenedContentView.swift PingIslandTests/NotificationFeedTests.swift
git commit -m "feat: 5s self-closing feed banner for notification-opened panels"
```

---

### Task 3: Docs + full suite

**Files:**
- Modify: `AGENTS.md` (extend the existing notification-feed bullet in Change Routing)

- [ ] **Step 1: Full suite**

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests` → `** TEST SUCCEEDED **`.

- [ ] **Step 2: AGENTS.md**

Extend the existing `notificationFeedMode` bullet: feed mode also decouples WHEN the island auto-opens — bare new-session/prompt-ready never opens it; actionable attention (`needsPromptNotification`) opens and stays; the completion card keeps its own 5 s flow; any other notification-opened panel left on the feed route self-closes after 5 s with completion-style hover pause (`NotchAutoOpenPolicy` holds the pure decision functions; the timer lives beside the completion dismissal machinery in `NotchView`). Session mode WHEN-behavior is untouched.

CLAUDE.md: no change needed (routing detail belongs to AGENTS.md).

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: note feed-mode auto-open rules"
```

---

### Task 4: Live Debug self-test (jack-loop, controller-run — NOT a dispatched subagent task)

Execute the spec's "Live Debug self-test" section verbatim (docs/superpowers/specs/2026-07-02-feed-mode-auto-open-design.md): fresh-session silence, banner + auto-close at ~7 s, hover pause, attention stays, session-mode parity, cleanup. Tooling already proven in this repo: Debug build launch from DerivedData, `defaults write com.wudanwu.PingIsland notificationFeedMode`, bridge event injection (PostToolUse for activity, a `Stop` event to bump `lastNotifiableActivityAt`), `cliclick`, `screencapture` + read-back. Evidence file: `.superpowers/sdd/feed-autoopen-selftest-report.md`. Every completion-report claim cites this evidence; non-executable steps are reported as explicit gaps. The report to the user happens ONLY after this passes.

---

## Self-Review

**Spec coverage:** rule-table row 1 (attention opens, stays) → Task 1 gate passes it through + predicate rejects arming; row 2 (bare ready never) → Task 1; row 3 (completion card untouched) → no task touches it, predicate rejects when card active; row 4 (feed-route banner 5 s, unread>0, hover pause, close guards) → Task 2; boot unchanged → untouched; AGENTS.md → Task 3; live self-test → Task 4; session-mode parity → feedMode gates in both tasks + policy tests.

**Placeholder scan:** the `highestPriorityAttentionSession` visibility check and the cancellation-site mirroring are read-the-real-code directives with exact anchors (signatures may differ from memory; inventing them would be worse). No TBDs.

**Type consistency:** `NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending:feedMode:)`, `shouldArmFeedBannerDismissal(feedMode:isOpened:openedByNotification:hasAttentionSession:hasActiveCompletionCard:isChatContent:unreadCount:)`, `onHoverChanged`/`onFeedHoverChanged` names match across Tasks 1-2.

## Success criteria

Spec's success criteria verbatim, gated on Task 4 evidence: new session never pops; completed reply pops a 5 s self-closing preview per settings; hover pauses; questions stay; badge independent of pops; session mode unchanged; AGENTS.md updated; unit matrix + live evidence green before reporting.
