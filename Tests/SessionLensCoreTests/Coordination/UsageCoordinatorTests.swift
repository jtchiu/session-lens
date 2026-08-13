import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct UsageCoordinatorTests {
    @Test @MainActor
    func refreshRunsProvidersConcurrentlyAndReturnsAllStates() async throws {
        let providers: [any UsageProvider] = ProviderID.allCases.map {
            DelayedUsageProvider(id: $0, delay: .milliseconds(80))
        }
        let repository = try SnapshotRepository.inMemory()
        let coordinator = UsageCoordinator(
            providers: providers,
            repository: repository
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        let state = await coordinator.refresh(at: Fixtures.now)

        #expect(startedAt.duration(to: clock.now) < .milliseconds(180))
        #expect(state.snapshots.count == 3)
        #expect(await coordinator.currentState() == state)
    }

    @Test @MainActor
    func overlappingRefreshReturnsCurrentStateWithoutStartingMoreWork() async throws {
        let provider = CountingDelayedUsageProvider(
            id: .codex,
            delay: .milliseconds(100)
        )
        let coordinator = UsageCoordinator(
            providers: [provider],
            repository: try SnapshotRepository.inMemory()
        )

        let first = Task { await coordinator.refresh(at: Fixtures.now) }
        try await Task.sleep(for: .milliseconds(20))
        let overlapping = await coordinator.refresh(
            at: Fixtures.now.addingTimeInterval(1)
        )

        #expect(overlapping.snapshots.isEmpty)
        #expect(await provider.refreshCount() == 1)
        _ = await first.value
        #expect(await provider.refreshCount() == 1)
    }

    @Test @MainActor
    func failureRetainsLastGoodSnapshotAndMarksEveryQuotaStale() async throws {
        let good = Fixtures.codexSnapshot(observedAt: Fixtures.now)
        let provider = SequencedUsageProvider(
            id: .codex,
            snapshots: [
                good,
                .unavailable(
                    provider: .codex,
                    health: .timedOut,
                    observedAt: Fixtures.now.addingTimeInterval(600)
                ),
            ]
        )
        let coordinator = UsageCoordinator(
            providers: [provider],
            repository: try SnapshotRepository.inMemory()
        )
        _ = await coordinator.refresh(at: Fixtures.now)

        let failed = await coordinator.refresh(
            at: Fixtures.now.addingTimeInterval(600)
        )

        let snapshot = try #require(failed[.codex])
        #expect(snapshot.health == .stale)
        #expect(snapshot.tokens == good.tokens)
        #expect(snapshot.primaryQuota?.usedPercent == 36)
        #expect(snapshot.quotaWindows.allSatisfy { $0.provenance == .stale })
        #expect(snapshot.observedAt == good.observedAt)
    }

    @Test @MainActor
    func timeoutIsAppliedPerProviderAndReturnsWithinConfiguredBoundary() async throws {
        let coordinator = UsageCoordinator(
            providers: [
                NonCancellableUsageProvider(id: .codex, delayMilliseconds: 250)
            ],
            repository: try SnapshotRepository.inMemory(),
            providerTimeout: .milliseconds(30)
        )
        let clock = ContinuousClock()

        let startedAt = clock.now
        let state = await coordinator.refresh(at: Fixtures.now)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(elapsed < .milliseconds(300))
        #expect(state[.codex]?.health == .timedOut)
    }

    @Test @MainActor
    func schemaFailureRetainsMetricsButExposesActionableHealth() async throws {
        let good = Fixtures.codexSnapshot(observedAt: Fixtures.now)
        let provider = SequencedUsageProvider(
            id: .codex,
            snapshots: [
                good,
                .unavailable(
                    provider: .codex,
                    health: .malformedData,
                    observedAt: Fixtures.now.addingTimeInterval(60)
                ),
            ]
        )
        let coordinator = UsageCoordinator(
            providers: [provider],
            repository: try SnapshotRepository.inMemory()
        )

        _ = await coordinator.refresh(at: Fixtures.now)
        let state = await coordinator.refresh(
            at: Fixtures.now.addingTimeInterval(60)
        )

        #expect(state[.codex]?.health == .malformedData)
        #expect(state[.codex]?.tokens == good.tokens)
        #expect(state[.codex]?.quotaWindows == good.quotaWindows)
    }

    @Test @MainActor
    func firstFailureDoesNotFabricatePriorMetricsOrZeroes() async throws {
        let coordinator = UsageCoordinator(
            providers: [
                StaticUsageProvider(
                    snapshot: .unavailable(
                        provider: .claude,
                        health: .toolMissing,
                        observedAt: Fixtures.now
                    )
                )
            ],
            repository: try SnapshotRepository.inMemory()
        )

        let state = await coordinator.refresh(at: Fixtures.now)

        #expect(state[.claude]?.health == .toolMissing)
        #expect(state[.claude]?.tokens == nil)
        #expect(state[.claude]?.primaryQuota == nil)
        #expect(state[.claude]?.costDisplay == .unavailable)
    }

    @Test @MainActor
    func successfulRefreshPersistsTheNormalizedSnapshot() async throws {
        let repository = try SnapshotRepository.inMemory()
        let snapshot = Fixtures.codexSnapshot(observedAt: Fixtures.now)
        let coordinator = UsageCoordinator(
            providers: [StaticUsageProvider(snapshot: snapshot)],
            repository: repository
        )

        _ = await coordinator.refresh(at: Fixtures.now)

        #expect(try repository.latest(provider: .codex) == snapshot)
    }

    @Test @MainActor
    func openCodeQuotaIsNotAttributedWithoutExplicitMapping() async throws {
        let coordinator = UsageCoordinator(
            providers: [
                StaticUsageProvider(
                    snapshot: Fixtures.openCodeSnapshot(providerIDs: ["openai"])
                ),
                StaticUsageProvider(snapshot: Fixtures.codexSnapshot()),
            ],
            repository: try SnapshotRepository.inMemory(),
            settings: .defaults
        )

        let state = await coordinator.refresh(at: Fixtures.now)

        #expect(state[.opencode]?.quotaWindows.isEmpty == true)
    }

    @Test @MainActor
    func explicitOpenCodeMappingCopiesOnlyTheMappedExactQuota() async throws {
        var settings = AppSettings.defaults
        settings.setQuotaProvider(.codex, forOpenCodeProviderID: "openai")
        let coordinator = UsageCoordinator(
            providers: [
                StaticUsageProvider(
                    snapshot: Fixtures.openCodeSnapshot(
                        providerIDs: ["openai", "unmapped"]
                    )
                ),
                StaticUsageProvider(snapshot: Fixtures.codexSnapshot()),
            ],
            repository: try SnapshotRepository.inMemory(),
            settings: settings
        )

        let state = await coordinator.refresh(at: Fixtures.now)
        let quota = try #require(state[.opencode]?.primaryQuota)

        #expect(quota.label == "Codex Weekly")
        #expect(quota.usedPercent == 36)
        #expect(quota.provenance == .exactProvider)
        #expect(quota.id == "attributed-codex-weekly")
    }

    @Test @MainActor
    func localOpenCodeBudgetsProduceFiveHourAndWeeklyRowsWhenExactQuotaIsAbsent() async throws {
        var settings = AppSettings.defaults
        settings.setLocalBudget(
            OpenCodeLocalBudget(fiveHourUSD: 0.50, weeklyUSD: 1.00),
            forOpenCodeProviderID: "openai"
        )
        let coordinator = UsageCoordinator(
            providers: [
                StaticUsageProvider(
                    snapshot: Fixtures.openCodeSnapshot(providerIDs: ["openai"])
                )
            ],
            repository: try SnapshotRepository.inMemory(),
            settings: settings
        )

        let state = await coordinator.refresh(at: Fixtures.now)
        let windows = try #require(state[.opencode]?.quotaWindows)

        #expect(windows.map(\.label) == ["5-hour", "Weekly"])
        #expect(windows.allSatisfy { $0.provenance == .localBudget })
        #expect(windows[0].usedPercent == 50)
        #expect(windows[1].usedPercent == 25)
    }

    @Test @MainActor
    func exactOpenCodeAttributionTakesPrecedenceOverLocalBudget() async throws {
        var settings = AppSettings.defaults
        settings.setQuotaProvider(.codex, forOpenCodeProviderID: "openai")
        settings.setLocalBudget(
            OpenCodeLocalBudget(fiveHourUSD: 0.01, weeklyUSD: 0.01),
            forOpenCodeProviderID: "openai"
        )
        let coordinator = UsageCoordinator(
            providers: [
                StaticUsageProvider(
                    snapshot: Fixtures.openCodeSnapshot(providerIDs: ["openai"])
                ),
                StaticUsageProvider(snapshot: Fixtures.codexSnapshot()),
            ],
            repository: try SnapshotRepository.inMemory(),
            settings: settings
        )

        let state = await coordinator.refresh(at: Fixtures.now)
        let windows = try #require(state[.opencode]?.quotaWindows)

        #expect(windows.allSatisfy { $0.provenance == .exactProvider })
        #expect(windows.allSatisfy { !$0.id.hasPrefix("local-") })
    }
}

private struct StaticUsageProvider: UsageProvider {
    let snapshot: ProviderSnapshot
    var id: ProviderID { snapshot.provider }

    func refresh(at now: Date) async -> ProviderSnapshot { snapshot }
}

private struct DelayedUsageProvider: UsageProvider {
    let id: ProviderID
    let delay: Duration

    func refresh(at now: Date) async -> ProviderSnapshot {
        try? await Task.sleep(for: delay)
        return Fixtures.aggregateSnapshot(provider: id, observedAt: now)
    }
}

private struct NonCancellableUsageProvider: UsageProvider {
    let id: ProviderID
    let delayMilliseconds: Int

    func refresh(at now: Date) async -> ProviderSnapshot {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(delayMilliseconds)
            ) {
                continuation.resume(
                    returning: Fixtures.aggregateSnapshot(
                        provider: id,
                        observedAt: now
                    )
                )
            }
        }
    }
}

private actor CountingDelayedUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let delay: Duration
    private var count = 0

    init(id: ProviderID, delay: Duration) {
        self.id = id
        self.delay = delay
    }

    func refresh(at now: Date) async -> ProviderSnapshot {
        count += 1
        try? await Task.sleep(for: delay)
        return Fixtures.aggregateSnapshot(provider: id, observedAt: now)
    }

    func refreshCount() -> Int { count }
}

private actor SequencedUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var snapshots: [ProviderSnapshot]

    init(id: ProviderID, snapshots: [ProviderSnapshot]) {
        self.id = id
        self.snapshots = snapshots
    }

    func refresh(at now: Date) async -> ProviderSnapshot {
        guard !snapshots.isEmpty else {
            return .unavailable(
                provider: id,
                health: .temporarilyUnavailable,
                observedAt: now
            )
        }
        return snapshots.removeFirst()
    }
}
