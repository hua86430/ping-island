import SwiftUI

struct NotificationFeedView: View {
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    /// Pure feed selection: unread only, newest activity first.
    nonisolated static func feedSessions(from sessions: [SessionState]) -> [SessionState] {
        sessions
            .filter(\.hasUnread)
            .sorted { $0.lastActivity > $1.lastActivity }
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
                        .foregroundColor(.white.opacity(0.55))
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

    private var previewLine: String? {
        // Latest LLM reply, falling back to the prompt preview, then the folder.
        SessionTextSanitizer.sanitizedDisplayText(session.lastMessage)
            ?? SessionTextSanitizer.sanitizedDisplayText(session.previewText)
            ?? session.projectName
    }

    private var timeLabel: String {
        SessionPhaseHelpers.timeBadgeLabel(for: session.lastActivity)
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
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
