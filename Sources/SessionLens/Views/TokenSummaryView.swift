import SessionLensCore
import SwiftUI

struct TokenSummaryView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Token Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Today")
                    .frame(width: 76, alignment: .trailing)
                Text("Last 7 Days")
                    .frame(width: 92, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.bottom, SessionLensSpacing.xSmall)

            metricRow(
                label: "Total Tokens",
                today: compact(todayTokens),
                week: compact(weekTokens),
                todayAccessibility: "\(todayTokens) tokens today",
                weekAccessibility: "\(weekTokens) tokens in the last seven days"
            )

            Divider()

            HStack {
                Text("Cost")
                Spacer()
                Text(costText)
                    .foregroundStyle(costIsUnavailable ? .secondary : .primary)
            }
            .font(.system(size: 11))
            .frame(minHeight: 25)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cost, \(costAccessibility)")

            if let tokens = snapshot.tokens {
                Divider()
                VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
                    Text("Token Detail")
                        .font(.system(size: 11, weight: .semibold))
                    detailRow("Input", tokens.input)
                    detailRow("Output", tokens.output)
                    detailRow("Reasoning", tokens.reasoning)
                    detailRow("Cache read", tokens.cacheRead)
                    detailRow("Cache write", tokens.cacheWrite)
                }
                .font(.system(size: 10))
                .padding(.vertical, SessionLensSpacing.xSmall)
            }

            if !snapshot.modelBreakdowns.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
                    Text("Model Breakdown")
                        .font(.system(size: 11, weight: .semibold))
                    ForEach(snapshot.modelBreakdowns.prefix(6)) { model in
                        HStack {
                            Text(modelLabel(model))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(compact(model.tokens.total))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .font(.system(size: 10))
                .padding(.vertical, SessionLensSpacing.xSmall)
            }
        }
    }

    private func detailRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(compact(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func modelLabel(_ model: ModelUsage) -> String {
        if let providerID = model.providerID, !providerID.isEmpty {
            return "\(providerID) · \(model.modelID)"
        }
        return model.modelID
    }

    private func metricRow(
        label: String,
        today: String,
        week: String,
        todayAccessibility: String,
        weekAccessibility: String
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(today)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
                .accessibilityLabel(todayAccessibility)
            Text(week)
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)
                .accessibilityLabel(weekAccessibility)
        }
        .font(.system(size: 11))
        .frame(minHeight: 25)
    }

    private var todayTokens: Int {
        guard let latest = snapshot.dailyBuckets.map(\.day).max() else { return 0 }
        return snapshot.dailyBuckets
            .filter { Calendar.current.isDate($0.day, inSameDayAs: latest) }
            .reduce(0) { $0 + $1.tokens }
    }

    private var weekTokens: Int {
        guard let latest = snapshot.dailyBuckets.map(\.day).max(),
            let start = Calendar.current.date(
                byAdding: .day,
                value: -6,
                to: Calendar.current.startOfDay(for: latest)
            )
        else {
            return 0
        }
        return snapshot.dailyBuckets
            .filter { $0.day >= start && $0.day <= latest }
            .reduce(0) { $0 + $1.tokens }
    }

    private var costText: String {
        switch snapshot.costDisplay {
        case let .exactUSD(value): value.formatted(.currency(code: "USD"))
        case let .estimatedUSD(value):
            "Estimated \(value.formatted(.currency(code: "USD")))"
        case .includedWithPlan: "Included with plan"
        case .unavailable: "—"
        }
    }

    private var costAccessibility: String {
        switch snapshot.costDisplay {
        case let .exactUSD(value):
            "exact local aggregate, \(value.formatted(.currency(code: "USD")))"
        case let .estimatedUSD(value):
            "estimated session cost, \(value.formatted(.currency(code: "USD")))"
        case .includedWithPlan: "included with plan"
        case .unavailable: "unavailable"
        }
    }

    private var costIsUnavailable: Bool {
        snapshot.costDisplay == .unavailable
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return String(value)
    }
}
