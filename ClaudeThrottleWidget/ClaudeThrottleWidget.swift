import WidgetKit
import SwiftUI

struct ThrottleEntry: TimelineEntry {
    let date: Date
    let status: ThrottleStatus
    let planUsage: PlanUsage?
}

struct ThrottleTimelineProvider: TimelineProvider {
    private let calculator = ThrottleCalculator()

    func placeholder(in context: Context) -> ThrottleEntry {
        ThrottleEntry(date: .now, status: calculator.calculate(), planUsage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ThrottleEntry) -> Void) {
        let usage = SharedDataStore.loadPlanUsage()
        completion(ThrottleEntry(date: .now, status: calculator.calculate(), planUsage: usage))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ThrottleEntry>) -> Void) {
        let now = Date()
        let status = calculator.calculate(at: now)

        Task {
            var planUsage = SharedDataStore.loadPlanUsage()

            // Fetch fresh usage data
            let fetcher = ClaudeUsageFetcher()
            if let fresh = try? await fetcher.fetchUsage() {
                planUsage = fresh
                SharedDataStore.savePlanUsage(fresh)
            }

            let entry = ThrottleEntry(date: now, status: status, planUsage: planUsage)
            let nextTransition = calculator.nextTransitionDate(after: now)
            let fiveMin = now.addingTimeInterval(5 * 60)
            let refreshDate = min(nextTransition, fiveMin)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }
}

// MARK: - Widget View

struct ClaudeThrottleWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ThrottleEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "gauge.high")
                    .font(.system(size: 11, weight: .semibold))
                Text("Claude")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if entry.status.isPromoActive {
                    Text(entry.status.is2x ? "2X" : "1X")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.status.is2x ? .green : .orange)
                }
            }
            .foregroundStyle(.secondary)

            if let usage = entry.planUsage {
                Spacer()

                MiniUsageBar(label: "Session",
                             percent: usage.sessionPercent,
                             resetText: "Resets \(usage.sessionResetFormatted)")
                MiniUsageBar(label: "Weekly",
                             percent: usage.weeklyAllPercent,
                             resetText: "Resets \(usage.weeklyAllResetFormatted)")
                MiniUsageBar(label: "Sonnet",
                             percent: usage.weeklySonnetPercent,
                             resetText: "Resets \(usage.weeklySonnetResetFormatted)")

                Spacer()

                HStack {
                    if entry.status.countdownSeconds > 0 && entry.status.isPromoActive {
                        Text("\(entry.status.countdownLabel): \(entry.status.countdownFormatted)")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(usage.fetchedAgo)
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
            } else {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(rateLabel)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                if entry.status.countdownSeconds > 0 {
                    Text(entry.status.countdownLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(entry.status.countdownFormatted)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(alignment: .center, spacing: 14) {
            // Left: throttle status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(rateLabel)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }

                Text(entry.status.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if entry.status.countdownSeconds > 0 {
                    Text(entry.status.countdownFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 85)

            // Right: plan usage
            if let usage = entry.planUsage {
                VStack(alignment: .leading, spacing: 10) {
                    CompactBar(label: "Session", percent: usage.sessionPercent)
                    CompactBar(label: "Weekly", percent: usage.weeklyAllPercent)
                    CompactBar(label: "Sonnet", percent: usage.weeklySonnetPercent)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Text("Needs Claude Code")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private var rateLabel: String {
        if !entry.status.isPromoActive { return "1X" }
        return entry.status.is2x ? "2X" : "1X"
    }

    private var statusColor: Color {
        if !entry.status.isPromoActive { return .gray }
        return entry.status.is2x ? .green : .orange
    }
}

// MARK: - Usage Bar Components

struct MiniUsageBar: View {
    let label: String
    let percent: Double
    var resetText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", min(percent, 100)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(percent))
                        .frame(width: max(0, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(height: 4)
        }
    }
}

struct CompactBar: View {
    let label: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text(String(format: "%.0f%%", min(percent, 100)))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(barColor(percent))
                        .frame(width: max(0, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

private func barColor(_ percent: Double) -> Color {
    if percent > 80 { return .red }
    if percent > 50 { return .orange }
    return .blue
}

// MARK: - Widget Definition

struct ClaudeThrottleWidget: Widget {
    let kind: String = "ClaudeThrottleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThrottleTimelineProvider()) { entry in
            ClaudeThrottleWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Throttle")
        .description("Claude plan usage and 2X rate status")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
