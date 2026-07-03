import AppKit
import Combine
import SwiftUI

@MainActor
final class AgentUsageAnalyticsViewModel: ObservableObject {
    @Published var selectedRange: AgentUsageRange = .sevenDays
    @Published private(set) var snapshot = AgentUsageDashboardSnapshot.empty(range: .sevenDays)
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadedSnapshot = false

    private var refreshTask: Task<Void, Never>?

    var isInitialLoading: Bool {
        isRefreshing && !hasLoadedSnapshot
    }

    func refresh() {
        refreshTask?.cancel()
        let range = selectedRange
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let nextSnapshot = await AgentUsageStore.shared.snapshot(range: range)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.snapshot = nextSnapshot
                self?.hasLoadedSnapshot = true
                self?.isRefreshing = false
            }
        }
    }

    func selectRange(_ range: AgentUsageRange) {
        guard selectedRange != range else { return }
        selectedRange = range
        refresh()
    }

    deinit {
        refreshTask?.cancel()
    }
}


struct AgentUsageAnalyticsContent: View {
    @StateObject private var viewModel = AgentUsageAnalyticsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized: "统计")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.94))

                Text(appLocalized: "查看 Agent、Token、工具调用与活跃概览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
            }

            AgentUsageSummaryCards(snapshot: viewModel.snapshot)

            spendCard

            perModelCard

            activityMapCard

            overviewCard

            HStack(alignment: .top, spacing: 18) {
                rankingCard(
                    title: "Agent 类型排行",
                    items: viewModel.snapshot.topAgents,
                    emptyTitle: "还没有可展示的 Agent 数据",
                    tint: SettingsCategory.analytics.tint
                )
                .frame(maxWidth: .infinity)

                rankingCard(
                    title: "工具调用 Top 5",
                    items: viewModel.snapshot.topTools,
                    emptyTitle: "还没有可展示的工具调用",
                    tint: TerminalColors.blue
                )
                .frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if viewModel.isInitialLoading {
                AgentUsageLoadingOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.isInitialLoading)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var activityMapCard: some View {
        SettingsSectionCard(title: "活跃地图") {
            AgentUsageHeatmapView(days: viewModel.snapshot.heatmapDays)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        }
    }

    private var spendCard: some View {
        SettingsSectionCard(title: "Token 费用预估") {
            AgentUsageSpendPanel(
                summary: viewModel.snapshot.spendSummary,
                // footer 呈現 30 天彙總，旗標用範圍無關的 perModelDailySpend（恆 30 天），
                // 不用隨 selectedRange 變動的 perModelBreakdown，避免旗標與 footer 範圍錯位。
                usesPerModelPricing: !viewModel.snapshot.perModelDailySpend.isEmpty
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var perModelCard: some View {
        SettingsSectionCard(title: "各模型用量与花费") {
            AgentUsagePerModelPanel(
                breakdown: viewModel.snapshot.perModelBreakdown,
                dailySpend: viewModel.snapshot.perModelDailySpend
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var overviewCard: some View {
        SettingsSectionCard(title: "概览") {
            AgentUsageRangeControl(
                selectedRange: viewModel.selectedRange,
                isRefreshing: viewModel.isRefreshing,
                selectRange: viewModel.selectRange,
                refresh: viewModel.refresh
            )
        } content: {
            VStack(spacing: 0) {
                AgentUsageOverviewLine(
                    icon: "person.crop.circle",
                    title: "Agent 类型",
                    value: "\(viewModel.snapshot.topAgents.count)",
                    subtitle: "本周期出现的客户端类型"
                )
                AgentUsageInsetDivider()
                AgentUsageOverviewLine(
                    icon: "bubble.left.and.bubble.right",
                    title: "会话数",
                    value: AgentUsageFormat.compactCount(viewModel.snapshot.sessionCount),
                    subtitle: "按 agent 类型去重后的会话"
                )
                AgentUsageInsetDivider()
                AgentUsageOverviewLine(
                    icon: "wrench.and.screwdriver",
                    title: "工具使用",
                    value: AgentUsageFormat.compactCount(viewModel.snapshot.toolUseCount),
                    subtitle: "去重后的工具调用次数"
                )
                AgentUsageInsetDivider()
                AgentUsageOverviewLine(
                    icon: "cube.transparent",
                    title: "Token 消耗",
                    value: AgentUsageFormat.compactTokenCount(viewModel.snapshot.tokenTotals.resolvedTotal),
                    subtitle: "Codex 累计快照的本地增量"
                )
                AgentUsageInsetDivider()
                AgentUsageTokenSplitLine(totals: viewModel.snapshot.tokenTotals)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }

    private func rankingCard(
        title: String,
        items: [AgentUsageRankItem],
        emptyTitle: String,
        tint: Color
    ) -> some View {
        SettingsSectionCard(title: title) {
            AgentUsageRankingList(
                items: items,
                emptyTitle: emptyTitle,
                tint: tint
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }
}


struct AgentUsageLoadingOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .background(
                    SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .opacity(0.90)
                )

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.84))

                Text(appLocalized: "正在加载统计")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }
}


struct AgentUsageRangeControl: View {
    let selectedRange: AgentUsageRange
    let isRefreshing: Bool
    let selectRange: (AgentUsageRange) -> Void
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker(AppLocalization.string("统计范围"), selection: Binding(
                get: { selectedRange },
                set: { selectRange($0) }
            )) {
                ForEach(AgentUsageRange.allCases) { range in
                    Text(appLocalized: range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 186)

            Button(action: refresh) {
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AppLocalization.string("刷新本地统计"))
        }
    }
}


enum AgentUsageFormat {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let usdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static func integer(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compactCount(_ value: Int) -> String {
        compactMetric(Double(value), suffixes: [(1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]) {
            integer(value)
        }
    }

    static func compactTokenCount(_ value: Int) -> String {
        compactCount(value)
    }

    static func usd(_ value: Double) -> String {
        if value > 0, value < 0.01 {
            return String(format: "$%.4f", value)
        }
        return usdFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func compactUSD(_ value: Double) -> String {
        guard value >= 10_000 else {
            return usd(value)
        }

        let compactValue = compactMetric(value, suffixes: [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]) {
            String(format: "%.0f", value)
        }
        return "$\(compactValue)"
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func shortMonth(_ date: Date) -> String {
        shortMonthFormatter.string(from: date)
    }

    private static func compactMetric(
        _ value: Double,
        suffixes: [(threshold: Double, suffix: String)],
        fallback: () -> String
    ) -> String {
        guard let scale = suffixes.first(where: { value >= $0.threshold }) else {
            return fallback()
        }

        let scaledValue = value / scale.threshold
        let formatted = scaledValue >= 100
            ? String(format: "%.0f", scaledValue)
            : String(format: "%.1f", scaledValue)
        return "\(formatted)\(scale.suffix)"
    }
}
