import Foundation
import SessionLensCore

enum PreviewFixtures {
    private static let now = Date()

    static let settings = AppSettings(
        refreshIntervalSeconds: 60,
        chartRange: .sevenDays,
        providerOrder: [.opencode, .claude, .codex],
        notificationThresholds: [70, 90],
        menuBarDisplayMode: .urgent,
        historyRetentionDays: 365
    )

    static let codexModelID = "gpt-5"

    static let pricingCatalog = PricingCatalog(
        models: [
            PricingCatalogModel(
                providerID: "openai",
                modelID: "gpt-5",
                rate: PricingRate(
                    inputPerMillion: 2.5,
                    outputPerMillion: 10,
                    reasoningPerMillion: 10,
                    cacheReadPerMillion: 0.25,
                    cacheWritePerMillion: 3.75
                )
            ),
            PricingCatalogModel(
                providerID: "anthropic",
                modelID: "claude-sonnet",
                rate: PricingRate(
                    inputPerMillion: 3,
                    outputPerMillion: 15,
                    reasoningPerMillion: 15,
                    cacheReadPerMillion: 0.3,
                    cacheWritePerMillion: 3.75
                )
            ),
        ],
        updatedAt: now,
        fetchedAt: now
    )

    static let pricingState = PricingCatalogState(
        source: .live,
        catalog: pricingCatalog
    )

    static let pricingCatalogClient = PricingCatalogClient(
        cacheURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLens-preview-pricing-catalog.json"),
        transport: PreviewPricingCatalogTransport()
    )

    static let pricingCatalogData = Data(
        #"""
        {
          "openai": {
            "models": {
              "gpt-5": {
                "cost": {
                  "input": 2.5,
                  "output": 10,
                  "reasoning": 10,
                  "cache_read": 0.25,
                  "cache_write": 3.75
                }
              }
            }
          },
          "anthropic": {
            "models": {
              "claude-sonnet": {
                "cost": {
                  "input": 3,
                  "output": 15,
                  "reasoning": 15,
                  "cache_read": 0.3,
                  "cache_write": 3.75
                }
              }
            }
          }
        }
        """#.utf8
    )

    private static let claudeSpendSample = ProviderSpendSample(
        provider: .claude,
        observedAt: now,
        scopeID: "preview-claude",
        cumulativeCostUSD: 3.10,
        cumulativeTokens: 250_000,
        provenance: .estimated
    )

    private static let claudeSpendBaseline = ProviderSpendSample(
        provider: .claude,
        observedAt: Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: now
        ) ?? now,
        scopeID: "preview-claude",
        cumulativeCostUSD: 1.20,
        cumulativeTokens: 100_000,
        provenance: .estimated
    )

    static let snapshots: [ProviderID: ProviderSnapshot] = [
        .opencode: ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: TokenBreakdown(
                input: 186_200,
                output: 41_800,
                reasoning: 12_400,
                cacheRead: 92_000,
                cacheWrite: 8_400
            ),
            costDisplay: .exactUSD(4.82),
            dailyBuckets: dailyBuckets(scale: 0.72, costScale: 0.55),
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "gpt-5",
                    tokens: TokenBreakdown(
                        input: 104_000,
                        output: 22_000,
                        reasoning: 8_000,
                        cacheRead: 32_000,
                        cacheWrite: 2_000
                    ),
                    costUSD: 2.40
                ),
                ModelUsage(
                    providerID: "anthropic",
                    modelID: "claude-sonnet",
                    tokens: TokenBreakdown(
                        input: 82_000,
                        output: 19_800,
                        reasoning: 4_400,
                        cacheRead: 60_000,
                        cacheWrite: 6_400
                    ),
                    costUSD: 2.42
                ),
            ]
        ),
        .claude: ProviderSnapshot(
            provider: .claude,
            observedAt: now,
            health: .ready,
            tokens: TokenBreakdown(
                input: 120_000,
                output: 80_000,
                reasoning: 0,
                cacheRead: 40_000,
                cacheWrite: 10_000
            ),
            costDisplay: .estimatedUSD(3.10),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [],
            costSample: claudeSpendSample
        ),
        .codex: ProviderSnapshot(
            provider: .codex,
            observedAt: now,
            health: .ready,
            tokens: TokenBreakdown(
                input: 0,
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                uncategorized: 8_942_000
            ),
            costDisplay: .includedWithPlan,
            dailyBuckets: dailyBuckets(scale: 1, costScale: nil),
            quotaWindows: [
                QuotaWindow(
                    id: "codex:300",
                    label: "5-hour",
                    durationMinutes: 300,
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(7_200),
                    provenance: .exactProvider
                ),
                QuotaWindow(
                    id: "codex:10080",
                    label: "Weekly",
                    durationMinutes: 10_080,
                    usedPercent: 36,
                    resetsAt: now.addingTimeInterval(4 * 86_400),
                    provenance: .exactProvider
                ),
            ],
            modelBreakdowns: []
        ),
    ]

    static let spendSummary: SpendSummary = {
        let dailyBuckets = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { provider in
                (provider, snapshots[provider]?.dailyBuckets ?? [])
            }
        )
        return SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: settings.historyRetentionDays,
            snapshots: snapshots,
            dailyBuckets: dailyBuckets,
            samples: [claudeSpendBaseline, claudeSpendSample],
            catalogState: pricingState,
            codexModelID: codexModelID
        )
    }()

    static let quotaHistory: [ProviderID: [QuotaHistoryPoint]] = [
        .codex: [26, 22, 31, 38, 50, 45, 49, 48, 42, 39, 36]
            .enumerated()
            .map { index, value in
                QuotaHistoryPoint(
                    observedAt: now.addingTimeInterval(
                        Double(index - 10) * 30 * 60
                    ),
                    usedPercent: Double(value),
                    resetsAt: now.addingTimeInterval(4 * 86_400),
                    provenance: .exactProvider
                )
            }
    ]

    private static func dailyBuckets(
        scale: Double,
        costScale: Double?
    ) -> [UsageBucket] {
        let values = [420_000, 780_000, 690_000, 1_240_000, 980_000, 1_560_000, 1_180_000]
        return values.enumerated().map { index, value in
            let day = Calendar.current.date(
                byAdding: .day,
                value: index - values.count + 1,
                to: now
            ) ?? now
            return UsageBucket(
                day: day,
                tokens: Int(Double(value) * scale),
                costUSD: costScale.map { Double(value) / 1_000_000 * $0 }
            )
        }
    }
}

private struct PreviewPricingCatalogTransport: PricingCatalogTransport {
    func fetch(ifNoneMatch: String?) async throws -> PricingCatalogHTTPResponse {
        PricingCatalogHTTPResponse(
            statusCode: 200,
            data: PreviewFixtures.pricingCatalogData,
            etag: nil,
            lastModified: nil
        )
    }
}
