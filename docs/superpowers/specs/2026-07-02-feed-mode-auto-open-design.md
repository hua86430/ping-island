# Feed mode auto-open decoupling (banner semantics + auto-close)

Date: 2026-07-02
Status: approved (design), pending implementation plan
Extends: `docs/superpowers/specs/2026-07-02-notification-feed-mode-design.md`

## Problem

Notification feed mode replaced WHAT the opened island renders, but every
WHEN-to-auto-open trigger is untouched legacy. Two user-verified failures:

1. Starting a fresh Claude session auto-pops the island showing an EMPTY feed.
   Root cause (traced): `handlePendingSessionsChange` (NotchView.swift:1020,
   open at :1040) fires for any new `needsAttention` session; a fresh CLI
   session lands in `.waitingForInput` → `needsAttention` → pop, while the feed
   filters to nothing because `hasUnread` is false.
2. A reply-completion notification opens the island on the FEED route and it
   never closes (user recording: still open at 12+ seconds, cursor away).
   Code truth: the ONLY auto-close timer in the app is the completion-card
   flow — `scheduleCompletionNotificationDismissal` (NotchView.swift:1377-1387,
   5 s) closing the notch at :1446-1452 only when
   `openReason == .notification && !hasPendingPermission && !hasHumanIntervention`.
   Hovering the card cancels the timer permanently (:1414; only hover-exit
   dismisses). Every OTHER `.notification`-opened panel — attention, chat, and
   anything that falls through to the feed/sessionList route (completion card
   dismissed with `closePanel: false` at :1297 / tap-dismiss keepPanelOpen at
   :862; drop-when-already-open at :1202-1206) — has NO timer and stays open
   until an explicit user gesture (mouse-down outside, trigger tap, detach,
   fullscreen transitions).

An earlier claim that "the completion popup already auto-dismisses, so feed
mode needs nothing" was wrong for exactly these fall-through paths and is
superseded by this spec.

## Goal (user-confirmed)

iPhone semantics, complete decoupling. Feed mode ON:

- Actionable attention (question/approval) pops and STAYS (needs action).
- Completion banner behaves per the user's existing auto-open-completion
  settings, 5 s auto-close (existing machinery, untouched).
- Any other notification-opened panel may open ONLY when there is at least one
  unread item, shows the feed, and AUTO-CLOSES after 5 s (hover pauses; leave
  closes; never force-close while a pending permission/intervention exists).
- A bare new-session / prompt-ready event NEVER auto-opens the island.

Feed mode OFF (session mode): byte-identical behavior to today, all four
triggers untouched.

## Design

### Rule table (feed mode ON)

| Event | Opens? | Content | Auto-close |
| --- | --- | --- | --- |
| New pending session, `needsPromptNotification` (question/approval, incl. terminal-routed reminder) | yes (T1/T2 as today) | attention card | none (stays until handled/gesture) |
| New pending session, bare `.waitingForInput` (fresh session, prompt ready) | NO | — | — |
| Completion notification (per `autoOpenCompletionPanel` / compacted setting) | yes (T3 as today) | completion card | existing 5 s timer |
| NEW unread appears while the island is closed (assistant reply landed) | yes (new trigger; respects reminder-mute, automatic-presentation suppression, and smartSuppression like T1) | feed | NEW 5 s timer (same as row below) |
| Any other `.notification` open landing on the feed route (T1 remnant, completion fall-through via `closePanel:false` / keepPanelOpen, session-vanished sync) | only if `unreadCount > 0` | feed | NEW 5 s timer (same semantics as completion: hover cancels, hover-exit closes, no force-close while `hasPendingPermission || hasHumanIntervention`) |
| Boot animation (T4) | yes | instances/feed | existing 1 s auto-close |

### Components

1. **T1 gate** (`NotchView.handlePendingSessionsChange`, ~:1020)
   In feed mode, only open when at least one NEW pending session
   `needsPromptNotification`. The `previousPendingIds` bookkeeping updates
   unconditionally (no missed-diff on later events). Decision extracted as a
   pure nonisolated static function for unit testing:
   `shouldAutoOpenForNewPendingSessions(newPending: [SessionState], feedMode: Bool) -> Bool`
   — feed off → `!newPending.isEmpty` (today's behavior); feed on →
   `newPending.contains { $0.needsPromptNotification }`.

2. **Feed banner auto-close** (`NotchView`)
   A feed-scoped dismissal timer mirroring the completion one
   (`scheduleFeedBannerDismissal` / cancel-on-hover / close-on-hover-exit),
   armed whenever ALL hold: feed mode on, `viewModel.status == .opened`,
   `openReason == .notification`, and the resolved route is the feed
   (`.sessionList`/`.hoverDashboard` with feed mode on — i.e. NOT
   `.attentionNotification`, NOT `.completionNotification`, NOT `.chat`).
   Fire → close the notch only if still `openReason == .notification` and
   `!hasPendingPermission && !hasHumanIntervention` (same guard as :1446).
   Hover semantics identical to the completion card: hover cancels the timer;
   hover-exit closes. User hover/click re-opening keeps the panel under manual
   control (openReason changes → timer inapplicable).
   The completion card's own dismissal handoffs (`closePanel: false`,
   `keepPanelOpen: true`) leave the panel on the feed route in feed mode —
   the banner timer arms at that moment, so those fall-throughs now close too.

3. **Unread precondition for feed-route notification opens**
   In feed mode, a `.notification` open that would land on the feed route is
   skipped entirely when `unreadCount == 0` (nothing to preview → no pop).
   Combined with (1), the empty-feed pop cannot happen.

4. **Timer constant**: reuse the completion flow's 5 seconds (single shared
   constant; no new setting — YAGNI, revisit only if asked).

3b. **Feed banner trigger on new unread** (added during live self-test)
   Live testing exposed that the pre-existing completion-card presenter never
   fires on this machine (all static guards pass — `autoOpenCompletionPanel`
   on, no mute, no smartSuppression — yet three real reply completions
   produced no card; a pre-existing issue outside this feature's diff). Relying
   on it for the banner would leave "reply completed" with badge-only and no
   pop. So feed mode gets its own banner trigger: when a session's `hasUnread`
   transitions to true while the island is CLOSED, open it with
   `reason: .notification` (feed route) and arm the 5 s banner timer.
   Gates mirror T1: reminder-mute, `shouldSuppressAutomaticPresentation`, and
   `smartSuppression` (user already watching the terminal sees the reply — no
   pop). Decision logic in `NotchAutoOpenPolicy` for unit testing. The
   completion-card mystery is left for its own diagnosis (out of scope).

5. **Docs (deliverable, not follow-up)**: update `AGENTS.md`'s notification-feed
   routing bullet to state the WHEN rules (attention stays, completion banner
   5 s, feed banner 5 s, bare-ready never opens, session mode untouched) and
   the new pure decision function + timer location. CLAUDE.md needs no change
   (routing detail belongs to AGENTS.md; nothing project-workflow-level
   changed).

### Out of scope (explicitly)

- Session-mode behavior of any trigger (byte-identical).
- Pre-existing completion-card quirks kept as-is: hover-cancel without
  rescheduling (relies on hover-exit), multi-completion queue chaining
  (5 s per card + 0.35 s), attention-vs-close guard asymmetry
  (`needsPromptNotification` vs `hasPendingPermission`/`hasHumanIntervention`).
  Noted, not fixed here.
- Detached/floating surface uses the same route resolver; the feed banner
  timer applies to the docked notch presentation only in v1 (detached bubble
  has its own presentation lifecycle).

## Testing

- **Unit (`PingIslandTests/NotificationFeedTests.swift`)**
  - `shouldAutoOpenForNewPendingSessions` matrix: feed off + any new pending →
    true; feed off + none → false; feed on + bare `.waitingForInput` only →
    false; feed on + one `needsPromptNotification` → true.
  - Feed-banner arming predicate (pure function over openReason/route/feedMode/
    unreadCount): arms only for notification-opened feed route with unread > 0;
    never arms for attention/completion/chat routes or in session mode.
- **Live Debug self-test (jack-loop, controller-run, gates the report — see
  next section).**

## Live Debug self-test (required before reporting done)

Run personally on the Debug build with `notificationFeedMode` on, evidence via
screencapture sequences read back + cliclick, written to
`.superpowers/sdd/feed-autoopen-selftest-report.md`. Every claim in the
completion report cites this evidence; anything not executable is reported as
an explicit gap.

1. Fresh-session silence: quit/relaunch Debug app, open a NEW Claude CLI
   session in a spare folder (drive via bridge PostToolUse injection if a real
   CLI session is impractical — a synthetic SessionStart/prompt-ready
   registration reproduces T1) → island must NOT auto-open; badge unchanged.
   Capture strip before/after.
2. Banner + auto-close: drive an assistant reply completion (real session
   reply, or synthetic Stop-event injection which bumps
   `lastNotifiableActivityAt`) → island auto-opens on the feed showing the
   unread row → WITHOUT touching the mouse, capture at ~1 s and ~7 s → second
   capture must show the island CLOSED and the badge still present.
3. Hover pause: repeat (2) but move the cursor onto the panel within 5 s →
   capture at ~7 s shows it still open; move cursor away → capture shows it
   closed within ~2 s.
4. Attention stays: drive a question/approval (AskUserQuestion in a real
   session, toggle for terminal-routed reminder irrelevant here) → attention
   card pops and is still open at 10 s+ (capture), until handled.
5. Session-mode parity: toggle off, relaunch, new session → island pops the
   classic list exactly as today (capture), no feed timer in play.
6. Cleanup: synthetic sessions/transcripts removed, toggle restored to the
   state the user had, production app relaunched if the user isn't actively
   using the Debug build.

## Success criteria

- Feed mode: opening a new Claude session never pops the island; a completed
  reply pops a 5 s self-closing preview (feed or completion card per settings)
  with hover-pause; questions/approvals pop and stay; badge always reflects
  unread regardless of pops.
- Session mode: today's behavior, unchanged.
- AGENTS.md updated with the WHEN rules alongside the existing feed bullet.
- Unit matrix + live self-test evidence both green before any "done" report.
