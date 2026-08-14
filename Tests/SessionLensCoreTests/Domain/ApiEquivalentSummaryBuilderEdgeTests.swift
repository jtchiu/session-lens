import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct ApiEquivalentSummaryBuilderEdgeTests {
    @Test
    func scalesNearIntMaxRatiosWithoutAllowingRoundedComponentsToOverflow() {
        let total = Int.max
        let scaled = ApiEquivalentSummaryBuilder.scaledTokens(
            total: total,
            proportions: TokenBreakdown(
                input: total - 2,
                output: 3,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                uncategorized: 0
            )
        )

        let components = [
            scaled?.input,
            scaled?.output,
            scaled?.reasoning,
            scaled?.cacheRead,
            scaled?.cacheWrite,
            scaled?.uncategorized,
        ].compactMap { $0 }
        let (sum, overflow) = components.reduce(into: (0, false)) { result, value in
            let (next, didOverflow) = result.0.addingReportingOverflow(value)
            result.0 = next
            result.1 = result.1 || didOverflow
        }

        #expect(!overflow)
        #expect(sum == total)
        #expect(scaled?.input == total - 3)
        #expect(scaled?.output == 3)
    }

    @Test
    func scalesIntMaxTotalsWithoutOverflowAndKeepsRemainderDeterministic() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let periods = SpendPeriods(
            week: SpendValue(costUSD: nil, tokens: Int.max, provenance: .exact),
            month: SpendValue(costUSD: nil, tokens: Int.max, provenance: .exact),
            retained: SpendValue(costUSD: nil, tokens: Int.max, provenance: .exact)
        )
        let summary = SpendSummary(
            providers: [
                .opencode: ProviderSpendSummary(
                    provider: .opencode,
                    periods: periods
                )
            ],
            combined: .unavailable,
            retentionDays: 30
        )
        let snapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(1),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "gpt-test",
                    tokens: TokenBreakdown(
                        input: Int.max,
                        output: Int.max,
                        reasoning: Int.max,
                        cacheRead: Int.max,
                        cacheWrite: Int.max,
                        uncategorized: Int.max
                    ),
                    costUSD: 1
                )
            ]
        )
        let catalog = PricingCatalog(
            models: [
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "gpt-test",
                    rate: PricingRate(inputPerMillion: 1, outputPerMillion: 2)
                )
            ],
            updatedAt: now,
            fetchedAt: now
        )
        let catalogState = PricingCatalogState(source: .live, catalog: catalog)

        let proportions = TokenBreakdown(
            input: Int.max,
            output: Int.max,
            reasoning: Int.max,
            cacheRead: Int.max,
            cacheWrite: Int.max,
            uncategorized: Int.max
        )
        let scaled = ApiEquivalentSummaryBuilder.scaledTokens(
            total: Int.max,
            proportions: proportions
        )
        let scaledAgain = ApiEquivalentSummaryBuilder.scaledTokens(
            total: Int.max,
            proportions: proportions
        )
        #expect(scaled == scaledAgain)
        let components = [
            scaled?.input,
            scaled?.output,
            scaled?.reasoning,
            scaled?.cacheRead,
            scaled?.cacheWrite,
            scaled?.uncategorized,
        ].compactMap { $0 }
        let (componentTotal, overflow) = components.reduce(into: (0, false)) { result, value in
            let (next, didOverflow) = result.0.addingReportingOverflow(value)
            result.0 = next
            result.1 = result.1 || didOverflow
        }
        #expect(!overflow)
        #expect(componentTotal == Int.max)

        let first = ApiEquivalentSummaryBuilder.make(
            summary: summary,
            snapshots: [.opencode: snapshot],
            catalog: catalog,
            catalogState: catalogState,
            codexModelID: nil,
            now: now,
            calendar: .current
        )
        let second = ApiEquivalentSummaryBuilder.make(
            summary: summary,
            snapshots: [.opencode: snapshot],
            catalog: catalog,
            catalogState: catalogState,
            codexModelID: nil,
            now: now,
            calendar: .current
        )

        #expect(first == second)
        #expect(first.providers[.opencode]?.week.tokens == Int.max)
        #expect(first.providers[.opencode]?.week.costUSD != nil)
    }
}
