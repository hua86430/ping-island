import AppKit
import SwiftUI

struct AgentUsageSummaryCards: View {
    let snapshot: AgentUsageDashboardSnapshot

    private let spacing: CGFloat = 16
    private let wideCardWidth: CGFloat = 220
    private let twoColumnMinWidth: CGFloat = 176

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                tokenCard
                    .frame(width: wideCardWidth)
                agentCard
                    .frame(width: wideCardWidth)
                toolCard
                    .frame(width: wideCardWidth)
                sessionCard
                    .frame(width: wideCardWidth)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: twoColumnMinWidth), spacing: spacing),
                    GridItem(.flexible(minimum: twoColumnMinWidth), spacing: spacing),
                ],
                alignment: .leading,
                spacing: spacing
            ) {
                tokenCard
                agentCard
                toolCard
                sessionCard
            }

            VStack(spacing: spacing) {
                tokenCard
                agentCard
                toolCard
                sessionCard
            }
        }
    }

    private var tokenCard: some View {
        AgentUsageSummaryCard(
            icon: "cube.transparent",
            title: "Token 消耗",
            value: AgentUsageFormat.compactTokenCount(snapshot.tokenTotals.resolvedTotal),
            subtitle: AppLocalization.format(
                "输入 %@ / 输出 %@",
                AgentUsageFormat.compactTokenCount(snapshot.tokenTotals.input),
                AgentUsageFormat.compactTokenCount(snapshot.tokenTotals.output)
            ),
            trendValues: snapshot.trendPoints.map(\.tokenTotal),
            tint: SettingsCategory.analytics.tint
        )
    }

    private var agentCard: some View {
        AgentUsageSummaryCard(
            icon: "person.crop.circle",
            title: "活跃 Agent",
            value: "\(snapshot.topAgents.count)",
            subtitle: "本周期出现的客户端类型",
            trendValues: snapshot.trendPoints.map(\.agentCount),
            tint: TerminalColors.blue
        )
    }

    private var toolCard: some View {
        AgentUsageSummaryCard(
            icon: "wrench.and.screwdriver",
            title: "工具调用",
            value: AgentUsageFormat.compactCount(snapshot.toolUseCount),
            subtitle: "去重后的工具调用次数",
            trendValues: snapshot.trendPoints.map(\.toolUseCount),
            tint: TerminalColors.amber
        )
    }

    private var sessionCard: some View {
        AgentUsageSummaryCard(
            icon: "bubble.left.and.bubble.right",
            title: "会话数",
            value: AgentUsageFormat.compactCount(snapshot.sessionCount),
            subtitle: "按 agent 类型去重后的会话",
            trendValues: snapshot.trendPoints.map(\.sessionCount),
            tint: TerminalColors.green
        )
    }
}


struct AgentUsageSummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let trendValues: [Int]
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(tint.opacity(0.94))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 7) {
                Text(appLocalized: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)

                Text(verbatim: value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                    .monospacedDigit()
                    .minimumScaleFactor(0.56)
                    .lineLimit(1)
                    .help(value)

                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .opacity(0.90)
                )
                .overlay(alignment: .bottomTrailing) {
                    AgentUsageSparklineBackdrop(values: trendValues, tint: tint)
                        .frame(width: 118, height: 58)
                        .padding(.trailing, 10)
                        .padding(.bottom, 8)
                        .opacity(0.82)
                }
                .overlay(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.13),
                            Color.white.opacity(0.035),
                            Color.black.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 16, y: 8)
    }
}


struct AgentUsageSpendPanel: View {
    let summary: AgentUsageSpendSummary

    private let columns = [
        GridItem(.flexible(minimum: 132), spacing: 14),
        GridItem(.flexible(minimum: 132), spacing: 14),
        GridItem(.flexible(minimum: 132), spacing: 14),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                AgentUsageSpendMetricTile(title: "今日", metric: summary.today)
                AgentUsageSpendMetricTile(title: "7 天费用", metric: summary.sevenDays)
                AgentUsageSpendMetricTile(title: "30 天费用", metric: summary.thirtyDays)
            }

            AgentUsageSpendBarChart(points: summary.dailyPoints)
                .frame(height: 104)
                .padding(.top, 2)

            AgentUsageSpendFooter(summary: summary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct AgentUsageSpendFooter: View {
    let summary: AgentUsageSpendSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            footerLine

            VStack(alignment: .leading, spacing: 4) {
                footerAmounts
                pricingLabel
            }
        }
    }

    private var footerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            footerAmounts
            Spacer(minLength: 8)
            pricingLabel
        }
    }

    private var footerAmounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: AppLocalization.format(
                "30 天：%@ Tokens",
                AgentUsageFormat.compactTokenCount(summary.thirtyDays.tokenTotals.resolvedTotal)
            ))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.80))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(verbatim: AppLocalization.format(
                "· %@ 预估",
                AgentUsageFormat.compactUSD(summary.thirtyDays.estimatedUSD)
            ))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(TerminalColors.blue.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .help(exactSummaryHelp)
    }

    private var pricingLabel: some View {
        Text(appLocalized: AgentUsageCostEstimator.blendedCodexClaudePricing.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.42))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var exactSummaryHelp: String {
        let tokenText = AgentUsageFormat.integer(summary.thirtyDays.tokenTotals.resolvedTotal)
        let costText = AppLocalization.format("· %@ 预估", AgentUsageFormat.usd(summary.thirtyDays.estimatedUSD))
        return "\(tokenText) \(costText)"
    }
}


struct AgentUsageSpendMetricTile: View {
    let title: String
    let metric: AgentUsageCostMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(appLocalized: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(1)

            Text(verbatim: AgentUsageFormat.compactUSD(metric.estimatedUSD))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.94))
                .monospacedDigit()
                .minimumScaleFactor(0.56)
                .lineLimit(1)
                .help(AgentUsageFormat.usd(metric.estimatedUSD))

            Text(verbatim: AppLocalization.format(
                "%@ Tokens",
                AgentUsageFormat.compactTokenCount(metric.tokenTotals.resolvedTotal)
            ))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .help(AgentUsageFormat.integer(metric.tokenTotals.resolvedTotal))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct AgentUsageOverviewLine: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalized: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
                    .lineLimit(1)
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Text(verbatim: value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .monospacedDigit()
                .minimumScaleFactor(0.56)
                .lineLimit(1)
                .frame(minWidth: 56, idealWidth: 86, alignment: .trailing)
                .help(value)
        }
        .padding(.vertical, 10)
    }
}


struct AgentUsageMetricLine: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appLocalized: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(2)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Text(verbatim: value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .monospacedDigit()
                .minimumScaleFactor(0.56)
                .lineLimit(1)
                .frame(minWidth: 56, idealWidth: 86, alignment: .trailing)
                .help(value)
        }
        .padding(.vertical, 11)
    }
}


struct AgentUsageTokenSplitLine: View {
    let totals: AgentUsageTokenTotals

    var body: some View {
        HStack(spacing: 16) {
            AgentUsageTokenPill(
                title: "输入 Token",
                value: AgentUsageFormat.compactTokenCount(totals.input),
                tint: TerminalColors.blue
            )
            AgentUsageTokenPill(
                title: "输出 Token",
                value: AgentUsageFormat.compactTokenCount(totals.output),
                tint: TerminalColors.amber
            )
        }
        .padding(.vertical, 12)
    }
}


struct AgentUsageTokenPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalized: title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.50))
            Text(verbatim: value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(tint.opacity(0.95))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct AgentUsageRankingList: View {
    let items: [AgentUsageRankItem]
    let emptyTitle: String
    let tint: Color

    var body: some View {
        if items.isEmpty {
            AgentUsageEmptyLine(title: emptyTitle)
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AgentUsageRankingRow(index: index, item: item, tint: tint)
                    if index < items.count - 1 {
                        AgentUsageInsetDivider()
                    }
                }
            }
        }
    }
}


struct AgentUsageRankingRow: View {
    let index: Int
    let item: AgentUsageRankItem
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(verbatim: "#\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(tint.opacity(0.86))
                    .frame(width: 30, alignment: .leading)

                Text(verbatim: item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(item.name)

                Spacer(minLength: 8)

                Text(verbatim: AgentUsageFormat.integer(item.count))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(minWidth: 46, idealWidth: 64, alignment: .trailing)
                    .help(AgentUsageFormat.integer(item.count))
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.opacity(0.72))
                            .frame(width: max(6, proxy.size.width * max(0.04, item.share)))
                    }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 10)
    }
}


struct AgentUsageInsetDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.10))
    }
}


struct AgentUsageEmptyLine: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.34))
            Text(appLocalized: title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.46))
            Spacer(minLength: 0)
        }
    }
}

