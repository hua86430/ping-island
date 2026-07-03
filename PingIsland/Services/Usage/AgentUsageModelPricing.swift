import Foundation

// Per-model official list prices (USD per million tokens).
// Bucketing keys are normalized at WRITE time: keep the version, strip the date suffix.
enum AgentUsageModelPricing {
    private struct Entry {
        let displayName: String
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    // ponytail: Sonnet 5 rate is the pre-2026-09-01 list price; make date-aware if the switch materially skews history
    private nonisolated static let entries: [String: Entry] = [
        "fable-5": Entry(displayName: "Fable 5", inputUSDPerMillion: 10, outputUSDPerMillion: 50),
        "mythos-5": Entry(displayName: "Mythos 5", inputUSDPerMillion: 10, outputUSDPerMillion: 50),
        "opus-4.5": Entry(displayName: "Opus 4.5", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.6": Entry(displayName: "Opus 4.6", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.7": Entry(displayName: "Opus 4.7", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.8": Entry(displayName: "Opus 4.8", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.x": Entry(displayName: "Opus 4.x", inputUSDPerMillion: 5, outputUSDPerMillion: 25),
        "opus-4.0": Entry(displayName: "Opus 4", inputUSDPerMillion: 15, outputUSDPerMillion: 75),
        "opus-4.1": Entry(displayName: "Opus 4.1", inputUSDPerMillion: 15, outputUSDPerMillion: 75),
        "sonnet-5": Entry(displayName: "Sonnet 5", inputUSDPerMillion: 2, outputUSDPerMillion: 10),
        "sonnet-4.5": Entry(displayName: "Sonnet 4.5", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "sonnet-4.6": Entry(displayName: "Sonnet 4.6", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "sonnet": Entry(displayName: "Sonnet", inputUSDPerMillion: 3, outputUSDPerMillion: 15),
        "haiku-4.5": Entry(displayName: "Haiku 4.5", inputUSDPerMillion: 1, outputUSDPerMillion: 5),
        "gpt-5.5": Entry(displayName: "GPT-5.5", inputUSDPerMillion: 5, outputUSDPerMillion: 30),
        "gpt-5.5-pro": Entry(displayName: "GPT-5.5 pro", inputUSDPerMillion: 30, outputUSDPerMillion: 180),
        "gpt-5.4-pro": Entry(displayName: "GPT-5.4 pro", inputUSDPerMillion: 30, outputUSDPerMillion: 180),
        "gpt-5.4": Entry(displayName: "GPT-5.4", inputUSDPerMillion: 2.5, outputUSDPerMillion: 15),
        "gpt-5.4-mini": Entry(displayName: "GPT-5.4 mini", inputUSDPerMillion: 0.75, outputUSDPerMillion: 4.5),
        "gpt-5.4-nano": Entry(displayName: "GPT-5.4 nano", inputUSDPerMillion: 0.2, outputUSDPerMillion: 1.25),
    ]

    nonisolated static func normalizedKey(forModel rawModel: String?) -> String {
        guard let raw = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return "unknown"
        }
        // Idempotence: already-normalized keys (registry keys, unknown, unknown:<raw>)
        // pass straight through, so pricing/displayName accept keys as well as raw ids.
        if raw == "unknown" || raw.hasPrefix("unknown:") || entries[raw] != nil {
            return raw
        }
        if raw.contains("fable") { return "fable-5" }
        if raw.contains("mythos") { return "mythos-5" }
        if raw.hasPrefix("claude-opus") { return opusKey(raw) }
        if raw.hasPrefix("claude-sonnet") { return sonnetKey(raw) }
        if raw.hasPrefix("claude-haiku") { return "haiku-4.5" }
        if raw.hasPrefix("gpt") { return gptKey(raw) }
        return "unknown:\(raw)"
    }

    nonisolated static func pricing(forModel rawModel: String?) -> AgentUsageTokenPricing {
        let key = normalizedKey(forModel: rawModel)
        guard let entry = entries[key] else {
            return AgentUsageCostEstimator.blendedCodexClaudePricing
        }
        return AgentUsageTokenPricing(
            inputUSDPerMillion: entry.inputUSDPerMillion,
            outputUSDPerMillion: entry.outputUSDPerMillion,
            label: entry.displayName
        )
    }

    // Deterministic pure function of the normalized key, never of the first-seen raw id.
    // For "unknown" this returns the Simplified localization key; render via Text(appLocalized:).
    nonisolated static func displayName(forModel rawModel: String?) -> String {
        let key = normalizedKey(forModel: rawModel)
        if let entry = entries[key] { return entry.displayName }
        if key == "unknown" { return "未知模型" }
        if key.hasPrefix("unknown:") { return String(key.dropFirst("unknown:".count)) }
        return key
    }

    nonisolated static func estimateUSD(perModel totalsByModel: [String: AgentUsageTokenTotals]) -> Double {
        totalsByModel.reduce(0) { partial, element in
            partial + pricing(forModel: element.key).estimateUSD(for: element.value)
        }
    }

    private nonisolated static func opusKey(_ raw: String) -> String {
        // claude-opus-4-8 / claude-opus-4-8-20260101 / claude-opus-4-1-20250805 / claude-opus-4-20250514
        let segments = raw.split(separator: "-").map(String.init)
        guard let fourIndex = segments.firstIndex(of: "4"), fourIndex + 1 < segments.count,
              let minor = Int(segments[fourIndex + 1]) else {
            return "opus-4.x"
        }
        if minor >= 1000 { return "opus-4.0" } // date suffix straight after "4" means plain Opus 4
        if (5...8).contains(minor) { return "opus-4.\(minor)" }
        if minor == 0 || minor == 1 { return "opus-4.\(minor)" }
        return "opus-4.x"
    }

    private nonisolated static func sonnetKey(_ raw: String) -> String {
        if raw.hasPrefix("claude-sonnet-5") { return "sonnet-5" }
        if raw.hasPrefix("claude-sonnet-4-5") { return "sonnet-4.5" }
        if raw.hasPrefix("claude-sonnet-4-6") { return "sonnet-4.6" }
        return "sonnet"
    }

    private nonisolated static func gptKey(_ raw: String) -> String {
        // Symmetric: -pro / -mini / -nano are only recognized for the listed 5.4 / 5.5
        // versions. Any other gpt variant (unlisted version, unreleased tier) → blend.
        if raw.hasPrefix("gpt-5.5") {
            if raw.contains("-pro") { return "gpt-5.5-pro" }
            if raw.contains("-mini") || raw.contains("-nano") { return "unknown:\(raw)" } // 5.5 mini/nano not listed
            return "gpt-5.5"
        }
        if raw.hasPrefix("gpt-5.4") {
            if raw.contains("-pro") { return "gpt-5.4-pro" }
            if raw.contains("-mini") { return "gpt-5.4-mini" }
            if raw.contains("-nano") { return "gpt-5.4-nano" }
            return "gpt-5.4"
        }
        return "unknown:\(raw)"
    }
}
