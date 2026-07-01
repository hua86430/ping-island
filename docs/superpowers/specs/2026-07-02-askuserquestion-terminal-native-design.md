# Let the terminal handle Claude AskUserQuestion (full hook exclusion)

Date: 2026-07-02
Status: approved (design), pending implementation plan
Supersedes: `docs/superpowers/specs/2026-07-01-askuserquestion-preview-design.md` (approach A — proven infeasible)

## Problem

When Claude Code runs `AskUserQuestion`, PingIsland intercepts it: the notch
pops an interactive question card, and Claude's native terminal picker only
appears after the island card is answered. The user wants to answer in the
terminal, not have the island seize the prompt first.

## What the evidence rules out

Traced from the bridge debug log (`~/.ping-island-debug/claude-hooks/20260701.jsonl`,
session run in `permission_mode: bypassPermissions`) plus the reverted approach-A
commits (`52a6a37`, `322ea71`; reverts `c35acc4`, `14b84e3`):

- The blocking gate for AskUserQuestion is the **PreToolUse** hook. In normal
  operation its envelope carries `expectsResponse=true`, so the bridge blocks
  and the island owns the answer. `PermissionRequest` envelopes for
  AskUserQuestion were `expectsResponse=false` throughout the log, so
  PermissionRequest was never the gate (correcting an earlier assumption).
- Making the PreToolUse hook **non-blocking** (approach A: `expectsResponse=false`,
  keep a read-only preview) makes Claude **dismiss** the question outright
  ("Question asked. No answer picked — dismissed."). Verified by the user via
  screen recording. So a non-blocking hook is unusable.
- There is **no content-bearing Notification channel**: 0 Notification hook
  events fired for AskUserQuestion (or at all) in the whole-day log. The
  question text and options exist only inside the `tool_input` of the
  PreToolUse / PermissionRequest envelopes.
- Claude's hook response vocabulary is `approve` / `approveForSession` /
  `deny`. There is no "defer to the terminal" verb.

Conclusion: through the hook model, "native terminal picker" and "island shows
a card" cannot coexist. Any hook that fires for AskUserQuestion either blocks
(island hijacks) or is non-blocking (Claude dismisses). The only way to get the
pure native terminal picker is to stop the hook from firing for AskUserQuestion
at all — which necessarily leaves the island with no signal to display.

## Goal

Add an opt-in setting that stops PingIsland from intercepting Claude Code's
AskUserQuestion, so Claude renders its native terminal picker exactly as it
would with PingIsland not installed. When the setting is on, the island shows
nothing for AskUserQuestion; this silence is an accepted trade-off, not a bug.

## Approach: full hook exclusion

A single new setting, off by default. When on, the Claude Code hook install
excludes AskUserQuestion (and AskFollowupQuestion) from the tool-matched events
that produce the intervention, so no bridge envelope is ever generated for
those tools and Claude falls back to its native prompt.

All changes live at the hook-install layer. No UI card work, no `SessionStore`
change, and deliberately **no app-side intervention drop** — dropping an
intervention while a pre-toggle session's blocking PreToolUse is still waiting
would leave Claude hung on that hook with neither surface answering. Excluding
at the matcher is the clean cut: the hook simply never runs.

### Components

1. **Setting** (`PingIsland/Core/Settings.swift`)
   New persisted `@Published var terminalHandlesAskUserQuestion: Bool`, default
   `false`. Mirror the existing `routePromptsToTerminal` pattern at
   `Settings.swift:946` (guard `isBootstrapping`, write to `defaults`, record
   telemetry). Its `didSet` triggers a Claude hook reinstall (component 3).

2. **Matcher exclusion** (`PingIsland/Services/Hooks/HookInstaller.swift`,
   `effectiveEvents(for:)` at line 821)
   `effectiveEvents(for:)` is the single choke point every install and
   settings-file-generation path routes through (callers at 841, 1288, 1686,
   and `createTemporarySettingsFile`). After the existing selection filtering,
   if the profile is the Claude Code profile (`id == "claude-code"`) and
   `terminalHandlesAskUserQuestion` is on, rewrite the `PreToolUse` and
   `PermissionRequest` descriptors' `.matcher("*")` to a regex that matches
   every tool name **except** `AskUserQuestion` and `AskFollowupQuestion`.
   `PostToolUse` is left as `.matcher("*")` — it is non-blocking, produces no
   intervention on its own, and lets the session's activity still update after
   the terminal answer completes.

   The matcher string is emitted verbatim into `settings.json` by
   `makeHookEntries` (line 1873) / line 1289 as `"matcher": "<value>"`.
   Intended regex: a full-match negative-lookahead such as
   `^(?!(?:AskUserQuestion|AskFollowupQuestion)$).+$`. The exact syntax that
   Claude Code's matcher engine accepts is verified in Task 1 (see Risk).

3. **Reinstall on toggle** (`Settings.swift` didSet → `HookInstaller`)
   Today the `routePromptsToTerminal` didSet only writes bridge runtime config;
   it does not reinstall hooks. This feature needs the toggle to rewrite
   `~/.claude/settings.json`. On change, reinstall the Claude Code profile via
   the existing `HookInstaller.reinstall(_:)` (line 853) /
   `reinstallWithUserAuthorization` (554) path, guarded so it only fires when
   the Claude profile is currently installed and not during bootstrap.

4. **Settings UI** (`PingIsland/UI/Views/SettingsWindowView.swift`)
   A toggle bound to the new setting, with a one-line note that it takes effect
   on the next Claude session. Claude reads `settings.json` at session start, so
   already-running sessions keep their existing hooks until restarted.

### Data flow

```mermaid
flowchart TD
    A[User toggles terminalHandlesAskUserQuestion ON] --> B[Settings didSet]
    B --> C[HookInstaller.reinstall Claude profile]
    C --> D[effectiveEvents rewrites PreToolUse and PermissionRequest matcher]
    D --> E["~/.claude/settings.json: matcher excludes AskUserQuestion"]
    E -.next Claude session reads settings.json.-> F[Claude runs AskUserQuestion]
    F --> G[No hook fires for AskUserQuestion]
    G --> H[Claude renders native terminal picker]
    H --> I[Island shows nothing for the question]
```

## Scope

- In scope: the Claude Code profile (`id == "claude-code"`) only. AskUserQuestion
  is a Claude tool.
- Out of scope: other Claude-compatible profiles (Qoder CLI, CodeBuddy CLI,
  etc.) even though some share Claude-style hooks — they can adopt the same
  exclusion later if wanted. Codex, Gemini, and the rest are untouched.
- Out of scope: any island preview of the question (the "read-only preview"
  and "transcript-watcher" alternatives were considered and declined).
- Out of scope: the zombie-card fix (already shipped, commit `31f18d3`); it
  stays and is unrelated once no AskUserQuestion card is created.

## Risk and fail-fast

The one unverified step is whether Claude Code's matcher engine accepts a
negative-lookahead regex and, once excluded, actually stops the PreToolUse hook
from firing for AskUserQuestion. Prior manual exclusion attempts did not take
effect (PreToolUse kept firing in the log), source unknown (regex not accepted,
Claude not reloading settings, or the edit not covering PreToolUse).

Task 1 of the implementation plan is a controlled check: generate the
exclusion `settings.json`, confirm its shape, and run one live Claude session to
confirm (a) no PreToolUse envelope arrives for AskUserQuestion and (b) the
native terminal picker renders. If the regex form is rejected, the fallback is
to enumerate a whitelist matcher of the tools to keep. The picker itself is
near-certain to work once the hook is gone — it is Claude's default behavior
with PingIsland not installed.

## Testing

- **Unit (`PingIslandTests`)** on the matcher generation:
  - Claude profile + toggle OFF → PreToolUse and PermissionRequest matchers are
    `"*"` (unchanged from today).
  - Claude profile + toggle ON → PreToolUse and PermissionRequest matchers are
    the exclusion regex; PostToolUse stays `"*"`; all other events unchanged.
  - A non-Claude profile + toggle ON → matchers unchanged (scope guard).
- **Unit** on the setting: persists across a `Settings` reload; default is
  `false`.
- **Manual (jack-loop, Task 1 spike)**: toggle ON, restart a Claude session,
  drive an AskUserQuestion, confirm the native terminal picker renders and the
  island shows no card; toggle OFF, confirm the island card returns.

## Success criteria

- With the setting on and a fresh Claude session, AskUserQuestion renders in the
  terminal natively and the island shows nothing for it.
- With the setting off, behavior is exactly as today.
- Toggling the setting rewrites `~/.claude/settings.json` and preserves
  unrelated settings and other clients' hooks.
- The exclusion is scoped to the Claude Code profile; no other client's hooks
  change.
