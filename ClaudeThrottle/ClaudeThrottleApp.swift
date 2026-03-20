import SwiftUI
import WidgetKit

@main
struct ClaudeThrottleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 400, height: 300)
    }
}

struct ContentView: View {
    @State private var status = ThrottleCalculator().calculate()
    @State private var planUsage: PlanUsage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let calculator = ThrottleCalculator()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // Throttle status
            HStack {
                Circle()
                    .fill(status.is2x && status.isPromoActive ? .green : .orange)
                    .frame(width: 10, height: 10)
                Text(status.statusText)
                    .font(.title2.bold())
                Spacer()
                if status.countdownSeconds > 0 {
                    Text("\(status.countdownLabel): \(status.countdownFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Plan usage
            if let usage = planUsage {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Plan Usage Limits")
                        .font(.headline)

                    UsageBar(label: "Current Session",
                             used: usage.sessionPercent,
                             detail: "Resets in \(usage.sessionResetFormatted)")
                    UsageBar(label: "Weekly - All Models",
                             used: usage.weeklyAllPercent,
                             detail: "Resets \(usage.weeklyAllResetFormatted)")
                    UsageBar(label: "Weekly - Sonnet",
                             used: usage.weeklySonnetPercent,
                             detail: "Resets in \(usage.weeklySonnetResetFormatted)")

                    HStack {
                        Text("Updated \(usage.fetchedAgo)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Refresh") {
                            Task { await fetchUsage() }
                        }
                        .disabled(isLoading)
                    }
                }
            } else if isLoading {
                ProgressView("Fetching usage...")
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await fetchUsage() }
                    }
                }
            }
        }
        .padding()
        .onReceive(timer) { _ in
            status = calculator.calculate()
        }
        .task {
            await fetchUsage()
        }
    }

    private func fetchUsage() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetcher = ClaudeUsageFetcher()
            let usage = try await fetcher.fetchUsage()
            planUsage = usage
            SharedDataStore.savePlanUsage(usage)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
            // Try loading cached data
            if planUsage == nil {
                planUsage = SharedDataStore.loadPlanUsage()
            }
        }
        isLoading = false
    }
}

struct UsageBar: View {
    let label: String
    let used: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                Spacer()
                Text(String(format: "%.0f%% used", min(used, 100)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * min(used, 100) / 100))
                }
            }
            .frame(height: 6)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var barColor: Color {
        if used > 80 { return .red }
        if used > 50 { return .orange }
        return .blue
    }
}
