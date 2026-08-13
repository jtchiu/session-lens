import Foundation

struct OpenCodeAggregateRow: Decodable, Sendable {
    let day: String
    let providerID: String?
    let modelID: String?
    let cost: Double
    let tokensInput: Int
    let tokensOutput: Int
    let tokensReasoning: Int
    let tokensCacheRead: Int
    let tokensCacheWrite: Int

    enum CodingKeys: String, CodingKey {
        case day
        case providerID = "provider_id"
        case modelID = "model_id"
        case cost
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
        case tokensReasoning = "tokens_reasoning"
        case tokensCacheRead = "tokens_cache_read"
        case tokensCacheWrite = "tokens_cache_write"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
        tokensInput = try container.decodeIfPresent(Int.self, forKey: .tokensInput) ?? 0
        tokensOutput = try container.decodeIfPresent(Int.self, forKey: .tokensOutput) ?? 0
        tokensReasoning =
            try container.decodeIfPresent(Int.self, forKey: .tokensReasoning) ?? 0
        tokensCacheRead =
            try container.decodeIfPresent(Int.self, forKey: .tokensCacheRead) ?? 0
        tokensCacheWrite =
            try container.decodeIfPresent(Int.self, forKey: .tokensCacheWrite) ?? 0
    }

    var tokens: TokenBreakdown {
        TokenBreakdown(
            input: max(0, tokensInput),
            output: max(0, tokensOutput),
            reasoning: max(0, tokensReasoning),
            cacheRead: max(0, tokensCacheRead),
            cacheWrite: max(0, tokensCacheWrite)
        )
    }
}

struct OpenCodeModelKey: Hashable, Sendable {
    let providerID: String?
    let modelID: String
}

struct OpenCodeAccumulator: Sendable {
    var input = 0
    var output = 0
    var reasoning = 0
    var cacheRead = 0
    var cacheWrite = 0
    var costUSD = 0.0

    mutating func add(_ row: OpenCodeAggregateRow) {
        let tokens = row.tokens
        input += tokens.input
        output += tokens.output
        reasoning += tokens.reasoning
        cacheRead += tokens.cacheRead
        cacheWrite += tokens.cacheWrite
        costUSD += max(0, row.cost)
    }

    var tokens: TokenBreakdown {
        TokenBreakdown(
            input: input,
            output: output,
            reasoning: reasoning,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite
        )
    }
}
