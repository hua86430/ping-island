import XCTest
@testable import Ping_Island

final class NotificationFeedTests: XCTestCase {

    // Build a minimal SessionState. Fill the required init parameters from the
    // real initializer; set only sessionId/cwd/provider-style essentials plus
    // the two dates under test.
    private func makeSession(
        id: String = "s1",
        lastActivity: Date,
        lastSeenAt: Date,
        lastNotifiableActivityAt: Date? = nil,
        phase: SessionPhase = .idle,
        intervention: SessionIntervention? = nil
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/project",
            intervention: intervention,
            phase: phase,
            lastActivity: lastActivity,
            lastSeenAt: lastSeenAt,
            lastNotifiableActivityAt: lastNotifiableActivityAt
        )
    }

    private func questionIntervention() -> SessionIntervention {
        SessionIntervention(
            id: "q-1",
            kind: .question,
            title: "q",
            message: "q",
            options: [],
            questions: [],
            supportsSessionScope: false,
            metadata: [:]
        )
    }

    func testHasUnreadTruthTable() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        // assistant reply after seen → unread
        XCTAssertTrue(makeSession(
            lastActivity: base.addingTimeInterval(10),
            lastSeenAt: base,
            lastNotifiableActivityAt: base.addingTimeInterval(10)
        ).hasUnread)
        // USER-only activity (session start / typing / tool churn bumps
        // lastActivity but never lastNotifiableActivityAt) → NOT unread
        XCTAssertFalse(makeSession(
            lastActivity: base.addingTimeInterval(10),
            lastSeenAt: base
        ).hasUnread)
        // assistant replied, then user saw it → read
        XCTAssertFalse(makeSession(
            lastActivity: base,
            lastSeenAt: base.addingTimeInterval(10),
            lastNotifiableActivityAt: base
        ).hasUnread)
    }

    func testDefaultLastSeenAtMakesFreshSessionRead() {
        // A session created "now" with lastActivity defaulting to now must not
        // be unread at creation (feed starts empty on launch).
        // Construct with the init's DEFAULTS for both dates (pass neither).
        let session = SessionState(sessionId: "fresh-session", cwd: "/tmp/project")
        XCTAssertFalse(session.hasUnread)
    }

    func testMarkSessionSeenClearsUnread() async {
        // Drive through the real store: insert a session whose lastActivity is
        // newer than lastSeenAt (unread), call markSessionSeen, read it back,
        // assert hasUnread == false. Use SessionStore.shared only if the store
        // exposes a test seam; otherwise test the mutation semantics at the
        // SessionState level: verify that setting lastSeenAt = Date() on a
        // session whose lastActivity is in the past flips hasUnread to false.
        var session = makeSession(
            lastActivity: Date(timeIntervalSinceNow: -60),
            lastSeenAt: Date(timeIntervalSinceNow: -120),
            lastNotifiableActivityAt: Date(timeIntervalSinceNow: -60)
        )
        XCTAssertTrue(session.hasUnread)
        session.lastSeenAt = Date()
        XCTAssertFalse(session.hasUnread)
    }

    @MainActor
    func testNotificationFeedModeDefaultsToFalseAndPersists() {
        let key = AppSettingsDefaultKeys.notificationFeedMode
        let suiteName = "test-\(key)-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: suite, bridgeRuntimeConfigWriter: { _ in })

        XCTAssertFalse(store.notificationFeedMode)
        store.notificationFeedMode = true
        XCTAssertTrue(suite.bool(forKey: key))
        store.notificationFeedMode = false
        XCTAssertFalse(suite.bool(forKey: key))
    }

    func testFeedSessionsOnlyUnreadNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let unreadOld = makeSession(id: "old", lastActivity: base.addingTimeInterval(10), lastSeenAt: base, lastNotifiableActivityAt: base.addingTimeInterval(10))
        let unreadNew = makeSession(id: "new", lastActivity: base.addingTimeInterval(100), lastSeenAt: base, lastNotifiableActivityAt: base.addingTimeInterval(100))
        let read = makeSession(id: "read", lastActivity: base, lastSeenAt: base.addingTimeInterval(1))

        let feed = NotificationFeedView.feedSessions(from: [read, unreadOld, unreadNew])
        XCTAssertEqual(feed.map(\.sessionId), ["new", "old"])
    }

    func testFeedIncludesUnreadOlderThanThirtyMinutes() {
        // Unread exempt from the 30-minute idle hide: an unread session whose
        // lastActivity is 45 minutes old must still be in the feed.
        let old = Date(timeIntervalSinceNow: -45 * 60)
        let stale = makeSession(id: "stale", lastActivity: old, lastSeenAt: old.addingTimeInterval(-1), lastNotifiableActivityAt: old)
        XCTAssertEqual(NotificationFeedView.feedSessions(from: [stale]).map(\.sessionId), ["stale"])
    }

    func testIdleExemptionOnlyForIdleHiddenSessions() {
        // Unread + idle (45 min old activity) → hidden only by the idle rule,
        // so the feed-mode exemption applies.
        let old = Date(timeIntervalSinceNow: -45 * 60)
        let idle = makeSession(id: "idle", lastActivity: old, lastSeenAt: old.addingTimeInterval(-1))
        XCTAssertTrue(idle.shouldHideFromPrimaryUI)
        XCTAssertTrue(idle.isHiddenFromPrimaryUIOnlyByIdle)

        // Fresh activity → not hidden at all, exemption not applicable.
        let fresh = makeSession(id: "fresh", lastActivity: Date(), lastSeenAt: Date(timeIntervalSinceNow: -60))
        XCTAssertFalse(fresh.shouldHideFromPrimaryUI)
        XCTAssertFalse(fresh.isHiddenFromPrimaryUIOnlyByIdle)
    }

    func testAutoOpenPolicyForNewPendingSessions() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let bareReady = makeSession(id: "ready", lastActivity: base, lastSeenAt: base, phase: .waitingForInput)
        let question = makeSession(id: "q", lastActivity: base, lastSeenAt: base, phase: .waitingForInput, intervention: questionIntervention())

        // Session mode: any new pending opens (today's behavior).
        XCTAssertTrue(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady], feedMode: false))
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [], feedMode: false))

        // Feed mode: bare prompt-ready must NOT open; actionable attention must.
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady], feedMode: true))
        XCTAssertTrue(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [bareReady, question], feedMode: true))
        XCTAssertFalse(NotchAutoOpenPolicy.shouldAutoOpenForNewPendingSessions(newPending: [], feedMode: true))
    }
}
