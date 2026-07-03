import AppKit
import SwiftUI

struct AgentUsageSpendBarChart: View {
    let points: [AgentUsageDailySpendPoint]

    var body: some View {
        GeometryReader { proxy in
            let maxTokens = max(points.map(\.tokenTotal).max() ?? 0, 1)
            let barSpacing: CGFloat = 4
            let barWidth = max(4, (proxy.size.width - CGFloat(max(points.count - 1, 0)) * barSpacing) / CGFloat(max(points.count, 1)))

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(points) { point in
                    let tokenShare = CGFloat(point.tokenTotal) / CGFloat(maxTokens)
                    let barHeight = max(point.tokenTotal > 0 ? 5 : 2, proxy.size.height * max(0.02, tokenShare))

                    RoundedRectangle(cornerRadius: min(4, barWidth * 0.45), style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: point.tokenTotal > 0 ? [
                                    Color.white.opacity(0.92),
                                    TerminalColors.blue.opacity(0.58),
                                    TerminalColors.blue.opacity(0.78)
                                ] : [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: min(4, barWidth * 0.45), style: .continuous)
                                .fill(Color.white.opacity(point.tokenTotal > 0 ? 0.18 : 0.05))
                                .frame(height: min(5, max(2, barHeight * 0.28)))
                        }
                        .frame(width: barWidth, height: barHeight)
                        .help(AppLocalization.format(
                            "%@ · %@ Tokens · %@",
                            AgentUsageFormat.shortDate(point.date),
                            AgentUsageFormat.compactTokenCount(point.tokenTotal),
                            AgentUsageFormat.usd(point.estimatedUSD)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}


struct AgentUsageSparklineBackdrop: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    AgentUsageSparklineFill(points: points)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.24),
                                    tint.opacity(0.05),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    AgentUsageSparklineStroke(points: points)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.18),
                                    tint.opacity(0.64),
                                    tint.opacity(0.24)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let usableValues = values.isEmpty ? [0, 0] : values
        let maxValue = max(usableValues.max() ?? 0, 1)
        let minValue = usableValues.min() ?? 0
        let range = max(maxValue - minValue, 1)
        let count = max(usableValues.count - 1, 1)

        return usableValues.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(count) * size.width
            let normalizedY = CGFloat(value - minValue) / CGFloat(range)
            let y = size.height - normalizedY * (size.height * 0.72) - size.height * 0.10
            return CGPoint(x: x, y: y)
        }
    }
}


struct AgentUsageSparklineStroke: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        smoothPath(points: points)
    }
}


struct AgentUsageSparklineFill: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var path = smoothPath(points: points)
        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

func smoothPath(points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)

    guard points.count > 1 else { return path }

    for index in 1..<points.count {
        let previous = points[index - 1]
        let current = points[index]
        let midX = (previous.x + current.x) / 2
        path.addCurve(
            to: current,
            control1: CGPoint(x: midX, y: previous.y),
            control2: CGPoint(x: midX, y: current.y)
        )
    }

    return path
}


struct AgentUsageHeatmapView: View {
    let days: [AgentUsageHeatmapDay]

    private let labelColumnWidth: CGFloat = 22
    private let labelGridSpacing: CGFloat = 10
    private let monthLabelHeight: CGFloat = 13
    private let headerHeight: CGFloat = 30
    private let legendHeight: CGFloat = 14
    private let calendarHeight: CGFloat = 178
    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { proxy in
            let weekList = weeks
            let layout = makeLayout(availableWidth: proxy.size.width, weekCount: weekList.count)

            VStack(alignment: .leading, spacing: 10) {
                heatmapHeader(layout: layout)
                .frame(height: headerHeight)

                HStack(alignment: .top, spacing: labelGridSpacing) {
                    weekdayLabels(layout: layout)
                    VStack(alignment: .leading, spacing: 6) {
                        heatmapGrid(weeks: weekList, layout: layout)
                        monthLabels(weeks: weekList, layout: layout)
                    }
                    .frame(width: layout.gridWidth, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: calendarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func heatmapHeader(layout: HeatmapLayout) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(appLocalized: "最近 6 个月")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))

            Text(appLocalized: "每日活跃记录")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.42))

            if days.allSatisfy({ $0.activityCount == 0 }) {
                Text(appLocalized: "还没有活跃记录")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer(minLength: 0)

            heatmapLegend(layout: layout)
        }
    }

    private func weekdayLabels(layout: HeatmapLayout) -> some View {
        VStack(alignment: .trailing, spacing: layout.rowSpacing) {
            ForEach(0..<7, id: \.self) { weekday in
                Text(appLocalized: weekdayLabel(for: weekday))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(weekdayLabel(for: weekday).isEmpty ? 0 : 0.46))
                    .frame(width: labelColumnWidth, height: layout.cellSize, alignment: .trailing)
            }
        }
    }

    private func monthLabels(weeks: [HeatmapWeek], layout: HeatmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarkers(for: weeks, layout: layout)) { marker in
                Text(verbatim: marker.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: marker.width, alignment: .leading)
                    .offset(x: marker.x)
            }
        }
        .frame(width: layout.gridWidth, height: monthLabelHeight, alignment: .topLeading)
        .clipped()
    }

    private func heatmapGrid(weeks: [HeatmapWeek], layout: HeatmapLayout) -> some View {
        HStack(alignment: .top, spacing: layout.columnSpacing) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: layout.rowSpacing) {
                    ForEach(0..<7, id: \.self) { weekday in
                        if let day = week.days[weekday] {
                            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                .fill(heatmapGradient(for: day.activityCount))
                                .overlay(alignment: .top) {
                                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                        .fill(Color.white.opacity(day.activityCount > 0 ? 0.13 : 0.04))
                                        .frame(height: max(1, layout.cellSize * 0.24))
                                }
                                .frame(width: layout.cellSize, height: layout.cellSize)
                                .help(AppLocalization.format(
                                    "%@ · %@ 条活跃记录",
                                    AgentUsageFormat.shortDate(day.date),
                                    AgentUsageFormat.integer(day.activityCount)
                                ))
                        } else {
                            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                .fill(Color.clear)
                                .frame(width: layout.cellSize, height: layout.cellSize)
                        }
                    }
                }
            }
        }
        .frame(width: layout.gridWidth, alignment: .leading)
    }

    private func heatmapLegend(layout: HeatmapLayout) -> some View {
        HStack(spacing: 5) {
            Text(appLocalized: "低")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                    .fill(heatmapGradient(forLevel: level))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(level > 0 ? 0.13 : 0.04))
                            .frame(height: max(1, layout.cellSize * 0.24))
                    }
                    .frame(width: layout.cellSize, height: layout.cellSize)
            }
            Text(appLocalized: "高")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(height: legendHeight)
    }

    private func heatmapGradient(for count: Int) -> LinearGradient {
        if count <= 0 { return heatmapGradient(forLevel: 0) }
        if count < 3 { return heatmapGradient(forLevel: 1) }
        if count < 8 { return heatmapGradient(forLevel: 2) }
        if count < 16 { return heatmapGradient(forLevel: 3) }
        return heatmapGradient(forLevel: 4)
    }

    private func heatmapGradient(forLevel level: Int) -> LinearGradient {
        let base = color(forLevel: level)
        return LinearGradient(
            colors: [
                Color.white.opacity(level > 0 ? 0.18 : 0.05),
                base.opacity(level > 0 ? 0.95 : 0.78),
                base
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func color(for count: Int) -> Color {
        if count <= 0 { return color(forLevel: 0) }
        if count < 3 { return color(forLevel: 1) }
        if count < 8 { return color(forLevel: 2) }
        if count < 16 { return color(forLevel: 3) }
        return color(forLevel: 4)
    }

    private func color(forLevel level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.08)
        case 1: return TerminalColors.cyan.opacity(0.34)
        case 2: return TerminalColors.cyan.opacity(0.58)
        case 3: return TerminalColors.blue.opacity(0.72)
        default: return TerminalColors.blue.opacity(0.95)
        }
    }

    private var weeks: [HeatmapWeek] {
        guard let firstDay = days.first else { return [] }

        var result: [HeatmapWeek] = []
        var currentWeek = HeatmapWeek(startDate: weekStart(for: firstDay.date), days: Array(repeating: nil, count: 7))

        for day in days {
            let dayWeekStart = weekStart(for: day.date)
            if !calendar.isDate(dayWeekStart, inSameDayAs: currentWeek.startDate) {
                result.append(currentWeek)
                currentWeek = HeatmapWeek(startDate: dayWeekStart, days: Array(repeating: nil, count: 7))
            }

            currentWeek.days[weekdayIndex(for: day.date)] = day
        }

        result.append(currentWeek)
        return result
    }

    private func weekdayIndex(for date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private func weekStart(for date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let daysFromMonday = weekdayIndex(for: startOfDay)
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    private func weekdayLabel(for index: Int) -> String {
        switch index {
        case 0: return "一"
        case 2: return "三"
        case 4: return "五"
        default: return ""
        }
    }

    private func monthLabel(for week: HeatmapWeek, at index: Int) -> String {
        guard let visibleDay = week.days.compactMap({ $0 }).first else { return "" }
        if index == 0 || calendar.component(.day, from: visibleDay.date) <= 7 {
            return AgentUsageFormat.shortMonth(visibleDay.date)
        }
        return ""
    }

    private func monthMarkers(for weeks: [HeatmapWeek], layout: HeatmapLayout) -> [MonthMarker] {
        Array(weeks.enumerated()).compactMap { index, week in
            let label = monthLabel(for: week, at: index)
            guard !label.isEmpty else { return nil }

            let preferredWidth: CGFloat = 26
            let x = min(layout.xOffset(forWeekAt: index), max(0, layout.gridWidth - preferredWidth))
            return MonthMarker(id: index, label: label, x: x, width: preferredWidth)
        }
    }

    private func makeLayout(availableWidth: CGFloat, weekCount: Int) -> HeatmapLayout {
        let resolvedWeekCount = max(1, weekCount)
        let availableGridWidth = max(160, availableWidth - labelColumnWidth - labelGridSpacing)
        let preferredCellSize: CGFloat
        if availableGridWidth >= 640 {
            preferredCellSize = 16
        } else if availableGridWidth >= 430 {
            preferredCellSize = 14
        } else {
            preferredCellSize = 11
        }
        let minimumColumnSpacing: CGFloat = availableGridWidth < 430 ? 2 : 4
        let cellSize = min(
            preferredCellSize,
            max(6, (availableGridWidth - CGFloat(resolvedWeekCount - 1) * minimumColumnSpacing) / CGFloat(resolvedWeekCount))
        )
        let columnSpacing = resolvedWeekCount > 1
            ? max(
                minimumColumnSpacing,
                (availableGridWidth - CGFloat(resolvedWeekCount) * cellSize) / CGFloat(resolvedWeekCount - 1)
            )
            : 0
        let rowSpacing = min(6, max(3, cellSize * 0.30))
        let gridWidth = CGFloat(resolvedWeekCount) * cellSize + CGFloat(resolvedWeekCount - 1) * columnSpacing

        return HeatmapLayout(
            cellSize: cellSize,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing,
            gridWidth: gridWidth,
            cornerRadius: min(3.5, cellSize * 0.32)
        )
    }

    private struct HeatmapLayout {
        let cellSize: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let gridWidth: CGFloat
        let cornerRadius: CGFloat

        func xOffset(forWeekAt index: Int) -> CGFloat {
            CGFloat(index) * (cellSize + columnSpacing)
        }
    }

    private struct MonthMarker: Identifiable {
        let id: Int
        let label: String
        let x: CGFloat
        let width: CGFloat
    }

    private struct HeatmapWeek {
        let startDate: Date
        var days: [AgentUsageHeatmapDay?]
    }
}

