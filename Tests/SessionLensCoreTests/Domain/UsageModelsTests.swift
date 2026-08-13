import Testing
@testable import SessionLensCore

@Suite
struct UsageModelsTests {
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
}
