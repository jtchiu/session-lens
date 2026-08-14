import Foundation

public enum ApiEquivalentSummaryBuilder {
    public static func make(
        summary: SpendSummary,
        snapshots: [ProviderID: ProviderSnapshot],
        catalog: PricingCatalog?,
        catalogState: PricingCatalogState,
        codexModelID: String?,
        now: Date,
        calendar: Calendar
    ) -> ApiEquivalentSummary {
        _ = now
        _ = calendar
        guard let catalog = catalog ?? catalogState.catalog else {
            return ApiEquivalentSummary(
                providers: Dictionary(
                    uniqueKeysWithValues: summary.providers.keys.map {
                        ($0, .unavailable)
                    }
                ),
                combined: .unavailable,
                catalogState: catalogState
            )
        }

        let providers = summary.providers.mapValues { providerSummary in
            periods(
                provider: providerSummary.provider,
                periods: providerSummary.periods,
                snapshot: snapshots[providerSummary.provider],
                catalog: catalog,
                catalogState: catalogState,
                codexModelID: codexModelID
            )
        }
        return ApiEquivalentSummary(
            providers: providers,
            combined: ApiEquivalentPeriods(
                week: combined(providers.values.map(\.week), ratesAsOf: catalogState.ratesAsOf),
                month: combined(providers.values.map(\.month), ratesAsOf: catalogState.ratesAsOf),
                retained: combined(providers.values.map(\.retained), ratesAsOf: catalogState.ratesAsOf)
            ),
            catalogState: catalogState
        )
    }
}

private extension ApiEquivalentSummaryBuilder {
    static func periods(
        provider: ProviderID,
        periods: SpendPeriods,
        snapshot: ProviderSnapshot?,
        catalog: PricingCatalog,
        catalogState: PricingCatalogState,
        codexModelID: String?
    ) -> ApiEquivalentPeriods {
        let resolved = resolvedRate(
            provider: provider,
            snapshot: snapshot,
            catalog: catalog,
            catalogIsStale: catalogState.message != nil,
            codexModelID: codexModelID
        )
        return ApiEquivalentPeriods(
            week: value(
                for: periods.week,
                resolved: resolved,
                ratesAsOf: catalogState.ratesAsOf
            ),
            month: value(
                for: periods.month,
                resolved: resolved,
                ratesAsOf: catalogState.ratesAsOf
            ),
            retained: value(
                for: periods.retained,
                resolved: resolved,
                ratesAsOf: catalogState.ratesAsOf
            )
        )
    }

    static func resolvedRate(
        provider: ProviderID,
        snapshot: ProviderSnapshot?,
        catalog: PricingCatalog,
        catalogIsStale: Bool,
        codexModelID: String?
    ) -> (rate: ResolvedModelRate, proportions: TokenBreakdown?)? {
        if let latest = snapshot?.modelBreakdowns.last,
           let resolved = ModelRateResolver.resolve(
               provider: provider,
               providerID: latest.providerID,
               modelID: latest.modelID,
               latestModelID: latest.modelID,
               catalog: catalog,
               catalogIsStale: catalogIsStale
           )
        {
            let coverage: PricingCoverage = resolved.coverage == .catalogStale
                ? .catalogStale
                : .latestKnownModel
            return (
                ResolvedModelRate(
                    modelID: resolved.modelID,
                    rate: resolved.rate,
                    coverage: coverage
                ),
                latest.tokens
            )
        }

        guard provider == .codex,
              let resolved = ModelRateResolver.resolve(
                  provider: provider,
                  providerID: nil,
                  modelID: codexModelID,
                  latestModelID: nil,
                  catalog: catalog,
                  catalogIsStale: catalogIsStale
              )
        else {
            return nil
        }
        return (resolved, nil)
    }

    static func value(
        for period: SpendValue,
        resolved: (rate: ResolvedModelRate, proportions: TokenBreakdown?)?,
        ratesAsOf: Date?
    ) -> ApiEquivalentValue {
        guard let tokens = period.tokens, let resolved else {
            return .unavailable
        }
        let rate = resolved.rate
        let coverage = rate.coverage
        guard let proportions = resolved.proportions,
              let scaled = scaledTokens(total: tokens, proportions: proportions)
        else {
            return ApiEquivalentEstimator.priceUncategorized(
                tokens: tokens,
                rate: rate.rate,
                coverage: coverage,
                modelID: rate.modelID,
                ratesAsOf: ratesAsOf
            )
        }

        var pricedValues: [Double] = []
        if hasPricedCategorizedTokens(scaled, rate: rate.rate) {
            let categorized = ApiEquivalentEstimator.price(
                tokens: scaled,
                rate: rate.rate,
                coverage: coverage,
                modelID: rate.modelID,
                ratesAsOf: ratesAsOf
            )
            if let cost = categorized.costUSD {
                pricedValues.append(cost)
            }
        }
        if scaled.uncategorized > 0 {
            let uncategorized = ApiEquivalentEstimator.priceUncategorized(
                tokens: scaled.uncategorized,
                rate: rate.rate,
                coverage: coverage,
                modelID: rate.modelID,
                ratesAsOf: ratesAsOf
            )
            if let cost = uncategorized.costUSD {
                pricedValues.append(cost)
            }
        }
        if max(0, tokens) == 0, pricedValues.isEmpty, hasAnyRate(rate.rate) {
            pricedValues = [0]
        }
        let cost = finiteSum(pricedValues)
        return ApiEquivalentValue(
            costUSD: cost,
            tokens: max(0, tokens),
            coverage: coverage,
            modelID: rate.modelID,
            ratesAsOf: ratesAsOf
        )
    }

    static func scaledTokens(
        total: Int,
        proportions: TokenBreakdown
    ) -> TokenBreakdown? {
        let source = [
            proportions.input,
            proportions.output,
            proportions.reasoning,
            proportions.cacheRead,
            proportions.cacheWrite,
            proportions.uncategorized,
        ].map { max(0, $0) }
        let sourceTotal = saturatingSum(source)
        guard sourceTotal > 0 else { return nil }

        let normalizedTotal = max(0, total)
        let scaled = source.map { sourceTokens in
            Int((Double(sourceTokens) / Double(sourceTotal) * Double(normalizedTotal)).rounded(.down))
        }
        let assigned = saturatingSum(scaled)
        let remainder = max(0, normalizedTotal - assigned)
        let largestSourceIndex = source.indices.max { source[$0] < source[$1] } ?? 0
        var result = scaled
        result[largestSourceIndex] = min(Int.max, result[largestSourceIndex] + remainder)
        return TokenBreakdown(
            input: result[0],
            output: result[1],
            reasoning: result[2],
            cacheRead: result[3],
            cacheWrite: result[4],
            uncategorized: result[5]
        )
    }

    static func hasPricedCategorizedTokens(
        _ tokens: TokenBreakdown,
        rate: PricingRate
    ) -> Bool {
        (tokens.input > 0 && rate.inputPerMillion != nil)
            || (tokens.output > 0 && rate.outputPerMillion != nil)
            || (tokens.reasoning > 0
                && (rate.reasoningPerMillion ?? rate.outputPerMillion) != nil)
            || (tokens.cacheRead > 0 && rate.cacheReadPerMillion != nil)
            || (tokens.cacheWrite > 0 && rate.cacheWritePerMillion != nil)
    }

    static func hasAnyRate(_ rate: PricingRate) -> Bool {
        rate.inputPerMillion != nil
            || rate.outputPerMillion != nil
            || rate.reasoningPerMillion != nil
            || rate.cacheReadPerMillion != nil
            || rate.cacheWritePerMillion != nil
    }

    static func combined(
        _ values: [ApiEquivalentValue],
        ratesAsOf: Date?
    ) -> ApiEquivalentValue {
        let priced = values.filter { $0.costUSD != nil }
        guard !priced.isEmpty else { return .unavailable }
        let cost = finiteSum(priced.compactMap(\.costUSD))
        let tokens = priced.allSatisfy { $0.tokens != nil }
            ? saturatingSum(priced.compactMap(\.tokens))
            : nil
        return ApiEquivalentValue(
            costUSD: cost,
            tokens: tokens,
            coverage: combinedCoverage(priced.map(\.coverage)),
            modelID: nil,
            ratesAsOf: ratesAsOf
        )
    }

    static func combinedCoverage(_ values: [PricingCoverage]) -> PricingCoverage {
        if values.contains(.catalogStale) { return .catalogStale }
        if values.contains(.latestKnownModel) { return .latestKnownModel }
        if values.contains(.detectedProviderModel) { return .detectedProviderModel }
        if values.contains(.modelAttributed) { return .modelAttributed }
        return .unavailable
    }

    static func saturatingSum(_ values: [Int]) -> Int {
        values.reduce(0) { total, value in
            let (next, overflow) = total.addingReportingOverflow(max(0, value))
            return overflow ? Int.max : next
        }
    }

    static func finiteSum(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(nil as Double?) { total, value in
            guard let total else { return value }
            let next = total + value
            return next.isFinite ? next : nil
        }
    }
}
