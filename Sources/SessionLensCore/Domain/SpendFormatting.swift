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
        let provenance: String
        switch value.provenance {
        case .exact: provenance = "exact"
        case .estimated: provenance = "estimated"
        case .mixed: provenance = "includes an estimate"
        case .includedWithPlan: provenance = "included with plan"
        case .unavailable: provenance = "unavailable"
        }
        var label = "\(provider), \(period), \(cost), \(provenance)."
        if let ratio = value.tokensPerDollar {
            label += " \(compact(ratio)) tokens per dollar."
        } else if value.costUSD != nil {
            label += " Cumulative token total is unavailable."
        }
        return label
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
