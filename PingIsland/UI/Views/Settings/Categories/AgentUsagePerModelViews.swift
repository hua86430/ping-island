import AppKit
import SwiftUI

private let perModelPalette: [Color] = [
    SettingsCategory.analytics.tint,
    TerminalColors.blue,
    TerminalColors.amber,
    TerminalColors.green,
    TerminalColors.cyan,
]
private let perModelOtherColor = Color.white.opacity(0.38)

// Deterministic color from the modelKey (not rank): the same model keeps its color
// across snapshots even when its ranking shifts. Chart, legend, and list share it.
// FNV-1a keeps the same hash on every launch, unlike String.hashValue (seeded per run).
private func perModelColor(forKey modelKey: String) -> Color {
    if modelKey == "__other__" { return perModelOtherColor }
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in modelKey.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return perModelPalette[Int(hash % UInt64(perModelPalette.count))]
}

struct AgentUsagePerModelChartSeries: Identifiable {
    let modelKey: String
    let displayName: String
    let values: [Double]   // 30 daily USD values, aligned with perModelDailySpend points
    let color: Color

    var id: String { modelKey }
}

struct AgentUsagePerModelPanel: View {
    let breakdown: [AgentUsageModelBreakdownItem]
    let dailySpend: [AgentUsageModelDailySpend]

    private static let maxLines = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if breakdown.isEmpty && dailySpend.isEmpty {
                AgentUsageEmptyLine(title: "还没有可展示的模型数据")
                    .padding(.vertical, 12)
            } else {
                Text(appLocalized: "每日花费")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))

                AgentUsagePerModelSpendChart(series: series)
                    .frame(height: 104)

                AgentUsagePerModelLegend(series: series)

                AgentUsageModelBreakdownList(items: breakdown, colorsByKey: colorsByKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Top 5 lines by totalUSD (dailySpend is already sorted descending); the rest are
    // merged pointwise into a single gray "其他" line.
    private var series: [AgentUsagePerModelChartSeries] {
        let top = Array(dailySpend.prefix(Self.maxLines))
        let rest = Array(dailySpend.dropFirst(Self.maxLines))

        var lines = top.map { spend in
            AgentUsagePerModelChartSeries(
                modelKey: spend.modelKey,
                displayName: spend.displayName,
                values: spend.points.map(\.estimatedUSD),
                color: perModelColor(forKey: spend.modelKey)
            )
        }

        if !rest.isEmpty {
            let dayCount = rest.first?.points.count ?? 0
            var merged = [Double](repeating: 0, count: dayCount)
            for spend in rest {
                for (index, point) in spend.points.enumerated() where index < merged.count {
                    merged[index] += point.estimatedUSD
                }
            }
            lines.append(AgentUsagePerModelChartSeries(
                modelKey: "__other__",
                displayName: "其他",
                values: merged,
                color: perModelOtherColor
            ))
        }

        return lines
    }

    // Same key, same color across chart, legend, and list rows.
    private var colorsByKey: [String: Color] {
        var colors: [String: Color] = [:]
        for line in series {
            colors[line.modelKey] = line.color
        }
        return colors
    }
}

struct AgentUsagePerModelSpendChart: View {
    let series: [AgentUsagePerModelChartSeries]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(series.flatMap(\.values).max() ?? 0, 0.000_1)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                ForEach(series) { line in
                    AgentUsageSparklineStroke(
                        points: points(for: line.values, in: proxy.size, maxValue: maxValue)
                    )
                    .stroke(
                        line.color.opacity(0.88),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    // y normalized against the max daily cost across ALL models and days.
    private func points(for values: [Double], in size: CGSize, maxValue: Double) -> [CGPoint] {
        let count = max(values.count - 1, 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(count) * size.width
            let y = size.height - CGFloat(value / maxValue) * (size.height * 0.84) - size.height * 0.08
            return CGPoint(x: x, y: y)
        }
    }
}

struct AgentUsagePerModelLegend: View {
    let series: [AgentUsagePerModelChartSeries]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(series) { line in
                HStack(spacing: 5) {
                    Circle()
                        .fill(line.color)
                        .frame(width: 7, height: 7)
                    Text(appLocalized: line.displayName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AgentUsageModelBreakdownList: View {
    let items: [AgentUsageModelBreakdownItem]
    let colorsByKey: [String: Color]

    var body: some View {
        if items.isEmpty {
            AgentUsageEmptyLine(title: "还没有可展示的模型数据")
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AgentUsageModelBreakdownRow(
                        item: item,
                        color: colorsByKey[item.modelKey] ?? perModelOtherColor
                    )
                    if index < items.count - 1 {
                        AgentUsageInsetDivider()
                    }
                }
            }
        }
    }
}

struct AgentUsageModelBreakdownRow: View {
    let item: AgentUsageModelBreakdownItem
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(appLocalized: item.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .help(item.modelKey)

            Spacer(minLength: 8)

            Text(verbatim: AppLocalization.format(
                "%@ Tokens",
                AgentUsageFormat.compactTokenCount(item.tokenTotal)
            ))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .help(AgentUsageFormat.integer(item.tokenTotal))

            Text(verbatim: AgentUsageFormat.compactUSD(item.estimatedUSD))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(TerminalColors.blue.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 56, alignment: .trailing)
                .help(AgentUsageFormat.usd(item.estimatedUSD))
        }
        .padding(.vertical, 9)
    }
}
