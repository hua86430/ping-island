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
