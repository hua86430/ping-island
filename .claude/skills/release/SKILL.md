---
name: release
description: Ship a PingIsland release end to end - write release notes, bump versions, tag, monitor CI, verify assets. Use whenever the user asks to release / publish a new version (發布新版).
---

# PingIsland Release Flow

Ship one version from working tree to verified GitHub release. Every step has
a verify. Do them in order; do not tag before the notes file exists.

## 0. Preflight

- [ ] `git status` clean or only the release-related files staged. Never tag with unrelated uncommitted work.
- [ ] Full app test suite green:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug \
  CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests
  ```
  Plain `xcodebuild` without `CODE_SIGNING_ALLOWED=NO` fails on this machine (no signing cert). Pipe through `tee` if you need the log, but check `${PIPESTATUS[0]}`, not the pipe's exit code.
- [ ] `AGENTS.md` / `TODO.md` / affected docs already updated for the changes being shipped (docs are part of the change, not follow-up).
- [ ] Enumerate the release scope: `git log --oneline v<prev>..HEAD`. Every user-visible commit must appear in the notes.

## 1. Write release notes (BEFORE tagging)

- [ ] Create `releases/notes/<version>.md` (e.g. `releases/notes/0.25.0.md`).
- [ ] Language: 繁體中文. Sections: `## 新增` / `## 修改` / `## 修復` / `## 移除` — state concretely what changed; omit sections with nothing in them. No vague lines like「修了一些問題」.
- [ ] Why before tagging: `.github/workflows/release-unsigned.yml` reads `releases/notes/$version.md` at tag-build time, uploads it as the Sparkle notes asset `PingIsland-$version.md`, and uses it for the GitHub release body. No file → boilerplate-only release (this happened for 0.24.6–0.24.12 and had to be backfilled).

## 2. Bump versions in `PingIsland.xcodeproj/project.pbxproj`

- [ ] Replace all 4 `MARKETING_VERSION = <old>;` with the new version.
- [ ] Replace all 4 `CURRENT_PROJECT_VERSION = <old build>;` with build+1.
- [ ] Do NOT touch the test-target `CURRENT_PROJECT_VERSION = 5;` entries.
- [ ] Verify counts:
  ```bash
  grep -c 'MARKETING_VERSION = <new>' PingIsland.xcodeproj/project.pbxproj   # must be 4
  grep -c 'CURRENT_PROJECT_VERSION = <newbuild>' PingIsland.xcodeproj/project.pbxproj  # must be 4
  ```

## 3. Commit and push

- [ ] Commit notes + bump (+ any doc updates). Conventional Commits, English, e.g. `chore: bump version to 0.25.0 (build 73)`.
- [ ] `git push origin main`.

## 4. Tag → CI release

- [ ] `git tag v<version> && git push origin v<version>`
- [ ] Tag push triggers `.github/workflows/release-unsigned.yml`: builds unsigned Release app, packages DMG + zip, generates the EdDSA-signed `appcast.xml` (keys from repo secrets), creates the GitHub release with the notes file as body + assets.

## 5. Monitor CI

- [ ] ```bash
  gh run list --workflow=release-unsigned.yml --limit 1   # grab the run id
  gh run watch <run-id> --exit-status
  ```
- [ ] On failure: `gh run view <run-id> --log-failed`, fix, delete and re-push the tag only if the failure happened before release creation; otherwise patch the release in place with `gh release upload/edit`.

## 6. Verify the release

- [ ] ```bash
  gh release view v<version> --json isDraft,assets,body \
    --jq '{draft:.isDraft, assets:[.assets[].name], body_head:(.body[:200])}'
  ```
- [ ] Must hold: `draft:false`; assets include `PingIsland-<version>.dmg`, `PingIsland-<version>.zip`, `appcast.xml`, `PingIsland-<version>.md` (notes asset), and the Linux bridge payload; body starts with the 新增/修改/... content, not bare boilerplate.
- [ ] Sparkle picks up `latest/download/appcast.xml` automatically — no extra step.

## Gotchas (learned the hard way)

- `log` is shadowed by a zsh function on this machine — always `/usr/bin/log` for `log stream`/`log show`.
- When verifying behavior on a local Debug build before release: binary-freshness check is mandatory. App process start time must be LATER than the binary mtime (`ps -o lstart= -p <pid>` vs `stat -f %Sm <binary>`), otherwise you are testing a stale build.
- CI signs the appcast with repo-secret EdDSA keys; never run local `scripts/create-release.sh` signing/notarization for this unsigned lane.
- Version scheme: `MARKETING_VERSION` is semver-ish (0.x.y), `CURRENT_PROJECT_VERSION` is a monotonically increasing integer build number shared across both counts of 4.
