import Foundation

public enum SpendFormatting {
    public static func costText(_ value: SpendValue) -> String {
        guard let cost = value.costUSD else {
            switch value.provenance {
            case .includedWithPlan:
                return "Included with plan"
            case .exact, .estimated, .mixed, .unavailable:
                return "—"
            }
        }
        let amount = String(format: "$%.2f", cost)
        switch value.provenance {
        case .estimated:
            return "Estimated \(amount)"
        case .mixed:
            return "Includes estimate \(amount)"
        case .exact, .includedWithPlan, .unavailable:
            return amount
        }
    }

    public static func efficiencyText(_ value: SpendValue) -> String {
        guard let tokensPerDollar = value.tokensPerDollar else { return "—" }
        return "\(compact(tokensPerDollar)) tok/$"
    }

    public static func apiEquivalentText(_ value: ApiEquivalentValue) -> String {
        guard let cost = value.costUSD else {
            return "API equivalent unavailable"
        }
        return String(format: "API eq. ~$%.2f", cost)
    }

    public static func coverageText(_ value: ApiEquivalentValue) -> String {
        switch value.coverage {
        case .modelAttributed:
            return "Model-attributed"
        case .latestKnownModel:
            return "Latest model estimate"
        case .detectedProviderModel:
            return "Detected model estimate"
        case .catalogStale:
            return "Cached pricing estimate"
        case .unavailable:
            return "API equivalent unavailable"
        }
    }

    public static func tokenText(_ tokens: Int?) -> String {
        guard let tokens else { return "Token count unavailable" }
        return "\(compact(Double(tokens))) tokens"
    }

    public static func comparisonAccessibilityLabel(
        provider: ProviderID,
        period: String,
        actual: SpendValue,
        apiEquivalent: ApiEquivalentValue
    ) -> String {
        comparisonAccessibilityLabel(
            provider: provider.displayName,
            period: period,
            actual: actual,
            apiEquivalent: apiEquivalent
        )
    }

    public static func accessibilityLabel(
        provider: ProviderID,
        period: String,
        actual: SpendValue,
        apiEquivalent: ApiEquivalentValue
    ) -> String {
        comparisonAccessibilityLabel(
            provider: provider,
            period: period,
            actual: actual,
            apiEquivalent: apiEquivalent
        )
    }

    public static func comparisonAccessibilityLabel(
        provider: String,
        period: String,
        actual: SpendValue,
        apiEquivalent: ApiEquivalentValue
    ) -> String {
        // Token consumption comes from the actual combined ledger. The API
        // equivalent may intentionally omit providers whose rates are unknown.
        let tokens = actual.tokens
        var label = "\(provider), \(period)."
        label += " Actual spend: \(costText(actual)), \(provenanceText(actual))."
        label += " API equivalent: \(apiEquivalentText(apiEquivalent)),"
        label += " \(coverageText(apiEquivalent))."
        if let tokens {
            label += " Token count: \(tokens.formatted(.number)) tokens."
        } else {
            label += " Token count unavailable."
        }
        if let ratesAsOf = apiEquivalent.ratesAsOf {
            label += " Rates as of \(ratesAsOf.formatted(date: .abbreviated, time: .omitted))."
        } else {
            label += " Rates as of unavailable."
        }
        return label
    }

    public static func accessibilityLabel(
        provider: String,
        period: String,
        actual: SpendValue,
        apiEquivalent: ApiEquivalentValue
    ) -> String {
        comparisonAccessibilityLabel(
            provider: provider,
            period: period,
            actual: actual,
            apiEquivalent: apiEquivalent
        )
    }

    public static func accessibilityLabel(
        provider: ProviderID,
        period: String,
        value: SpendValue
    ) -> String {
        accessibilityLabel(
            provider: provider.displayName,
            period: period,
            value: value
        )
    }

    public static func accessibilityLabel(
        provider: String,
        period: String,
        value: SpendValue
    ) -> String {
        let cost = costText(value)
        let provenance = provenanceText(value)
        var label = "\(provider), \(period), \(cost), \(provenance)."
        if let ratio = value.tokensPerDollar {
            label += " \(compact(ratio)) tokens per dollar."
        } else if value.costUSD != nil {
            label += " Cumulative token total is unavailable."
        }
        return label
    }

    private static func provenanceText(_ value: SpendValue) -> String {
        switch value.provenance {
        case .exact: return "exact"
        case .estimated: return "estimated"
        case .mixed: return "includes an estimate"
        case .includedWithPlan: return "included with plan"
        case .unavailable: return "unavailable"
        }
    }

    private static func compact(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(Int(value.rounded()))
    }
}
