import Foundation

public struct PricingRate: Codable, Hashable, Sendable {
    public let inputPerMillion: Double?
    public let outputPerMillion: Double?
    public let reasoningPerMillion: Double?
    public let cacheReadPerMillion: Double?
    public let cacheWritePerMillion: Double?

    public init(
        inputPerMillion: Double? = nil,
        outputPerMillion: Double? = nil,
        reasoningPerMillion: Double? = nil,
        cacheReadPerMillion: Double? = nil,
        cacheWritePerMillion: Double? = nil
    ) {
        self.inputPerMillion = Self.normalized(inputPerMillion)
        self.outputPerMillion = Self.normalized(outputPerMillion)
        self.reasoningPerMillion = Self.normalized(reasoningPerMillion)
        self.cacheReadPerMillion = Self.normalized(cacheReadPerMillion)
        self.cacheWritePerMillion = Self.normalized(cacheWritePerMillion)
    }

    private enum CodingKeys: String, CodingKey {
        case inputPerMillion
        case outputPerMillion
        case reasoningPerMillion
        case cacheReadPerMillion
        case cacheWritePerMillion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inputPerMillion: try container.decodeIfPresent(Double.self, forKey: .inputPerMillion),
            outputPerMillion: try container.decodeIfPresent(Double.self, forKey: .outputPerMillion),
            reasoningPerMillion: try container.decodeIfPresent(Double.self, forKey: .reasoningPerMillion),
            cacheReadPerMillion: try container.decodeIfPresent(Double.self, forKey: .cacheReadPerMillion),
            cacheWritePerMillion: try container.decodeIfPresent(Double.self, forKey: .cacheWritePerMillion)
        )
    }

    private static func normalized(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }
}

public enum PricingCoverage: String, Codable, Hashable, Sendable {
    case modelAttributed
    case latestKnownModel
    case detectedProviderModel
    case catalogStale
    case unavailable
}

public enum PricingCatalogSource: String, Codable, Hashable, Sendable {
    case live
    case cached
    case unavailable
}

public struct PricingCatalogModel: Codable, Hashable, Sendable {
    public let providerID: String
    public let modelID: String
    public let rate: PricingRate

    public init(providerID: String, modelID: String, rate: PricingRate) {
        self.providerID = providerID
        self.modelID = modelID
        self.rate = rate
    }
}

public struct PricingCatalog: Codable, Hashable, Sendable {
    public let models: [PricingCatalogModel]
    public let updatedAt: Date?
    public let fetchedAt: Date

    public init(models: [PricingCatalogModel], updatedAt: Date?, fetchedAt: Date) {
        self.models = models
        self.updatedAt = updatedAt
        self.fetchedAt = fetchedAt
    }

    public func model(providerID: String, modelID: String) -> PricingCatalogModel? {
        models.first { $0.providerID == providerID && $0.modelID == modelID }
    }
}

public struct PricingCatalogState: Codable, Hashable, Sendable {
    public let source: PricingCatalogSource
    public let catalog: PricingCatalog?
    public let message: String?

    public init(source: PricingCatalogSource, catalog: PricingCatalog?, message: String? = nil) {
        self.source = source
        self.catalog = catalog
        self.message = message
    }

    public var ratesAsOf: Date? {
        catalog?.updatedAt ?? catalog?.fetchedAt
    }
}

public struct ApiEquivalentValue: Codable, Hashable, Sendable {
    public let costUSD: Double?
    public let tokens: Int?
    public let coverage: PricingCoverage
    public let modelID: String?
    public let ratesAsOf: Date?

    public init(
        costUSD: Double?,
        tokens: Int?,
        coverage: PricingCoverage,
        modelID: String?,
        ratesAsOf: Date?
    ) {
        if let costUSD, costUSD.isFinite {
            self.costUSD = max(0, costUSD)
        } else {
            self.costUSD = nil
        }
        self.tokens = tokens.map { max(0, $0) }
        self.coverage = coverage
        self.modelID = modelID
        self.ratesAsOf = ratesAsOf
    }

    private enum CodingKeys: String, CodingKey {
        case costUSD
        case tokens
        case coverage
        case modelID
        case ratesAsOf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            costUSD: try container.decodeIfPresent(Double.self, forKey: .costUSD),
            tokens: try container.decodeIfPresent(Int.self, forKey: .tokens),
            coverage: try container.decode(PricingCoverage.self, forKey: .coverage),
            modelID: try container.decodeIfPresent(String.self, forKey: .modelID),
            ratesAsOf: try container.decodeIfPresent(Date.self, forKey: .ratesAsOf)
        )
    }
}

public struct ApiEquivalentPeriods: Codable, Hashable, Sendable {
    public let week: ApiEquivalentValue
    public let month: ApiEquivalentValue
    public let retained: ApiEquivalentValue

    public init(week: ApiEquivalentValue, month: ApiEquivalentValue, retained: ApiEquivalentValue) {
        self.week = week
        self.month = month
        self.retained = retained
    }

    public static var unavailable: ApiEquivalentPeriods {
        ApiEquivalentPeriods(
            week: .unavailable,
            month: .unavailable,
            retained: .unavailable
        )
    }
}

public struct ApiEquivalentSummary: Codable, Hashable, Sendable {
    public let providers: [ProviderID: ApiEquivalentPeriods]
    public let combined: ApiEquivalentPeriods
    public let catalogState: PricingCatalogState

    public init(
        providers: [ProviderID: ApiEquivalentPeriods],
        combined: ApiEquivalentPeriods,
        catalogState: PricingCatalogState
    ) {
        self.providers = providers
        self.combined = combined
        self.catalogState = catalogState
    }

    public static var unavailable: ApiEquivalentSummary {
        ApiEquivalentSummary(
            providers: [:],
            combined: .unavailable,
            catalogState: PricingCatalogState(
                source: .unavailable,
                catalog: nil
            )
        )
    }
}

public extension ApiEquivalentValue {
    static var unavailable: ApiEquivalentValue {
        ApiEquivalentValue(
            costUSD: nil,
            tokens: nil,
            coverage: .unavailable,
            modelID: nil,
            ratesAsOf: nil
        )
    }
}
