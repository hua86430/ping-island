# Clear stuck AskUserQuestion cards (zombie card)

Date: 2026-07-02
Status: approved (design), pending implementation plan

## Problem

An AskUserQuestion intervention card in the notch sometimes never clears: the
underlying question is already resolved (answered elsewhere, dismissed, or the
tool completed) but the card stays, un-dismissable ("關不掉也點不掉").

Root cause (traced): `SessionStore.isQuestionToolPostToolUse` decides whether an
incoming `PostToolUse` clears the current question intervention:

```swift
guard let toolUseId = event.toolUseId else { return true }
return intervention?.matchesResolvedToolUseId(toolUseId) == true
```

`matchesResolvedToolUseId` compares the PostToolUse's `tool_use_id` against the
intervention's `id` and its `metadata["originalToolUseId" | "toolUseId" | "tool_use_id"]`
(`SessionProvider.swift:1104`). When the intervention was created from a channel
that carries **no** `tool_use_id` (a `Notification`-derived question, or the
`routePromptsToTerminal` suppress path), none of those match the PostToolUse's
id, so the guard returns false and the card is never cleared. In the normal
flow the card originates from `PreToolUse` / `PermissionRequest`, which carry
the `tool_use_id`, so the match succeeds and the card clears — the bug only
bites for id-less origins.

## Goal

A resolved AskUserQuestion clears its notch card even when the intervention has
no `tool_use_id` to match against, without wrongly clearing a *different*
concurrent question that does carry an id.

## Approach

Add `SessionIntervention.hasResolvableToolUseId: Bool` — true iff at least one
of `metadata["originalToolUseId"]`, `metadata["toolUseId"]`, `metadata["tool_use_id"]`
is present and non-empty. (The synthetic `id` is not counted, because a
Notification-origin intervention's `id` is not the tool's real `tool_use_id`.)

Change `isQuestionToolPostToolUse` so an AskUserQuestion PostToolUse clears the
current question when EITHER the id matches OR the intervention has no resolvable
tool-use-id at all:

```swift
guard event.event == "PostToolUse" else { return false }
// (tool-name normalization unchanged: askuserquestion / askfollowupquestion)
guard let toolUseId = event.toolUseId else { return true }
if intervention?.matchesResolvedToolUseId(toolUseId) == true { return true }
// The intervention carries no tool_use_id to disambiguate against; a completed
// AskUserQuestion means this question is done, so clear it.
return intervention?.hasResolvableToolUseId == false
```

Behavior:

| Intervention origin | carries tool_use_id? | AskUserQuestion PostToolUse (id X) |
| --- | --- | --- |
| PreToolUse / PermissionRequest | yes | clears only if X matches (unchanged) |
| Notification / suppress path | no | clears (new) |
| PostToolUse without an id on the event | n/a | clears (unchanged, existing `guard let ... else return true`) |

Concurrent-question safety: interventions that carry a real id keep strict
matching, so a different pending question (with its own id) is not cleared by an
unrelated PostToolUse. Only id-less interventions (which cannot be
disambiguated anyway) clear on a matching-tool completion.

## Scope

- `PingIsland/Models/SessionProvider.swift`: add `hasResolvableToolUseId` to `SessionIntervention`.
- `PingIsland/Services/State/SessionStore.swift`: the one extra branch in `isQuestionToolPostToolUse`.

Out of scope: the AskUserQuestion preview feature (B), and Ctrl-C session
liveness (separate specs). This fix stands alone and helps both.

## Testing

- **Unit (`PingIslandTests`)** for `isQuestionToolPostToolUse` (relax access or test through the intervention model + a synthetic PostToolUse `HookEvent`):
  - intervention with matching `tool_use_id` metadata + PostToolUse same id → clears.
  - intervention with a *different* id + PostToolUse id → does NOT clear.
  - intervention with NO tool-use-id metadata + AskUserQuestion PostToolUse (with an id) → clears (the zombie case).
  - PostToolUse with no id → clears (unchanged).
  - non-AskUserQuestion PostToolUse → does not clear.
- **Unit** for `hasResolvableToolUseId`: true when any of the three metadata keys is set; false when all absent/empty.
- **Manual (jack-loop)**: reproduce by driving an AskUserQuestion whose island card comes from the Notification path, resolve it in the terminal, and confirm the card clears within the normal update cycle instead of sticking.

## Success criteria

- A resolved AskUserQuestion clears its notch card even when the card had no `tool_use_id`.
- A concurrent question that carries its own id is not wrongly cleared by another question's PostToolUse.
- No change to the normal PreToolUse/PermissionRequest-origin clearing.
