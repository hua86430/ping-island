import XCTest
@testable import Ping_Island

final class AskUserQuestionExclusionTests: XCTestCase {

    private func descriptor(_ name: String, _ templates: [HookInstallEntryTemplate], timeout: Int? = nil) -> HookInstallEventDescriptor {
        HookInstallEventDescriptor(name: name, templates: templates, timeout: timeout)
    }

    // Pure helper: scope + rewrite behavior
    func testExclusionRewritesClaudePreAndPermissionMatchers() {
        let events = [
            descriptor("PreToolUse", [.matcher("*")]),
            descriptor("PostToolUse", [.matcher("*")]),
            descriptor("PermissionRequest", [.matcher("*")], timeout: 86_400),
            descriptor("Stop", [.plain]),
        ]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: true, profileID: "claude-hooks")
        func matcher(_ name: String) -> String? {
            guard let e = out.first(where: { $0.name == name }), case .matcher(let m) = e.templates.first else { return nil }
            return m
        }
        XCTAssertEqual(matcher("PreToolUse"), HookInstaller.askUserQuestionExclusionMatcher)
        XCTAssertEqual(matcher("PermissionRequest"), HookInstaller.askUserQuestionExclusionMatcher)
        XCTAssertEqual(matcher("PostToolUse"), "*") // untouched
        // Stop stays .plain; PermissionRequest keeps its timeout
        let perm = try? XCTUnwrap(out.first { $0.name == "PermissionRequest" })
        XCTAssertEqual(perm?.timeout, 86_400)
        if let stop = out.first(where: { $0.name == "Stop" }) {
            if case .plain = stop.templates.first {} else { XCTFail("Stop template changed") }
        }
    }

    func testExclusionDisabledLeavesMatchersUntouched() {
        let events = [descriptor("PreToolUse", [.matcher("*")])]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: false, profileID: "claude-hooks")
        if case .matcher(let m) = out[0].templates.first { XCTAssertEqual(m, "*") } else { XCTFail() }
    }

    func testExclusionScopedToClaudeProfileOnly() {
        let events = [descriptor("PreToolUse", [.matcher("*")])]
        let out = HookInstaller.applyingAskUserQuestionTerminalExclusion(to: events, enabled: true, profileID: "codex-hooks")
        if case .matcher(let m) = out[0].templates.first { XCTAssertEqual(m, "*") } else { XCTFail() }
    }

    // Regex behavior
    func testExclusionMatcherRegexExcludesOnlyQuestionTools() throws {
        let re = try NSRegularExpression(pattern: HookInstaller.askUserQuestionExclusionMatcher)
        func matches(_ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        XCTAssertFalse(matches("AskUserQuestion"))
        XCTAssertFalse(matches("AskFollowupQuestion"))
        for t in ["Bash", "Edit", "Read", "Write", "Task"] { XCTAssertTrue(matches(t), t) }
    }

    // Real emitted settings.json via the public install path
    func testTemporarySettingsFileExcludesQuestionToolsWhenEnabled() throws {
        let key = AppSettingsDefaultKeys.terminalHandlesAskUserQuestion
        let had = UserDefaults.standard.object(forKey: key) != nil
        let prev = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { had ? UserDefaults.standard.set(prev, forKey: key) : UserDefaults.standard.removeObject(forKey: key) }

        let url = try XCTUnwrap(HookInstaller.createTemporarySettingsFile(for: "claude-hooks"))
        defer { HookInstaller.removeTemporarySettingsFile(at: url) }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.first?["matcher"] as? String, HookInstaller.askUserQuestionExclusionMatcher)
        let perm = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(perm.first?["matcher"] as? String, HookInstaller.askUserQuestionExclusionMatcher)
        let post = try XCTUnwrap(hooks["PostToolUse"] as? [[String: Any]])
        XCTAssertEqual(post.first?["matcher"] as? String, "*")
    }
}
