import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct UsageModelsTests {
    @Test
    func quotaWindowExposesRemainingCapacityWithoutChangingUsedValue() {
        let window = QuotaWindow(
            id: "weekly",
            label: "Weekly",
            durationMinutes: 10_080,
            usedPercent: 22,
            resetsAt: nil,
            provenance: .exactProvider
        )

        #expect(window.usedPercent == 22)
        #expect(window.remainingPercent == 78)
    }

    @Test
    func remainingCapacityClampsAtFullAndDepleted() {
        #expect(
            QuotaWindow(
                id: "full",
                label: "5-hour",
                durationMinutes: 300,
                usedPercent: 0,
                resetsAt: nil,
                provenance: .exactProvider
            ).remainingPercent == 100
        )
        #expect(
            QuotaWindow(
                id: "depleted",
                label: "5-hour",
                durationMinutes: 300,
                usedPercent: 100,
                resetsAt: nil,
                provenance: .exactProvider
            ).remainingPercent == 0
        )
        #expect(
            QuotaWindow(
                id: "unknown",
                label: "5-hour",
                durationMinutes: 300,
                usedPercent: nil,
                resetsAt: nil,
                provenance: .unavailable
            ).remainingPercent == nil
        )
    }

    @Test
    func quotaHistoryExposesRemainingCapacityForCharts() {
        let point = QuotaHistoryPoint(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            usedPercent: 22,
            resetsAt: nil,
            provenance: .exactProvider
        )

        #expect(point.usedPercent == 22)
        #expect(point.remainingPercent == 78)
    }

    @Test
    func quotaWindowClampsProviderPercentageAtUpperBound() {
        let window = QuotaWindow(
            id: "weekly",
            label: "Weekly",
            durationMinutes: 10_080,
            usedPercent: 112,
            resetsAt: nil,
            provenance: .exactProvider
        )

        #expect(window.usedPercent == 100)
    }

    @Test
    func quotaWindowClampsProviderPercentageAtLowerBound() {
        let window = QuotaWindow(
            id: "weekly",
            label: "Weekly",
            durationMinutes: 10_080,
            usedPercent: -4,
            resetsAt: nil,
            provenance: .exactProvider
        )

        #expect(window.usedPercent == 0)
    }

    @Test
    func unavailableMetricNeverBecomesZero() {
        let snapshot = ProviderSnapshot.unavailable(
            provider: .claude,
            health: .toolMissing
        )

        #expect(snapshot.primaryQuota?.usedPercent == nil)
        #expect(snapshot.costUSD == nil)
        #expect(snapshot.tokens == nil)
    }

    @Test
    func tokenTotalIncludesEveryNormalizedCategory() {
        let tokens = TokenBreakdown(
            input: 10,
            output: 20,
            reasoning: 30,
            cacheRead: 40,
            cacheWrite: 50
        )

        #expect(tokens.total == 150)
    }

    @Test
    func modelUsageDecodesExistingMetadataWithoutRecency() throws {
        let data = Data("""
        {"providerID":"openai","modelID":"gpt-legacy","tokens":{"input":10,"output":0,"reasoning":0,"cacheRead":0,"cacheWrite":0},"costUSD":0.25}
        """.utf8)

        let usage = try JSONDecoder().decode(ModelUsage.self, from: data)

        #expect(usage.modelID == "gpt-legacy")
        #expect(usage.lastObservedAt == nil)
    }
}
