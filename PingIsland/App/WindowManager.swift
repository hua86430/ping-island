//
//  WindowManager.swift
//  PingIsland
//
//  Manages the notch window lifecycle
//

import AppKit
import Combine
import os.log

/// Logger for window management
private let logger = Logger(subsystem: "com.wudanwu.pingisland", category: "Window")

@MainActor
class WindowManager {
    private(set) var presentationCoordinator: IslandPresentationCoordinator?
    private var activeScreenNumber: NSNumber?
    private var cancellables = Set<AnyCancellable>()
    private var lastMigrationTime: Date = .distantPast
    private var pendingMigrationScreenID: CGDirectDisplayID?
    private var pendingMigrationSince: Date?
    private var dwellWorkItem: DispatchWorkItem?
    private static let cursorFollowDwell: TimeInterval = 0.2

    init() {
        startFocusTracking()
    }

    /// Set up or recreate the notch window
    func setupNotchWindow() -> NotchWindowController? {
        // Use ScreenSelector for screen selection
        let screenSelector = ScreenSelector.shared
        screenSelector.refreshScreens()

        guard let screen = screenSelector.selectedScreen else {
            logger.warning("No screen found")
            return nil
        }

        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let presentationCoordinator,
           activeScreenNumber == screenNumber {
            presentationCoordinator.updateScreen(screen)
            return nil
        }

        presentationCoordinator?.invalidate()
        let presentationCoordinator = IslandPresentationCoordinator(screen: screen)
        self.presentationCoordinator = presentationCoordinator
        activeScreenNumber = screenNumber
        return nil
    }

    // MARK: - Focus-based screen migration

    /// Track application focus changes. When the user activates an app on a
    /// different screen, migrate the notch to follow.
    private func startFocusTracking() {
        // Track app-level focus changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.handleFocusChange()
            }
            .store(in: &cancellables)

        // Track window-level focus changes (covers same-app window switches)
        NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] _ in
                self?.handleFocusChange()
            }
            .store(in: &cancellables)

        // Follow the cursor across screens in automatic mode (full monitoring only;
        // the mouseMoved source is energy-gated in EventMonitors).
        EventMonitors.shared.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point in
                self?.handleCursorMovement(point)
            }
            .store(in: &cancellables)
    }

    private func handleFocusChange() {
        let selector = ScreenSelector.shared
        guard selector.selectionMode == .automatic else { return }

        // Debounce
        let now = Date()
        guard now.timeIntervalSince(lastMigrationTime) > 1.0 else { return }

        // Determine target screen from cursor position
        guard let targetScreen = selector.screenContaining(NSEvent.mouseLocation),
              let currentScreen = selector.selectedScreen else { return }

        let targetID = selector.screenID(of: targetScreen)
        let currentID = selector.screenID(of: currentScreen)

        guard targetID != currentID else { return }

        logger.info("Focus changed, migrating notch to cursor screen")
        migrate(to: targetScreen)
    }

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
                cancelDwellCheck()
            }
        case .beginDwell(let id):
            pendingMigrationScreenID = id
            pendingMigrationSince = Date()
            scheduleDwellCheck()
        case .migrate:
            pendingMigrationScreenID = nil
            pendingMigrationSince = nil
            cancelDwellCheck()
            if let target = cursorScreen { migrate(to: target) }
        }
    }

    // The dwell check runs inside the mouseLocation handler, so a cursor that
    // stops on the new screen (no further mouseMoved events) would never satisfy
    // the elapsed-dwell branch. Fire a one-shot timer to re-evaluate at the
    // current cursor position once the dwell has passed.
    private func scheduleDwellCheck() {
        dwellWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.handleCursorMovement(NSEvent.mouseLocation)
        }
        dwellWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorFollowDwell + 0.03, execute: item)
    }

    private func cancelDwellCheck() {
        dwellWorkItem?.cancel()
        dwellWorkItem = nil
    }

    /// Cheap migration: reposition the existing notch window, no rebuild.
    private func migrate(to screen: NSScreen) {
        let selector = ScreenSelector.shared
        selector.migrateToScreen(screen)
        presentationCoordinator?.updateScreen(screen)
        activeScreenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        lastMigrationTime = Date()
    }
}
