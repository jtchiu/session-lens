import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct ApiEquivalentEstimatorTests {
    @Test
    func pricesTokenCategoriesAtPerMillionRates() {
        let value = ApiEquivalentEstimator.price(
            tokens: TokenBreakdown(
                input: 1_000_000,
                output: 2_000_000,
                reasoning: 500_000,
                cacheRead: 100_000,
                cacheWrite: 50_000
            ),
            rate: PricingRate(
                inputPerMillion: 1,
                outputPerMillion: 2,
                reasoningPerMillion: 4,
                cacheReadPerMillion: 0.1,
                cacheWritePerMillion: 0.5
            ),
            coverage: .modelAttributed,
            modelID: "gpt-test",
            ratesAsOf: nil
        )

        #expect(abs((value.costUSD ?? 0) - 7.035) < 0.000_001)
        #expect(value.tokens == 3_650_000)
        #expect(value.coverage == .modelAttributed)
        #expect(value.modelID == "gpt-test")
    }

    @Test
    func uncategorizedTokensUseExplicitMeanFallbackAndNeverBecomeZero() {
        let value = ApiEquivalentEstimator.priceUncategorized(
            tokens: 1_000_000,
            rate: PricingRate(inputPerMillion: 1, outputPerMillion: 3),
            coverage: .detectedProviderModel,
            modelID: "codex-model",
            ratesAsOf: nil
        )

        #expect(value.costUSD == 2)
        #expect(value.coverage == .detectedProviderModel)
    }

    @Test
    func leavesCostUnavailableWhenNoCategoryHasAPrice() {
        let value = ApiEquivalentEstimator.price(
            tokens: TokenBreakdown(
                input: 10,
                output: 20,
                reasoning: 30,
                cacheRead: 40,
                cacheWrite: 50
            ),
            rate: PricingRate(),
            coverage: .catalogStale,
            modelID: "old-model",
            ratesAsOf: nil
        )

        #expect(value.costUSD == nil)
        #expect(value.tokens == 150)
        #expect(value.coverage == .catalogStale)
    }

    @Test
    func normalizesInvalidRatesAndNegativeTokensWithoutFabricatingCost() {
        let rate = PricingRate(
            inputPerMillion: -.infinity,
            outputPerMillion: .nan,
            reasoningPerMillion: -1,
            cacheReadPerMillion: 2,
            cacheWritePerMillion: .infinity
        )
        let value = ApiEquivalentEstimator.price(
            tokens: TokenBreakdown(
                input: -1,
                output: -2,
                reasoning: -3,
                cacheRead: 1_000_000,
                cacheWrite: -4
            ),
            rate: rate,
            coverage: .unavailable,
            modelID: nil,
            ratesAsOf: nil
        )

        #expect(rate.inputPerMillion == nil)
        #expect(rate.outputPerMillion == nil)
        #expect(rate.reasoningPerMillion == 0)
        #expect(rate.cacheWritePerMillion == nil)
        #expect(value.costUSD == 2)
        #expect(value.tokens == 1_000_000)
    }

    @Test
    func usesOutputRateWhenReasoningRateIsUnavailable() {
        let value = ApiEquivalentEstimator.price(
            tokens: TokenBreakdown(
                input: 0,
                output: 0,
                reasoning: 1_000_000,
                cacheRead: 0,
                cacheWrite: 0
            ),
            rate: PricingRate(outputPerMillion: 3),
            coverage: .latestKnownModel,
            modelID: "latest",
            ratesAsOf: nil
        )

        #expect(value.costUSD == 3)
    }

    @Test
    func zeroTokensRetainAnExplicitZeroForAvailablePricing() {
        let value = ApiEquivalentEstimator.priceUncategorized(
            tokens: 0,
            rate: PricingRate(inputPerMillion: 1, outputPerMillion: 3),
            coverage: .modelAttributed,
            modelID: "zero",
            ratesAsOf: nil
        )

        #expect(value.costUSD == 0)
        #expect(value.tokens == 0)
    }

    @Test
    func capsLargeCategorizedTokenTotalsAtIntMax() {
        let value = ApiEquivalentEstimator.price(
            tokens: TokenBreakdown(
                input: Int.max,
                output: Int.max,
                reasoning: Int.max,
                cacheRead: Int.max,
                cacheWrite: Int.max
            ),
            rate: PricingRate(inputPerMillion: 1),
            coverage: .modelAttributed,
            modelID: "large",
            ratesAsOf: nil
        )

        #expect(value.tokens == Int.max)
        #expect(value.costUSD != nil)
    }

    @Test
    func uncategorizedTokensRequireBothInputAndOutputRates() {
        let value = ApiEquivalentEstimator.priceUncategorized(
            tokens: 100,
            rate: PricingRate(inputPerMillion: 1),
            coverage: .modelAttributed,
            modelID: "incomplete",
            ratesAsOf: nil
        )

        #expect(value.costUSD == nil)
        #expect(value.tokens == 100)
    }

    @Test
    func decodingRatesAppliesTheSameFiniteNonNegativeNormalization() throws {
        let data = Data("""
        {"inputPerMillion": -1, "outputPerMillion": 2}
        """.utf8)

        let rate = try JSONDecoder().decode(PricingRate.self, from: data)

        #expect(rate.inputPerMillion == 0)
        #expect(rate.outputPerMillion == 2)
        #expect(rate.reasoningPerMillion == nil)
    }
}
