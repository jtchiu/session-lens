import Foundation

public enum SpendProvenance: String, Codable, Hashable, Sendable {
    case exact
    case estimated
    case mixed
    case includedWithPlan
    case unavailable
}

public struct ProviderSpendSample: Codable, Hashable, Sendable, Identifiable {
    public let provider: ProviderID
    public let observedAt: Date
    public let scopeID: String?
    public let cumulativeCostUSD: Double?
    public let cumulativeTokens: Int?
    public let provenance: SpendProvenance

    public init(
        provider: ProviderID,
        observedAt: Date,
        scopeID: String?,
        cumulativeCostUSD: Double?,
        cumulativeTokens: Int?,
        provenance: SpendProvenance
    ) {
        self.provider = provider
        self.observedAt = observedAt
        self.scopeID = scopeID
        self.cumulativeCostUSD = Self.normalizedCost(cumulativeCostUSD)
        self.cumulativeTokens = cumulativeTokens.map { max(0, $0) }
        self.provenance = provenance
    }

    public var id: String {
        let scope = scopeID ?? "-"
        return "\(provider.rawValue):\(scope):\(observedAt.timeIntervalSinceReferenceDate.bitPattern)"
    }

    private static func normalizedCost(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }
}

public struct SpendValue: Codable, Hashable, Sendable {
    public let costUSD: Double?
    public let tokens: Int?
    public let provenance: SpendProvenance

    public init(
        costUSD: Double?,
        tokens: Int?,
        provenance: SpendProvenance
    ) {
        if let costUSD, costUSD.isFinite {
            self.costUSD = max(0, costUSD)
        } else {
            self.costUSD = nil
        }
        self.tokens = tokens.map { max(0, $0) }
        self.provenance = provenance
    }

    public var tokensPerDollar: Double? {
        guard let costUSD, costUSD > 0, let tokens else { return nil }
        let value = Double(tokens) / costUSD
        return value.isFinite ? value : nil
    }

    public static var unavailable: SpendValue {
        SpendValue(costUSD: nil, tokens: nil, provenance: .unavailable)
    }
}

public struct SpendPeriods: Codable, Hashable, Sendable {
    public let week: SpendValue
    public let month: SpendValue
    public let retained: SpendValue

    public init(
        week: SpendValue,
        month: SpendValue,
        retained: SpendValue
    ) {
        self.week = week
        self.month = month
        self.retained = retained
    }

    public static var unavailable: SpendPeriods {
        SpendPeriods(
            week: .unavailable,
            month: .unavailable,
            retained: .unavailable
        )
    }
}

public struct ProviderSpendSummary: Codable, Hashable, Sendable {
    public let provider: ProviderID
    public let periods: SpendPeriods

    public init(provider: ProviderID, periods: SpendPeriods) {
        self.provider = provider
        self.periods = periods
    }

    public var week: SpendValue { periods.week }
    public var month: SpendValue { periods.month }
    public var retained: SpendValue { periods.retained }
}

public struct SpendSummary: Codable, Hashable, Sendable {
    public let providers: [ProviderID: ProviderSpendSummary]
    public let combined: SpendPeriods
    public let retentionDays: Int
    public let apiEquivalent: ApiEquivalentSummary

    public init(
        providers: [ProviderID: ProviderSpendSummary],
        combined: SpendPeriods,
        retentionDays: Int,
        apiEquivalent: ApiEquivalentSummary = .unavailable
    ) {
        self.providers = providers
        self.combined = combined
        self.retentionDays = max(1, retentionDays)
        self.apiEquivalent = apiEquivalent
    }

    private enum CodingKeys: String, CodingKey {
        case providers
        case combined
        case retentionDays
        case apiEquivalent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            providers: try container.decode([ProviderID: ProviderSpendSummary].self, forKey: .providers),
            combined: try container.decode(SpendPeriods.self, forKey: .combined),
            retentionDays: try container.decode(Int.self, forKey: .retentionDays),
            apiEquivalent: try container.decodeIfPresent(
                ApiEquivalentSummary.self,
                forKey: .apiEquivalent
            ) ?? .unavailable
        )
    }

    public static func empty(
        retentionDays: Int = AppSettings.defaults.historyRetentionDays
    ) -> SpendSummary {
        SpendSummary(
            providers: [:],
            combined: .unavailable,
            retentionDays: retentionDays
        )
    }
}

public enum SpendSource: Sendable {
    case dailyBuckets(
        provider: ProviderID,
        buckets: [UsageBucket],
        provenance: SpendProvenance,
        includedWithPlan: Bool
    )
    case cumulativeSamples(
        provider: ProviderID,
        samples: [ProviderSpendSample],
        provenance: SpendProvenance
    )

    public static func daily(
        provider: ProviderID,
        buckets: [UsageBucket],
        provenance: SpendProvenance,
        includedWithPlan: Bool = false
    ) -> SpendSource {
        .dailyBuckets(
            provider: provider,
            buckets: buckets,
            provenance: provenance,
            includedWithPlan: includedWithPlan
        )
    }

    public static func samples(
        provider: ProviderID,
        samples: [ProviderSpendSample],
        provenance: SpendProvenance
    ) -> SpendSource {
        .cumulativeSamples(
            provider: provider,
            samples: samples,
            provenance: provenance
        )
    }
}
