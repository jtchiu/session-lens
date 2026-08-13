import Foundation

public enum MetricProvenance: String, Codable, Hashable, Sendable {
    case exactProvider
    case exactLocalAggregate
    case localBudget
    case estimated
    case stale
    case unavailable
}

public enum ProviderHealth: String, Codable, Hashable, Sendable {
    case ready
    case setupRequired
    case toolMissing
    case stale
    case malformedData
    case timedOut
    case temporarilyUnavailable
}

public enum CostDisplay: Codable, Hashable, Sendable {
    case exactUSD(Double)
    case includedWithPlan
    case unavailable
}

public struct TokenBreakdown: Codable, Hashable, Sendable {
    public let input: Int
    public let output: Int
    public let reasoning: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let uncategorized: Int

    public init(
        input: Int,
        output: Int,
        reasoning: Int,
        cacheRead: Int,
        cacheWrite: Int,
        uncategorized: Int = 0
    ) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.uncategorized = uncategorized
    }

    public var total: Int {
        input + output + reasoning + cacheRead + cacheWrite + uncategorized
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case reasoning
        case cacheRead
        case cacheWrite
        case uncategorized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(Int.self, forKey: .input)
        output = try container.decode(Int.self, forKey: .output)
        reasoning = try container.decode(Int.self, forKey: .reasoning)
        cacheRead = try container.decode(Int.self, forKey: .cacheRead)
        cacheWrite = try container.decode(Int.self, forKey: .cacheWrite)
        uncategorized =
            try container.decodeIfPresent(Int.self, forKey: .uncategorized) ?? 0
    }
}

public struct UsageBucket: Codable, Hashable, Sendable, Identifiable {
    public let day: Date
    public let tokens: Int
    public let costUSD: Double?

    public init(day: Date, tokens: Int, costUSD: Double?) {
        self.day = day
        self.tokens = tokens
        self.costUSD = costUSD
    }

    public var id: Date { day }
}

public struct ModelUsage: Codable, Hashable, Sendable, Identifiable {
    public let providerID: String?
    public let modelID: String
    public let tokens: TokenBreakdown
    public let costUSD: Double?

    public init(
        providerID: String?,
        modelID: String,
        tokens: TokenBreakdown,
        costUSD: Double?
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.tokens = tokens
        self.costUSD = costUSD
    }

    public var id: String {
        [providerID, modelID]
            .compactMap { $0 }
            .joined(separator: "/")
    }
}

public struct QuotaWindow: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let durationMinutes: Int?
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let provenance: MetricProvenance

    public init(
        id: String,
        label: String,
        durationMinutes: Int?,
        usedPercent: Double?,
        resetsAt: Date?,
        provenance: MetricProvenance
    ) {
        self.id = id
        self.label = label
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
        self.resetsAt = resetsAt
        self.provenance = provenance
    }
}

public struct ProviderSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let provider: ProviderID
    public let observedAt: Date
    public var health: ProviderHealth
    public let tokens: TokenBreakdown?
    public let costDisplay: CostDisplay
    public let dailyBuckets: [UsageBucket]
    public let quotaWindows: [QuotaWindow]
    public let modelBreakdowns: [ModelUsage]

    public init(
        provider: ProviderID,
        observedAt: Date,
        health: ProviderHealth,
        tokens: TokenBreakdown?,
        costDisplay: CostDisplay,
        dailyBuckets: [UsageBucket],
        quotaWindows: [QuotaWindow],
        modelBreakdowns: [ModelUsage]
    ) {
        self.provider = provider
        self.observedAt = observedAt
        self.health = health
        self.tokens = tokens
        self.costDisplay = costDisplay
        self.dailyBuckets = dailyBuckets
        self.quotaWindows = quotaWindows
        self.modelBreakdowns = modelBreakdowns
    }

    public var id: ProviderID { provider }

    public var costUSD: Double? {
        guard case let .exactUSD(value) = costDisplay else { return nil }
        return value
    }

    public var primaryQuota: QuotaWindow? { quotaWindows.first }

    public static func unavailable(
        provider: ProviderID,
        health: ProviderHealth,
        observedAt: Date = Date()
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            observedAt: observedAt,
            health: health,
            tokens: nil,
            costDisplay: .unavailable,
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: []
        )
    }
}

public struct UsageState: Sendable, Equatable {
    public var snapshots: [ProviderID: ProviderSnapshot]

    public init(snapshots: [ProviderID: ProviderSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public subscript(provider: ProviderID) -> ProviderSnapshot? {
        snapshots[provider]
    }
}
