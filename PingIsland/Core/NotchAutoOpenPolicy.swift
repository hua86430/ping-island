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

    /// A `.notification`-opened panel is sitting on the FEED route (not an
    /// attention card, not the completion card, not chat). Such a panel is a
    /// transient banner: it must self-dismiss after the banner interval.
    nonisolated static func shouldArmFeedBannerDismissal(
        feedMode: Bool,
        isOpened: Bool,
        openedByNotification: Bool,
        hasAttentionSession: Bool,
        hasActiveCompletionCard: Bool,
        isChatContent: Bool,
        unreadCount: Int
    ) -> Bool {
        feedMode
            && isOpened
            && openedByNotification
            && !hasAttentionSession
            && !hasActiveCompletionCard
            && !isChatContent
            && unreadCount > 0
    }
}
