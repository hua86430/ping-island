import SwiftUI
import AppKit

struct NotificationFeedView: View {
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    var onHoverChanged: (Bool) -> Void = { _ in }

    @State private var clearAllHovered = false

    /// Pure feed selection: unread only, newest activity first.
    nonisolated static func feedSessions(from sessions: [SessionState]) -> [SessionState] {
        sessions
            .filter(\.hasUnread)
            .sorted {
                ($0.lastNotifiableActivityAt ?? $0.lastActivity)
                    > ($1.lastNotifiableActivityAt ?? $1.lastActivity)
            }
    }

    private var feed: [SessionState] {
        Self.feedSessions(from: sessionMonitor.instances)
    }

    var body: some View {
        // Mirror SessionHoverDashboardView: the whole content lives inside the
        // ScrollView and reports its height via the opened-panel preference so
        // the panel grows with the row count instead of clipping the feed.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(appLocalized: "新通知")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    if !feed.isEmpty {
                        Button(AppLocalization.string("清除全部")) {
                            sessionMonitor.markAllSessionsSeen()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(clearAllHovered ? 0.9 : 0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(clearAllHovered ? 0.12 : 0.0))
                        )
                        .contentShape(Capsule())
                        .pointerCursor()
                        .onHover { hovering in
                            clearAllHovered = hovering
                        }
                        .animation(.easeOut(duration: 0.12), value: clearAllHovered)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if feed.isEmpty {
                    Text(appLocalized: "没有新通知")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(feed) { session in
                            NotificationFeedRow(session: session) {
                                open(session)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: OpenedPanelContentHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .onHover(perform: onHoverChanged)
    }

    private func open(_ session: SessionState) {
        viewModel.notchClose()
        sessionMonitor.markSessionSeen(sessionId: session.sessionId)
        Task {
            _ = await SessionLauncher.shared.activate(session)
        }
    }
}

/// Lightweight session-list row look: mascot, name, folder, preview, relative time.
/// Not `InstanceRow` — no selection/hover/action-cluster state applies to a feed row.
private struct NotificationFeedRow: View {
    let session: SessionState
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovered = false

    private var previewLine: String? {
        // Latest LLM reply, falling back to the prompt preview, then the folder.
        SessionTextSanitizer.sanitizedDisplayText(session.lastMessage)
            ?? SessionTextSanitizer.sanitizedDisplayText(session.previewText)
            ?? session.projectName
    }

    private var timeLabel: String {
        SessionPhaseHelpers.timeBadgeLabel(for: session.lastNotifiableActivityAt ?? session.lastActivity)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(timeLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let previewLine {
                        Text(previewLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovered ? 0.16 : 0.08), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .pointerCursor()
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))

            MascotView(
                kind: settings.mascotKind(for: session.mascotClient),
                status: MascotStatus(session: session),
                size: 18,
                animationTime: 0
            )
            .padding(6)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Pointer cursor inside the notch panel

extension View {
    /// Shows the pointing-hand cursor while hovering, working inside the notch
    /// panel where `.onHover` + `NSCursor.push()` does not: `NotchPanel` is a
    /// borderless non-activating `NSPanel`, and feed banners open it with the
    /// window left non-key / the app non-active (see NotchWindowController's
    /// `openReason != .notification` guard). A pushed cursor gets reset by the
    /// window's cursor-rect management on the next mouse move. An AppKit
    /// tracking area with `.cursorUpdate` + `.activeAlways` sets the cursor on
    /// the cursorUpdate event instead, which survives redraws and does not
    /// depend on the panel being active.
    func pointerCursor() -> some View {
        overlay(PointerCursorArea().allowsHitTesting(false))
    }
}

private struct PointerCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PointerCursorNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class PointerCursorNSView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    // cursorUpdate can be skipped if the panel isn't active; set on enter too.
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
