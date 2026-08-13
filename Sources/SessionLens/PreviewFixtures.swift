import Foundation
import SessionLensCore

enum PreviewFixtures {
    private static let now = Date()

    static let settings = AppSettings(
        refreshIntervalSeconds: 60,
        chartRange: .sevenDays,
        providerOrder: [.opencode, .claude, .codex],
        notificationThresholds: [70, 90],
        menuBarDisplayMode: .urgent,
        historyRetentionDays: 365
    )

    static let snapshots: [ProviderID: ProviderSnapshot] = [
        .opencode: ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: TokenBreakdown(
                input: 186_200,
                output: 41_800,
                reasoning: 12_400,
                cacheRead: 92_000,
                cacheWrite: 8_400
            ),
            costDisplay: .exactUSD(4.82),
            dailyBuckets: dailyBuckets(scale: 0.72, costScale: 0.55),
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "gpt-5",
                    tokens: TokenBreakdown(
                        input: 104_000,
                        output: 22_000,
                        reasoning: 8_000,
                        cacheRead: 32_000,
                        cacheWrite: 2_000
                    ),
                    costUSD: 2.40
                ),
                ModelUsage(
                    providerID: "anthropic",
                    modelID: "claude-sonnet",
                    tokens: TokenBreakdown(
                        input: 82_000,
                        output: 19_800,
                        reasoning: 4_400,
                        cacheRead: 60_000,
                        cacheWrite: 6_400
                    ),
                    costUSD: 2.42
                ),
            ]
        ),
        .claude: .unavailable(
            provider: .claude,
            health: .setupRequired,
            observedAt: now
        ),
        .codex: ProviderSnapshot(
            provider: .codex,
            observedAt: now,
            health: .ready,
            tokens: TokenBreakdown(
                input: 0,
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                uncategorized: 8_942_000
            ),
            costDisplay: .includedWithPlan,
            dailyBuckets: dailyBuckets(scale: 1, costScale: nil),
            quotaWindows: [
                QuotaWindow(
                    id: "codex:300",
                    label: "5-hour",
                    durationMinutes: 300,
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(7_200),
                    provenance: .exactProvider
                ),
                QuotaWindow(
                    id: "codex:10080",
                    label: "Weekly",
                    durationMinutes: 10_080,
                    usedPercent: 36,
                    resetsAt: now.addingTimeInterval(4 * 86_400),
                    provenance: .exactProvider
                ),
            ],
            modelBreakdowns: []
        ),
    ]

    static let quotaHistory: [ProviderID: [QuotaHistoryPoint]] = [
        .codex: [26, 22, 31, 38, 50, 45, 49, 48, 42, 39, 36]
            .enumerated()
            .map { index, value in
                QuotaHistoryPoint(
                    observedAt: now.addingTimeInterval(
                        Double(index - 10) * 30 * 60
                    ),
                    usedPercent: Double(value),
                    resetsAt: now.addingTimeInterval(4 * 86_400),
                    provenance: .exactProvider
                )
            }
    ]

    private static func dailyBuckets(
        scale: Double,
        costScale: Double?
    ) -> [UsageBucket] {
        let values = [420_000, 780_000, 690_000, 1_240_000, 980_000, 1_560_000, 1_180_000]
        return values.enumerated().map { index, value in
            let day = Calendar.current.date(
                byAdding: .day,
                value: index - values.count + 1,
                to: now
            ) ?? now
            return UsageBucket(
                day: day,
                tokens: Int(Double(value) * scale),
                costUSD: costScale.map { Double(value) / 1_000_000 * $0 }
            )
        }
    }
}
