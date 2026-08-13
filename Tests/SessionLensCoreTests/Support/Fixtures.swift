import Foundation
@testable import SessionLensCore

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_735_689_600)
    static let claudeOfficialStatusLineJSON = Data(
        #"""
        {
          "session_id": "session-secret",
          "model": {"id": "claude-opus-4-1", "display_name": "Opus 4.1"},
          "cost": {
            "total_cost_usd": 0.01234,
            "total_duration_ms": 45000,
            "total_api_duration_ms": 2300,
            "total_lines_added": 156,
            "total_lines_removed": 23
          },
          "context_window": {
            "total_input_tokens": 15500,
            "total_output_tokens": 1200,
            "context_window_size": 200000,
            "used_percentage": 8,
            "remaining_percentage": 92,
            "current_usage": {
              "input_tokens": 8500,
              "output_tokens": 1200,
              "cache_creation_input_tokens": 5000,
              "cache_read_input_tokens": 2000
            }
          },
          "rate_limits": {
            "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
            "seven_day": {"used_percentage": 41.2, "resets_at": 1738857600}
          },
          "version": "2.1.90",
          "cwd": "/private/project",
          "workspace": {"current_dir": "/private/project"},
          "transcript_path": "/private/transcript.jsonl",
          "session_name": "private session",
          "prompt": "private prompt",
          "source": "private source",
          "git": {"branch": "secret"},
          "agent": {"name": "secret-agent"}
        }
        """#.utf8
    )
    static let openCodeDatabaseURL = URL(fileURLWithPath: "/dev/null")
    static let sqliteURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    static let openCodeRowsJSON = Data(
        #"""
        [
          {
            "day": "2025-01-01",
            "provider_id": "openai",
            "model_id": "gpt-5",
            "cost": 0.5,
            "tokens_input": 1000,
            "tokens_output": 500,
            "tokens_reasoning": 100,
            "tokens_cache_read": 200,
            "tokens_cache_write": 100
          },
          {
            "day": "2025-01-02",
            "provider_id": "openai",
            "model_id": "gpt-5",
            "cost": 0.75,
            "tokens_input": 1500,
            "tokens_output": 400,
            "tokens_reasoning": 100,
            "tokens_cache_read": 200,
            "tokens_cache_write": 100
          }
        ]
        """#.utf8
    )

    static func codexResponse(
        id: Int,
        result: [String: JSONValue]
    ) -> [String: JSONValue] {
        [
            "id": .number(Double(id)),
            "result": .object(result),
        ]
    }

    static func codexInitializeResponse(id: Int) -> [String: JSONValue] {
        codexResponse(id: id, result: [:])
    }

    static func codexRateLimitResponse(id: Int) -> [String: JSONValue] {
        codexResponse(
            id: id,
            result: [
                "rateLimits": .object(codexRateLimitSnapshot),
                "rateLimitsByLimitId": .object([
                    "codex": .object(codexRateLimitSnapshot)
                ]),
            ]
        )
    }

    static func codexUsageResponse(id: Int) -> [String: JSONValue] {
        codexResponse(
            id: id,
            result: [
                "summary": .object([
                    "lifetimeTokens": .number(500_000_000),
                    "currentStreakDays": .number(4),
                    "longestStreakDays": .number(12),
                    "peakDailyTokens": .number(453_544_969),
                    "longestRunningTurnSec": .number(3_600),
                ]),
                "dailyUsageBuckets": .array([
                    .object([
                        "startDate": .string("2025-01-01"),
                        "tokens": .number(1_000),
                    ]),
                    .object([
                        "startDate": .string("2025-01-02"),
                        "tokens": .number(453_544_969),
                    ]),
                ]),
            ]
        )
    }

    private static let codexRateLimitSnapshot: [String: JSONValue] = [
        "limitId": .string("codex"),
        "limitName": .string("Codex"),
        "planType": .string("plus"),
        "primary": .object([
            "usedPercent": .number(42),
            "windowDurationMins": .number(300),
            "resetsAt": .number(1_735_693_200),
        ]),
        "secondary": .object([
            "usedPercent": .number(36),
            "windowDurationMins": .number(10_080),
            "resetsAt": .number(1_736_294_400),
        ]),
        "rateLimitReachedType": .null,
        "spendControlReached": .bool(false),
    ]

    static let codexTwoWindowLimits = CodexRateLimitsResponse(
        rateLimits: CodexRateLimitSnapshot(
            limitId: "codex",
            limitName: "Codex",
            planType: "plus",
            primary: CodexRateLimitWindow(
                usedPercent: 42,
                windowDurationMins: 300,
                resetsAt: 1_735_693_200
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 36,
                windowDurationMins: 10_080,
                resetsAt: 1_736_294_400
            )
        ),
        rateLimitsByLimitId: [
            "codex": CodexRateLimitSnapshot(
                limitId: "codex",
                limitName: "Codex",
                planType: "plus",
                primary: CodexRateLimitWindow(
                    usedPercent: 42,
                    windowDurationMins: 300,
                    resetsAt: 1_735_693_200
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 36,
                    windowDurationMins: 10_080,
                    resetsAt: 1_736_294_400
                )
            )
        ]
    )

    static let codexUsage = CodexAccountUsageResponse(
        summary: CodexAccountUsageSummary(
            lifetimeTokens: 500_000_000,
            currentStreakDays: 4,
            longestStreakDays: 12,
            peakDailyTokens: 453_544_969,
            longestRunningTurnSec: 3_600
        ),
        dailyUsageBuckets: [
            CodexDailyUsageBucket(startDate: "2025-01-01", tokens: 1_000),
            CodexDailyUsageBucket(
                startDate: "2025-01-02",
                tokens: 453_544_969
            ),
        ]
    )

    static func day(_ offset: Int) -> Date {
        Calendar.utc.date(byAdding: .day, value: offset, to: now)!
    }

    static func quota(
        _ usedPercent: Double?,
        id: String = "weekly",
        label: String = "Weekly",
        provenance: MetricProvenance = .exactProvider
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            label: label,
            durationMinutes: 10_080,
            usedPercent: usedPercent,
            resetsAt: day(1),
            provenance: provenance
        )
    }

    static func unavailable(
        _ provider: ProviderID,
        health: ProviderHealth = .toolMissing
    ) -> ProviderSnapshot {
        .unavailable(provider: provider, health: health, observedAt: now)
    }

    static func aggregateSnapshot(
        provider: ProviderID,
        observedAt: Date = now,
        tokens: TokenBreakdown = .init(
            input: 100,
            output: 50,
            reasoning: 25,
            cacheRead: 20,
            cacheWrite: 5
        ),
        costDisplay: CostDisplay = .exactUSD(1.25),
        quotaWindows: [QuotaWindow] = [],
        dailyBuckets: [UsageBucket]? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            observedAt: observedAt,
            health: .ready,
            tokens: tokens,
            costDisplay: costDisplay,
            dailyBuckets: dailyBuckets ?? [
                UsageBucket(day: day(0), tokens: tokens.total, costUSD: 1.25),
            ],
            quotaWindows: quotaWindows,
            modelBreakdowns: []
        )
    }

    static func codexSnapshot(
        observedAt: Date = now,
        percent: Double = 36
    ) -> ProviderSnapshot {
        aggregateSnapshot(
            provider: .codex,
            observedAt: observedAt,
            costDisplay: .includedWithPlan,
            quotaWindows: [quota(percent)]
        )
    }

    static func openCodeLocalBudget(_ percent: Double) -> ProviderSnapshot {
        aggregateSnapshot(
            provider: .opencode,
            quotaWindows: [
                quota(
                    percent,
                    id: "local-weekly",
                    label: "Weekly",
                    provenance: .localBudget
                )
            ]
        )
    }

    static func openCodeSnapshot(
        providerIDs: [String],
        observedAt: Date = now
    ) -> ProviderSnapshot {
        let breakdowns = providerIDs.enumerated().map { index, providerID in
            ModelUsage(
                providerID: providerID,
                modelID: "model-\(index)",
                tokens: TokenBreakdown(
                    input: 100,
                    output: 25,
                    reasoning: 0,
                    cacheRead: 0,
                    cacheWrite: 0
                ),
                costUSD: 0.25
            )
        }
        let tokens = TokenBreakdown(
            input: breakdowns.reduce(0) { $0 + $1.tokens.input },
            output: breakdowns.reduce(0) { $0 + $1.tokens.output },
            reasoning: 0,
            cacheRead: 0,
            cacheWrite: 0
        )
        return ProviderSnapshot(
            provider: .opencode,
            observedAt: observedAt,
            health: .ready,
            tokens: tokens,
            costDisplay: .exactUSD(Double(providerIDs.count) * 0.25),
            dailyBuckets: [
                UsageBucket(day: observedAt, tokens: tokens.total, costUSD: 0.25)
            ],
            quotaWindows: [],
            modelBreakdowns: breakdowns
        )
    }

    static func claudeCache(
        tokens: Int,
        sessionCostUSD: Double?,
        sessionHash: String = String(repeating: "a", count: 64),
        observedAt: Date = now
    ) -> ClaudeNormalizedCache {
        ClaudeNormalizedCache(
            observedAt: observedAt,
            sessionHash: sessionHash,
            modelID: "claude-opus-4-1",
            modelDisplayName: "Opus 4.1",
            estimatedSessionCostUSD: sessionCostUSD,
            contextTokens: TokenBreakdown(
                input: tokens,
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0
            ),
            contextWindowSize: 200_000,
            contextUsedPercent: 12,
            fiveHour: ClaudeNormalizedRateLimit(
                usedPercent: 23.5,
                resetsAt: now.addingTimeInterval(3_600)
            ),
            sevenDay: ClaudeNormalizedRateLimit(
                usedPercent: 41.2,
                resetsAt: now.addingTimeInterval(86_400)
            ),
            version: "2.1.90"
        )
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
