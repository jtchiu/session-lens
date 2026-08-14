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
