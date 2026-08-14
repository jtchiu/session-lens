import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct SpendSummaryLoaderTests {
    @Test
    func assemblesPersistedBucketsSamplesAndSnapshotProvenance() {
        let now = Self.date(2025, 1, 15)
        let claudeSnapshot = ProviderSnapshot(
            provider: .claude,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .estimatedUSD(3),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: []
        )
        let codexSnapshot = ProviderSnapshot(
            provider: .codex,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .includedWithPlan,
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: []
        )
        let samples = [
            ProviderSpendSample(
                provider: .claude,
                observedAt: Self.date(2025, 1, 14),
                scopeID: "claude",
                cumulativeCostUSD: 1,
                cumulativeTokens: 100,
                provenance: .estimated
            ),
            ProviderSpendSample(
                provider: .claude,
                observedAt: Self.date(2025, 1, 15),
                scopeID: "claude",
                cumulativeCostUSD: 3,
                cumulativeTokens: 500,
                provenance: .estimated
            ),
        ]
        let summary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: [
                .claude: claudeSnapshot,
                .codex: codexSnapshot,
            ],
            dailyBuckets: [
                .opencode: [
                    UsageBucket(
                        day: Self.date(2025, 1, 15),
                        tokens: 100,
                        costUSD: 1
                    ),
                ],
            ],
            samples: samples,
            calendar: Self.calendar
        )

        #expect(summary.providers[.opencode]?.week.costUSD == 1)
        #expect(summary.providers[.claude]?.week.costUSD == 2)
        #expect(summary.providers[.claude]?.week.provenance == .estimated)
        #expect(summary.providers[.codex]?.week.provenance == .includedWithPlan)
        #expect(summary.combined.week.costUSD == 3)
    }

    @Test
    func keepsActualSpendSeparateWhileEstimatingCodexAndLeavingUnknownModelsUnavailable() {
        let now = Self.date(2025, 1, 15)
        let codexSnapshot = ProviderSnapshot(
            provider: .codex,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .includedWithPlan,
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: []
        )
        let unknownModelSnapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(9),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "unknown-model",
                    tokens: TokenBreakdown(
                        input: 3,
                        output: 1,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 9
                )
            ]
        )
        let catalog = PricingCatalog(
            models: [
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "gpt-codex",
                    rate: PricingRate(inputPerMillion: 1, outputPerMillion: 3)
                )
            ],
            updatedAt: now,
            fetchedAt: now
        )

        let summary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: [
                .codex: codexSnapshot,
                .opencode: unknownModelSnapshot,
            ],
            dailyBuckets: [
                .codex: [
                    UsageBucket(day: Self.date(2025, 1, 14), tokens: 1_000_000, costUSD: nil),
                    UsageBucket(day: Self.date(2025, 1, 10), tokens: 2_000_000, costUSD: nil),
                ],
                .opencode: [
                    UsageBucket(day: Self.date(2025, 1, 14), tokens: 500_000, costUSD: 9),
                ],
            ],
            samples: [],
            catalogState: PricingCatalogState(source: .cached, catalog: catalog),
            codexModelID: "gpt-codex",
            calendar: Self.calendar
        )

        #expect(summary.providers[.codex]?.week.costUSD == nil)
        #expect(summary.providers[.codex]?.month.costUSD == nil)
        #expect(summary.providers[.codex]?.retained.costUSD == nil)
        #expect(summary.providers[.codex]?.week.tokens == 1_000_000)
        #expect(summary.providers[.codex]?.month.tokens == 3_000_000)
        #expect(summary.providers[.codex]?.retained.tokens == 3_000_000)
        #expect(summary.combined.week.costUSD == 9)

        #expect(summary.apiEquivalent.providers[.codex]?.week.costUSD == 2)
        #expect(summary.apiEquivalent.providers[.codex]?.month.costUSD == 6)
        #expect(summary.apiEquivalent.providers[.codex]?.retained.costUSD == 6)
        #expect(summary.apiEquivalent.providers[.codex]?.week.coverage == .detectedProviderModel)
        #expect(summary.apiEquivalent.providers[.opencode]?.week.costUSD == nil)
        #expect(summary.apiEquivalent.providers[.opencode]?.week.coverage == .unavailable)
        #expect(summary.apiEquivalent.combined.week.costUSD == 2)
    }

    @Test
    func decodesLegacySummaryWithoutApiEquivalentData() throws {
        let encoded = try JSONEncoder().encode(
            SpendSummary.empty(retentionDays: 30)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "apiEquivalent")
        let data = try JSONSerialization.data(withJSONObject: object)

        let summary = try JSONDecoder().decode(SpendSummary.self, from: data)

        #expect(summary.apiEquivalent == .unavailable)
    }

    @Test
    func doesNotTurnUnpricedTokenCategoriesIntoZeroDollarEstimates() {
        let now = Self.date(2025, 1, 15)
        let snapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(7),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "output-only-model",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 7
                )
            ]
        )
        let catalog = PricingCatalog(
            models: [
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "output-only-model",
                    rate: PricingRate(outputPerMillion: 3)
                )
            ],
            updatedAt: now,
            fetchedAt: now
        )

        let summary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: [.opencode: snapshot],
            dailyBuckets: [
                .opencode: [
                    UsageBucket(day: Self.date(2025, 1, 14), tokens: 1_000_000, costUSD: 7),
                ]
            ],
            samples: [],
            catalogState: PricingCatalogState(source: .live, catalog: catalog),
            calendar: Self.calendar
        )

        #expect(summary.apiEquivalent.providers[.opencode]?.week.costUSD == nil)
        #expect(summary.apiEquivalent.combined.week.costUSD == nil)
    }

    @Test
    func selectsTheMostRecentlyObservedModelInsteadOfLexicalBreakdownOrder() {
        let now = Self.date(2025, 1, 15)
        let oldObservedAt = Self.date(2025, 1, 10)
        let currentObservedAt = Self.date(2025, 1, 14)
        let snapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(11),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "a-current-model",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 10,
                    lastObservedAt: currentObservedAt
                ),
                ModelUsage(
                    providerID: "openai",
                    modelID: "z-old-model",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 1,
                    lastObservedAt: oldObservedAt
                ),
            ]
        )
        let catalog = PricingCatalog(
            models: [
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "a-current-model",
                    rate: PricingRate(inputPerMillion: 10)
                ),
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "z-old-model",
                    rate: PricingRate(inputPerMillion: 1)
                ),
            ],
            updatedAt: now,
            fetchedAt: now
        )

        let summary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: [.opencode: snapshot],
            dailyBuckets: [
                .opencode: [
                    UsageBucket(day: currentObservedAt, tokens: 1_000_000, costUSD: 11),
                ]
            ],
            samples: [],
            catalogState: PricingCatalogState(source: .live, catalog: catalog),
            calendar: Self.calendar
        )

        #expect(summary.apiEquivalent.providers[.opencode]?.week.modelID == "a-current-model")
        #expect(summary.apiEquivalent.providers[.opencode]?.week.costUSD == 10)
        #expect(summary.apiEquivalent.providers[.opencode]?.week.coverage == .latestKnownModel)
    }

    @Test
    func usesStableModelIDFallbackForLegacyBreakdownsWithoutRecency() {
        let now = Self.date(2025, 1, 15)
        let snapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(11),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "a-model",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 10
                ),
                ModelUsage(
                    providerID: "openai",
                    modelID: "z-model",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 1
                ),
            ]
        )
        let catalog = PricingCatalog(
            models: [
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "a-model",
                    rate: PricingRate(inputPerMillion: 10)
                ),
                PricingCatalogModel(
                    providerID: "openai",
                    modelID: "z-model",
                    rate: PricingRate(inputPerMillion: 1)
                ),
            ],
            updatedAt: now,
            fetchedAt: now
        )

        let summary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: [.opencode: snapshot],
            dailyBuckets: [
                .opencode: [
                    UsageBucket(day: now, tokens: 1_000_000, costUSD: 11),
                ]
            ],
            samples: [],
            catalogState: PricingCatalogState(source: .live, catalog: catalog),
            calendar: Self.calendar
        )

        #expect(summary.apiEquivalent.providers[.opencode]?.week.modelID == "a-model")
        #expect(summary.apiEquivalent.providers[.opencode]?.week.costUSD == 10)
    }
}

private extension SpendSummaryLoaderTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
