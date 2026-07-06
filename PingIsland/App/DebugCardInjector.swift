#if DEBUG
import AppKit
import Foundation

// Debug-only card summoner. Notification / intervention cards are gated behind
// real session lifecycles and completion policy (recency, active-session blocker),
// which makes them slow and flaky to reproduce during manual/scripted testing.
// This lets you conjure a completion card or a question card on demand, reusing
// the most-recently-active real session so terminal identifiers (focus / answer
// routing) are genuine.
//
// Trigger it from a terminal:
//     echo completion > /tmp/pingisland-debug-inject
//     echo question   > /tmp/pingisland-debug-inject
//
// Compiled only in DEBUG builds; the release app contains none of this.

extension Notification.Name {
    static let pingIslandDebugInjectCompletion = Notification.Name("pingIslandDebugInjectCompletion")
    static let pingIslandDebugInjectQuestion = Notification.Name("pingIslandDebugInjectQuestion")
}

/// Polls a well-known trigger file and fans a matching notification out to the UI.
/// A file (not the hook socket) so it can be driven from a shell without speaking
/// the bridge's envelope framing.
final class DebugCardInjector {
    static let triggerPath = "/tmp/pingisland-debug-inject"

    private var timer: Timer?

    func start() {
        // Clear any stale trigger from a previous run so we don't fire on launch.
        try? FileManager.default.removeItem(atPath: Self.triggerPath)
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSLog("[PingIsland][debug] DebugCardInjector watching \(Self.triggerPath) — echo completion|question into it")
    }

    private func poll() {
        guard let contents = try? String(contentsOfFile: Self.triggerPath, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: Self.triggerPath)
        let command = contents.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch command {
        case "completion", "complete", "done":
            NotificationCenter.default.post(name: .pingIslandDebugInjectCompletion, object: nil)
        case "question", "select", "ask":
            NotificationCenter.default.post(name: .pingIslandDebugInjectQuestion, object: nil)
        default:
            NSLog("[PingIsland][debug] unknown inject command: \(command) (want completion|question)")
        }
    }
}
#endif
