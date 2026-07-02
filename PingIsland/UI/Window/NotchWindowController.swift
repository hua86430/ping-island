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
    private var cancellables = Set<AnyCancellable>()
    private var hoverSensor: NotchHoverSensorWindow!

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
        // (which early-return below) so the sensor orders out when suppressed
        // and re-frames to the reveal rect in fullscreen edge-reveal.
        hoverSensor.update(rect: viewModel.status == .opened ? nil : viewModel.hoverSensorRect)

        let shouldHideWindow = viewModel.shouldHideWindowPresentation

        if shouldHideWindow {
            window.ignoresMouseEvents = true
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }

        if window.frame != fullWindowFrame {
            window.setFrame(fullWindowFrame, display: true)
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
    }

    /// Reposition the existing window onto a different screen without rebuilding it.
    func moveToScreen(_ screen: NSScreen) {
        let frame = Self.dockedWindowFrame(screenFrame: screen.frame)
        guard frame != fullWindowFrame else { return }
        fullWindowFrame = frame
        window?.setFrame(frame, display: true)
    }
}
