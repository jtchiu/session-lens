import Foundation

public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let store: any ClaudeCacheStoring
    private let staleAfter: TimeInterval

    public init(
        store: any ClaudeCacheStoring = ClaudeBridgeStore.live,
        staleAfter: TimeInterval = 300
    ) {
        self.store = store
        self.staleAfter = staleAfter
    }

    public func refresh(at now: Date) async -> ProviderSnapshot {
        do {
            guard let cache = try store.read() else {
                return .unavailable(
                    provider: id,
                    health: .setupRequired,
                    observedAt: now
                )
            }
            return snapshot(cache: cache, now: now)
        } catch {
            return .unavailable(
                provider: id,
                health: .malformedData,
                observedAt: now
            )
        }
    }

    private func snapshot(
        cache: ClaudeNormalizedCache,
        now: Date
    ) -> ProviderSnapshot {
        let isStale = now.timeIntervalSince(cache.observedAt) > staleAfter
        let provenance: MetricProvenance = isStale ? .stale : .exactProvider
        let quotas = [
            quota(
                cache.fiveHour,
                id: "five-hour",
                label: "5-hour",
                durationMinutes: 300,
                provenance: provenance
            ),
            quota(
                cache.sevenDay,
                id: "seven-day",
                label: "Weekly",
                durationMinutes: 10_080,
                provenance: provenance
            ),
        ].compactMap { $0 }
        let costDisplay = cache.estimatedSessionCostUSD.map {
            CostDisplay.estimatedUSD(max(0, $0))
        } ?? .unavailable
        let modelBreakdowns: [ModelUsage]
        if let modelID = cache.modelID, let tokens = cache.contextTokens {
            modelBreakdowns = [
                ModelUsage(
                    providerID: "anthropic",
                    modelID: modelID,
                    tokens: tokens,
                    costUSD: cache.estimatedSessionCostUSD
                )
            ]
        } else {
            modelBreakdowns = []
        }

        return ProviderSnapshot(
            provider: id,
            observedAt: cache.observedAt,
            health: isStale ? .stale : .ready,
            tokens: cache.contextTokens,
            costDisplay: costDisplay,
            dailyBuckets: [],
            quotaWindows: quotas,
            modelBreakdowns: modelBreakdowns
        )
    }

    private func quota(
        _ source: ClaudeNormalizedRateLimit?,
        id: String,
        label: String,
        durationMinutes: Int,
        provenance: MetricProvenance
    ) -> QuotaWindow? {
        guard let source else { return nil }
        return QuotaWindow(
            id: id,
            label: label,
            durationMinutes: durationMinutes,
            usedPercent: source.usedPercent,
            resetsAt: source.resetsAt,
            provenance: provenance
        )
    }
}
