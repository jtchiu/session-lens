import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct NotificationEvaluatorTests {
    @Test
    func thresholdFiresOnlyOnFirstCrossingFromThePreviousValue() {
        let evaluator = NotificationEvaluator()

        let crossing = evaluator.events(
            provider: .codex,
            previous: quota(69),
            current: quota(71),
            thresholds: [70]
        )
        let alreadyAbove = evaluator.events(
            provider: .codex,
            previous: quota(71),
            current: quota(75),
            thresholds: [70]
        )

        #expect(crossing.map(\.kind) == [.threshold(70)])
        #expect(alreadyAbove.isEmpty)
    }

    @Test
    func initialAboveThresholdDoesNotPretendACrossingOccurred() {
        let events = NotificationEvaluator().events(
            provider: .codex,
            previous: nil,
            current: quota(91),
            thresholds: [70, 90]
        )

        #expect(events.isEmpty)
    }

    @Test
    func resetFiresAfterPreviouslyNonzeroWindowMovesToNewEpoch() {
        let events = NotificationEvaluator().events(
            provider: .codex,
            previous: quota(92, reset: Fixtures.day(2)),
            current: quota(0, reset: Fixtures.day(9)),
            thresholds: [70, 90]
        )

        #expect(events.map(\.kind) == [.reset])
    }

    @Test
    func unchangedResetEpochDoesNotFireReset() {
        let reset = Fixtures.day(2)
        let events = NotificationEvaluator().events(
            provider: .codex,
            previous: quota(92, reset: reset),
            current: quota(0, reset: reset),
            thresholds: [70, 90]
        )

        #expect(events.isEmpty)
    }

    @Test
    func staleUnavailableAndEstimatedQuotasNeverNotify() {
        let evaluator = NotificationEvaluator()

        for provenance in [
            MetricProvenance.stale,
            .unavailable,
            .estimated,
            .exactLocalAggregate,
        ] {
            let events = evaluator.events(
                provider: .claude,
                previous: quota(69, provenance: provenance),
                current: quota(91, provenance: provenance),
                thresholds: [70, 90]
            )
            #expect(events.isEmpty)
        }
    }

    @Test
    func snapshotEvaluationMatchesWindowsByIdentity() {
        let evaluator = NotificationEvaluator()
        let previous = snapshot(
            quotas: [quota(69, id: "five-hour"), quota(91, id: "weekly")]
        )
        let current = snapshot(
            quotas: [quota(71, id: "five-hour"), quota(92, id: "weekly")]
        )

        let events = evaluator.events(
            provider: .codex,
            previous: previous,
            current: current,
            thresholds: [70, 90]
        )

        #expect(events.map(\.kind) == [.threshold(70)])
        #expect(events.map(\.quotaID) == ["five-hour"])
    }

    @Test
    func eventKeyContainsScopeWindowKindAndResetEpoch() throws {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let event = try #require(
            NotificationEvaluator().events(
                provider: .codex,
                accountScopeHash: "abc123",
                previous: quota(69, id: "weekly", reset: reset),
                current: quota(71, id: "weekly", reset: reset),
                thresholds: [70]
            ).first
        )

        #expect(
            event.key
                == "codex:abc123:weekly:threshold-70:1700000000"
        )
    }

    @Test
    func recrossingWithinSameEpochUsesSameDurableDeduplicationKey() throws {
        let evaluator = NotificationEvaluator()
        let reset = Fixtures.day(2)
        let first = try #require(
            evaluator.events(
                provider: .codex,
                previous: quota(69, reset: reset),
                current: quota(71, reset: reset),
                thresholds: [70]
            ).first
        )
        let recross = try #require(
            evaluator.events(
                provider: .codex,
                previous: quota(68, reset: reset),
                current: quota(72, reset: reset),
                thresholds: [70]
            ).first
        )
        let newEpoch = try #require(
            evaluator.events(
                provider: .codex,
                previous: quota(69, reset: Fixtures.day(9)),
                current: quota(71, reset: Fixtures.day(9)),
                thresholds: [70]
            ).first
        )

        #expect(first.key == recross.key)
        #expect(newEpoch.key != first.key)
    }

    @Test
    func localBudgetNotificationIsLabeledHonestly() throws {
        let event = try #require(
            NotificationEvaluator().events(
                provider: .opencode,
                previous: quota(69, provenance: .localBudget),
                current: quota(71, provenance: .localBudget),
                thresholds: [70]
            ).first
        )

        #expect(event.title.contains("Local budget"))
        #expect(event.provenance == .localBudget)
    }

    @Test @MainActor
    func schedulerDeduplicatesWithoutRequestingPermissionImplicitly() async throws {
        let repository = try SnapshotRepository.inMemory()
        let delivery = FakeNotificationDelivery()
        let scheduler = NotificationScheduler(
            repository: repository,
            delivery: delivery
        )
        let event = try #require(
            NotificationEvaluator().events(
                provider: .codex,
                previous: quota(69),
                current: quota(71),
                thresholds: [70]
            ).first
        )

        try await scheduler.schedule(event)
        try await scheduler.schedule(event)

        #expect(delivery.deliveredKeys == [event.key])
        #expect(delivery.authorizationRequestCount == 0)
        #expect(try repository.hasNotification(event.key))
    }

    @Test @MainActor
    func authorizationIsRequestedOnlyByExplicitEnableFlow() async throws {
        let delivery = FakeNotificationDelivery(grantsAuthorization: true)
        let scheduler = NotificationScheduler(
            repository: try SnapshotRepository.inMemory(),
            delivery: delivery
        )

        let granted = try await scheduler.requestAuthorization()

        #expect(granted)
        #expect(delivery.authorizationRequestCount == 1)
    }

    private func quota(
        _ percent: Double?,
        id: String = "weekly",
        reset: Date? = Fixtures.day(2),
        provenance: MetricProvenance = .exactProvider
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            label: id == "weekly" ? "Weekly" : "5-hour",
            durationMinutes: id == "weekly" ? 10_080 : 300,
            usedPercent: percent,
            resetsAt: reset,
            provenance: provenance
        )
    }

    private func snapshot(quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .codex,
            observedAt: Fixtures.now,
            health: .ready,
            tokens: nil,
            costDisplay: .includedWithPlan,
            dailyBuckets: [],
            quotaWindows: quotas,
            modelBreakdowns: []
        )
    }
}

@MainActor
private final class FakeNotificationDelivery: NotificationDelivering {
    private(set) var authorizationRequestCount = 0
    private(set) var deliveredKeys: [String] = []
    private let grantsAuthorization: Bool

    init(grantsAuthorization: Bool = false) {
        self.grantsAuthorization = grantsAuthorization
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return grantsAuthorization
    }

    func deliver(_ event: NotificationEvent) async throws {
        deliveredKeys.append(event.key)
    }
}
