import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct AppSettingsTests {
    @Test
    func launchHydrationUsesPersistedCalendarRangeAndWeeklyWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -14_400)!
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 13, hour: 15, minute: 30)
        )!
        let snapshot = Fixtures.aggregateSnapshot(
            provider: .codex,
            quotaWindows: [
                QuotaWindow(
                    id: "five-hour",
                    label: "Five Hour",
                    durationMinutes: 300,
                    usedPercent: 22,
                    resetsAt: reference,
                    provenance: .exactProvider
                ),
                QuotaWindow(
                    id: "weekly",
                    label: "Weekly",
                    durationMinutes: 10_080,
                    usedPercent: 44,
                    resetsAt: reference,
                    provenance: .exactProvider
                ),
            ]
        )

        let queries = QuotaHistoryQueryBuilder.launchHydration(
            snapshots: [.codex: snapshot],
            settings: AppSettings(chartRange: .thirtyDays),
            endingAt: reference,
            calendar: calendar
        )

        #expect(queries.count == 1)
        #expect(queries.first?.provider == .codex)
        #expect(queries.first?.durationMinutes == 10_080)
        #expect(queries.first?.range.lowerBound == calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 15)
        ))
        #expect(queries.first?.range.upperBound == reference)
    }

    @Test
    func rangeChangeUsesUpdatedCalendarRangeAndFallbackWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -14_400)!
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 13, hour: 15, minute: 30)
        )!
        let snapshot = Fixtures.aggregateSnapshot(
            provider: .codex,
            quotaWindows: [
                QuotaWindow(
                    id: "five-hour",
                    label: "Five Hour",
                    durationMinutes: 300,
                    usedPercent: 22,
                    resetsAt: reference,
                    provenance: .exactProvider
                )
            ]
        )

        let queries = QuotaHistoryQueryBuilder.rangeChange(
            snapshots: [.codex: snapshot],
            chartRange: .ninetyDays,
            endingAt: reference,
            calendar: calendar
        )

        #expect(queries.count == 1)
        #expect(queries.first?.provider == .codex)
        #expect(queries.first?.durationMinutes == 300)
        #expect(queries.first?.range.lowerBound == calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 16)
        ))
        #expect(queries.first?.range.upperBound == reference)
    }

    @Test
    func sevenDayDateRangeStartsAtTheLocalDaySixDaysBeforeTheReferenceTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -14_400)!
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 13, hour: 15, minute: 30)
        )!

        let range = UsageChartRange.sevenDays.dateRange(
            endingAt: reference,
            calendar: calendar
        )

        #expect(range.lowerBound == calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7)
        ))
        #expect(range.upperBound == reference)
    }

    @Test
    func defaultsHaveNoImplicitOpenCodeQuotaAttribution() {
        let settings = AppSettings.defaults

        #expect(settings.quotaProvider(forOpenCodeProviderID: "anthropic") == nil)
        #expect(settings.quotaProvider(forOpenCodeProviderID: "openai") == nil)
        #expect(settings.menuBarDisplayMode == .urgent)
        #expect(settings.providerOrder == ProviderID.allCases)
        #expect(settings.notificationThresholds == [70, 90])
        #expect(settings.refreshIntervalSeconds == 60)
        #expect(settings.localBudgets.isEmpty)
    }

    @Test
    func mappingsAcceptOnlyExactNonemptyIDsAndAccountProviders() {
        var settings = AppSettings.defaults

        settings.setQuotaProvider(.codex, forOpenCodeProviderID: "openai")
        settings.setQuotaProvider(.claude, forOpenCodeProviderID: "anthropic")
        settings.setQuotaProvider(.opencode, forOpenCodeProviderID: "recursive")
        settings.setQuotaProvider(.codex, forOpenCodeProviderID: "")

        #expect(settings.quotaProvider(forOpenCodeProviderID: "openai") == .codex)
        #expect(
            settings.quotaProvider(forOpenCodeProviderID: "anthropic") == .claude
        )
        #expect(settings.quotaProvider(forOpenCodeProviderID: "recursive") == nil)
        #expect(settings.quotaProvider(forOpenCodeProviderID: "") == nil)

        settings.setQuotaProvider(nil, forOpenCodeProviderID: "openai")
        #expect(settings.quotaProvider(forOpenCodeProviderID: "openai") == nil)
    }

    @Test
    func initializerNormalizesThresholdsAndProviderOrder() {
        let settings = AppSettings(
            refreshIntervalSeconds: 1,
            chartRange: .thirtyDays,
            providerOrder: [.codex, .codex],
            notificationThresholds: [90, -4, 70, 70, 101],
            menuBarDisplayMode: .active,
            historyRetentionDays: 2
        )

        #expect(settings.refreshIntervalSeconds == 30)
        #expect(settings.providerOrder == [.codex, .opencode, .claude])
        #expect(settings.notificationThresholds == [70, 90])
        #expect(settings.historyRetentionDays == 7)
    }

    @Test
    func settingsRoundTripThroughCodable() throws {
        var original = AppSettings.defaults
        original.chartRange = .ninetyDays
        original.menuBarDisplayMode = .icons
        original.setQuotaProvider(.claude, forOpenCodeProviderID: "anthropic")
        original.setLocalBudget(
            OpenCodeLocalBudget(fiveHourUSD: 2.5, weeklyUSD: 18),
            forOpenCodeProviderID: "openai"
        )

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
    }

    @Test
    func localBudgetsNormalizeInvalidValuesAndEmptyEntries() {
        var settings = AppSettings(
            openCodeLocalBudgets: [
                "openai": OpenCodeLocalBudget(
                    fiveHourUSD: -1,
                    weeklyUSD: .infinity
                ),
                "": OpenCodeLocalBudget(weeklyUSD: 4),
                "anthropic": OpenCodeLocalBudget(weeklyUSD: 12),
            ]
        )

        #expect(settings.localBudget(forOpenCodeProviderID: "openai") == nil)
        #expect(settings.localBudget(forOpenCodeProviderID: "") == nil)
        #expect(
            settings.localBudget(forOpenCodeProviderID: "anthropic")
                == OpenCodeLocalBudget(weeklyUSD: 12)
        )

        settings.setLocalBudget(nil, forOpenCodeProviderID: "anthropic")
        #expect(settings.localBudgets.isEmpty)
    }

    @Test
    func missingFieldsDecodeToConservativeDefaults() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data("{}".utf8)
        )

        #expect(decoded == .defaults)
    }

    @Test @MainActor
    func repositoryPersistsSettingsWithoutRawProviderPayloads() throws {
        let repository = try SnapshotRepository.inMemory()
        var settings = AppSettings.defaults
        settings.setQuotaProvider(.codex, forOpenCodeProviderID: "openai")

        try repository.saveSettings(settings)

        #expect(try repository.loadSettings() == settings)
    }
}
