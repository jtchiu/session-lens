import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

public struct CodexAccountUsageResponse: Codable, Hashable, Sendable {
    public let summary: CodexAccountUsageSummary
    public let dailyUsageBuckets: [CodexDailyUsageBucket]?

    public init(
        summary: CodexAccountUsageSummary,
        dailyUsageBuckets: [CodexDailyUsageBucket]?
    ) {
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
    }
}

public struct CodexAccountUsageSummary: Codable, Hashable, Sendable {
    public let lifetimeTokens: Int?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?
    public let peakDailyTokens: Int?
    public let longestRunningTurnSec: Int?

    public init(
        lifetimeTokens: Int? = nil,
        currentStreakDays: Int? = nil,
        longestStreakDays: Int? = nil,
        peakDailyTokens: Int? = nil,
        longestRunningTurnSec: Int? = nil
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
    }
}

public struct CodexDailyUsageBucket: Codable, Hashable, Sendable {
    public let startDate: String
    public let tokens: Int

    public init(startDate: String, tokens: Int) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

public struct CodexRateLimitsResponse: Codable, Hashable, Sendable {
    public let rateLimits: CodexRateLimitSnapshot
    public let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?

    public init(
        rateLimits: CodexRateLimitSnapshot,
        rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }
}

public struct CodexRateLimitSnapshot: Codable, Hashable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let planType: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let rateLimitReachedType: String?
    public let spendControlReached: Bool?

    public init(
        limitId: String? = nil,
        limitName: String? = nil,
        planType: String? = nil,
        primary: CodexRateLimitWindow? = nil,
        secondary: CodexRateLimitWindow? = nil,
        rateLimitReachedType: String? = nil,
        spendControlReached: Bool? = nil
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.rateLimitReachedType = rateLimitReachedType
        self.spendControlReached = spendControlReached
    }
}

public struct CodexRateLimitWindow: Codable, Hashable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int64?

    public init(
        usedPercent: Int,
        windowDurationMins: Int? = nil,
        resetsAt: Int64? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public protocol CodexAccountReading: Sendable {
    func readUsage() async throws -> CodexAccountUsageResponse
    func readRateLimits() async throws -> CodexRateLimitsResponse
}
