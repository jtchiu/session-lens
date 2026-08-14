import Testing

@testable import SessionLensCore

@Suite
struct SpendFormattingTests {
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
