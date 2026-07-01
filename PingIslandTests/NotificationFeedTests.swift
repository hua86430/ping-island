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
}
