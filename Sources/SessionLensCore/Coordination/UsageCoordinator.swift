import Foundation

public actor UsageCoordinator {
    private let providers: [any UsageProvider]
    private let repository: any SnapshotPersisting
    private var state = UsageState()
    private var settings: AppSettings
    private var isRefreshing = false
    private let providerTimeout: Duration

    public init(
        providers: [any UsageProvider],
        repository: any SnapshotPersisting,
        settings: AppSettings = .defaults,
        initialState: UsageState = UsageState(),
        providerTimeout: Duration = .seconds(8)
    ) {
        self.providers = providers
        self.repository = repository
        self.settings = settings
        self.state = initialState
        self.providerTimeout = providerTimeout
    }

    public func currentState() -> UsageState { state }

    public func currentSettings() -> AppSettings { settings }

    public func shutdown() async {
        for provider in providers {
            if let stoppable = provider as? any StoppableUsageProvider {
                await stoppable.shutdown()
            }
        }
    }

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
                    await Self.refresh(
                        provider: provider,
                        at: now,
                        timeout: self.providerTimeout
                    )
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
            case .timedOut:
                if let previous = state[snapshot.provider],
                    previous.health == .ready || previous.health == .stale
                {
                    next.snapshots[snapshot.provider] = previous.markingStale()
                } else {
                    next.snapshots[snapshot.provider] = snapshot
                }
            case .setupRequired, .toolMissing, .malformedData,
                .temporarilyUnavailable:
                if let previous = state[snapshot.provider],
                    previous.health == .ready || previous.health == .stale
                {
                    next.snapshots[snapshot.provider] = previous.retainMetrics(
                        health: snapshot.health,
                        diagnostic: snapshot.diagnostic
                    )
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

    private static func refresh(
        provider: any UsageProvider,
        at now: Date,
        timeout: Duration
    ) async -> ProviderSnapshot {
        let providerTask = Task {
            await provider.refresh(at: now)
        }
        let gate = SnapshotResultGate()
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: max(.zero, timeout))
            } catch {
                return
            }
            providerTask.cancel()
            if let stoppable = provider as? any StoppableUsageProvider {
                await stoppable.shutdown()
            }
            gate.resolve(
                .unavailable(
                    provider: provider.id,
                    health: .timedOut,
                    observedAt: now
                )
            )
        }
        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<ProviderSnapshot, Never>) in
            gate.install(continuation)
            Task {
                gate.resolve(await providerTask.value)
            }
        }
        timeoutTask.cancel()
        return result
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

        let exactWindows = attributed
        let localWindows = exactWindows.isEmpty
            ? Self.localBudgetWindows(for: openCode, settings: settings)
            : []

        output.snapshots[.opencode] = ProviderSnapshot(
            provider: .opencode,
            observedAt: openCode.observedAt,
            health: openCode.health,
            tokens: openCode.tokens,
            costDisplay: openCode.costDisplay,
            dailyBuckets: openCode.dailyBuckets,
            quotaWindows: exactWindows.isEmpty ? localWindows : exactWindows,
            modelBreakdowns: openCode.modelBreakdowns
        )
        return output
    }

    private static func localBudgetWindows(
        for openCode: ProviderSnapshot,
        settings: AppSettings
    ) -> [QuotaWindow] {
        guard !settings.localBudgets.isEmpty else { return [] }

        let modelProviderIDs = Set(
            openCode.modelBreakdowns.compactMap(\.providerID)
        )
        let configured = settings.localBudgets.filter { providerID, _ in
            providerID == "*" || modelProviderIDs.contains(providerID)
        }
        guard !configured.isEmpty else { return [] }

        let weeklyCost = openCode.dailyBuckets.reduce(0.0) { total, bucket in
            guard bucket.day >= openCode.observedAt.addingTimeInterval(-7 * 86_400)
            else { return total }
            return total + (bucket.costUSD ?? 0)
        }
        let fiveHourCost = openCode.dailyBuckets
            .filter {
                Calendar.current.isDate($0.day, inSameDayAs: openCode.observedAt)
            }
            .reduce(0.0) { $0 + ($1.costUSD ?? 0) }

        let budget = configured.values.reduce(
            OpenCodeLocalBudget(),
            Self.mergeBudgets
        )
        return [
            Self.localWindow(
                id: "local-five-hour",
                label: "5-hour",
                duration: 300,
                used: fiveHourCost,
                limit: budget.fiveHourUSD,
                observedAt: openCode.observedAt
            ),
            Self.localWindow(
                id: "local-weekly",
                label: "Weekly",
                duration: 10_080,
                used: weeklyCost,
                limit: budget.weeklyUSD,
                observedAt: openCode.observedAt
            ),
        ].compactMap { $0 }
    }

    private static func mergeBudgets(
        _ lhs: OpenCodeLocalBudget,
        _ rhs: OpenCodeLocalBudget
    ) -> OpenCodeLocalBudget {
        OpenCodeLocalBudget(
            fiveHourUSD: lhs.fiveHourUSD ?? rhs.fiveHourUSD,
            weeklyUSD: lhs.weeklyUSD ?? rhs.weeklyUSD
        )
    }

    private static func localWindow(
        id: String,
        label: String,
        duration: Int,
        used: Double,
        limit: Double?,
        observedAt: Date
    ) -> QuotaWindow? {
        guard let limit, limit > 0 else { return nil }
        return QuotaWindow(
            id: id,
            label: label,
            durationMinutes: duration,
            usedPercent: min(100, max(0, used / limit * 100)),
            resetsAt: observedAt.addingTimeInterval(Double(duration) * 60),
            provenance: .localBudget
        )
    }
}

private extension ProviderSnapshot {
    func retainMetrics(
        health: ProviderHealth,
        diagnostic: String?
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            observedAt: observedAt,
            health: health,
            tokens: tokens,
            costDisplay: costDisplay,
            dailyBuckets: dailyBuckets,
            quotaWindows: quotaWindows,
            modelBreakdowns: modelBreakdowns,
            diagnostic: diagnostic,
            costSample: costSample
        )
    }

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
            modelBreakdowns: modelBreakdowns,
            diagnostic: diagnostic,
            costSample: costSample
        )
    }
}

private final class SnapshotResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProviderSnapshot, Never>?
    private var result: ProviderSnapshot?

    func install(
        _ continuation: CheckedContinuation<ProviderSnapshot, Never>
    ) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resolve(_ result: ProviderSnapshot) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
