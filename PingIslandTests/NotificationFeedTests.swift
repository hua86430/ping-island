import XCTest
@testable import Ping_Island

final class NotificationFeedTests: XCTestCase {

    // Build a minimal SessionState. Fill the required init parameters from the
    // real initializer; set only sessionId/cwd/provider-style essentials plus
    // the two dates under test.
    private func makeSession(
        id: String = "s1",
        lastActivity: Date,
        lastSeenAt: Date
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/project",
            lastActivity: lastActivity,
            lastSeenAt: lastSeenAt
        )
    }

    func testHasUnreadTruthTable() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        // activity after seen → unread
        XCTAssertTrue(makeSession(lastActivity: base.addingTimeInterval(10), lastSeenAt: base).hasUnread)
        // seen at same instant as activity → read
        XCTAssertFalse(makeSession(lastActivity: base, lastSeenAt: base).hasUnread)
        // seen after activity → read
        XCTAssertFalse(makeSession(lastActivity: base, lastSeenAt: base.addingTimeInterval(10)).hasUnread)
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
        var session = makeSession(lastActivity: Date(timeIntervalSinceNow: -60), lastSeenAt: Date(timeIntervalSinceNow: -120))
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
        let unreadOld = makeSession(id: "old", lastActivity: base.addingTimeInterval(10), lastSeenAt: base)
        let unreadNew = makeSession(id: "new", lastActivity: base.addingTimeInterval(100), lastSeenAt: base)
        let read = makeSession(id: "read", lastActivity: base, lastSeenAt: base.addingTimeInterval(1))

        let feed = NotificationFeedView.feedSessions(from: [read, unreadOld, unreadNew])
        XCTAssertEqual(feed.map(\.sessionId), ["new", "old"])
    }

    func testFeedIncludesUnreadOlderThanThirtyMinutes() {
        // Unread exempt from the 30-minute idle hide: an unread session whose
        // lastActivity is 45 minutes old must still be in the feed.
        let old = Date(timeIntervalSinceNow: -45 * 60)
        let stale = makeSession(id: "stale", lastActivity: old, lastSeenAt: old.addingTimeInterval(-1))
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
}
