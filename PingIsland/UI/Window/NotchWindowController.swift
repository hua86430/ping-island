//
//  NotchWindowController.swift
//  PingIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private var fullWindowFrame: NSRect
    /// Screen frame the window is currently pinned to; source for per-status frames.
    private var dockedScreenFrame: NSRect
    private var cancellables = Set<AnyCancellable>()
    private var hoverSensor: NotchHoverSensorWindow!

    static let windowHeight: CGFloat = 750

    /// Window width for both closed and opened states. The docked opened panel is at
    /// most `min(screenWidth-64, 600)` wide (`NotchViewModel.panelSize`) plus the
    /// hit-test corner padding (~52), so 700 covers it with margin. The window is
    /// centered on screen, so a centered panel still lands at screen center — but the
    /// transparent frame no longer spans the full display width.
    static let panelWindowWidth: CGFloat = 700

    /// Extra height below the closed pill so the idle strip is not tight against the
    /// pill (mascot bob / shadow). Popping/boot scale-up uses the full-height frame,
    /// so this only covers the steady closed pill. Small so the strip tracks the
    /// dynamic `closedHeight`; tune by measurement.
    static let closedFrameSlack: CGFloat = 24

    /// Delay before shrinking back to the closed strip. Must exceed the SwiftUI
    /// collapse animation (`NotchViewModel` `.easeOut(duration: 0.25)`) so a
    /// collapsing panel is never cut off mid-animation.
    static let closedFrameShrinkDelay: TimeInterval = 0.30

    /// Centered, top-pinned docked frame: `panelWindowWidth` wide, full 750pt tall.
    static func dockedWindowFrame(screenFrame: CGRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - panelWindowWidth / 2,
            y: screenFrame.maxY - windowHeight,
            width: panelWindowWidth,
            height: windowHeight
        )
    }

    /// Centered, top-pinned strip just tall enough for the closed pill (+ slack).
    /// Used while idle so the transparent window no longer spans the screen.
    static func closedWindowFrame(screenFrame: CGRect, closedHeight: CGFloat) -> NSRect {
        let height = closedHeight + closedFrameSlack
        return NSRect(
            x: screenFrame.midX - panelWindowWidth / 2,
            y: screenFrame.maxY - height,
            width: panelWindowWidth,
            height: height
        )
    }

    /// Target window frame for the given notch status: the closed strip while
    /// `.closed`, the full 750pt canvas while `.opened` / `.popping`.
    static func targetWindowFrame(status: NotchStatus, screenFrame: CGRect, closedHeight: CGFloat) -> NSRect {
        switch status {
        case .closed:
            return closedWindowFrame(screenFrame: screenFrame, closedHeight: closedHeight)
        case .opened, .popping:
            return dockedWindowFrame(screenFrame: screenFrame)
        }
    }

    init(
        screen: NSScreen,
        viewModel: NotchViewModel,
        sessionMonitor: SessionMonitor,
        performBootAnimation: Bool
    ) {
        self.viewModel = viewModel

        let screenFrame = screen.frame

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowFrame = Self.dockedWindowFrame(screenFrame: screenFrame)
        self.fullWindowFrame = windowFrame
        self.dockedScreenFrame = screenFrame

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(
            viewModel: viewModel,
            sessionMonitor: sessionMonitor
        )
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // macOS 26 re-derives a content-shaped window shadow after the content view
        // and frame are set, ignoring the `hasShadow = false` from NotchPanel.init().
        // Re-assert it and invalidate so the transparent notch panel stays shadowless.
        notchWindow.hasShadow = false
        notchWindow.invalidateShadow()

        // Hover-sensor window: drives idle-independent hover-open (click/drag
        // still ride the local NSEvent monitor into handleMouseDown).
        hoverSensor = NotchHoverSensorWindow(
            onEnter: { [weak viewModel] in viewModel?.hoverSensorEntered() },
            onExit: { [weak viewModel] in viewModel?.hoverSensorExited() }
        )

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened: ignoresMouseEvents = false (buttons inside panel work)
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$openReason
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isFullscreenEdgeRevealActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Geometry / closed-width changes move the trigger rect; refresh the
        // sensor (and opened-close rect) via the same chokepoint.
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

        viewModel.$isFullscreenBrowserHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isIdleAutoHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isQuietBackgroundPresentationActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$presentationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isFullscreenBrowserHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        viewModel.$isIdleAutoHiddenActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] _ in
                guard let self, let notchWindow, let viewModel else { return }
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        EnergyGovernor.shared.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak notchWindow, weak viewModel] mode in
                guard let self, let notchWindow, let viewModel else { return }
                viewModel.updateQuietBackgroundPresentationState(isActive: mode == .quietBackground)
                self.updateWindowPresentation(window: notchWindow, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true
        updateWindowPresentation(window: notchWindow, viewModel: viewModel)

        // Perform boot animation after a brief delay
        if performBootAnimation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateWindowPresentation(window: NotchPanel, viewModel: NotchViewModel) {
        // Drive the hover sensor first — this must run even in hidden states
        // (which early-return below) so the sensor orders out when suppressed and
        // re-frames to the reveal rect in fullscreen edge-reveal. Ordered out
        // while opened; the bounded hover-close timer handles close-on-leave.
        hoverSensor.update(rect: viewModel.status == .opened ? nil : viewModel.hoverSensorRect)

        let shouldHideWindow = viewModel.shouldHideWindowPresentation

        if shouldHideWindow {
            window.ignoresMouseEvents = true
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }

        let targetFrame = Self.targetWindowFrame(
            status: viewModel.status,
            screenFrame: dockedScreenFrame,
            closedHeight: viewModel.closedHeight
        )
        switch viewModel.status {
        case .opened, .popping:
            // Grow to the full canvas BEFORE showing / opening (same runloop, ahead
            // of orderFront below) so expanding SwiftUI content is never clipped.
            if window.frame != targetFrame {
                window.setFrame(targetFrame, display: true)
            }
        case .closed:
            // Shrink to the idle strip, but only after the collapse animation and
            // only if still closed — a re-open during the delay cancels the shrink.
            if window.frame != targetFrame {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.closedFrameShrinkDelay) { [weak self, weak window, weak viewModel] in
                    guard let self, let window, let viewModel, viewModel.status == .closed else { return }
                    let strip = Self.targetWindowFrame(
                        status: .closed,
                        screenFrame: self.dockedScreenFrame,
                        closedHeight: viewModel.closedHeight
                    )
                    guard window.frame != strip else { return }
                    window.setFrame(strip, display: true)
                    self.reassertNoShadow(window: window)
                }
            }
        }

        if !window.isVisible {
            window.orderFront(nil)
        }

        switch viewModel.status {
        case .opened:
            window.ignoresMouseEvents = false
            // Hover-open is a preview: never steal keyboard focus from the
            // terminal. Only deliberate opens (click / shortcut) activate.
            if viewModel.openReason != .notification && viewModel.openReason != .hover {
                NSApp.activate(ignoringOtherApps: false)
                window.makeKey()
            }
        case .closed, .popping:
            window.ignoresMouseEvents = true
        }

        // macOS 26 re-derives a content-shaped window shadow from the opaque pill
        // after the SwiftUI content renders (which happens on the next runloop pass,
        // after this method returns), so a one-shot invalidate at init leaves a faint
        // residual. Re-assert once content has drawn on every presentation update.
        reassertNoShadow(window: window)
    }

    /// Re-assert the shadowless transparent panel on the next runloop pass. Must run
    /// after every `setFrame` (including the delayed shrink and `moveToScreen`) so the
    /// macOS 26 content-shaped shadow never lingers around the notch.
    private func reassertNoShadow(window: NotchPanel) {
        DispatchQueue.main.async { [weak window] in
            window?.hasShadow = false
            window?.invalidateShadow()
        }
    }

    /// Reposition the existing window onto a different screen without rebuilding it.
    func moveToScreen(_ screen: NSScreen) {
        let frame = Self.dockedWindowFrame(screenFrame: screen.frame)
        guard frame != fullWindowFrame else { return }
        fullWindowFrame = frame
        dockedScreenFrame = screen.frame
        guard let panel = window as? NotchPanel else { return }
        // Keep the per-status height across the migration: closed stays a strip,
        // opened/popping stay the full canvas.
        let target = Self.targetWindowFrame(
            status: viewModel.status,
            screenFrame: screen.frame,
            closedHeight: viewModel.closedHeight
        )
        panel.setFrame(target, display: true)
        reassertNoShadow(window: panel)
    }

    /// Close the notch window AND its hover-sensor panel. Callers must use this
    /// (not `close()`) before dropping the controller: the sensor is a separate
    /// ordered-in NSPanel that AppKit keeps on screen after the controller is
    /// released, so skipping it leaks one sensor window per rebuild — and each
    /// leaked panel stacks a faint shadow around the notch on macOS 26.
    func teardown() {
        hoverSensor?.orderOut(nil)
        hoverSensor?.close()
        window?.orderOut(nil)
        close()
    }
}
