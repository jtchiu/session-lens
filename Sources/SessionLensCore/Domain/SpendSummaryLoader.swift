import Foundation

public enum SpendSummaryLoader {
    public static func makeSummary(
        now: Date,
        historyRetentionDays: Int,
        snapshots: [ProviderID: ProviderSnapshot],
        dailyBuckets: [ProviderID: [UsageBucket]],
        samples: [ProviderSpendSample],
        calendar: Calendar = .current
    ) -> SpendSummary {
        let sampleProviders = Set(samples.map(\.provider))
        var providers = Set(ProviderID.allCases)
        providers.formUnion(snapshots.keys)
        providers.formUnion(dailyBuckets.keys)
        providers.formUnion(sampleProviders)

        var sources: [SpendSource] = []
        for provider in providers {
            let snapshot = snapshots[provider]
            let provenance = Self.provenance(for: snapshot, buckets: dailyBuckets[provider] ?? [])
            let includedWithPlan = snapshot?.costDisplay == .includedWithPlan
            if dailyBuckets[provider] != nil || includedWithPlan {
                sources.append(
                    .daily(
                        provider: provider,
                        buckets: dailyBuckets[provider] ?? [],
                        provenance: provenance,
                        includedWithPlan: includedWithPlan
                    )
                )
            }

            let providerSamples = samples.filter { $0.provider == provider }
            if !providerSamples.isEmpty {
                sources.append(
                    .samples(
                        provider: provider,
                        samples: providerSamples,
                        provenance: provenance
                    )
                )
            }
        }

        return SpendAggregator.makeSummary(
            now: now,
            historyRetentionDays: historyRetentionDays,
            sources: sources,
            calendar: calendar
        )
    }
}

private extension SpendSummaryLoader {
    static func provenance(
        for snapshot: ProviderSnapshot?,
        buckets: [UsageBucket]
    ) -> SpendProvenance {
        guard let snapshot else {
            return buckets.contains(where: { $0.costUSD != nil })
                ? .exact
                : .unavailable
        }
        switch snapshot.costDisplay {
        case .exactUSD:
            return .exact
        case .estimatedUSD:
            return .estimated
        case .includedWithPlan:
            return .includedWithPlan
        case .unavailable:
            return .unavailable
        }
    }
}
