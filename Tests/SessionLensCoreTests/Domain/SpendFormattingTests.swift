import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct SpendFormattingTests {
    @Test
    func formatsIncludedPlanAndApiEquivalentSeparately() {
        let value = ApiEquivalentValue(
            costUSD: 12.4,
            tokens: 3_400_000,
            coverage: .detectedProviderModel,
            modelID: "codex-model",
            ratesAsOf: nil
        )

        #expect(SpendFormatting.apiEquivalentText(value) == "API eq. ~$12.40")
        #expect(SpendFormatting.coverageText(value) == "Detected model estimate")
    }

    @Test
    func comparisonAccessibilityLabelNamesActualApiTokensAndRatesDate() {
        let label = SpendFormatting.comparisonAccessibilityLabel(
            provider: .codex,
            period: "This week",
            actual: SpendValue(
                costUSD: nil,
                tokens: 3_400_000,
                provenance: .includedWithPlan
            ),
            apiEquivalent: ApiEquivalentValue(
                costUSD: 12.4,
                tokens: 3_400_000,
                coverage: .detectedProviderModel,
                modelID: "codex-model",
                ratesAsOf: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(label.contains("Actual spend: Included with plan"))
        #expect(label.contains("API equivalent: API eq. ~$12.40"))
        #expect(label.contains("3,400,000 tokens"))
        #expect(label.contains("Detected model estimate"))
        #expect(label.contains("Rates as of"))
    }

    @Test
    func formatsCostEfficiencyAndProvenanceWithoutFabricatingValues() {
        #expect(
            SpendFormatting.costText(
                SpendValue(costUSD: 1.25, tokens: 1_000, provenance: .exact)
            ) == "$1.25"
        )
        #expect(
            SpendFormatting.costText(
                SpendValue(costUSD: 1.25, tokens: 1_000, provenance: .estimated)
            ) == "Estimated $1.25"
        )
        #expect(
            SpendFormatting.costText(
                SpendValue(
                    costUSD: nil,
                    tokens: 1_000,
                    provenance: .includedWithPlan
                )
            ) == "Included with plan"
        )
        #expect(
            SpendFormatting.efficiencyText(
                SpendValue(costUSD: 1.25, tokens: 1_000, provenance: .exact)
            ) == "800 tok/$"
        )
        #expect(
            SpendFormatting.efficiencyText(.unavailable) == "—"
        )
    }

    @Test
    func accessibilityLabelExplainsMissingEfficiencyData() {
        let label = SpendFormatting.accessibilityLabel(
            provider: .claude,
            period: "This month",
            value: SpendValue(
                costUSD: 2,
                tokens: nil,
                provenance: .estimated
            )
        )

        #expect(label.contains("Claude Code"))
        #expect(label.contains("This month"))
        #expect(label.contains("estimated"))
        #expect(label.lowercased().contains("cumulative token"))
    }
}
