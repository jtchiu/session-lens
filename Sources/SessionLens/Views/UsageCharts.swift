import Charts
import SessionLensCore
import SwiftUI

struct UsageRateChart: View {
    let points: [QuotaHistoryPoint]
    let provider: ProviderID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("Usage Rate")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("of weekly limit")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Time", point.observedAt),
                        y: .value("Used", point.usedPercent)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.13), accent.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.observedAt),
                        y: .value("Used", point.usedPercent)
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXScale(range: .plotDimension(padding: 24))
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(SessionLensPalette.separator.opacity(0.45))
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text("\(percent)%")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 8))
                    }
                }
                .frame(height: 88)

                if points.count < 2 {
                    Text("Usage history appears after a few refreshes")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SessionLensSpacing.small)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Usage rate for \(provider.displayName)")
            .accessibilityValue(accessibilityValue)
        }
    }

    private var accent: Color {
        SessionLensPalette.accent(for: provider, scheme: colorScheme)
    }

    private var accessibilityValue: String {
        guard let latest = points.last else { return "Insufficient history" }
        return "Latest value \(Int(latest.usedPercent.rounded())) percent"
    }
}

struct DailyUsageChart: View {
    let snapshot: ProviderSnapshot
    @Binding var range: UsageChartRange

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
            HStack {
                Text("Daily Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Range", selection: $range) {
                    Text("7d").tag(UsageChartRange.sevenDays)
                    Text("30d").tag(UsageChartRange.thirtyDays)
                    Text("90d").tag(UsageChartRange.ninetyDays)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 132)
                .accessibilityLabel("Daily usage range")
            }

            ZStack {
                Chart(filteredBuckets) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Tokens", bucket.tokens)
                    )
                    .foregroundStyle(accent.opacity(isCurrentDay(bucket.day) ? 1 : 0.65))
                    .cornerRadius(2)
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .sevenDays ? 7 : 5)) {
                        value in
                        AxisValueLabel(format: range == .sevenDays ? .dateTime.weekday(.abbreviated) : .dateTime.month().day())
                            .font(.system(size: 8))
                    }
                }
                .frame(height: 92)

                if filteredBuckets.isEmpty {
                    Text("No daily usage in this range")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily usage for \(snapshot.provider.displayName)")
            .accessibilityValue("\(filteredBuckets.reduce(0) { $0 + $1.tokens }) tokens across \(filteredBuckets.count) days")
        }
    }

    private var filteredBuckets: [UsageBucket] {
        let calendar = Calendar.current
        let reference = snapshot.dailyBuckets.map(\.day).max() ?? Date()
        let end = calendar.startOfDay(for: reference)
        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: end
        ) ?? reference.addingTimeInterval(86_400)
        let start = calendar.date(
            byAdding: .day,
            value: -(range.days - 1),
            to: end
        ) ?? .distantPast
        return snapshot.dailyBuckets.filter {
            $0.day >= start && $0.day < endExclusive
        }
    }

    private var accent: Color {
        SessionLensPalette.accent(for: snapshot.provider, scheme: colorScheme)
    }

    private func isCurrentDay(_ date: Date) -> Bool {
        guard let latest = snapshot.dailyBuckets.map(\.day).max() else { return false }
        return Calendar.current.isDate(date, inSameDayAs: latest)
    }
}
