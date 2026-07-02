# Notch hover sensor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the docked notch open/close on hover at all `EnergyGovernor` levels (including idle) via an always-mouse-active hover-sensor window, without breaking menu-bar click-through, click-through replay, or keyboard focus.

**Architecture:** A small, near-transparent, nonactivating hover-sensor panel covers only the closed-notch trigger rect; an `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeAlways`) on it drives hover-open (the spike verified this fires while the app is a background accessory). Close-on-leave while open is driven by a second tracking area sized to the actual opened-panel rect. Click-open and drag-to-detach are unchanged — they ride the existing local `NSEvent` monitor. The energy-gated global `.mouseMoved` monitor keeps serving `WindowManager` cursor-follow only.

**Tech Stack:** Swift, AppKit (NSPanel/NSTrackingArea/NSEvent), Combine, XCTest. Spec: `docs/superpowers/specs/2026-07-03-notch-hover-sensor-design.md`.

**Revision note:** revised after a Fable 5 plan review that found four blocking issues (fixed below): sensor update was placed after `updateWindowPresentation`'s hidden-state early return; the opened-close overlay lacked a frame + `hitTest` override; the sensor/close rects were not refreshed on all geometry/size changes; and plan/spec disagreed on the hidden-state sensor. The spec was updated to match the resolved semantics.

## Global Constraints

- Branch: `notch-hover-tracking-area`. Develop + verify on a local Debug build before merging to main.
- Commit style: ticket-less Conventional Commits.
- Sensor is HOVER-ONLY. Do NOT override `mouseDown/mouseDragged/mouseUp` anywhere for it: the local `NSEvent` monitor (`EventMonitor.swift:104-115`) already delivers those to `handleMouseDown`; forwarding would double-fire and break detachment (spike: `globalDown=0`, `localDown=1`).
- Sensor window: match `NotchPanel` space/level (`NotchWindow.swift:42-50`) — `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `level = .mainMenu + 3`; `nonactivatingPanel`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `ignoresMouseEvents = false`, `hidesOnDeactivate = false`, `canBecomeKey = false`, near-zero-alpha content (alpha ≈ 0.01) so the window stays in hit-testing.
- Opened-close overlay: `frame = contentView.bounds`, `autoresizingMask = [.width, .height]`, and `override func hitTest(_:) -> NSView? { nil }` so it never intercepts SwiftUI panel clicks and never breaks `NotchPanel.sendEvent` click-through replay (`NotchWindow.swift:69-79`, which passes through when `contentView.hitTest == nil`). Tracking-area events are dispatched to the owner regardless of `hitTest`.
- Sensor + close-rect refresh must run on EVERY input that moves the rects. `updateWindowPresentation` early-returns when `shouldHideWindowPresentation` (`NotchWindowController.swift:165-171`), and its Combine sinks currently cover only `$status/$openReason/$isFullscreenEdgeRevealActive/$isFullscreenBrowserHiddenActive/$isIdleAutoHiddenActive/$isQuietBackgroundPresentationActive/$presentationMode` + EnergyGovernor `$mode`. This plan adds sinks for `$geometry`, `$closedWidth` (sensor rect) and `$contentType`, `$openedMeasuredHeight` (opened-close rect), and drives the sensor update BEFORE the early return.
- Preserve the `458e0a5` focus-theft fix: hover uses reason `.hover`, excluded from `NSApp.activate`/`makeKey`.
- Keep the feel: `hoverActivationDelay` before opening; `shouldAutoCollapseHoverPreview` rules on close.
- Hidden-state semantics (matches the spec): sensor is `nil` (ordered out) when detached OR suppress-hidden (`isFullscreenBrowserHiddenActive`, or `isIdleAutoHiddenActive`/`isQuietBackgroundPresentationActive` while not opened) — no invisible click-eater when the notch is deliberately gone. Sensor uses `fullscreenRevealTriggerRect` only for fullscreen edge-reveal (`isFullscreenEdgeRevealActive` while not opened). Otherwise the closed trigger rect.

---

### Task 1: Pure hover-sensor frame selector

**Files:**
- Create: `PingIsland/Core/NotchHoverSensorFrame.swift`
- Test: `PingIslandTests/NotchHoverSensorFrameTests.swift`

**Interfaces:**
- Produces: `enum NotchHoverSensorFrame { static func rect(isDetached: Bool, isSuppressedHidden: Bool, isFullscreenReveal: Bool, closedTriggerRect: CGRect, fullscreenRevealRect: CGRect) -> CGRect? }`. `nil` when detached or suppress-hidden; reveal rect when fullscreen edge-reveal; otherwise the closed trigger rect.

- [ ] **Step 1: Write the failing test**

Create `PingIslandTests/NotchHoverSensorFrameTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Ping_Island

final class NotchHoverSensorFrameTests: XCTestCase {
    private let closed = CGRect(x: 620, y: 810, width: 200, height: 40)
    private let reveal = CGRect(x: 560, y: 800, width: 320, height: 60)

    private func rect(det: Bool = false, sup: Bool = false, rev: Bool = false) -> CGRect? {
        NotchHoverSensorFrame.rect(isDetached: det, isSuppressedHidden: sup,
            isFullscreenReveal: rev, closedTriggerRect: closed, fullscreenRevealRect: reveal)
    }

    func testNormalUsesClosedTriggerRect() { XCTAssertEqual(rect(), closed) }
    func testDetachedHasNoSensor() { XCTAssertNil(rect(det: true)) }
    func testSuppressedHiddenHasNoSensor() { XCTAssertNil(rect(sup: true)) }
    func testFullscreenRevealUsesRevealRect() { XCTAssertEqual(rect(rev: true), reveal) }
    func testDetachedWinsOverReveal() { XCTAssertNil(rect(det: true, rev: true)) }
    func testSuppressedWinsOverReveal() { XCTAssertNil(rect(sup: true, rev: true)) }
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
enum NotchHoverSensorFrame {
    static func rect(
        isDetached: Bool,
        isSuppressedHidden: Bool,
        isFullscreenReveal: Bool,
        closedTriggerRect: CGRect,
        fullscreenRevealRect: CGRect
    ) -> CGRect? {
        if isDetached || isSuppressedHidden { return nil }
        return isFullscreenReveal ? fullscreenRevealRect : closedTriggerRect
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests/NotchHoverSensorFrameTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Core/NotchHoverSensorFrame.swift PingIslandTests/NotchHoverSensorFrameTests.swift
git commit -m "feat: add pure hover-sensor frame selector"
```

---

### Task 2: Expose hover-trigger rect, sensor rect, opened-panel rect on NotchViewModel

**Files:**
- Modify: `PingIsland/Core/NotchViewModel.swift` (`isPointInHoverTrigger` ~753; add computed vars)

**Interfaces:**
- Consumes: `NotchHoverSensorFrame.rect(...)` (Task 1).
- Produces: `hoverTriggerRect: CGRect`, `hoverSensorRect: CGRect?`, `openedPanelScreenRect: CGRect`.

No-behavior-change refactor; verified by build + existing tests.

- [ ] **Step 1: Add rects and refactor `isPointInHoverTrigger`**

Replace `isPointInHoverTrigger` (`:753-758`) and add:

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
    /// is not present (detached or suppress-hidden). Reveal rect only for the
    /// fullscreen edge-reveal case.
    var hoverSensorRect: CGRect? {
        let isRevealActive = isFullscreenEdgeRevealActive && status != .opened
        let isSuppressed = isFullscreenBrowserHiddenActive
            || (isIdleAutoHiddenActive && status != .opened)
            || (isQuietBackgroundPresentationActive && status != .opened)
        return NotchHoverSensorFrame.rect(
            isDetached: presentationMode != .docked,
            isSuppressedHidden: isSuppressed,
            isFullscreenReveal: isRevealActive,
            closedTriggerRect: closedScreenRect.insetBy(dx: -10, dy: -5),
            fullscreenRevealRect: fullscreenRevealTriggerRect
        )
    }

    /// Screen rect of the opened panel (used for close-on-leave tracking).
    var openedPanelScreenRect: CGRect {
        geometry.openedScreenRect(for: openedSize)
    }
```

If `isPointInClosedNotch` (`:760`) becomes unused (`rg "isPointInClosedNotch" PingIsland`), delete it.

- [ ] **Step 2: Verify build + existing tests**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PingIsland/Core/NotchViewModel.swift
git commit -m "refactor: expose hoverTriggerRect / hoverSensorRect / openedPanelScreenRect"
```

---

### Task 3: Hover entry points + isHovering ownership on NotchViewModel

**Files:**
- Modify: `PingIsland/Core/NotchViewModel.swift` (`handleMouseMove` ~538-574; `setupEventHandlers` ~500-505; near `performDeferredHoverOpenIfNeeded` ~827)

**Interfaces:**
- Produces: `hoverSensorEntered()`, `hoverSensorExited()`, `openedPanelExited()`.

Design points from the review:
- `isHovering` is set true only when transitioning from not-hovering; cleared only on a real exit, NOT on close. This prevents the close-while-cursor-still-inside → auto-reopen loop: after an explicit close the cursor has not left, `isHovering` stays true, and the sensor's re-show (with its synthetic enter, Task 4) is gated out until a real exit+enter.
- `isHovering` has no UI reader today (verified); it only guards `performDeferredHoverOpenIfNeeded`. Keeping it true after close is safe.

- [ ] **Step 1: Add entry points**

Add near `performDeferredHoverOpenIfNeeded` (~827):

```swift
    /// Cursor entered the closed-notch hover-sensor rect (real or synthetic).
    /// Idempotent: only starts the dwell on a not-hovering → hovering edge.
    func hoverSensorEntered() {
        guard presentationMode == .docked else { return }
        guard status == .closed || status == .popping else { return }
        guard !isHovering else { return }
        isHovering = true
        hoverTimer?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDeferredHoverOpenIfNeeded()
        }
        hoverTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverActivationDelay, execute: workItem)
    }

    /// Cursor left the closed-notch hover-sensor rect.
    func hoverSensorExited() {
        hoverTimer?.cancel()
        hoverTimer = nil
        isHovering = false
    }

    /// Cursor left the opened panel rect.
    func openedPanelExited() {
        guard presentationMode == .docked else { return }
        guard status == .opened else { return }
        // Backstop against a stale tracking rect: re-check the current panel rect.
        if openedPanelScreenRect.contains(NSEvent.mouseLocation) { return }
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

- [ ] **Step 2: Remove the mouseLocation hover subscription + handleMouseMove**

In `setupEventHandlers` (`:500-505`), delete the `events.mouseLocation` sink that calls `handleMouseMove`. Delete `handleMouseMove` (`:538-574`). Keep `mouseDown/mouseDragged/mouseUp` subscriptions. Verify: `rg "handleMouseMove" PingIsland` returns nothing.

- [ ] **Step 3: Verify build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED. (Hover is inert until Tasks 4-5 wire the sensor and close area; click-open still works. This is an expected intermediate state — do not treat inert hover as a bug during Task 3/4 verification.)

- [ ] **Step 4: Run the suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PingIsland/Core/NotchViewModel.swift
git commit -m "refactor: hover open/close via explicit entry points, drop mouseMoved hover"
```

---

### Task 4: NotchHoverSensorWindow + wire hover-open (with full refresh coverage)

**Files:**
- Create: `PingIsland/UI/Window/NotchHoverSensorWindow.swift`
- Modify: `PingIsland/UI/Window/NotchWindowController.swift` (add sink subscriptions; drive sensor in `updateWindowPresentation` before the early return)

**Interfaces:**
- Consumes: `hoverSensorEntered()/hoverSensorExited()` (Task 3), `hoverSensorRect` (Task 2).
- Produces: `NotchHoverSensorWindow(onEnter:onExit:)`; `func update(rect: CGRect?)`.

- [ ] **Step 1: Create the sensor window**

Create `PingIsland/UI/Window/NotchHoverSensorWindow.swift`:

```swift
import AppKit

/// Near-transparent, nonactivating panel over the closed-notch trigger rect.
/// Its .activeAlways tracking area fires enter/exit even when the app is a
/// background accessory (verified by spike), so hover works at all energy levels.
final class NotchHoverSensorWindow: NSPanel {
    private let sensorView: SensorView

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        sensorView = SensorView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = .mainMenu + 3
        sensorView.onEnter = onEnter
        sensorView.onExit = onExit
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show + frame for `rect`, or order out when nil. Fires onEnter if the
    /// cursor is already inside (AppKit emits no mouseEntered for a cursor
    /// already within a freshly installed/moved tracking area). onEnter is
    /// itself idempotent (guarded by !isHovering in the view model), so a
    /// re-show under a stationary cursor after a close does not reopen.
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
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onEnter() }
        override func mouseExited(with event: NSEvent) { onExit() }
    }
}
```

- [ ] **Step 2: Own the sensor + add refresh sinks in NotchWindowController**

Add a stored property (created in `init`, after the notch window exists, using the controller's `viewModel`):

```swift
    private let hoverSensor: NotchHoverSensorWindow
```

In `init`, before the sink setup:

```swift
        hoverSensor = NotchHoverSensorWindow(
            onEnter: { [weak viewModel] in viewModel?.hoverSensorEntered() },
            onExit: { [weak viewModel] in viewModel?.hoverSensorExited() }
        )
```

(Order stored-property init before `super.init` per Swift rules; if `viewModel` is needed in the closure, assign the closures after `super.init` via a small setter, or capture `self` weakly and read `self.viewModel`. Simplest: give the window settable `onEnter/onExit` and wire them right after `super.init`.)

Add refresh sinks alongside the existing `$status`/`$openReason` sinks (~65-87), so the sensor re-frames on geometry and width changes too:

```swift
        viewModel.$geometry
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$closedWidth
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)
```

- [ ] **Step 3: Drive the sensor BEFORE the early return**

In `updateWindowPresentation(window:viewModel:)`, at the very TOP (before the `shouldHideWindow` early-return block ~163-171), add:

```swift
        hoverSensor.update(rect: viewModel.status == .opened ? nil : viewModel.hoverSensorRect)
```

This runs for hidden states too, so the sensor orders out when suppress-hidden (`hoverSensorRect == nil`) and re-frames to the reveal rect in fullscreen edge-reveal. The `moveToScreen` migration path needs no extra sensor call: `IslandPresentationCoordinator.updateScreen` updates `geometry`, which fires the `$geometry` sink → `updateWindowPresentation` → sensor refresh, covering both a screen change and a menu-bar-height-only change (where `moveToScreen` early-returns).

- [ ] **Step 4: Verify build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Runtime-verify hover-open while idle**

Kill any stale instance; build + relaunch Debug; confirm process start > binary mtime. With NO active session (`interactionOnly`): hover over the closed notch → opens after ~`hoverActivationDelay`; move away before the delay → does not open. Confirm a menu-bar item beside the notch still clicks; hover-open does not steal terminal keyboard focus. Migrate to another screen (cursor-follow) → hover opens on the new screen, including when the cursor is already sitting on the new-screen notch.

- [ ] **Step 6: Commit**

```bash
git add PingIsland/UI/Window/NotchHoverSensorWindow.swift PingIsland/UI/Window/NotchWindowController.swift
git commit -m "feat: hover-sensor window drives idle-independent notch hover-open"
```

---

### Task 5: Opened-panel close tracking area

**Files:**
- Modify: `PingIsland/UI/Window/NotchWindowController.swift` (add overlay + close-rect sinks; set rect in `updateWindowPresentation`)

**Interfaces:**
- Consumes: `openedPanelExited()` (Task 3), `openedPanelScreenRect` (Task 2).
- Produces: an `OpenedCloseTrackingView` subview of the notch window content view.

- [ ] **Step 1: Add the overlay tracking view**

Add this subclass in `NotchWindowController.swift`:

```swift
    private final class OpenedCloseTrackingView: NSView {
        var panelRectInView: CGRect = .zero { didSet { updateTrackingAreas() } }
        var onExit: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // transparent to clicks + click-through replay
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            guard !panelRectInView.isEmpty else { return }
            addTrackingArea(NSTrackingArea(rect: panelRectInView,
                options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
        }
        override func mouseExited(with event: NSEvent) { onExit() }
    }
```

Attach one instance to the window content view in `init` (after `contentViewController` is set), full-size and auto-resizing:

```swift
        if let contentView = notchWindow.contentView {
            openedCloseTracking.frame = contentView.bounds
            openedCloseTracking.autoresizingMask = [.width, .height]
            openedCloseTracking.onExit = { [weak viewModel] in viewModel?.openedPanelExited() }
            contentView.addSubview(openedCloseTracking)
        }
```

with `private let openedCloseTracking = OpenedCloseTrackingView()`.

- [ ] **Step 2: Set the close rect + add resize sinks**

In `updateWindowPresentation`, after the sensor line (Step 4-3), maintain the close rect:

```swift
        if viewModel.status == .opened, let contentView = window.contentView {
            let screenRect = viewModel.openedPanelScreenRect
            let rectInWindow = window.convertFromScreen(screenRect)
            openedCloseTracking.panelRectInView = contentView.convert(rectInWindow, from: nil)
        } else {
            openedCloseTracking.panelRectInView = .zero
        }
```

Note: this block sits AFTER the early return, which is fine — the close rect only matters while `.opened` (never a hidden state). Add sinks so the rect follows panel resize:

```swift
        viewModel.$contentType
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$openedMeasuredHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)
```

(The `openedPanelExited()` backstop from Task 3 re-checks the live rect, so a one-frame-stale rect never mis-closes.)

- [ ] **Step 3: Verify build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Runtime-verify close-on-leave while idle**

With no active session, hover-open the notch, then move off the panel → it closes. It should NOT close while a settings popover or inline text input is active. Open a taller panel (longer session list / switch content) and confirm it closes at the panel edge, not the screen edge. Clicking a button inside the opened panel still works (overlay `hitTest` is nil).

- [ ] **Step 5: Run the suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project PingIsland.xcodeproj -scheme PingIsland -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:PingIslandTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add PingIsland/UI/Window/NotchWindowController.swift
git commit -m "feat: close docked notch on leaving the opened panel rect (energy-independent)"
```

---

### Task 6: Full runtime verification + docs

**Files:**
- Modify: `AGENTS.md` (notch sizing/visibility bullet)

- [ ] **Step 1: End-to-end runtime verification (jack-loop)**

On the Debug build, idle (no active session), verify the spec success criteria:
1. Hover opens the closed notch (~`hoverActivationDelay`); leaving closes it.
2. Menu-bar item beside the notch still clicks (click-through preserved).
3. Closed-notch click-open and drag-to-detach still work.
4. Screen migration (cursor-follow): hover works on the new screen, including cursor-already-there.
5. Hover-open does not steal terminal keyboard focus.
6. Close-then-reopen loop is absent: click/Esc-close while the cursor stays on the notch does NOT auto-reopen; you must leave and re-enter.
7. Suppress-hidden states: when the notch is idle-auto-hidden / quiet-background, a click on the top-center area is NOT swallowed (sensor is `nil` there).
8. External screen with a crowded menu bar: the sensor rect does not swallow a needed status-item / app-menu click; if it does, narrow `hoverSensorRect`'s closed rect to `closedScreenRect` (drop the `-10` inset) and re-verify.

- [ ] **Step 2: Update AGENTS.md**

Under the notch sizing/visibility change-routing bullet, add:

```markdown
  - Docked-notch hover open/close is driven by `NotchHoverSensorWindow` (a nonactivating near-transparent panel over the trigger rect with an `.activeAlways` NSTrackingArea) plus an opened-panel-rect `OpenedCloseTrackingView` in `NotchWindowController`, not by the energy-gated global `.mouseMoved` monitor — so hover works when the app is idle. Click-open and drag-detach still ride the local `NSEvent` monitor into `handleMouseDown`. The sensor rect is `NotchViewModel.hoverSensorRect` (nil when detached/suppress-hidden, reveal rect in fullscreen edge-reveal), refreshed from `updateWindowPresentation` via `$status/$openReason/$geometry/$closedWidth/...` sinks. Trace `NotchHoverSensorFrame`, `NotchViewModel.hoverSensorRect/openedPanelScreenRect`, and `NotchWindowController.updateWindowPresentation` together when changing hover.
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

**Spec coverage:** hover-only sensor (Task 4); click/drag via local monitor unchanged (Constraints + Task 3); opened-panel-rect close, not full window (Task 5, Finding 2); cursor-already-inside hit-test (Task 4 `update`, Finding 4); isHovering ownership + no-reopen gate (Task 3, Findings 5/6); lifecycle before early-return + full sink coverage (Tasks 4-5, Findings 1/3); window properties incl. hidesOnDeactivate + near-zero alpha (Task 4, Finding 3); overlay hitTest→nil protecting click-through replay (Task 5, Finding 2); hidden-state semantics aligned with spec (Constraints + Task 2, Finding 4); migration via $geometry sink (Task 4); click-consume verification (Task 6.1.7-8, Finding 5); focus-theft preserved (Constraints); frame selector unit test (Task 1).

**Placeholder scan:** none. AppKit-integration tasks (3-5) verify via build + runtime because only the frame selector is unit-testable without a live window; the spike de-risked the mechanism. Runtime steps state exact conditions + expected behavior.

**Type consistency:** `hoverSensorRect: CGRect?`, `hoverTriggerRect: CGRect`, `openedPanelScreenRect: CGRect`, `hoverSensorEntered()/hoverSensorExited()/openedPanelExited()`, `NotchHoverSensorWindow(onEnter:onExit:)`+`update(rect:)`, `OpenedCloseTrackingView.panelRectInView/onExit`, `NotchHoverSensorFrame.rect(isDetached:isSuppressedHidden:isFullscreenReveal:closedTriggerRect:fullscreenRevealRect:)` are used identically across tasks.

## Success criteria

- Hover opens/closes the docked notch with no active session (idle), same feel as today.
- Menu-bar click-through, click-through replay, closed-notch click-open, drag-to-detach all still work.
- Hover-open never steals keyboard focus; no close→reopen loop.
- Sensor tracks the notch across screen migration, width changes, and fullscreen reveal; absent (no click-eater) when suppress-hidden.
- `NotchHoverSensorFrameTests` + full `PingIslandTests` pass; app builds.
