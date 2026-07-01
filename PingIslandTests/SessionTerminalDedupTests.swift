import XCTest
@testable import Ping_Island

final class SessionTerminalDedupTests: XCTestCase {

    private func makeSession(
        sessionId: String = "s1",
        cwd: String = "/tmp/project",
        tty: String? = nil,
        clientInfo: SessionClientInfo? = nil,
        lastActivity: Date = Date()
    ) -> SessionState {
        SessionState(
            sessionId: sessionId,
            cwd: cwd,
            provider: .claude,
            clientInfo: clientInfo,
            tty: tty,
            lastActivity: lastActivity
        )
    }

    // MARK: - terminalDedupIdentity

    func testIdentityPrefersTmuxPaneOverEverything() {
        let info = SessionClientInfo(
            kind: .claudeCode,
            profileID: "claude_code",
            name: "Claude Code",
            terminalSessionIdentifier: "term-1",
            iTermSessionIdentifier: "iterm-1",
            tmuxPaneIdentifier: "%3"
        )
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: info).terminalDedupIdentity, "pane:%3")
    }

    func testIdentityFallsBackThroughPriority() {
        let iterm = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", iTermSessionIdentifier: "ITERM-1")
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: iterm).terminalDedupIdentity, "iterm:iterm-1")

        let term = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", terminalSessionIdentifier: "Term-2")
        XCTAssertEqual(makeSession(tty: "ttys001", clientInfo: term).terminalDedupIdentity, "term:term-2")
    }

    func testIdentityTtyFallbackAndLowercasing() {
        XCTAssertEqual(makeSession(tty: "TTYS004").terminalDedupIdentity, "tty:ttys004")
    }

    func testIdentityTtyFallbackPrefixesRemoteHost() {
        let info = SessionClientInfo(kind: .claudeCode, profileID: "claude_code", name: "Claude Code", remoteHost: "BuildBox")
        XCTAssertEqual(makeSession(tty: "ttys004", clientInfo: info).terminalDedupIdentity, "tty:buildbox:ttys004")
    }

    func testIdentityIsNilWhenNoTerminalInfo() {
        XCTAssertNil(makeSession(tty: nil).terminalDedupIdentity)
        XCTAssertNil(makeSession(tty: "   ").terminalDedupIdentity)
    }

    // MARK: - deduplicateSameProjectClaudeSessions

    func testDifferentTerminalsSameCwdStaySeparate() {
        let a = makeSession(sessionId: "a", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 100))
        let b = makeSession(sessionId: "b", tty: "ttys002", lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [a, b])
        XCTAssertEqual(Set(result.map(\.sessionId)), ["a", "b"])
    }

    func testSameTerminalSameCwdCollapsesToMostRecent() {
        let old = makeSession(sessionId: "old", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 100))
        let new = makeSession(sessionId: "new", tty: "ttys001", lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [old, new])
        XCTAssertEqual(result.map(\.sessionId), ["new"])
    }

    func testNoTerminalIdentitySessionsStaySeparate() {
        let a = makeSession(sessionId: "a", tty: nil, lastActivity: Date(timeIntervalSince1970: 100))
        let b = makeSession(sessionId: "b", tty: nil, lastActivity: Date(timeIntervalSince1970: 200))
        let result = SessionMonitor.deduplicateSameProjectClaudeSessions(from: [a, b])
        XCTAssertEqual(Set(result.map(\.sessionId)), ["a", "b"])
    }
}
