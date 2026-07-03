import Foundation

enum AgentUsageRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    nonisolated var dayCount: Int {
        switch self {
        case .today:
            return 1
        case .sevenDays:
            return 7
        case .thirtyDays:
            return 30
        }
    }

    nonisolated var title: String {
        switch self {
        case .today:
            return "今日"
        case .sevenDays:
            return "7 天"
        case .thirtyDays:
            return "30 天"
        }
    }
}

struct AgentUsageTokenTotals: Codable, Equatable, Sendable {
    var input: Int
    var cacheCreation: Int
    var cacheRead: Int
    var output: Int

    nonisolated init(input: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = max(0, input)
        self.cacheCreation = max(0, cacheCreation)
        self.cacheRead = max(0, cacheRead)
        self.output = max(0, output)
    }

    private enum CodingKeys: String, CodingKey {
        case input, cacheCreation, cacheRead, output
    }

    // Custom decode tolerates the legacy {input, output, total} shape (unknown keys
    // like `total` are ignored; missing cache fields default to 0) so old persisted
    // data decodes without crashing before the store's schema reset wipes it.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = max(0, try container.decodeIfPresent(Int.self, forKey: .input) ?? 0)
        cacheCreation = max(0, try container.decodeIfPresent(Int.self, forKey: .cacheCreation) ?? 0)
        cacheRead = max(0, try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0)
        output = max(0, try container.decodeIfPresent(Int.self, forKey: .output) ?? 0)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(input, forKey: .input)
        try container.encode(cacheCreation, forKey: .cacheCreation)
        try container.encode(cacheRead, forKey: .cacheRead)
        try container.encode(output, forKey: .output)
    }

    nonisolated mutating func add(_ other: AgentUsageTokenTotals) {
        input += max(0, other.input)
        cacheCreation += max(0, other.cacheCreation)
        cacheRead += max(0, other.cacheRead)
        output += max(0, other.output)
    }

    // Consumption total. EXCLUDES cache reads: cache_read_input_tokens is the same
    // cached context re-read every turn, so summing it inflates the figure into the
    // billions and misrepresents actual usage.
    nonisolated var resolvedTotal: Int {
        input + cacheCreation + output
    }

    // Input-side consumption for display: fresh input + cache writes, excluding cache
    // re-reads. So the shown 輸入 + 輸出 adds up to the 消耗 (resolvedTotal).
    nonisolated var displayInput: Int {
        input + cacheCreation
    }

    nonisolated var hasTokens: Bool {
        input > 0 || cacheCreation > 0 || cacheRead > 0 || output > 0
    }
}

struct AgentUsageTokenSourceBaseline: Codable, Equatable, Sendable {
    var totalsByModel: [String: AgentUsageTokenTotals]
    var fileSize: UInt64?
    var contentHash: String?

    nonisolated init(
        totalsByModel: [String: AgentUsageTokenTotals],
        fileSize: UInt64? = nil,
        contentHash: String? = nil
    ) {
        self.totalsByModel = totalsByModel
        self.fileSize = fileSize
        self.contentHash = contentHash
    }

    private enum CodingKeys: String, CodingKey {
        case totalsByModel, fileSize, contentHash
    }

    // Legacy shape stored a single aggregate `totals`: decode it as an EMPTY map so the
    // next scan takes the first-sight branch and re-seeds per model without dumping
    // history (Claude/Codex callers use recordInitialSnapshot:false). No schemaVersion
    // bump, no data wipe. Downgrade note: an older app decoding the new shape fails on
    // the missing non-optional `totals` and loads an empty document; downgrades are
    // not a supported scenario.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalsByModel = try container.decodeIfPresent([String: AgentUsageTokenTotals].self, forKey: .totalsByModel) ?? [:]
        fileSize = try container.decodeIfPresent(UInt64.self, forKey: .fileSize)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
    }
}

struct AgentUsageRankItem: Equatable, Identifiable, Sendable {
    let name: String
    let count: Int
    let share: Double

    nonisolated var id: String { name }
}

struct AgentUsageHeatmapDay: Equatable, Identifiable, Sendable {
    let date: Date
    let activityCount: Int

    nonisolated var id: Date { date }
}

struct AgentUsageTrendPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let tokenTotal: Int
    let agentCount: Int
    let toolUseCount: Int
    let sessionCount: Int

    nonisolated var id: Date { date }
}

struct AgentUsageCostMetric: Equatable, Identifiable, Sendable {
    let range: AgentUsageRange
    let tokenTotals: AgentUsageTokenTotals
    let estimatedUSD: Double

    nonisolated var id: AgentUsageRange { range }
}

struct AgentUsageDailySpendPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let tokenTotals: AgentUsageTokenTotals
    let estimatedUSD: Double

    nonisolated var id: Date { date }
    nonisolated var tokenTotal: Int { tokenTotals.resolvedTotal }
}

struct AgentUsageModelBreakdownItem: Identifiable, Equatable, Sendable {
    let modelKey: String       // 正規化後用於配色的穩定鍵
    let displayName: String
    let tokenTotals: AgentUsageTokenTotals
    let estimatedUSD: Double
    nonisolated var id: String { modelKey }
    nonisolated var tokenTotal: Int { tokenTotals.resolvedTotal }
}

struct AgentUsageModelDailySpend: Identifiable, Equatable, Sendable {
    let modelKey: String
    let displayName: String
    let points: [AgentUsageDailySpendPoint]   // 對齊 spendDayCount(30) 天，缺日補 0
    nonisolated var id: String { modelKey }
    nonisolated var totalUSD: Double { points.reduce(0) { $0 + $1.estimatedUSD } }   // computed，非 stored（fable5 6b）
}

struct AgentUsageSpendSummary: Equatable, Sendable {
    let today: AgentUsageCostMetric
    let sevenDays: AgentUsageCostMetric
    let thirtyDays: AgentUsageCostMetric
    let dailyPoints: [AgentUsageDailySpendPoint]

    nonisolated var metrics: [AgentUsageCostMetric] {
        [today, sevenDays, thirtyDays]
    }
}

struct AgentUsageDiagnosticsRangeSummary: Equatable, Sendable {
    let range: String
    let sessionCount: Int
    let toolUseCount: Int
    let tokenTotals: AgentUsageTokenTotals
}

struct AgentUsageDiagnosticsDailyBucket: Equatable, Sendable {
    let day: String
    let agentCount: Int
    let sessionCount: Int
    let toolUseCount: Int
    let tokenTotals: AgentUsageTokenTotals
    let activityCount: Int
}

struct AgentUsageDiagnosticsSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let tokenSourceCount: Int
    let ranges: [AgentUsageDiagnosticsRangeSummary]
    let recentBuckets: [AgentUsageDiagnosticsDailyBucket]
}

struct AgentUsageTokenPricing: Equatable, Sendable {
    let inputUSDPerMillion: Double
    let outputUSDPerMillion: Double
    let label: String
    // Cache tokens are billed relative to the input rate: writes ~1.25x, reads ~0.1x.
    let cacheCreationMultiplier: Double = 1.25
    let cacheReadMultiplier: Double = 0.1

    nonisolated func estimateUSD(for totals: AgentUsageTokenTotals) -> Double {
        func cost(_ tokens: Int, _ rate: Double) -> Double {
            Double(tokens) / 1_000_000 * rate
        }
        return cost(totals.input, inputUSDPerMillion)
            + cost(totals.cacheCreation, inputUSDPerMillion * cacheCreationMultiplier)
            + cost(totals.cacheRead, inputUSDPerMillion * cacheReadMultiplier)
            + cost(totals.output, outputUSDPerMillion)
    }
}

enum AgentUsageCostEstimator {
    nonisolated static let blendedCodexClaudePricing = AgentUsageTokenPricing(
        inputUSDPerMillion: 2.375,
        outputUSDPerMillion: 14.50,
        label: "Codex / Claude Code 均价"
    )

    nonisolated static func estimateUSD(
        for totals: AgentUsageTokenTotals,
        pricing: AgentUsageTokenPricing = blendedCodexClaudePricing
    ) -> Double {
        pricing.estimateUSD(for: totals)
    }
}

struct AgentUsageDashboardSnapshot: Equatable, Sendable {
    private nonisolated static let heatmapDayCount = 180
    private nonisolated static let trendDayCount = 7
    private nonisolated static let spendDayCount = 30

    let range: AgentUsageRange
    let sessionCount: Int
    let toolUseCount: Int
    let tokenTotals: AgentUsageTokenTotals
    let topAgents: [AgentUsageRankItem]
    let topTools: [AgentUsageRankItem]
    let heatmapDays: [AgentUsageHeatmapDay]
    let trendPoints: [AgentUsageTrendPoint]
    let spendSummary: AgentUsageSpendSummary
    let perModelBreakdown: [AgentUsageModelBreakdownItem]     // 依 estimatedUSD 降序，範圍隨 selectedRange
    let perModelDailySpend: [AgentUsageModelDailySpend]       // 30 天，逐 model 一條線，依 totalUSD 降序

    nonisolated static func empty(range: AgentUsageRange, now: Date = Date(), calendar: Calendar = .current) -> AgentUsageDashboardSnapshot {
        AgentUsageDashboardSnapshot(
            range: range,
            sessionCount: 0,
            toolUseCount: 0,
            tokenTotals: AgentUsageTokenTotals(),
            topAgents: [],
            topTools: [],
            heatmapDays: recentHeatmapDays(now: now, buckets: [:], calendar: calendar),
            trendPoints: trendPoints(now: now, buckets: [:], calendar: calendar),
            spendSummary: Self.spendSummary(now: now, buckets: [:], calendar: calendar),
            perModelBreakdown: [],
            perModelDailySpend: []
        )
    }

    nonisolated var hasActivity: Bool {
        sessionCount > 0 || toolUseCount > 0 || tokenTotals.resolvedTotal > 0
    }

    fileprivate nonisolated static func recentHeatmapDays(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> [AgentUsageHeatmapDay] {
        let today = calendar.startOfDay(for: now)

        return (0..<heatmapDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let key = AgentUsageStore.dayKey(for: date, calendar: calendar)
            return AgentUsageHeatmapDay(date: date, activityCount: buckets[key]?.activityCount ?? 0)
        }
    }

    fileprivate nonisolated static func trendPoints(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> [AgentUsageTrendPoint] {
        let today = calendar.startOfDay(for: now)

        return (0..<trendDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let key = AgentUsageStore.dayKey(for: date, calendar: calendar)
            let bucket = buckets[key]
            let sessionCount = bucket?.sessionIDsByAgent.values.reduce(0) { $0 + $1.count } ?? 0
            return AgentUsageTrendPoint(
                date: date,
                tokenTotal: bucket?.tokenTotals.resolvedTotal ?? 0,
                agentCount: bucket?.sessionIDsByAgent.count ?? 0,
                toolUseCount: bucket?.toolCounts.values.reduce(0, +) ?? 0,
                sessionCount: sessionCount
            )
        }
    }

    fileprivate nonisolated static func spendSummary(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> AgentUsageSpendSummary {
        AgentUsageSpendSummary(
            today: costMetric(range: .today, now: now, buckets: buckets, calendar: calendar),
            sevenDays: costMetric(range: .sevenDays, now: now, buckets: buckets, calendar: calendar),
            thirtyDays: costMetric(range: .thirtyDays, now: now, buckets: buckets, calendar: calendar),
            dailyPoints: dailySpendPoints(now: now, buckets: buckets, calendar: calendar)
        )
    }

    // Per-bucket cost: official per-model rates for the mapped share, blended rate for
    // the residual. Post-upgrade buckets: residual == 0 (invariant). Legacy buckets:
    // empty map, whole aggregate stays blended. Mixed upgrade-day buckets: the
    // pre-upgrade share stays blended so it does not vanish (fable5 6a).
    fileprivate nonisolated static func bucketCost(_ bucket: AgentUsageDailyBucket) -> Double {
        var perModelSum = AgentUsageTokenTotals()
        for totals in bucket.tokenTotalsByModel.values {
            perModelSum.add(totals)
        }
        let residual = AgentUsageTokenTotals(
            input: max(0, bucket.tokenTotals.input - perModelSum.input),
            cacheCreation: max(0, bucket.tokenTotals.cacheCreation - perModelSum.cacheCreation),
            cacheRead: max(0, bucket.tokenTotals.cacheRead - perModelSum.cacheRead),
            output: max(0, bucket.tokenTotals.output - perModelSum.output)
        )
        return AgentUsageModelPricing.estimateUSD(perModel: bucket.tokenTotalsByModel)
            + AgentUsageCostEstimator.estimateUSD(for: residual)
    }

    private nonisolated static func costMetric(
        range: AgentUsageRange,
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> AgentUsageCostMetric {
        let today = calendar.startOfDay(for: now)
        var totals = AgentUsageTokenTotals()
        var estimatedUSD: Double = 0

        for offset in 0..<range.dayCount {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }
            let key = AgentUsageStore.dayKey(for: date, calendar: calendar)
            guard let bucket = buckets[key] else { continue }
            totals.add(bucket.tokenTotals)
            estimatedUSD += bucketCost(bucket)
        }

        return AgentUsageCostMetric(range: range, tokenTotals: totals, estimatedUSD: estimatedUSD)
    }

    private nonisolated static func dailySpendPoints(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> [AgentUsageDailySpendPoint] {
        let today = calendar.startOfDay(for: now)

        return (0..<spendDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let key = AgentUsageStore.dayKey(for: date, calendar: calendar)
            let totals = buckets[key]?.tokenTotals ?? AgentUsageTokenTotals()
            return AgentUsageDailySpendPoint(
                date: date,
                tokenTotals: totals,
                estimatedUSD: buckets[key].map(Self.bucketCost) ?? 0
            )
        }
    }

    fileprivate nonisolated static func perModelDailySpend(
        now: Date,
        buckets: [String: AgentUsageDailyBucket],
        calendar: Calendar
    ) -> [AgentUsageModelDailySpend] {
        let today = calendar.startOfDay(for: now)
        let dayEntries: [(date: Date, bucket: AgentUsageDailyBucket?)] = (0..<spendDayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return (date, buckets[AgentUsageStore.dayKey(for: date, calendar: calendar)])
        }

        var modelKeys: Set<String> = []
        for entry in dayEntries {
            if let bucket = entry.bucket {
                modelKeys.formUnion(bucket.tokenTotalsByModel.keys)
            }
        }

        return modelKeys
            .map { key in
                let points = dayEntries.map { entry -> AgentUsageDailySpendPoint in
                    let totals = entry.bucket?.tokenTotalsByModel[key] ?? AgentUsageTokenTotals()
                    return AgentUsageDailySpendPoint(
                        date: entry.date,
                        tokenTotals: totals,
                        estimatedUSD: AgentUsageModelPricing.pricing(forModel: key).estimateUSD(for: totals)
                    )
                }
                return AgentUsageModelDailySpend(
                    modelKey: key,
                    displayName: AgentUsageModelPricing.displayName(forModel: key),
                    points: points
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalUSD == rhs.totalUSD { return lhs.modelKey < rhs.modelKey }
                return lhs.totalUSD > rhs.totalUSD
            }
    }
}

struct CodexTokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    nonisolated init(inputTokens: Int, cachedInputTokens: Int = 0, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens, cachedInputTokens, outputTokens, totalTokens
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
    }

    nonisolated var totals: AgentUsageTokenTotals {
        // Assumption (verified against local rollout samples, not official semantics):
        // input_tokens INCLUDES cached_input_tokens (input + output == total, cached < input),
        // so subtract to avoid double-counting. Cache hits are billed at the 0.1x read rate.
        // cacheCreation stays 0: OpenAI has no cache-write surcharge.
        AgentUsageTokenTotals(
            input: max(0, inputTokens - cachedInputTokens),
            cacheRead: cachedInputTokens,
            output: outputTokens
        )
    }
}

struct AgentUsageDailyBucket: Codable, Equatable, Sendable {
    var day: String
    var sessionIDsByAgent: [String: Set<String>]
    var toolCounts: [String: Int]
    var tokenTotals: AgentUsageTokenTotals
    var tokenTotalsByModel: [String: AgentUsageTokenTotals]
    var activityCount: Int

    nonisolated init(
        day: String,
        sessionIDsByAgent: [String: Set<String>] = [:],
        toolCounts: [String: Int] = [:],
        tokenTotals: AgentUsageTokenTotals = AgentUsageTokenTotals(),
        tokenTotalsByModel: [String: AgentUsageTokenTotals] = [:],
        activityCount: Int = 0
    ) {
        self.day = day
        self.sessionIDsByAgent = sessionIDsByAgent
        self.toolCounts = toolCounts
        self.tokenTotals = tokenTotals
        self.tokenTotalsByModel = tokenTotalsByModel
        self.activityCount = activityCount
    }

    private enum CodingKeys: String, CodingKey {
        case day, sessionIDsByAgent, toolCounts, tokenTotals, tokenTotalsByModel, activityCount
    }

    // Pre-upgrade buckets have no tokenTotalsByModel key: decode it as an empty map
    // so old data keeps loading (no schemaVersion bump, no wipe).
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        sessionIDsByAgent = try container.decodeIfPresent([String: Set<String>].self, forKey: .sessionIDsByAgent) ?? [:]
        toolCounts = try container.decodeIfPresent([String: Int].self, forKey: .toolCounts) ?? [:]
        tokenTotals = try container.decodeIfPresent(AgentUsageTokenTotals.self, forKey: .tokenTotals) ?? AgentUsageTokenTotals()
        tokenTotalsByModel = try container.decodeIfPresent([String: AgentUsageTokenTotals].self, forKey: .tokenTotalsByModel) ?? [:]
        activityCount = try container.decodeIfPresent(Int.self, forKey: .activityCount) ?? 0
    }

    nonisolated mutating func recordSession(agent: String, sessionID: String) {
        sessionIDsByAgent[agent, default: []].insert(sessionID)
        activityCount += 1
    }

    nonisolated mutating func recordTool(_ toolName: String) {
        toolCounts[toolName, default: 0] += 1
        activityCount += 1
    }

    // Invariant: tokenTotals always equals the sum of tokenTotalsByModel values for
    // data written through this method.
    nonisolated mutating func recordTokens(perModel deltasByModel: [String: AgentUsageTokenTotals]) {
        var combined = AgentUsageTokenTotals()
        for (model, delta) in deltasByModel {
            guard delta.hasTokens else { continue }
            tokenTotalsByModel[model, default: AgentUsageTokenTotals()].add(delta)
            combined.add(delta)
        }
        tokenTotals.add(combined)
        if combined.resolvedTotal > 0 {
            activityCount += 1
        }
    }
}

struct AgentUsageDocument: Codable, Equatable, Sendable {
    var buckets: [String: AgentUsageDailyBucket]
    var seenToolEventIDs: Set<String>
    var codexTokenBaselines: [String: CodexTokenUsage]
    var tokenBaselines: [String: AgentUsageTokenSourceBaseline]

    nonisolated init(
        buckets: [String: AgentUsageDailyBucket] = [:],
        seenToolEventIDs: Set<String> = [],
        codexTokenBaselines: [String: CodexTokenUsage] = [:],
        tokenBaselines: [String: AgentUsageTokenSourceBaseline] = [:]
    ) {
        self.buckets = buckets
        self.seenToolEventIDs = seenToolEventIDs
        self.codexTokenBaselines = codexTokenBaselines
        self.tokenBaselines = tokenBaselines
        for (sourceKey, _) in codexTokenBaselines {
            let migratedKey = Self.codexTokenSourceKey(sourceKey)
            if !self.tokenBaselines.keys.contains(migratedKey) {
                // Empty map = first-sight branch on next scan; never seed an "unknown"
                // key here or the first real-model scan would double count (fable5 1b).
                self.tokenBaselines[migratedKey] = AgentUsageTokenSourceBaseline(totalsByModel: [:])
            }
        }
    }

    // v2: cache_read is tracked separately and excluded from consumption/pricing.
    // Older on-disk data summed cache_read into `input`, inflating totals into the
    // billions, so it is discarded on load rather than migrated.
    nonisolated static let currentSchemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case buckets
        case seenToolEventIDs
        case codexTokenBaselines
        case tokenBaselines
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version >= Self.currentSchemaVersion else {
            // Drop the polluted pre-v2 history. Baselines re-seed to current totals on
            // the next transcript scan with no retroactive delta, so counts restart clean.
            buckets = [:]
            seenToolEventIDs = []
            codexTokenBaselines = [:]
            tokenBaselines = [:]
            return
        }

        buckets = try container.decodeIfPresent([String: AgentUsageDailyBucket].self, forKey: .buckets) ?? [:]
        seenToolEventIDs = try container.decodeIfPresent(Set<String>.self, forKey: .seenToolEventIDs) ?? []
        codexTokenBaselines = try container.decodeIfPresent([String: CodexTokenUsage].self, forKey: .codexTokenBaselines) ?? [:]
        tokenBaselines = try container.decodeIfPresent(
            [String: AgentUsageTokenSourceBaseline].self,
            forKey: .tokenBaselines
        ) ?? [:]

        for (sourceKey, _) in codexTokenBaselines {
            let migratedKey = Self.codexTokenSourceKey(sourceKey)
            if !tokenBaselines.keys.contains(migratedKey) {
                // Empty map = first-sight branch on next scan; never seed an "unknown"
                // key here or the first real-model scan would double count (fable5 1b).
                tokenBaselines[migratedKey] = AgentUsageTokenSourceBaseline(totalsByModel: [:])
            }
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(buckets, forKey: .buckets)
        try container.encode(seenToolEventIDs, forKey: .seenToolEventIDs)
        try container.encode(codexTokenBaselines, forKey: .codexTokenBaselines)
        try container.encode(tokenBaselines, forKey: .tokenBaselines)
    }

    nonisolated static func codexTokenSourceKey(_ sourceKey: String) -> String {
        "codex|\(sourceKey)"
    }
}

actor AgentUsageStore {
    static let shared = AgentUsageStore()

    nonisolated static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ping-island", isDirectory: true)
        .appendingPathComponent("usage", isDirectory: true)
        .appendingPathComponent("agent-usage.json")

    private let fileURL: URL
    private let calendar: Calendar
    private let retentionDays: Int
    private var document: AgentUsageDocument?
    private var pendingSaveTask: Task<Void, Never>?

    init(
        fileURL: URL = AgentUsageStore.defaultFileURL,
        calendar: Calendar = .current,
        retentionDays: Int = 180
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.retentionDays = retentionDays
    }

    func recordHookEvent(_ event: HookEvent, resolvedSessionID: String? = nil, now: Date = Date()) async {
        var document = await loadDocument()
        let day = Self.dayKey(for: now, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        let agent = agentLabel(provider: event.provider, clientInfo: event.clientInfo)
        let sessionID = resolvedSessionID ?? event.sessionId
        bucket.recordSession(agent: agent, sessionID: sessionID)

        if let toolName = normalizedToolName(event.tool),
           shouldCountToolEvent(event.event),
           document.seenToolEventIDs.insert(toolEventID(
                sessionID: sessionID,
                toolID: event.toolUseId,
                toolName: toolName,
                fallbackEvent: event.event
           )).inserted {
            bucket.recordTool(toolName)
        }

        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }

    func recordSessionActivity(_ session: SessionState, now: Date = Date()) async {
        var document = await loadDocument()
        let day = Self.dayKey(for: now, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        bucket.recordSession(
            agent: agentLabel(provider: session.provider, clientInfo: session.clientInfo),
            sessionID: session.sessionId
        )
        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }

    func recordFileUpdate(session: SessionState, payload: FileUpdatePayload, now: Date = Date()) async {
        var document = await loadDocument()
        let day = Self.dayKey(for: now, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        bucket.recordSession(
            agent: agentLabel(provider: session.provider, clientInfo: session.clientInfo),
            sessionID: session.sessionId
        )

        for message in payload.messages {
            for block in message.content {
                guard case .toolUse(let tool) = block,
                      let toolName = normalizedToolName(tool.name),
                      document.seenToolEventIDs.insert(
                        toolEventID(
                            sessionID: payload.sessionId,
                            toolID: tool.id,
                            toolName: toolName,
                            fallbackEvent: "file"
                        )
                      ).inserted else {
                    continue
                }
                bucket.recordTool(toolName)
            }
        }

        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }

    func recordSubagentTool(sessionID: String, tool: SubagentToolCall, now: Date = Date()) async {
        var document = await loadDocument()
        let day = Self.dayKey(for: now, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        if let toolName = normalizedToolName(tool.name),
           document.seenToolEventIDs.insert(
            toolEventID(
                sessionID: sessionID,
                toolID: tool.id,
                toolName: toolName,
                fallbackEvent: "subagent"
            )
           ).inserted {
            bucket.recordTool(toolName)
        }
        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }

    func recordCodexUsageSnapshot(_ snapshot: CodexUsageSnapshot, now: Date = Date()) async {
        guard let currentUsage = snapshot.tokenUsage,
              currentUsage.totalTokens > 0 || currentUsage.inputTokens > 0 || currentUsage.outputTokens > 0 else {
            return
        }

        let sourceKey = snapshot.threadID ?? snapshot.sourceFilePath
        let baselineKey = AgentUsageDocument.codexTokenSourceKey(sourceKey)

        // Key stability (fable5 3b): a Codex thread is pinned to one model, but a scan
        // may miss the turn_context (model == nil). Reuse the baseline's sole key so the
        // map key never flips nil <-> model and double counts the thread. Only when there
        // is no previous key either does it fall back to "unknown". (loadDocument() is
        // cached, so reading the baseline first is cheap.)
        let existingBaseline = await loadDocument().tokenBaselines[baselineKey]
        let modelKey: String
        if let model = snapshot.model {
            modelKey = AgentUsageModelPricing.normalizedKey(forModel: model)
        } else if existingBaseline?.totalsByModel.count == 1,
                  let soleKey = existingBaseline?.totalsByModel.keys.first {
            modelKey = soleKey
        } else {
            modelKey = AgentUsageModelPricing.normalizedKey(forModel: nil)
        }

        await recordTokenUsage(
            provider: .codex,
            clientInfo: .codexCLI(),
            sessionID: snapshot.threadID,
            sourceKey: baselineKey,
            totalsByModel: [modelKey: currentUsage.totals],
            capturedAt: snapshot.capturedAt ?? now,
            recordInitialSnapshot: false
        )

        var document = await loadDocument()
        document.codexTokenBaselines[sourceKey] = currentUsage
        self.document = document
        scheduleSave()
    }

    func recordTokenUsage(
        provider: SessionProvider,
        clientInfo: SessionClientInfo,
        sessionID: String?,
        sourceKey: String,
        totalsByModel currentTotalsByModel: [String: AgentUsageTokenTotals],
        capturedAt: Date,
        sourceFileSize: UInt64? = nil,
        sourceContentHash: String? = nil,
        recordInitialSnapshot: Bool = true,
        now: Date = Date()
    ) async {
        guard currentTotalsByModel.values.contains(where: \.hasTokens) else {
            return
        }

        var document = await loadDocument()
        let previous = document.tokenBaselines[sourceKey]
        let didReset = didTokenSourceReset(
            previous: previous,
            currentFileSize: sourceFileSize
        )
        document.tokenBaselines[sourceKey] = AgentUsageTokenSourceBaseline(
            totalsByModel: currentTotalsByModel,
            fileSize: sourceFileSize,
            contentHash: sourceContentHash
        )

        let deltasByModel: [String: AgentUsageTokenTotals]
        if let previous, !previous.totalsByModel.isEmpty, !didReset {
            // Per-model delta. A key missing from a NON-empty baseline is a model that
            // appeared mid-source (e.g. a subagent on haiku): count it in full. This is
            // distinct from the empty-map first-sight branch below; do not merge them.
            var deltas: [String: AgentUsageTokenTotals] = [:]
            for (model, current) in currentTotalsByModel {
                if let base = previous.totalsByModel[model] {
                    deltas[model] = AgentUsageTokenTotals(
                        input: max(0, current.input - base.input),
                        cacheCreation: max(0, current.cacheCreation - base.cacheCreation),
                        cacheRead: max(0, current.cacheRead - base.cacheRead),
                        output: max(0, current.output - base.output)
                    )
                } else {
                    deltas[model] = current
                }
            }
            deltasByModel = deltas
        } else if recordInitialSnapshot {
            // First sight of the whole source (nil baseline, legacy empty map, or reset).
            deltasByModel = currentTotalsByModel
        } else {
            // Seed the baseline only; counting starts from the next scan.
            self.document = document
            scheduleSave()
            return
        }

        guard deltasByModel.values.contains(where: \.hasTokens) else {
            self.document = document
            scheduleSave()
            return
        }

        let day = Self.dayKey(for: capturedAt, calendar: calendar)
        var bucket = document.buckets[day] ?? AgentUsageDailyBucket(day: day)
        if let sessionID = nonEmpty(sessionID) {
            bucket.recordSession(
                agent: agentLabel(provider: provider, clientInfo: clientInfo),
                sessionID: sessionID
            )
        }
        bucket.recordTokens(perModel: deltasByModel)
        document.buckets[day] = bucket
        pruneDocument(&document, now: now)
        self.document = document
        scheduleSave()
    }

    func snapshot(range: AgentUsageRange, now: Date = Date()) async -> AgentUsageDashboardSnapshot {
        let document = await loadDocument()
        return Self.makeSnapshot(
            range: range,
            document: document,
            now: now,
            calendar: calendar
        )
    }

    func diagnosticsSnapshot(now: Date = Date()) async -> AgentUsageDiagnosticsSnapshot {
        let document = await loadDocument()
        let ranges = AgentUsageRange.allCases.map { range in
            let snapshot = Self.makeSnapshot(
                range: range,
                document: document,
                now: now,
                calendar: calendar
            )
            return AgentUsageDiagnosticsRangeSummary(
                range: range.rawValue,
                sessionCount: snapshot.sessionCount,
                toolUseCount: snapshot.toolUseCount,
                tokenTotals: snapshot.tokenTotals
            )
        }

        let recentBuckets = document.buckets
            .sorted { $0.key > $1.key }
            .prefix(30)
            .map { day, bucket in
                AgentUsageDiagnosticsDailyBucket(
                    day: day,
                    agentCount: bucket.sessionIDsByAgent.count,
                    sessionCount: bucket.sessionIDsByAgent.values.reduce(0) { $0 + $1.count },
                    toolUseCount: bucket.toolCounts.values.reduce(0, +),
                    tokenTotals: bucket.tokenTotals,
                    activityCount: bucket.activityCount
                )
            }

        return AgentUsageDiagnosticsSnapshot(
            generatedAt: now,
            tokenSourceCount: document.tokenBaselines.count,
            ranges: ranges,
            recentBuckets: Array(recentBuckets)
        )
    }

    func diagnosticsSnapshotData(now: Date = Date()) async throws -> Data {
        let snapshot = await diagnosticsSnapshot(now: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let object: [String: Any] = [
            "generatedAt": formatter.string(from: snapshot.generatedAt),
            "tokenSourceCount": snapshot.tokenSourceCount,
            "ranges": snapshot.ranges.map { range in
                [
                    "range": range.range,
                    "sessionCount": range.sessionCount,
                    "toolUseCount": range.toolUseCount,
                    "tokenTotals": tokenTotalsJSONObject(range.tokenTotals),
                ] as [String: Any]
            },
            "recentBuckets": snapshot.recentBuckets.map { bucket in
                [
                    "day": bucket.day,
                    "agentCount": bucket.agentCount,
                    "sessionCount": bucket.sessionCount,
                    "toolUseCount": bucket.toolUseCount,
                    "tokenTotals": tokenTotalsJSONObject(bucket.tokenTotals),
                    "activityCount": bucket.activityCount,
                ] as [String: Any]
            },
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    func flush() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard let document else { return }
        Self.save(document, to: fileURL)
    }

    nonisolated static func makeSnapshot(
        range: AgentUsageRange,
        document: AgentUsageDocument,
        now: Date,
        calendar: Calendar = .current
    ) -> AgentUsageDashboardSnapshot {
        let today = calendar.startOfDay(for: now)
        let includedKeys = (0..<range.dayCount).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return dayKey(for: date, calendar: calendar)
        }
        let includedBuckets = includedKeys.compactMap { document.buckets[$0] }

        var agentSessions: [String: Set<String>] = [:]
        var toolCounts: [String: Int] = [:]
        var tokenTotals = AgentUsageTokenTotals()
        var perModelTotals: [String: AgentUsageTokenTotals] = [:]

        for bucket in includedBuckets {
            for (agent, sessions) in bucket.sessionIDsByAgent {
                agentSessions[agent, default: []].formUnion(sessions)
            }
            for (tool, count) in bucket.toolCounts {
                toolCounts[tool, default: 0] += count
            }
            tokenTotals.add(bucket.tokenTotals)
            for (model, totals) in bucket.tokenTotalsByModel {
                perModelTotals[model, default: AgentUsageTokenTotals()].add(totals)
            }
        }

        let sessionCount = agentSessions.values.reduce(0) { $0 + $1.count }
        let toolUseCount = toolCounts.values.reduce(0, +)
        let perModelBreakdown = perModelTotals
            .map { key, totals in
                AgentUsageModelBreakdownItem(
                    modelKey: key,
                    displayName: AgentUsageModelPricing.displayName(forModel: key),
                    tokenTotals: totals,
                    estimatedUSD: AgentUsageModelPricing.pricing(forModel: key).estimateUSD(for: totals)
                )
            }
            .sorted { lhs, rhs in
                if lhs.estimatedUSD == rhs.estimatedUSD { return lhs.modelKey < rhs.modelKey }
                return lhs.estimatedUSD > rhs.estimatedUSD
            }

        return AgentUsageDashboardSnapshot(
            range: range,
            sessionCount: sessionCount,
            toolUseCount: toolUseCount,
            tokenTotals: tokenTotals,
            topAgents: rankItems(
                counts: agentSessions.mapValues(\.count),
                total: max(1, sessionCount)
            ),
            topTools: rankItems(counts: toolCounts, total: max(1, toolUseCount)),
            heatmapDays: AgentUsageDashboardSnapshot.recentHeatmapDays(
                now: now,
                buckets: document.buckets,
                calendar: calendar
            ),
            trendPoints: AgentUsageDashboardSnapshot.trendPoints(
                now: now,
                buckets: document.buckets,
                calendar: calendar
            ),
            spendSummary: AgentUsageDashboardSnapshot.spendSummary(
                now: now,
                buckets: document.buckets,
                calendar: calendar
            ),
            perModelBreakdown: perModelBreakdown,
            perModelDailySpend: AgentUsageDashboardSnapshot.perModelDailySpend(
                now: now,
                buckets: document.buckets,
                calendar: calendar
            )
        )
    }

    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func rankItems(counts: [String: Int], total: Int) -> [AgentUsageRankItem] {
        counts
            .map { name, count in
                AgentUsageRankItem(name: name, count: count, share: Double(count) / Double(total))
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.count > rhs.count
            }
            .prefix(5)
            .map { $0 }
    }

    private func loadDocument() async -> AgentUsageDocument {
        if let document {
            return document
        }

        let loaded = Self.load(from: fileURL)
        document = loaded
        return loaded
    }

    private nonisolated static func load(from fileURL: URL) -> AgentUsageDocument {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(AgentUsageDocument.self, from: data) else {
            return AgentUsageDocument()
        }
        return document
    }

    private nonisolated static func save(_ document: AgentUsageDocument, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Local analytics must never block session tracking.
        }
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let fileURL = fileURL
        let document = document
        pendingSaveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let document else { return }
            Self.save(document, to: fileURL)
        }
    }

    private func pruneDocument(_ document: inout AgentUsageDocument, now: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else {
            return
        }
        let cutoffKey = Self.dayKey(for: cutoff, calendar: calendar)
        document.buckets = document.buckets.filter { key, _ in key >= cutoffKey }
        if document.seenToolEventIDs.count > 50_000 {
            document.seenToolEventIDs.removeAll(keepingCapacity: true)
        }
    }

    private nonisolated func didTokenSourceReset(
        previous: AgentUsageTokenSourceBaseline?,
        currentFileSize: UInt64?
    ) -> Bool {
        guard let previous else { return false }
        if let previousFileSize = previous.fileSize,
           let currentFileSize,
           currentFileSize < previousFileSize {
            return true
        }
        return false
    }

    private nonisolated func tokenTotalsJSONObject(_ totals: AgentUsageTokenTotals) -> [String: Int] {
        [
            "input": totals.input,
            "cacheCreation": totals.cacheCreation,
            "cacheRead": totals.cacheRead,
            "output": totals.output,
            "resolvedTotal": totals.resolvedTotal,
        ]
    }

    private nonisolated func agentLabel(provider: SessionProvider, clientInfo: SessionClientInfo) -> String {
        nonEmpty(clientInfo.badgeLabel(for: provider)) ?? provider.displayName
    }

    private nonisolated func normalizedToolName(_ raw: String?) -> String? {
        nonEmpty(raw).map { value in
            value
                .replacingOccurrences(of: "mcp__", with: "mcp:")
                .replacingOccurrences(of: "__", with: ".")
        }
    }

    private nonisolated func shouldCountToolEvent(_ eventName: String) -> Bool {
        switch eventName {
        case "PreToolUse", "BeforeTool", "preToolUse", "PermissionRequest":
            return true
        default:
            return false
        }
    }

    private nonisolated func toolEventID(
        sessionID: String,
        toolID: String?,
        toolName: String,
        fallbackEvent: String
    ) -> String {
        let resolvedID = nonEmpty(toolID)
            ?? "\(fallbackEvent)-\(toolName)"
        return "\(sessionID)|\(resolvedID)|\(toolName)"
    }

    private nonisolated func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
