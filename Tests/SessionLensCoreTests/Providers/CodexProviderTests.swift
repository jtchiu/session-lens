import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct CodexProviderTests {
    @Test
    func providerNormalizesWeeklyAndFiveHourWindows() async {
        let client = FakeCodexClient()

        let snapshot = await CodexProvider(client: client).refresh(at: Fixtures.now)

        #expect(snapshot.provider == .codex)
        #expect(snapshot.health == .ready)
        #expect(snapshot.quotaWindows.map(\.label) == ["5-hour", "Weekly"])
        #expect(snapshot.quotaWindows.map(\.usedPercent) == [42, 36])
        #expect(snapshot.quotaWindows.allSatisfy { $0.provenance == .exactProvider })
        #expect(snapshot.dailyBuckets.last?.tokens == 453_544_969)
        #expect(snapshot.tokens?.total == 500_000_000)
        #expect(snapshot.tokens?.uncategorized == 500_000_000)
        #expect(snapshot.costUSD == nil)
    }

    @Test
    func providerDeduplicatesLegacyAndMultiBucketWindows() async {
        let snapshot = await CodexProvider(client: FakeCodexClient())
            .refresh(at: Fixtures.now)

        #expect(snapshot.quotaWindows.count == 2)
        #expect(
            snapshot.quotaWindows.map(\.resetsAt)
                == [
                    Date(timeIntervalSince1970: 1_735_693_200),
                    Date(timeIntervalSince1970: 1_736_294_400),
                ]
        )
    }

    @Test
    func includedPlanCostIsDomainStateNotFabricatedDollars() async {
        let snapshot = await CodexProvider(client: FakeCodexClient())
            .refresh(at: Fixtures.now)

        #expect(snapshot.costDisplay == .includedWithPlan)
        #expect(snapshot.costUSD == nil)
    }

    @Test
    func durationLabelsArePureAndForwardCompatible() {
        #expect(CodexProvider.label(for: 300) == "5-hour")
        #expect(CodexProvider.label(for: 10_080) == "Weekly")
        #expect(CodexProvider.label(for: 60) == "60 min")
        #expect(CodexProvider.label(for: nil) == "Quota")
    }

    @Test
    func missingPlanDoesNotClaimIncludedOrDollarCost() async {
        let limits = CodexRateLimitsResponse(
            rateLimits: CodexRateLimitSnapshot(
                primary: CodexRateLimitWindow(
                    usedPercent: 10,
                    windowDurationMins: 300
                )
            ),
            rateLimitsByLimitId: nil
        )
        let snapshot = await CodexProvider(
            client: FakeCodexClient(rateLimits: limits)
        ).refresh(at: Fixtures.now)

        #expect(snapshot.costDisplay == .unavailable)
        #expect(snapshot.costUSD == nil)
    }

    @Test
    func malformedDailyDateReturnsNoFabricatedMetrics() async {
        let usage = CodexAccountUsageResponse(
            summary: CodexAccountUsageSummary(lifetimeTokens: 100),
            dailyUsageBuckets: [
                CodexDailyUsageBucket(startDate: "not-a-day", tokens: 100)
            ]
        )
        let snapshot = await CodexProvider(
            client: FakeCodexClient(usage: usage)
        ).refresh(at: Fixtures.now)

        #expect(snapshot.health == .malformedData)
        #expect(snapshot.tokens == nil)
        #expect(snapshot.quotaWindows.isEmpty)
    }

    @Test
    func clientFailureReturnsUnavailableWithoutFabricatedMetrics() async {
        let snapshot = await CodexProvider(
            client: FakeCodexClient(failsRateLimits: true)
        ).refresh(at: Fixtures.now)

        #expect(snapshot.health == .temporarilyUnavailable)
        #expect(snapshot.tokens == nil)
        #expect(snapshot.costUSD == nil)
    }
}
