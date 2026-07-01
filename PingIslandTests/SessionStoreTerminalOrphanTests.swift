import Foundation
import XCTest
@testable import Ping_Island

/// Verifies endOrphanedSessions only removes a relaunch orphan from the SAME
/// terminal surface, so two concurrent Claude sessions in the same cwd but
/// different terminals both survive.
final class SessionStoreTerminalOrphanTests: XCTestCase {

    func testDifferentTerminalSameCwdSessionsBothSurvive() async {
        let cwd = "/tmp/ttydedup-\(UUID().uuidString)"
        let idA = "orphanA-\(UUID().uuidString)"
        let idB = "orphanB-\(UUID().uuidString)"
        let store = SessionStore.shared

        // Session A in terminal ttys101, no live pid so the pid guard cannot
        // save it — only the terminal-identity guard should.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idA, cwd: cwd, tty: "ttys101")))
        let aAfterCreate = await store.session(for: idA)
        XCTAssertNotNil(aAfterCreate)

        // Session B arrives in a DIFFERENT terminal (ttys102), same cwd. This
        // triggers endOrphanedSessions against A.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idB, cwd: cwd, tty: "ttys102")))

        let aAfterB = await store.session(for: idA)
        let bAfterB = await store.session(for: idB)
        XCTAssertNotNil(aAfterB,
                        "Different-terminal session must NOT be removed as an orphan")
        XCTAssertNotNil(bAfterB)

        await store.process(.sessionArchived(sessionId: idA))
        await store.process(.sessionArchived(sessionId: idB))
    }

    func testSameTerminalRelaunchOrphanIsRemoved() async {
        let cwd = "/tmp/ttydedup-\(UUID().uuidString)"
        let idOld = "relaunchOld-\(UUID().uuidString)"
        let idNew = "relaunchNew-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(makeClaudeEvent(sessionId: idOld, cwd: cwd, tty: "ttys201")))
        let oldAfterCreate = await store.session(for: idOld)
        XCTAssertNotNil(oldAfterCreate)

        // Relaunch in the SAME terminal (ttys201): old session is an orphan.
        await store.process(.hookReceived(makeClaudeEvent(sessionId: idNew, cwd: cwd, tty: "ttys201")))

        let oldAfterRelaunch = await store.session(for: idOld)
        let newAfterRelaunch = await store.session(for: idNew)
        XCTAssertNil(oldAfterRelaunch,
                     "Same-terminal relaunch orphan must be removed")
        XCTAssertNotNil(newAfterRelaunch)

        await store.process(.sessionArchived(sessionId: idNew))
    }

    // MARK: - Helpers

    private func makeClaudeEvent(
        sessionId: String,
        cwd: String,
        tty: String
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: "UserPromptSubmit",
            status: "processing",
            provider: .claude,
            clientInfo: SessionClientInfo(
                kind: .claudeCode,
                profileID: "claude_code",
                name: "Claude Code",
                bundleIdentifier: "com.anthropic.claudecode"
            ),
            pid: nil,
            tty: tty,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        )
    }
}
