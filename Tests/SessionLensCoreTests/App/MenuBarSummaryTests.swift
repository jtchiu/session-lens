import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct MenuBarSummaryTests {
    @Test
    func urgentModeChoosesHighestExactQuotaAheadOfLocalBudget() {
        let summary = MenuBarSummary.make(
            mode: .urgent,
            snapshots: [
                Fixtures.openCodeLocalBudget(95),
                Fixtures.codexSnapshot(percent: 72),
            ],
            providerOrder: [.opencode, .claude, .codex]
        )

        #expect(summary.text == "CX 72%")
        #expect(summary.severity == .warning)
    }

    @Test
    func urgentModeUsesLocalBudgetWhenNoExactQuotaExists() {
        let summary = MenuBarSummary.make(
            mode: .urgent,
            snapshots: [Fixtures.openCodeLocalBudget(91)],
            providerOrder: ProviderID.allCases
        )

        #expect(summary.text == "OC 91%")
        #expect(summary.severity == .critical)
        #expect(summary.accessibilityLabel.contains("Local budget"))
    }

    @Test
    func unavailableAndStaleMetricsDoNotRenderAsZeroOrCurrentQuota() {
        let stale = ProviderSnapshot(
            provider: .codex,
            observedAt: Fixtures.now,
            health: .stale,
            tokens: nil,
            costDisplay: .unavailable,
            dailyBuckets: [],
            quotaWindows: [Fixtures.quota(88, provenance: .stale)],
            modelBreakdowns: []
        )
        let summary = MenuBarSummary.make(
            mode: .urgent,
            snapshots: [
                .unavailable(provider: .claude, health: .toolMissing),
                stale,
            ],
            providerOrder: ProviderID.allCases
        )

        #expect(!summary.text.contains("0%"))
        #expect(!summary.text.contains("88%"))
        #expect(summary.severity == .muted)
    }

    @Test
    func activeModeUsesMostRecentlyObservedReadyProvider() {
        let older = Fixtures.aggregateSnapshot(
            provider: .opencode,
            observedAt: Fixtures.now
        )
        let newer = Fixtures.codexSnapshot(
            observedAt: Fixtures.now.addingTimeInterval(60),
            percent: 36
        )

        let summary = MenuBarSummary.make(
            mode: .active,
            snapshots: [older, newer],
            providerOrder: ProviderID.allCases
        )

        #expect(summary.text == "CX 36%")
        #expect(summary.accessibilityLabel.contains("Codex"))
    }

    @Test
    func activeModeFallsBackToCompactTokenCountWhenQuotaIsUnavailable() {
        let snapshot = Fixtures.aggregateSnapshot(
            provider: .opencode,
            tokens: TokenBreakdown(
                input: 1_200,
                output: 34,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0
            ),
            quotaWindows: []
        )

        let summary = MenuBarSummary.make(
            mode: .active,
            snapshots: [snapshot],
            providerOrder: ProviderID.allCases
        )

        #expect(summary.text == "OC 1.2K")
    }

    @Test
    func urgentTieUsesUserProviderOrder() {
        let summary = MenuBarSummary.make(
            mode: .urgent,
            snapshots: [
                Fixtures.codexSnapshot(percent: 70),
                Fixtures.aggregateSnapshot(
                    provider: .claude,
                    quotaWindows: [Fixtures.quota(70)]
                ),
            ],
            providerOrder: [.claude, .codex, .opencode]
        )

        #expect(summary.text == "CL 70%")
    }

    @Test
    func iconsModeExposesOrderedHealthWithoutNumericText() {
        let summary = MenuBarSummary.make(
            mode: .icons,
            snapshots: [
                Fixtures.codexSnapshot(),
                .unavailable(provider: .claude, health: .toolMissing),
            ],
            providerOrder: [.codex, .claude, .opencode]
        )

        #expect(summary.text.isEmpty)
        #expect(summary.indicators.map(\.provider) == [.codex, .claude, .opencode])
        #expect(summary.indicators.map(\.health) == [.ready, .toolMissing, nil])
    }

    @Test
    func minimalModeShowsOnlyTheMark() {
        let summary = MenuBarSummary.make(
            mode: .minimal,
            snapshots: [Fixtures.codexSnapshot()],
            providerOrder: ProviderID.allCases
        )

        #expect(summary.text.isEmpty)
        #expect(summary.indicators.isEmpty)
        #expect(summary.accessibilityLabel == "SessionLens")
    }
}
