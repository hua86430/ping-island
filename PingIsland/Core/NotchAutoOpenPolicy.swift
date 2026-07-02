import Foundation

/// Pure decision logic for WHEN the docked notch may auto-open, so the
/// feed-mode rules are unit-testable apart from the SwiftUI observers.
enum NotchAutoOpenPolicy {
    /// New pending (needsAttention) sessions appeared. Session mode opens for
    /// any of them (legacy behavior). Feed mode opens only when at least one
    /// actually needs the user to act (question/approval); a bare prompt-ready
    /// session stays silent.
    nonisolated static func shouldAutoOpenForNewPendingSessions(
        newPending: [SessionState],
        feedMode: Bool
    ) -> Bool {
        guard feedMode else { return !newPending.isEmpty }
        return newPending.contains { $0.needsPromptNotification }
    }
}
