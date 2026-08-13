import Foundation

public actor UsageCoordinator {
    private let providers: [any UsageProvider]
    private let repository: any SnapshotPersisting
    private var state = UsageState()
    private var settings: AppSettings
    private var isRefreshing = false

    public init(
        providers: [any UsageProvider],
        repository: any SnapshotPersisting,
        settings: AppSettings = .defaults
    ) {
        self.providers = providers
        self.repository = repository
        self.settings = settings
    }

    public func currentState() -> UsageState { state }

    public func currentSettings() -> AppSettings { settings }

    public func updateSettings(_ newSettings: AppSettings) async {
        settings = newSettings
        state = Self.attributingOpenCodeQuota(
            in: state,
            settings: newSettings
        )
        try? await repository.saveSettings(newSettings)
    }

    public func refresh(at now: Date = Date()) async -> UsageState {
        guard !isRefreshing else { return state }
        isRefreshing = true
        defer { isRefreshing = false }

        let results = await withTaskGroup(
            of: ProviderSnapshot.self,
            returning: [ProviderSnapshot].self
        ) { group in
            for provider in providers {
                group.addTask {
                    await provider.refresh(at: now)
                }
            }

            var snapshots: [ProviderSnapshot] = []
            for await snapshot in group {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        var next = state
        var successfulProviders = Set<ProviderID>()
        for snapshot in results {
            switch snapshot.health {
            case .ready:
                next.snapshots[snapshot.provider] = snapshot
                successfulProviders.insert(snapshot.provider)
            case .stale:
                next.snapshots[snapshot.provider] = snapshot
            case .setupRequired, .toolMissing, .malformedData, .timedOut,
                .temporarilyUnavailable:
                if let previous = state[snapshot.provider],
                    previous.health == .ready || previous.health == .stale
                {
                    next.snapshots[snapshot.provider] = previous.markingStale()
                } else {
                    next.snapshots[snapshot.provider] = snapshot
                }
            }
        }

        next = Self.attributingOpenCodeQuota(in: next, settings: settings)
        state = next

        for provider in successfulProviders {
            if let snapshot = next[provider] {
                try? await repository.record(snapshot)
            }
        }
        return next
    }

    private static func attributingOpenCodeQuota(
        in input: UsageState,
        settings: AppSettings
    ) -> UsageState {
        guard let openCode = input[.opencode] else { return input }
        var output = input

        let mappedProviders = Set(
            openCode.modelBreakdowns.compactMap { breakdown in
                breakdown.providerID.flatMap {
                    settings.quotaProvider(forOpenCodeProviderID: $0)
                }
            }
        )
        let orderedTargets = settings.providerOrder.filter {
            mappedProviders.contains($0) && $0 != .opencode
        }
        let attributed: [QuotaWindow] = orderedTargets.flatMap {
            target -> [QuotaWindow] in
            (input[target]?.quotaWindows ?? []).compactMap { window in
                guard window.provenance == .exactProvider
                    || window.provenance == .stale
                else {
                    return nil
                }
                return QuotaWindow(
                    id: "attributed-\(target.rawValue)-\(window.id)",
                    label: "\(target.displayName) \(window.label)",
                    durationMinutes: window.durationMinutes,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt,
                    provenance: window.provenance
                )
            }
        }

        output.snapshots[.opencode] = ProviderSnapshot(
            provider: .opencode,
            observedAt: openCode.observedAt,
            health: openCode.health,
            tokens: openCode.tokens,
            costDisplay: openCode.costDisplay,
            dailyBuckets: openCode.dailyBuckets,
            quotaWindows: attributed,
            modelBreakdowns: openCode.modelBreakdowns
        )
        return output
    }
}

private extension ProviderSnapshot {
    func markingStale() -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            observedAt: observedAt,
            health: .stale,
            tokens: tokens,
            costDisplay: costDisplay,
            dailyBuckets: dailyBuckets,
            quotaWindows: quotaWindows.map {
                QuotaWindow(
                    id: $0.id,
                    label: $0.label,
                    durationMinutes: $0.durationMinutes,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt,
                    provenance: .stale
                )
            },
            modelBreakdowns: modelBreakdowns
        )
    }
}
