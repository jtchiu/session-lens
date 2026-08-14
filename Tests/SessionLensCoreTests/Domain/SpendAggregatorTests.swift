import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct SpendAggregatorTests {
    @Test
    func aggregatesLocalWeekMonthAndRetainedTotals() {
        let now = Self.date(2025, 1, 15, 12)
        let summary = SpendAggregator.makeSummary(
            now: now,
            historyRetentionDays: 30,
            sources: [
                .daily(
                    provider: .opencode,
                    buckets: [
                        UsageBucket(
                            day: Self.date(2025, 1, 13),
                            tokens: 100,
                            costUSD: 1
                        ),
                        UsageBucket(
                            day: Self.date(2025, 1, 15),
                            tokens: 300,
                            costUSD: 3
                        ),
                        UsageBucket(
                            day: Self.date(2025, 1, 5),
                            tokens: 999,
                            costUSD: 9
                        ),
                    ],
                    provenance: .exact
                ),
            ],
            calendar: Self.calendar
        )

        let openCode = summary.providers[.opencode]
        #expect(openCode?.week.costUSD == 4)
        #expect(openCode?.month.tokens == 1_399)
        #expect(openCode?.retained.costUSD == 13)
        #expect(openCode?.retained.tokensPerDollar == Double(1_399) / 13)
    }

    @Test
    func turnsPositiveCumulativeDeltasIntoSpendAndResetsBaseline() {
        let samples = [
            Self.sample(day: 1, scope: "first", cost: 1, tokens: 100),
            Self.sample(day: 2, scope: "first", cost: 2, tokens: 250),
            Self.sample(day: 3, scope: "first", cost: 2, tokens: 250),
            Self.sample(day: 4, scope: "first", cost: 1.5, tokens: 200),
            Self.sample(day: 5, scope: "first", cost: 2, tokens: 350),
            Self.sample(day: 6, scope: "second", cost: 0.5, tokens: 50),
            Self.sample(day: 7, scope: "second", cost: 1, tokens: 150),
        ]

        let summary = SpendAggregator.makeSummary(
            now: Self.date(2025, 1, 10),
            historyRetentionDays: 30,
            sources: [
                .samples(
                    provider: .claude,
                    samples: samples,
                    provenance: .estimated
                ),
            ],
            calendar: Self.calendar
        )

        let claude = summary.providers[.claude]
        #expect(claude?.retained.costUSD == 2)
        #expect(claude?.retained.tokens == 400)
    }

    @Test
    func combinesExactAndEstimatedCostsButExcludesIncludedPlanDollars() {
        let summary = SpendAggregator.makeSummary(
            now: Self.date(2025, 1, 15),
            historyRetentionDays: 30,
            sources: [
                .daily(
                    provider: .opencode,
                    buckets: [
                        UsageBucket(
                            day: Self.date(2025, 1, 14),
                            tokens: 100,
                            costUSD: 1
                        ),
                    ],
                    provenance: .exact
                ),
                .samples(
                    provider: .claude,
                    samples: [
                        Self.sample(
                            day: 13,
                            scope: "claude",
                            cost: 1,
                            tokens: 100
                        ),
                        Self.sample(
                            day: 14,
                            scope: "claude",
                            cost: 3,
                            tokens: 500
                        ),
                    ],
                    provenance: .estimated
                ),
                .daily(
                    provider: .codex,
                    buckets: [
                        UsageBucket(
                            day: Self.date(2025, 1, 14),
                            tokens: 9_000,
                            costUSD: nil
                        ),
                    ],
                    provenance: .includedWithPlan,
                    includedWithPlan: true
                ),
            ],
            calendar: Self.calendar
        )

        let combined = summary.combined
        #expect(combined.week.costUSD == 3)
        #expect(combined.week.tokens == 500)
        #expect(combined.week.provenance == .mixed)
        #expect(combined.week.tokensPerDollar == Double(500) / 3)
        #expect(summary.providers[.codex]?.week.costUSD == nil)
        #expect(summary.providers[.codex]?.week.provenance == .includedWithPlan)
    }

    @Test
    func missingCumulativeTokensDoNotProduceAnEfficiencyRatio() {
        let samples = [
            ProviderSpendSample(
                provider: .claude,
                observedAt: Self.date(2025, 1, 14),
                scopeID: "claude",
                cumulativeCostUSD: 2,
                cumulativeTokens: nil,
                provenance: .estimated
            ),
            ProviderSpendSample(
                provider: .claude,
                observedAt: Self.date(2025, 1, 15),
                scopeID: "claude",
                cumulativeCostUSD: 3,
                cumulativeTokens: nil,
                provenance: .estimated
            ),
        ]

        let summary = SpendAggregator.makeSummary(
            now: Self.date(2025, 1, 15),
            historyRetentionDays: 30,
            sources: [
                .samples(
                    provider: .claude,
                    samples: samples,
                    provenance: .estimated
                ),
            ],
            calendar: Self.calendar
        )

        #expect(summary.providers[.claude]?.week.costUSD == 1)
        #expect(summary.providers[.claude]?.week.tokens == nil)
        #expect(summary.providers[.claude]?.week.tokensPerDollar == nil)
    }

    @Test
    func zeroCostNeverProducesInfiniteEfficiency() {
        let summary = SpendAggregator.makeSummary(
            now: Self.date(2025, 1, 15),
            historyRetentionDays: 30,
            sources: [
                .daily(
                    provider: .opencode,
                    buckets: [
                        UsageBucket(
                            day: Self.date(2025, 1, 14),
                            tokens: 100,
                            costUSD: 0
                        ),
                    ],
                    provenance: .exact
                ),
            ],
            calendar: Self.calendar
        )

        #expect(summary.providers[.opencode]?.week.costUSD == 0)
        #expect(summary.providers[.opencode]?.week.tokensPerDollar == nil)
    }
}

private extension SpendAggregatorTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    static func sample(
        day: Int,
        scope: String,
        cost: Double,
        tokens: Int
    ) -> ProviderSpendSample {
        ProviderSpendSample(
            provider: .claude,
            observedAt: date(2025, 1, day),
            scopeID: scope,
            cumulativeCostUSD: cost,
            cumulativeTokens: tokens,
            provenance: .estimated
        )
    }
}
