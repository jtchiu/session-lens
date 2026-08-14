import CryptoKit
import Foundation

public struct ClaudeNormalizedRateLimit: Codable, Hashable, Sendable {
    public let usedPercent: Double?
    public let resetsAt: Date?

    public init(usedPercent: Double?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ClaudeNormalizedCache: Codable, Hashable, Sendable {
    public static let allowedKeys: Set<String> = [
        "observedAt",
        "reportedSessionTokenTotal",
        "sessionHash",
        "modelID",
        "modelDisplayName",
        "estimatedSessionCostUSD",
        "contextTokens",
        "contextWindowSize",
        "contextUsedPercent",
        "fiveHour",
        "sevenDay",
        "version",
    ]

    public let observedAt: Date
    public let sessionHash: String
    public let modelID: String?
    public let modelDisplayName: String?
    public let estimatedSessionCostUSD: Double?
    public let reportedSessionTokenTotal: Int?
    public let contextTokens: TokenBreakdown?
    public let contextWindowSize: Int?
    public let contextUsedPercent: Double?
    public let fiveHour: ClaudeNormalizedRateLimit?
    public let sevenDay: ClaudeNormalizedRateLimit?
    public let version: String?

    public init(
        observedAt: Date,
        sessionHash: String,
        modelID: String?,
        modelDisplayName: String?,
        estimatedSessionCostUSD: Double?,
        reportedSessionTokenTotal: Int? = nil,
        contextTokens: TokenBreakdown?,
        contextWindowSize: Int?,
        contextUsedPercent: Double?,
        fiveHour: ClaudeNormalizedRateLimit?,
        sevenDay: ClaudeNormalizedRateLimit?,
        version: String?
    ) {
        self.observedAt = observedAt
        self.sessionHash = sessionHash
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.estimatedSessionCostUSD = estimatedSessionCostUSD
        self.reportedSessionTokenTotal = reportedSessionTokenTotal.map { max(0, $0) }
        self.contextTokens = contextTokens
        self.contextWindowSize = contextWindowSize
        self.contextUsedPercent = contextUsedPercent
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case observedAt
        case sessionHash
        case modelID
        case modelDisplayName
        case estimatedSessionCostUSD
        case reportedSessionTokenTotal
        case contextTokens
        case contextWindowSize
        case contextUsedPercent
        case fiveHour
        case sevenDay
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        sessionHash = try container.decode(String.self, forKey: .sessionHash)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        modelDisplayName = try container.decodeIfPresent(String.self, forKey: .modelDisplayName)
        estimatedSessionCostUSD = try container.decodeIfPresent(
            Double.self,
            forKey: .estimatedSessionCostUSD
        )
        if let reportedSessionTokenTotal = try container.decodeIfPresent(
            Int.self,
            forKey: .reportedSessionTokenTotal
        ) {
            self.reportedSessionTokenTotal = max(0, reportedSessionTokenTotal)
        } else {
            self.reportedSessionTokenTotal = nil
        }
        contextTokens = try container.decodeIfPresent(
            TokenBreakdown.self,
            forKey: .contextTokens
        )
        contextWindowSize = try container.decodeIfPresent(Int.self, forKey: .contextWindowSize)
        contextUsedPercent = try container.decodeIfPresent(Double.self, forKey: .contextUsedPercent)
        fiveHour = try container.decodeIfPresent(
            ClaudeNormalizedRateLimit.self,
            forKey: .fiveHour
        )
        sevenDay = try container.decodeIfPresent(
            ClaudeNormalizedRateLimit.self,
            forKey: .sevenDay
        )
        version = try container.decodeIfPresent(String.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(sessionHash, forKey: .sessionHash)
        try container.encodeIfPresent(modelID, forKey: .modelID)
        try container.encodeIfPresent(modelDisplayName, forKey: .modelDisplayName)
        try container.encodeIfPresent(estimatedSessionCostUSD, forKey: .estimatedSessionCostUSD)
        try container.encodeIfPresent(
            reportedSessionTokenTotal,
            forKey: .reportedSessionTokenTotal
        )
        try container.encodeIfPresent(contextTokens, forKey: .contextTokens)
        try container.encodeIfPresent(contextWindowSize, forKey: .contextWindowSize)
        try container.encodeIfPresent(contextUsedPercent, forKey: .contextUsedPercent)
        try container.encodeIfPresent(fiveHour, forKey: .fiveHour)
        try container.encodeIfPresent(sevenDay, forKey: .sevenDay)
        try container.encodeIfPresent(version, forKey: .version)
    }
}

public struct ClaudeStatusPayload: Decodable, Sendable {
    private let sessionID: String
    private let model: Model?
    private let cost: Cost?
    private let contextWindow: ContextWindow?
    private let rateLimits: RateLimits?
    private let version: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case model
        case cost
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
        case version
    }

    public func normalized(observedAt: Date) -> ClaudeNormalizedCache {
        ClaudeNormalizedCache(
            observedAt: observedAt,
            sessionHash: Self.hash(sessionID),
            modelID: model?.id,
            modelDisplayName: model?.displayName,
            estimatedSessionCostUSD: cost?.totalCostUSD.map { max(0, $0) },
            reportedSessionTokenTotal: contextWindow?.reportedSessionTokenTotal,
            contextTokens: contextWindow?.normalizedTokens,
            contextWindowSize: contextWindow?.contextWindowSize.map { max(0, $0) },
            contextUsedPercent: contextWindow?.usedPercentage.map {
                min(100, max(0, $0))
            },
            fiveHour: rateLimits?.fiveHour?.normalized,
            sevenDay: rateLimits?.sevenDay?.normalized,
            version: version
        )
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension ClaudeStatusPayload {
    struct Model: Decodable, Sendable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    struct Cost: Decodable, Sendable {
        let totalCostUSD: Double?

        enum CodingKeys: String, CodingKey {
            case totalCostUSD = "total_cost_usd"
        }
    }

    struct ContextWindow: Decodable, Sendable {
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let contextWindowSize: Int?
        let usedPercentage: Double?
        let currentUsage: CurrentUsage?

        enum CodingKeys: String, CodingKey {
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case contextWindowSize = "context_window_size"
            case usedPercentage = "used_percentage"
            case currentUsage = "current_usage"
        }

        var normalizedTokens: TokenBreakdown? {
            if let currentUsage {
                return TokenBreakdown(
                    input: max(0, currentUsage.inputTokens),
                    output: max(0, currentUsage.outputTokens),
                    reasoning: 0,
                    cacheRead: max(0, currentUsage.cacheReadInputTokens),
                    cacheWrite: max(0, currentUsage.cacheCreationInputTokens)
                )
            }

            guard totalInputTokens != nil || totalOutputTokens != nil else {
                return nil
            }
            return TokenBreakdown(
                input: 0,
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                uncategorized: max(0, totalInputTokens ?? 0)
                    + max(0, totalOutputTokens ?? 0)
            )
        }

        var reportedSessionTokenTotal: Int? {
            guard totalInputTokens != nil || totalOutputTokens != nil else {
                return nil
            }
            let input = max(0, totalInputTokens ?? 0)
            let output = max(0, totalOutputTokens ?? 0)
            return input > Int.max - output ? Int.max : input + output
        }
    }

    struct CurrentUsage: Decodable, Sendable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationInputTokens: Int
        let cacheReadInputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decodeIfPresent(
                Int.self,
                forKey: .inputTokens
            ) ?? 0
            outputTokens = try container.decodeIfPresent(
                Int.self,
                forKey: .outputTokens
            ) ?? 0
            cacheCreationInputTokens = try container.decodeIfPresent(
                Int.self,
                forKey: .cacheCreationInputTokens
            ) ?? 0
            cacheReadInputTokens = try container.decodeIfPresent(
                Int.self,
                forKey: .cacheReadInputTokens
            ) ?? 0
        }
    }

    struct RateLimits: Decodable, Sendable {
        let fiveHour: RateLimit?
        let sevenDay: RateLimit?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    struct RateLimit: Decodable, Sendable {
        let usedPercentage: Double?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }

        var normalized: ClaudeNormalizedRateLimit {
            ClaudeNormalizedRateLimit(
                usedPercent: usedPercentage.map { min(100, max(0, $0)) },
                resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }
}
