import Foundation

public enum ApiEquivalentEstimator {
    public static func price(
        tokens: TokenBreakdown,
        rate: PricingRate,
        coverage: PricingCoverage,
        modelID: String?,
        ratesAsOf: Date?
    ) -> ApiEquivalentValue {
        let categories: [(Int, Double?)] = [
            (tokens.input, rate.inputPerMillion),
            (tokens.output, rate.outputPerMillion),
            (tokens.reasoning, rate.reasoningPerMillion ?? rate.outputPerMillion),
            (tokens.cacheRead, rate.cacheReadPerMillion),
            (tokens.cacheWrite, rate.cacheWritePerMillion),
        ]

        let normalizedTokens = saturatingSum(categories.map { $0.0 })
        let cost = categories.reduce(into: Optional<Double>.none) { total, category in
            guard let rate = category.1,
                  let categoryCost = estimatedCost(tokens: category.0, perMillion: rate)
            else { return }

            guard let currentTotal = total else {
                total = categoryCost
                return
            }

            let next = currentTotal + categoryCost
            if next.isFinite {
                total = next
            }
        }

        return ApiEquivalentValue(
            costUSD: cost,
            tokens: normalizedTokens,
            coverage: coverage,
            modelID: modelID,
            ratesAsOf: ratesAsOf
        )
    }

    public static func priceUncategorized(
        tokens: Int,
        rate: PricingRate,
        coverage: PricingCoverage,
        modelID: String?,
        ratesAsOf: Date?
    ) -> ApiEquivalentValue {
        let normalizedTokens = max(0, tokens)
        let cost: Double?
        if let input = rate.inputPerMillion, let output = rate.outputPerMillion {
            cost = Self.estimatedCost(tokens: normalizedTokens, perMillion: (input + output) / 2)
        } else {
            cost = nil
        }

        return ApiEquivalentValue(
            costUSD: cost,
            tokens: normalizedTokens,
            coverage: coverage,
            modelID: modelID,
            ratesAsOf: ratesAsOf
        )
    }

    private static func estimatedCost(tokens: Int, perMillion: Double) -> Double? {
        let normalizedTokens = max(0, tokens)
        let value = Double(normalizedTokens) * perMillion / 1_000_000
        return value.isFinite ? value : nil
    }

    private static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { total, value in
            let normalizedValue = max(0, value)
            let result = total.addingReportingOverflow(normalizedValue)
            return result.overflow ? Int.max : result.partialValue
        }
    }
}
