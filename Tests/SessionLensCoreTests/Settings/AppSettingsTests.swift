import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct AppSettingsTests {
    @Test
    func defaultsHaveNoImplicitOpenCodeQuotaAttribution() {
        let settings = AppSettings.defaults

        #expect(settings.quotaProvider(forOpenCodeProviderID: "anthropic") == nil)
        #expect(settings.quotaProvider(forOpenCodeProviderID: "openai") == nil)
        #expect(settings.menuBarDisplayMode == .urgent)
        #expect(settings.providerOrder == ProviderID.allCases)
        #expect(settings.notificationThresholds == [70, 90])
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

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
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
