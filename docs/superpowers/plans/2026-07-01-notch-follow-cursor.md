# Instant cursor-follow for the docked notch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In automatic screen mode, make the docked notch follow the cursor to another screen promptly and without rebuilding the window.

**Architecture:** Two pure, unit-tested cores plus one integration wiring. (1) `NotchWindowController` can recompute its docked frame for any screen and move there. (2) A pure `NotchScreenMigrationDecider` decides ignore / begin-dwell / migrate from cursor + current screen + dwell timing. (3) `WindowManager` subscribes to the existing `mouseLocation` stream, applies the decider, and migrates via the cheap `IslandPresentationCoordinator.updateScreen` reposition path instead of the rebuild path.

**Tech Stack:** Swift, AppKit (NSScreen/NSWindow), Combine, XCTest. Tests in `PingIslandTests` (`@testable import Ping_Island`).

## Global Constraints

- Only `.automatic` screen mode migrates on cursor movement; `.specificScreen` never does.
- No new always-on high-frequency event monitor; reuse the existing `EventMonitors.shared.mouseLocation` subject (its `.mouseMoved` source is already gated to `EnergyGovernor` level `.full`).
- Routine cursor/focus migration must use the cheap reposition path (`updateScreen` → `moveToScreen`), never `invalidate()` + new coordinator. Rebuild stays only for lifecycle events (screen list change, first launch).
- Docked window height is 750 (existing `NotchWindowController` value); the docked frame is full screen width, pinned to the top of the screen.
- Dwell default: 0.2 s (single tunable constant).
- Commit style: ticket-less Conventional Commits.

---

### Task 1: Recomputable docked frame + window reposition

**Files:**
- Modify: `PingIsland/UI/Window/NotchWindowController.swift` (`fullWindowFrame` at line 14; init frame math at lines 28-35; `updateWindowPresentation` at ~167)
- Test: `PingIslandTests/NotchWindowControllerFrameTests.swift` (create)

**Interfaces:**
- Produces: `NotchWindowController.dockedWindowFrame(screenFrame: CGRect) -> NSRect` (static, internal); `NotchWindowController.windowHeight: CGFloat` (static, = 750); `NotchWindowController.moveToScreen(_ screen: NSScreen)` (instance).

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/NotchWindowControllerFrameTests.swift`:

```swift
import AppKit
import XCTest
@testable import Ping_Island

@MainActor
final class NotchWindowControllerFrameTests: XCTestCase {
    func testDockedFrameForPrimaryScreenPinsFullWidthToTop() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        XCTAssertEqual(frame, NSRect(x: 0, y: 900 - 750, width: 1440, height: 750))
    }

    func testDockedFrameForOffsetExternalScreenUsesItsOrigin() {
        let frame = NotchWindowController.dockedWindowFrame(
            screenFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        )
        XCTAssertEqual(frame, NSRect(x: 1440, y: 1440 - 750, width: 2560, height: 750))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchWindowControllerFrameTests`
Expected: FAIL to compile — `dockedWindowFrame` does not exist.

- [ ] **Step 3: Add the static frame helper + window height constant**

In `NotchWindowController.swift`, add inside the class (near the top, after `private var cancellables`):

```swift
    static let windowHeight: CGFloat = 750

    /// Full-width docked window frame pinned to the top of the given screen.
    static func dockedWindowFrame(screenFrame: CGRect) -> NSRect {
        NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }
```

- [ ] **Step 4: Make `fullWindowFrame` mutable and computed from the helper**

Change line 14 from:

```swift
    private let fullWindowFrame: NSRect
```

to:

```swift
    private var fullWindowFrame: NSRect
```

In `init`, replace the local frame math (lines 28-35) so it uses the helper:

```swift
        // Window covers full width at top, tall enough for largest content (chat view)
        let windowFrame = Self.dockedWindowFrame(screenFrame: screenFrame)
        self.fullWindowFrame = windowFrame
```

- [ ] **Step 5: Add `moveToScreen`**

Add this method to the class (near `updateWindowPresentation`):

```swift
    /// Reposition the existing window onto a different screen without rebuilding it.
    func moveToScreen(_ screen: NSScreen) {
        let frame = Self.dockedWindowFrame(screenFrame: screen.frame)
        guard frame != fullWindowFrame else { return }
        fullWindowFrame = frame
        window?.setFrame(frame, display: true)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchWindowControllerFrameTests`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add PingIsland/UI/Window/NotchWindowController.swift PingIslandTests/NotchWindowControllerFrameTests.swift
git commit -m "feat: let NotchWindowController reposition across screens"
```

---

### Task 2: Pure migration decider

**Files:**
- Create: `PingIsland/App/NotchScreenMigrationDecider.swift`
- Test: `PingIslandTests/NotchScreenMigrationDeciderTests.swift` (create)

**Interfaces:**
- Consumes: `ScreenSelectionMode` (existing enum in `ScreenSelector.swift`).
- Produces: `enum NotchMigrationAction: Equatable { case none; case beginDwell(CGDirectDisplayID); case migrate(CGDirectDisplayID) }` and `enum NotchScreenMigrationDecider { static func evaluate(mode:cursorScreenID:currentScreenID:pendingScreenID:pendingSince:now:dwell:) -> NotchMigrationAction }`.

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/NotchScreenMigrationDeciderTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import Ping_Island

final class NotchScreenMigrationDeciderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testSpecificModeNeverMigrates() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .specificScreen, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(10), dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testCursorOnCurrentScreenDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 1, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testCursorOnNewScreenWithoutPendingBeginsDwell() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .beginDwell(2))
    }

    func testCursorHoppingToYetAnotherScreenRestartsDwell() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 3, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.1), dwell: 0.2
        )
        XCTAssertEqual(action, .beginDwell(3))
    }

    func testPendingScreenBeforeDwellElapsedDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.1), dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }

    func testPendingScreenAfterDwellElapsedMigrates() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: 2, currentScreenID: 1,
            pendingScreenID: 2, pendingSince: t0, now: t0.addingTimeInterval(0.25), dwell: 0.2
        )
        XCTAssertEqual(action, .migrate(2))
    }

    func testNilCursorScreenDoesNothing() {
        let action = NotchScreenMigrationDecider.evaluate(
            mode: .automatic, cursorScreenID: nil, currentScreenID: 1,
            pendingScreenID: nil, pendingSince: nil, now: t0, dwell: 0.2
        )
        XCTAssertEqual(action, .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchScreenMigrationDeciderTests`
Expected: FAIL to compile — `NotchScreenMigrationDecider` / `NotchMigrationAction` do not exist.

- [ ] **Step 3: Implement the decider**

Create `PingIsland/App/NotchScreenMigrationDecider.swift`:

```swift
//
//  NotchScreenMigrationDecider.swift
//  PingIsland
//
//  Pure decision logic for cursor-follow screen migration of the docked notch.
//

import CoreGraphics
import Foundation

enum NotchMigrationAction: Equatable {
    case none
    case beginDwell(CGDirectDisplayID)
    case migrate(CGDirectDisplayID)
}

enum NotchScreenMigrationDecider {
    /// Decide whether the docked notch should migrate to the cursor's screen.
    /// Pure: all timing is passed in so it can be unit-tested deterministically.
    static func evaluate(
        mode: ScreenSelectionMode,
        cursorScreenID: CGDirectDisplayID?,
        currentScreenID: CGDirectDisplayID?,
        pendingScreenID: CGDirectDisplayID?,
        pendingSince: Date?,
        now: Date,
        dwell: TimeInterval
    ) -> NotchMigrationAction {
        guard mode == .automatic else { return .none }
        guard let cursorScreenID else { return .none }
        guard cursorScreenID != currentScreenID else { return .none }

        // Cursor is on a different screen than the notch. Require it to dwell
        // there before migrating, so a cursor merely passing through does not
        // drag the notch along.
        guard pendingScreenID == cursorScreenID, let pendingSince else {
            return .beginDwell(cursorScreenID)
        }
        return now.timeIntervalSince(pendingSince) >= dwell
            ? .migrate(cursorScreenID)
            : .none
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchScreenMigrationDeciderTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add PingIsland/App/NotchScreenMigrationDecider.swift PingIslandTests/NotchScreenMigrationDeciderTests.swift
git commit -m "feat: add pure cursor-follow migration decider"
```

---

### Task 3: Wire cursor-follow through the cheap reposition path

**Files:**
- Modify: `PingIsland/App/IslandPresentationCoordinator.swift` (`updateScreen` at line 25)
- Modify: `PingIsland/App/WindowManager.swift` (add cursor subscription + migration; `handleFocusChange` at ~73; `setupNotchWindow` at ~30)
- Modify: `AGENTS.md` (notch sizing / screen migration note)

**Interfaces:**
- Consumes: `NotchWindowController.moveToScreen(_:)` (Task 1); `NotchScreenMigrationDecider.evaluate(...)` + `NotchMigrationAction` (Task 2); `EventMonitors.shared.mouseLocation` (`CurrentValueSubject<CGPoint, Never>`); `ScreenSelector.screenContaining(_:)`, `.migrateToScreen(_:)`, `.screenID(of:)`, `.selectionMode`, `.selectedScreen`.

- [ ] **Step 1: Make `updateScreen` reposition the existing window**

In `IslandPresentationCoordinator.swift`, `updateScreen(_ screen:)` (line 25) already sets `self.screen`, recomputes geometry, and re-applies the surface mode. Add a single window-reposition call so a cross-screen call moves the existing window instead of needing a rebuild. Replace the body so it reads:

```swift
    func updateScreen(_ screen: NSScreen) {
        self.screen = screen
        let geometry = Self.makeDockedScreenGeometry(for: screen)
        viewModel.updateScreenGeometry(
            deviceNotchRect: geometry.deviceNotchRect,
            screenRect: geometry.screenRect,
            windowHeight: geometry.windowHeight,
            hasPhysicalNotch: geometry.hasPhysicalNotch,
            menuBarHeight: geometry.menuBarHeight
        )
        dockedWindowController?.moveToScreen(screen)
        applySurfaceMode(AppSettings.surfaceMode, performBootAnimation: false)
    }
```

(Only one line is new: the `dockedWindowController?.moveToScreen(screen)` call, inserted just before `applySurfaceMode`. Everything else already exists verbatim, including `self.screen = screen` and the `menuBarHeight` argument.)

- [ ] **Step 2: Verify it still builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Add cursor-follow migration to WindowManager**

In `WindowManager.swift`, add stored state for the dwell + a cheap migration helper, subscribe to `mouseLocation`, and route the existing focus trigger through the same cheap path.

Add these stored properties near `lastMigrationTime`:

```swift
    private var pendingMigrationScreenID: CGDirectDisplayID?
    private var pendingMigrationSince: Date?
    private static let cursorFollowDwell: TimeInterval = 0.2
```

Add a cursor subscription inside `startFocusTracking()` (after the existing `didBecomeKeyNotification` subscription):

```swift
        // Follow the cursor across screens in automatic mode (full monitoring only;
        // the mouseMoved source is energy-gated in EventMonitors).
        EventMonitors.shared.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point in
                self?.handleCursorMovement(point)
            }
            .store(in: &cancellables)
```

Add the cursor handler + a shared cheap-migrate method:

```swift
    private func handleCursorMovement(_ point: CGPoint) {
        let selector = ScreenSelector.shared
        let cursorScreen = selector.screenContaining(point)
        let action = NotchScreenMigrationDecider.evaluate(
            mode: selector.selectionMode,
            cursorScreenID: cursorScreen.flatMap { selector.screenID(of: $0) },
            currentScreenID: selector.selectedScreen.flatMap { selector.screenID(of: $0) },
            pendingScreenID: pendingMigrationScreenID,
            pendingSince: pendingMigrationSince,
            now: Date(),
            dwell: Self.cursorFollowDwell
        )
        switch action {
        case .none:
            if cursorScreen.flatMap({ selector.screenID(of: $0) })
                == selector.selectedScreen.flatMap({ selector.screenID(of: $0) }) {
                pendingMigrationScreenID = nil
                pendingMigrationSince = nil
            }
        case .beginDwell(let id):
            pendingMigrationScreenID = id
            pendingMigrationSince = Date()
        case .migrate:
            pendingMigrationScreenID = nil
            pendingMigrationSince = nil
            if let target = cursorScreen { migrate(to: target) }
        }
    }

    /// Cheap migration: reposition the existing notch window, no rebuild.
    private func migrate(to screen: NSScreen) {
        let selector = ScreenSelector.shared
        selector.migrateToScreen(screen)
        presentationCoordinator?.updateScreen(screen)
        activeScreenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        lastMigrationTime = Date()
    }
```

Then change `handleFocusChange` so its migration uses the cheap path instead of `setupNotchWindow()` rebuild. Replace its final two lines:

```swift
        lastMigrationTime = now
        logger.info("Focus changed, migrating notch to cursor screen")
        selector.migrateToScreen(targetScreen)
        _ = setupNotchWindow()
```

with:

```swift
        logger.info("Focus changed, migrating notch to cursor screen")
        migrate(to: targetScreen)
```

- [ ] **Step 4: Verify it builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the migration + frame test suites (no regression)**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchScreenMigrationDeciderTests -only-testing:PingIslandTests/NotchWindowControllerFrameTests -only-testing:PingIslandTests/NotchViewModelTests`
Expected: PASS.

- [ ] **Step 6: Update AGENTS.md**

In `AGENTS.md`, under the change-routing bullet about notch sizing/visibility ("If you change notch sizing, opening behavior, or visibility, inspect both `NotchViewModel` and `NotchView`."), add a sub-bullet:

```markdown
  - Docked-notch screen migration in automatic mode follows the cursor: `WindowManager` subscribes to `EventMonitors.mouseLocation`, `NotchScreenMigrationDecider.evaluate` gates it with a dwell, and migration repositions the existing window via `IslandPresentationCoordinator.updateScreen` → `NotchWindowController.moveToScreen` (no coordinator rebuild). The `.mouseMoved` source is energy-gated to `EnergyGovernor` level `.full`, so low-power falls back to focus-change migration.
```

- [ ] **Step 7: Full suite + build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Manual verification (jack-loop)**

1. Build + launch on a multi-monitor Mac in automatic screen mode.
2. Move the cursor to another screen and leave it there. The docked notch should appear on that screen within ~0.2 s, with no rebuild flicker.
3. Sweep the cursor quickly across a screen without stopping — the notch should not chase every transient crossing.
4. Switch to specific-screen mode: cursor movement must NOT migrate the notch.
5. Cross between the built-in (notched) screen and an external screen: the closed bar height stays correct on each (physical notch vs menu bar).

- [ ] **Step 9: Commit**

```bash
git add PingIsland/App/IslandPresentationCoordinator.swift PingIsland/App/WindowManager.swift AGENTS.md
git commit -m "feat: follow cursor across screens without rebuilding the notch"
```

---

## Self-Review

**Spec coverage:**
- Reposition instead of rebuild → Task 1 (`moveToScreen`) + Task 3 Step 1 (`updateScreen` calls it).
- Trigger on cursor screen-crossing with dwell → Task 2 (decider) + Task 3 Step 3 (subscription).
- Only automatic mode → decider `guard mode == .automatic` (Task 2) + tested.
- Cheap path only, rebuild reserved for lifecycle → Task 3 `migrate(to:)` uses `updateScreen`; `setupNotchWindow` rebuild left for screen-list/first-launch.
- Energy degradation → relies on existing `mouseLocation` gating; documented in Task 3 Step 6.
- Notch↔non-notch transition height → `updateScreen` passes `menuBarHeight` (Task 3 Step 1) and `hasPhysicalNotch`; covered by manual Step 8.5.
- Dwell tunable constant → `cursorFollowDwell = 0.2` (Task 3 Step 3).

**Placeholder scan:** No TBD/TODO; all steps carry concrete code + commands.

**Type consistency:** `dockedWindowFrame(screenFrame:)`, `moveToScreen(_:)`, `NotchMigrationAction`, `NotchScreenMigrationDecider.evaluate(...)`, and `screenID(of:) -> CGDirectDisplayID?` are used identically across tasks and match the existing `ScreenSelector` / `EventMonitors` / `IslandPresentationCoordinator` signatures.

## Success criteria

- Cursor to another screen (automatic mode, full monitoring) → notch moves there within ~one dwell interval, no rebuild flicker.
- Specific-screen mode never migrates on cursor movement.
- Low-power still migrates on focus change.
- All new unit tests + full `PingIslandTests` pass; app builds.
