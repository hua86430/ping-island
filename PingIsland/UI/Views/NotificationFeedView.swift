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
                        Button {
                            sessionMonitor.markAllSessionsSeen()
                        } label: {
                            Text(appLocalized: "清除全部")
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

    // Scale feed text with the content-font-size setting, mirroring SessionListView
    // so the feed matches the session list / hover preview the slider already drives.
    private var titleFontSize: CGFloat {
        CGFloat(settings.contentFontSize)
    }

    private var previewFontSize: CGFloat {
        max(11, titleFontSize - 2)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(session.displayTitle)
                            .font(.system(size: titleFontSize, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(timeLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let previewLine {
                        Text(previewLine)
                            .font(.system(size: previewFontSize, weight: .medium))
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

// Pointer-cursor-on-hover was removed: the notch panel is a non-activating,
// non-key NSPanel, so on macOS 26 neither NSCursor.set() (ignored while the app
// is inactive) nor cursorUpdate (no longer delivered to a non-key panel) can
// change the system cursor from here. It worked on macOS 15 because cursorUpdate
// still fired for the non-key panel. Making it work would require activating the
// app / making the panel key on hover, which would steal the user's keyboard
// focus — not acceptable for a passive hover. See git history for the prior
// tracking-area attempt.
