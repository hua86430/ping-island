# Notch hover sensor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the docked notch open/close on hover at all `EnergyGovernor` levels (including idle) via an always-mouse-active hover-sensor window, without breaking menu-bar click-through or stealing keyboard focus.

**Architecture:** A small, near-transparent, nonactivating hover-sensor panel covers only the closed-notch trigger rect; an `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeAlways`) on it drives hover-open (the spike verified this fires while the app is a background accessory). Close-on-leave while open is driven by a second tracking area sized to the actual opened-panel rect. Click-open and drag-to-detach are unchanged — they ride the existing local `NSEvent` monitor. The energy-gated global `.mouseMoved` monitor keeps serving `WindowManager` cursor-follow only.

**Tech Stack:** Swift, AppKit (NSPanel/NSTrackingArea/NSEvent), Combine, XCTest. Spec: `docs/superpowers/specs/2026-07-03-notch-hover-sensor-design.md`.

## Global Constraints

- Branch: `notch-hover-tracking-area`. Develop + verify on a local Debug build before merging to main.
- Commit style: ticket-less Conventional Commits.
- Do NOT add a sensor-view override for `mouseDown/mouseDragged/mouseUp`: the local `NSEvent` monitor (`EventMonitor.swift:104-115`) already delivers those to `handleMouseDown`; forwarding would double-fire and break the detachment gesture (spike: `globalDown=0`, `localDown=1`).
- Sensor is hover-only. Click-open / drag-detach / click-outside-to-close stay on the existing monitor path.
- Sensor window must match `NotchPanel`'s space behavior: `collectionBehavior` and `level` copied from `NotchWindow.swift:42-50`; near-zero-alpha content (alpha ≈ 0.01), `ignoresMouseEvents = false`, `nonactivatingPanel`, `canBecomeKey = false`.
- Preserve the `458e0a5` focus-theft fix: hover uses reason `.hover`, which is excluded from `NSApp.activate`/`makeKey`.
- Keep the current feel: `hoverActivationDelay` before opening; `shouldAutoCollapseHoverPreview` rules on close.

---

### Task 1: Pure hover-sensor frame selector

**Files:**
- Create: `PingIsland/Core/NotchHoverSensorFrame.swift`
- Test: `PingIslandTests/NotchHoverSensorFrameTests.swift`

**Interfaces:**
- Produces: `enum NotchHoverSensorFrame { static func rect(isDetached: Bool, shouldHideClosed: Bool, closedTriggerRect: CGRect, fullscreenRevealRect: CGRect) -> CGRect? }`. Returns `nil` when detached (no docked sensor); the reveal rect when the closed presentation is hidden (idle/quiet/fullscreen); otherwise the closed trigger rect. This mirrors `NotchViewModel.isPointInHoverTrigger` plus the `presentationMode == .docked` guard in `handleMouseMove`.

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/NotchHoverSensorFrameTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Ping_Island

final class NotchHoverSensorFrameTests: XCTestCase {
    private let closed = CGRect(x: 620, y: 810, width: 200, height: 40)
    private let reveal = CGRect(x: 560, y: 800, width: 320, height: 60)

    func testDetachedHasNoSensor() {
        XCTAssertNil(NotchHoverSensorFrame.rect(
            isDetached: true, shouldHideClosed: false,
            closedTriggerRect: closed, fullscreenRevealRect: reveal))
    }

    func testNormalUsesClosedTriggerRect() {
        XCTAssertEqual(NotchHoverSensorFrame.rect(
            isDetached: false, shouldHideClosed: false,
            closedTriggerRect: closed, fullscreenRevealRect: reveal), closed)
    }

    func testHiddenClosedUsesRevealRect() {
        XCTAssertEqual(NotchHoverSensorFrame.rect(
            isDetached: false, shouldHideClosed: true,
            closedTriggerRect: closed, fullscreenRevealRect: reveal), reveal)
    }

    func testDetachedWinsOverHidden() {
        XCTAssertNil(NotchHoverSensorFrame.rect(
            isDetached: true, shouldHideClosed: true,
            closedTriggerRect: closed, fullscreenRevealRect: reveal))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchHoverSensorFrameTests`
Expected: FAIL to compile — `NotchHoverSensorFrame` does not exist.

- [ ] **Step 3: Implement the selector**

Create `PingIsland/Core/NotchHoverSensorFrame.swift`:

```swift
import CoreGraphics

/// Pure selection of the docked notch's hover-sensor frame.
/// Mirrors NotchViewModel.isPointInHoverTrigger plus the docked-only guard.
enum NotchHoverSensorFrame {
    static func rect(
        isDetached: Bool,
        shouldHideClosed: Bool,
        closedTriggerRect: CGRect,
        fullscreenRevealRect: CGRect
    ) -> CGRect? {
        if isDetached { return nil }
        return shouldHideClosed ? fullscreenRevealRect : closedTriggerRect
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchHoverSensorFrameTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Core/NotchHoverSensorFrame.swift PingIslandTests/NotchHoverSensorFrameTests.swift
git commit -m "feat: add pure hover-sensor frame selector"
```

---

### Task 2: Expose hover-trigger rect and sensor rect on NotchViewModel

**Files:**
- Modify: `PingIsland/Core/NotchViewModel.swift` (`isPointInHoverTrigger` at ~753; add computed vars near it)

**Interfaces:**
- Consumes: `NotchHoverSensorFrame.rect(...)` (Task 1).
- Produces: `NotchViewModel.hoverTriggerRect: CGRect` (the rect `isPointInHoverTrigger` tests); `NotchViewModel.hoverSensorRect: CGRect?` (nil when detached, else the trigger rect); `NotchViewModel.openedPanelScreenRect: CGRect` (`geometry.openedScreenRect(for: openedSize)`).

This task is a no-behavior-change refactor: it introduces the rects the sensor and the opened close-area consume. Verified by build + existing tests.

- [ ] **Step 1: Extract `hoverTriggerRect` and refactor `isPointInHoverTrigger`**

Replace `isPointInHoverTrigger` (`:753-758`) and add the sensor/opened rects:

```swift
    var hoverTriggerRect: CGRect {
        if shouldHideClosedPresentation {
            return fullscreenRevealTriggerRect
        }
        return closedScreenRect.insetBy(dx: -10, dy: -5)
    }

    func isPointInHoverTrigger(_ point: CGPoint) -> Bool {
        hoverTriggerRect.contains(point)
    }

    /// Frame for the always-on hover-sensor window; nil when the docked notch
    /// is not the active presentation (detached).
    var hoverSensorRect: CGRect? {
        NotchHoverSensorFrame.rect(
            isDetached: presentationMode != .docked,
            shouldHideClosed: shouldHideClosedPresentation,
            closedTriggerRect: closedScreenRect.insetBy(dx: -10, dy: -5),
            fullscreenRevealRect: fullscreenRevealTriggerRect
        )
    }

    /// Screen rect of the opened panel (used for close-on-leave tracking).
    var openedPanelScreenRect: CGRect {
        geometry.openedScreenRect(for: openedSize)
    }
```

Note: `isPointInClosedNotch` (`:760-762`) may now be unused; leave it if other callers remain, otherwise delete it. Verify with `rg "isPointInClosedNotch" PingIsland`.

- [ ] **Step 2: Verify it builds and existing tests pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **` (no behavior change; `isPointInHoverTrigger` returns the same values).

- [ ] **Step 3: Commit**

```bash
git add PingIsland/Core/NotchViewModel.swift
git commit -m "refactor: expose hoverTriggerRect / hoverSensorRect / openedPanelScreenRect"
```

---

### Task 3: Hover-open entry points + isHovering ownership on NotchViewModel

**Files:**
- Modify: `PingIsland/Core/NotchViewModel.swift` (`handleMouseMove` ~538-574; `setupEventHandlers` ~497-527; `performDeferredHoverOpenIfNeeded` ~827; `hoverTimer`)

**Interfaces:**
- Produces: `NotchViewModel.hoverSensorEntered()`, `NotchViewModel.hoverSensorExited()`, `NotchViewModel.openedPanelExited()` — called by the sensor window (Task 4) and the opened close-area (Task 5). They own `isHovering` set/clear and the dwell timer, replacing the hover role of `handleMouseMove`.

Rationale: `handleMouseMove` currently sets/clears `isHovering` and starts the hover dwell from the energy-gated `mouseLocation` stream (`:538-574`). Move that logic to explicit entry points the tracking areas call. Keep `handleMouseDown/Dragged/Up` untouched. Remove the `mouseLocation` subscription so hover no longer depends on `.mouseMoved`.

- [ ] **Step 1: Add the hover entry points**

Add to `NotchViewModel` (near `performDeferredHoverOpenIfNeeded`, ~827):

```swift
    /// Cursor entered the closed-notch hover-sensor rect.
    func hoverSensorEntered() {
        guard presentationMode == .docked else { return }
        guard status == .closed || status == .popping else { return }
        isHovering = true
        hoverTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDeferredHoverOpenIfNeeded()
        }
        hoverTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverActivationDelay, execute: workItem)
    }

    /// Cursor left the closed-notch hover-sensor rect before opening.
    func hoverSensorExited() {
        hoverTimer?.cancel()
        hoverTimer = nil
        if status == .closed || status == .popping {
            isHovering = false
        }
    }

    /// Cursor left the opened panel rect.
    func openedPanelExited() {
        guard presentationMode == .docked else { return }
        guard status == .opened else { return }
        isHovering = false
        if Self.shouldAutoCollapseHoverPreview(
            isHovering: false,
            status: status,
            openReason: openReason,
            isSettingsPopoverPresented: isSettingsPopoverPresented,
            isInlineTextInputActive: isInlineTextInputActive,
            autoCollapseOnLeave: AppSettings.autoCollapseOnLeave
        ) {
            notchClose()
        }
    }
```

- [ ] **Step 2: Remove the hover role from the mouseLocation stream**

In `setupEventHandlers` (`:500-505`), delete the `events.mouseLocation` subscription block (the sink that calls `handleMouseMove`). Then delete `handleMouseMove` (`:538-574`). Leave `mouseDown`/`mouseDragged`/`mouseUp` subscriptions intact.

Verify no other caller: `rg "handleMouseMove" PingIsland` should return nothing after deletion.

- [ ] **Step 3: Verify it builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED. (Hover is temporarily inert until Tasks 4-5 wire the sensor; click-open still works.)

- [ ] **Step 4: Run the suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Core/NotchViewModel.swift
git commit -m "refactor: move hover open/close to explicit entry points, drop mouseMoved hover"
```

---

### Task 4: NotchHoverSensorWindow + wire it for hover-open

**Files:**
- Create: `PingIsland/UI/Window/NotchHoverSensorWindow.swift`
- Modify: `PingIsland/UI/Window/NotchWindowController.swift` (own the sensor in `updateWindowPresentation` ~162; reposition in `moveToScreen`)

**Interfaces:**
- Consumes: `NotchViewModel.hoverSensorEntered()/hoverSensorExited()` (Task 3), `NotchViewModel.hoverSensorRect` (Task 2).
- Produces: `NotchHoverSensorWindow(onEnter:onExit:)`; `func update(rect: CGRect?)` (shows + frames when non-nil, orders out when nil, and hit-tests the current cursor to fire `onEnter` when the cursor is already inside a freshly shown/moved rect).

- [ ] **Step 1: Create the sensor window**

Create `PingIsland/UI/Window/NotchHoverSensorWindow.swift`:

```swift
import AppKit

/// A near-transparent, nonactivating panel over the closed-notch trigger rect.
/// Its tracking area fires enter/exit even when the app is a background
/// accessory (verified by spike), so hover works at all energy levels.
final class NotchHoverSensorWindow: NSPanel {
    private let sensorView: SensorView

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        sensorView = SensorView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        // Match NotchPanel space/level behavior (NotchWindow.swift:42-50).
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = .mainMenu + 3
        sensorView.onEnter = onEnter
        sensorView.onExit = onExit
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show + frame the sensor for `rect`, or order out when nil. Fires onEnter
    /// if the cursor is already inside (AppKit does not emit mouseEntered for a
    /// cursor already within a freshly installed/moved tracking area).
    func update(rect: CGRect?) {
        guard let rect else {
            if isVisible { orderOut(nil) }
            return
        }
        setFrame(rect, display: false)
        if !isVisible { orderFrontRegardless() }
        if rect.contains(NSEvent.mouseLocation) {
            sensorView.onEnter()
        }
    }

    private final class SensorView: NSView {
        var onEnter: () -> Void = {}
        var onExit: () -> Void = {}

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            // Near-zero alpha keeps the window in hit-testing (spike finding).
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onEnter() }
        override func mouseExited(with event: NSEvent) { onExit() }
    }
}
```

- [ ] **Step 2: Own the sensor from NotchWindowController**

In `NotchWindowController.swift`, add a stored property and create the sensor in `init` (after the notch window is set up), wiring it to the viewModel:

```swift
    private lazy var hoverSensor = NotchHoverSensorWindow(
        onEnter: { [weak viewModel] in viewModel?.hoverSensorEntered() },
        onExit: { [weak viewModel] in viewModel?.hoverSensorExited() }
    )
```

(`viewModel` is already a stored `let` on the controller.) At the end of `updateWindowPresentation(window:viewModel:)` (~191), drive the sensor from the viewModel's current rect:

```swift
        hoverSensor.update(rect: viewModel.hoverSensorRect)
```

Because `updateWindowPresentation` is already the sink for `$status`, `$openReason`, `$isFullscreenEdgeRevealActive` and is called on geometry changes, the sensor re-frames on every relevant state change. When opened, `hoverSensorRect` is still the trigger rect — order the sensor out while opened to avoid overlap: change the line to

```swift
        hoverSensor.update(rect: viewModel.status == .opened ? nil : viewModel.hoverSensorRect)
```

- [ ] **Step 3: Reposition the sensor on screen migration**

In `moveToScreen(_:)` (added by the cursor-follow work), after `window?.setFrame(...)`, refresh the sensor so it follows to the new screen:

```swift
        hoverSensor.update(rect: viewModel.status == .opened ? nil : viewModel.hoverSensorRect)
```

(`viewModel.hoverSensorRect` recomputes from the new screen geometry once `updateScreenGeometry` has run in the same `updateScreen` call.)

- [ ] **Step 4: Verify it builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Runtime-verify hover-open works while idle**

Build + relaunch the Debug app (kill any stale instance; confirm the new process start time is later than the binary mtime). With NO active session (mode `interactionOnly`, so `.mouseMoved` is off), move the cursor over the closed notch and leave it: the notch should open after ~`hoverActivationDelay`. Move away before the delay: it should not open. Confirm a menu-bar item beside the notch still clicks, and hover-open does not steal keyboard focus from a terminal.

- [ ] **Step 6: Commit**

```bash
git add PingIsland/UI/Window/NotchHoverSensorWindow.swift PingIsland/UI/Window/NotchWindowController.swift
git commit -m "feat: hover-sensor window drives idle-independent notch hover-open"
```

---

### Task 5: Opened-panel close tracking area

**Files:**
- Modify: `PingIsland/UI/Window/NotchWindowController.swift` (opened window content view; `updateWindowPresentation`)

**Interfaces:**
- Consumes: `NotchViewModel.openedPanelExited()` (Task 3), `NotchViewModel.openedPanelScreenRect` (Task 2).
- Produces: a tracking area on the notch window's content view, sized to the opened panel rect (converted to view coordinates), installed while `status == .opened` and rebuilt when the panel size changes; `mouseExited` → `viewModel.openedPanelExited()`.

Rationale (spec Finding 2): the notch window is full-screen-width × 750pt, so a content-view-bounds tracking area only fires when leaving the whole top strip. The close area must equal the actual panel rect (`openedPanelScreenRect`) converted to the window's content-view coordinates.

- [ ] **Step 1: Add an opened-close tracking view**

Give the notch window content view (or a dedicated overlay subview) a tracking area covering the opened panel rect. Implement a small `NSView` subclass owned by `NotchWindowController` that installs the area from a settable `panelRectInView: CGRect` and calls a closure on `mouseExited`:

```swift
    private final class OpenedCloseTrackingView: NSView {
        var panelRectInView: CGRect = .zero { didSet { needsUpdateTrackingAreas() } }
        var onExit: () -> Void = {}
        private func needsUpdateTrackingAreas() { updateTrackingAreas() }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            guard !panelRectInView.isEmpty else { return }
            addTrackingArea(NSTrackingArea(
                rect: panelRectInView,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self, userInfo: nil))
        }
        override func mouseExited(with event: NSEvent) { onExit() }
    }
```

Wire an instance onto the opened window. In `updateWindowPresentation`, when `status == .opened`, set its `panelRectInView` to `viewModel.openedPanelScreenRect` converted from screen to the window's content-view space:

```swift
        if viewModel.status == .opened, let window = self.window {
            let screenRect = viewModel.openedPanelScreenRect
            let rectInWindow = window.convertFromScreen(screenRect)
            openedCloseTracking.panelRectInView = window.contentView?.convert(rectInWindow, from: nil) ?? .zero
            openedCloseTracking.onExit = { [weak viewModel] in viewModel?.openedPanelExited() }
        } else {
            openedCloseTracking.panelRectInView = .zero
        }
```

(Attach `openedCloseTracking` as a subview of the window's content view once, in `init`.)

- [ ] **Step 2: Verify it builds**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Runtime-verify close-on-leave works while idle**

With no active session, hover-open the notch (Task 4), then move the cursor off the panel: it should close (respecting the auto-collapse rules — it should NOT close if a settings popover or inline text input is active). Resize-triggering content (e.g. a longer session list) should still close correctly at the panel edge, not at the screen edge.

- [ ] **Step 4: Run the suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PingIsland/UI/Window/NotchWindowController.swift
git commit -m "feat: close docked notch on leaving the opened panel rect (energy-independent)"
```

---

### Task 6: Full runtime verification + docs

**Files:**
- Modify: `AGENTS.md` (notch sizing/visibility bullet — record the hover-sensor mechanism)

- [ ] **Step 1: End-to-end runtime verification (jack-loop)**

On the Debug build, with NO active session (idle), verify against the spec success criteria:
1. Hover over the closed notch opens it (~`hoverActivationDelay`); moving away closes it.
2. A menu-bar item beside the notch still clicks (click-through preserved).
3. Closed-notch click-open and drag-to-detach still work.
4. Migrate the notch to another screen (cursor-follow) and confirm hover opens on the new screen, including when the cursor is already sitting on the new-screen notch (the `update(rect:)` hit-test path).
5. Hover-open does not steal keyboard focus from a terminal.
6. If an external screen has a crowded menu bar, confirm the sensor rect does not swallow a needed status item / app-menu click (spec Finding 5); if it does, narrow the sensor rect to `closedScreenRect` (drop the `-10` inset) in `hoverSensorRect` and re-verify.

- [ ] **Step 2: Update AGENTS.md**

Under the notch sizing/visibility change-routing bullet, add:

```markdown
  - Docked-notch hover open/close is driven by `NotchHoverSensorWindow` (a nonactivating near-transparent panel over the trigger rect with an `.activeAlways` NSTrackingArea) plus an opened-panel-rect tracking area in `NotchWindowController`, not by the energy-gated global `.mouseMoved` monitor — so hover works when the app is idle. Click-open and drag-detach still ride the local `NSEvent` monitor into `handleMouseDown`. Trace `NotchHoverSensorFrame`, `NotchViewModel.hoverSensorRect/openedPanelScreenRect`, and `NotchWindowController.updateWindowPresentation` together when changing hover.
```

- [ ] **Step 3: Full suite + build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: record notch hover-sensor mechanism in AGENTS.md"
```

---

## Self-Review

**Spec coverage:**
- Hover-only sensor window + tracking area → Task 4. Spec "Approach", "Components".
- Click/drag unchanged via local monitor → Global Constraints + Task 3 keeps `handleMouseDown` untouched. Spec Finding 1.
- Opened-panel-rect close (not full window) → Task 5. Spec Finding 2.
- Cursor-already-inside hit-test → Task 4 `update(rect:)`. Spec Finding 4.
- isHovering ownership → Task 3 entry points. Spec Finding 6.
- Lifecycle in `updateWindowPresentation` → Tasks 4-5. Spec Finding 7.
- Window properties (collectionBehavior/level/near-zero alpha) → Task 4. Spec Finding 3.
- Migration sync → Task 4 Step 3. Spec edge cases.
- Fullscreen reveal rect → Task 2 `hoverTriggerRect` / `hoverSensorRect`. Spec geometry contract.
- Click-consume external-screen risk → Task 6 Step 1.6 verification. Spec Finding 5.
- Focus-theft preserved → Global Constraints (reason `.hover`). Spec goal.
- Frame selector unit test → Task 1.

**Placeholder scan:** none. AppKit-integration tasks (3-5) verify via build + runtime because only the frame selector is unit-testable without a live window; the spike already de-risked the tracking-area mechanism. Runtime steps state exact conditions and expected behavior.

**Type consistency:** `hoverSensorRect: CGRect?`, `hoverTriggerRect: CGRect`, `openedPanelScreenRect: CGRect`, `hoverSensorEntered()/hoverSensorExited()/openedPanelExited()`, `NotchHoverSensorWindow(onEnter:onExit:)` + `update(rect:)`, `NotchHoverSensorFrame.rect(isDetached:shouldHideClosed:closedTriggerRect:fullscreenRevealRect:)` are used identically across tasks.

## Success criteria

- Hover opens/closes the docked notch with no active session (idle), same feel as today.
- Menu-bar click-through, closed-notch click-open, drag-to-detach all still work.
- Hover-open never steals keyboard focus.
- Sensor tracks the notch across screen migration and fullscreen reveal.
- `NotchHoverSensorFrameTests` + full `PingIslandTests` pass; app builds.
