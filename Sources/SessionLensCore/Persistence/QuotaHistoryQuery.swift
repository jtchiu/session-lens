import Foundation

public struct QuotaHistoryQuery: Equatable, Sendable {
    public let provider: ProviderID
    public let durationMinutes: Int
    public let range: ClosedRange<Date>

    public init(
        provider: ProviderID,
        durationMinutes: Int,
        range: ClosedRange<Date>
    ) {
        self.provider = provider
        self.durationMinutes = durationMinutes
        self.range = range
    }
}

public enum QuotaHistoryQueryBuilder {
    public static func launchHydration(
        snapshots: [ProviderID: ProviderSnapshot],
        settings: AppSettings,
        endingAt: Date,
        calendar: Calendar
    ) -> [QuotaHistoryQuery] {
        queries(
            snapshots: snapshots,
            chartRange: settings.chartRange,
            endingAt: endingAt,
            calendar: calendar
        )
    }

    public static func rangeChange(
        snapshots: [ProviderID: ProviderSnapshot],
        chartRange: UsageChartRange,
        endingAt: Date,
        calendar: Calendar
    ) -> [QuotaHistoryQuery] {
        queries(
            snapshots: snapshots,
            chartRange: chartRange,
            endingAt: endingAt,
            calendar: calendar
        )
    }

    private static func queries(
        snapshots: [ProviderID: ProviderSnapshot],
        chartRange: UsageChartRange,
        endingAt: Date,
        calendar: Calendar
    ) -> [QuotaHistoryQuery] {
        let range = chartRange.dateRange(endingAt: endingAt, calendar: calendar)
        return snapshots.compactMap { provider, snapshot in
            let window = snapshot.quotaWindows.first(where: {
                $0.durationMinutes == 10_080
            }) ?? snapshot.quotaWindows.first
            guard let duration = window?.durationMinutes else { return nil }
            return QuotaHistoryQuery(
                provider: provider,
                durationMinutes: duration,
                range: range
            )
        }
    }
}
