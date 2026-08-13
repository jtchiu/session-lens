import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct PrivacyBoundaryTests {
    @Test
    func openCodeAggregateQueryContainsOnlyApprovedIdentifiers() {
        let approved: Set<String> = [
            "asc",
            "as",
            "by",
            "cost",
            "date",
            "day",
            "from",
            "group",
            "json_extract",
            "model",
            "model_id",
            "order",
            "provider_id",
            "select",
            "session",
            "sum",
            "time_updated",
            "tokens_cache_read",
            "tokens_cache_write",
            "tokens_input",
            "tokens_output",
            "tokens_reasoning",
        ]
        let identifiers = SQLIdentifierLexer.identifiers(
            in: OpenCodeProvider.fixedAggregateSQL
        )

        #expect(OpenCodeProvider.allowedSQLIdentifiers == approved)
        #expect(identifiers == approved)
    }

    @Test
    func codexClientMethodAllowlistIsClosedToAccountUsage() {
        #expect(
            CodexAppServerClient.allowedMethods == [
                "account/rateLimits/read",
                "account/usage/read",
                "initialize",
                "initialized",
            ]
        )
    }

    @Test
    func persistentModelsContainNoSensitivePropertyNames() {
        let approved = Set([
            "costKindRaw",
            "costUSD",
            "createdAt",
            "day",
            "healthRaw",
            "key",
            "observedAt",
            "providerRaw",
            "quotaData",
            "settingsData",
            "tokenData",
            "tokens",
            "updatedAt",
        ])
        let forbiddenFragments = [
            "command",
            "content",
            "credential",
            "diff",
            "message",
            "path",
            "project",
            "prompt",
            "reasoning",
            "response",
            "secret",
            "source",
            "title",
            "transcript",
        ]

        let properties = PersistencePrivacyIntrospector.persistedPropertyNames
        #expect(properties == approved)

        for property in properties {
            for fragment in forbiddenFragments {
                #expect(
                    !property.lowercased().contains(fragment),
                    "Persisted property '\(property)' contains forbidden fragment '\(fragment)'"
                )
            }
        }
    }

    @Test
    func claudeNormalizedCacheEncodesOnlyApprovedAggregateKeys() throws {
        let approved: Set<String> = [
            "contextTokens",
            "contextUsedPercent",
            "contextWindowSize",
            "estimatedSessionCostUSD",
            "fiveHour",
            "modelDisplayName",
            "modelID",
            "observedAt",
            "sessionHash",
            "sevenDay",
            "version",
        ]
        let cache = ClaudeNormalizedCache(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sessionHash: "synthetic-hash",
            modelID: "claude-synthetic",
            modelDisplayName: "Synthetic Claude",
            estimatedSessionCostUSD: 1.25,
            contextTokens: TokenBreakdown(
                input: 100,
                output: 20,
                reasoning: 0,
                cacheRead: 10,
                cacheWrite: 5
            ),
            contextWindowSize: 200_000,
            contextUsedPercent: 7.5,
            fiveHour: ClaudeNormalizedRateLimit(
                usedPercent: 25,
                resetsAt: Date(timeIntervalSince1970: 1_700_003_600)
            ),
            sevenDay: ClaudeNormalizedRateLimit(
                usedPercent: 40,
                resetsAt: Date(timeIntervalSince1970: 1_700_604_800)
            ),
            version: "synthetic"
        )

        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(cache)
            ) as? [String: Any]
        )
        let encodedKeys = Set(object.keys)

        #expect(ClaudeNormalizedCache.allowedKeys == approved)
        #expect(encodedKeys == approved)
    }
}
