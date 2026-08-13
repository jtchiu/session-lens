import Foundation
@testable import SessionLensCore

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_735_689_600)

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
        tokens: TokenBreakdown = .init(
            input: 100,
            output: 50,
            reasoning: 25,
            cacheRead: 20,
            cacheWrite: 5
        ),
        costDisplay: CostDisplay = .exactUSD(1.25),
        quotaWindows: [QuotaWindow] = []
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            observedAt: now,
            health: .ready,
            tokens: tokens,
            costDisplay: costDisplay,
            dailyBuckets: [
                UsageBucket(day: day(0), tokens: tokens.total, costUSD: 1.25),
            ],
            quotaWindows: quotaWindows,
            modelBreakdowns: []
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
