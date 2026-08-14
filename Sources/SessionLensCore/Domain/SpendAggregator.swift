import Foundation

public enum SpendAggregator {
    public static func makeSummary(
        now: Date,
        historyRetentionDays: Int,
        sources: [SpendSource],
        calendar: Calendar = .current
    ) -> SpendSummary {
        let retentionDays = min(3_650, max(7, historyRetentionDays))
        let day = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? day
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? day
        let retainedStart = calendar.date(
            byAdding: .day,
            value: -(retentionDays - 1),
            to: day
        ) ?? day

        var contributionsByProvider: [ProviderID: ProviderAccumulator] = [:]
        for source in sources {
            let provider: ProviderID
            let contributions: [Contribution]
            let includedWithPlan: Bool
            switch source {
            case let .dailyBuckets(sourceProvider, buckets, provenance, included):
                provider = sourceProvider
                includedWithPlan = included
                contributions = buckets.map {
                    Contribution(
                        day: calendar.startOfDay(for: $0.day),
                        costUSD: normalizedCost($0.costUSD),
                        tokens: max(0, $0.tokens),
                        tokenCountIsKnown: true,
                        provenance: provenance
                    )
                }
            case let .cumulativeSamples(sourceProvider, samples, provenance):
                provider = sourceProvider
                includedWithPlan = false
                contributions = cumulativeContributions(
                    samples: samples,
                    fallbackProvenance: provenance,
                    calendar: calendar
                )
            }

            var accumulator = contributionsByProvider[provider] ?? ProviderAccumulator(
                provider: provider,
                includedWithPlan: includedWithPlan
            )
            accumulator.includedWithPlan = accumulator.includedWithPlan || includedWithPlan
            accumulator.contributions.append(contentsOf: contributions)
            contributionsByProvider[provider] = accumulator
        }

        let providers = contributionsByProvider.mapValues { accumulator in
            ProviderSpendSummary(
                provider: accumulator.provider,
                periods: SpendPeriods(
                    week: accumulator.value(
                        range: weekStart...now,
                        calendar: calendar
                    ),
                    month: accumulator.value(
                        range: monthStart...now,
                        calendar: calendar
                    ),
                    retained: accumulator.value(
                        range: retainedStart...now,
                        calendar: calendar
                    )
                )
            )
        }

        let combined = SpendPeriods(
            week: combinedValue(providers.values.map(\.week)),
            month: combinedValue(providers.values.map(\.month)),
            retained: combinedValue(providers.values.map(\.retained))
        )
        return SpendSummary(
            providers: providers,
            combined: combined,
            retentionDays: retentionDays
        )
    }
}

private extension SpendAggregator {
    struct Contribution: Sendable {
        let day: Date
        let costUSD: Double?
        let tokens: Int
        let tokenCountIsKnown: Bool
        let provenance: SpendProvenance
    }

    struct ProviderAccumulator: Sendable {
        let provider: ProviderID
        var includedWithPlan: Bool
        var contributions: [Contribution] = []

        func value(
            range: ClosedRange<Date>,
            calendar: Calendar
        ) -> SpendValue {
            let matching = contributions.filter {
                range.contains($0.day)
            }
            let costContributions = matching.filter { $0.costUSD != nil }
            let cost = costContributions.reduce(0.0) {
                $0 + ($1.costUSD ?? 0)
            }
            let hasCost = !costContributions.isEmpty
            let tokensKnown = !costContributions.contains {
                !$0.tokenCountIsKnown
            }
            let tokens: Int?
            if hasCost, tokensKnown {
                tokens = costContributions.reduce(0) { $0 + $1.tokens }
            } else if !hasCost && includedWithPlan {
                tokens = matching.reduce(0) { $0 + $1.tokens }
            } else if !hasCost {
                tokens = matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.tokens }
            } else {
                tokens = nil
            }

            let provenance: SpendProvenance
            if hasCost {
                provenance = mergedProvenance(
                    costContributions.map(\.provenance)
                )
            } else if includedWithPlan {
                provenance = .includedWithPlan
            } else {
                provenance = matching.isEmpty ? .unavailable : .unavailable
            }
            return SpendValue(
                costUSD: hasCost ? cost : nil,
                tokens: tokens,
                provenance: provenance
            )
        }
    }

    static func cumulativeContributions(
        samples: [ProviderSpendSample],
        fallbackProvenance: SpendProvenance,
        calendar: Calendar
    ) -> [Contribution] {
        let grouped = Dictionary(grouping: samples) { $0.scopeID ?? "-" }
        return grouped.values.flatMap { scopeSamples in
            let sorted = scopeSamples.sorted { $0.observedAt < $1.observedAt }
            guard let first = sorted.first else { return [Contribution]() }
            var previousCost = first.cumulativeCostUSD
            var previousTokens = first.cumulativeTokens
            var output: [Contribution] = []
            for sample in sorted.dropFirst() {
                let costDelta = delta(current: sample.cumulativeCostUSD, previous: previousCost)
                let tokenDelta = delta(current: sample.cumulativeTokens, previous: previousTokens)
                let counterReset = isLower(sample.cumulativeCostUSD, than: previousCost)
                    || isLower(sample.cumulativeTokens, than: previousTokens)
                previousCost = sample.cumulativeCostUSD
                previousTokens = sample.cumulativeTokens
                if counterReset {
                    continue
                }

                let hasCostDelta = (costDelta ?? 0) > 0
                let hasTokenDelta = (tokenDelta ?? 0) > 0
                guard hasCostDelta || hasTokenDelta else { continue }
                output.append(
                    Contribution(
                        day: calendar.startOfDay(for: sample.observedAt),
                        costUSD: hasCostDelta ? costDelta : nil,
                        tokens: tokenDelta ?? 0,
                        tokenCountIsKnown: !hasCostDelta || tokenDelta != nil,
                        provenance: sample.provenance == .unavailable
                            ? fallbackProvenance
                            : sample.provenance
                    )
                )
            }
            return output
        }
    }

    static func combinedValue<S: Sequence>(_ values: S) -> SpendValue
    where S.Element == SpendValue {
        let dollarValues = values.filter { $0.costUSD != nil }
        guard !dollarValues.isEmpty else { return .unavailable }
        let cost = dollarValues.reduce(0.0) { $0 + ($1.costUSD ?? 0) }
        let tokens: Int?
        if dollarValues.allSatisfy({ $0.tokens != nil }) {
            tokens = dollarValues.reduce(0) { $0 + ($1.tokens ?? 0) }
        } else {
            tokens = nil
        }
        return SpendValue(
            costUSD: cost,
            tokens: tokens,
            provenance: mergedProvenance(dollarValues.map(\.provenance))
        )
    }

    static func mergedProvenance(_ values: [SpendProvenance]) -> SpendProvenance {
        let meaningful = Set(values.filter {
            $0 == .exact || $0 == .estimated || $0 == .mixed
        })
        if meaningful.contains(.mixed) || meaningful.count > 1 {
            return .mixed
        }
        return meaningful.first ?? .unavailable
    }

    static func normalizedCost(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    static func delta<T: BinaryInteger>(
        current: T?,
        previous: T?
    ) -> Int? {
        guard let current, let previous, current >= previous else { return nil }
        return Int(current - previous)
    }

    static func delta(
        current: Double?,
        previous: Double?
    ) -> Double? {
        guard let current, let previous, current.isFinite, previous.isFinite,
            current >= previous
        else { return nil }
        return max(0, current - previous)
    }

    static func isLower<T: Comparable>(_ current: T?, than previous: T?) -> Bool {
        guard let current, let previous else { return false }
        return current < previous
    }
}
