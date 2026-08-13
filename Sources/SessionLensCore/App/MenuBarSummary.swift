import Foundation

public enum MenuBarSeverity: String, Equatable, Hashable, Sendable {
    case neutral
    case warning
    case critical
    case muted
}

public struct MenuBarProviderIndicator: Equatable, Hashable, Sendable {
    public let provider: ProviderID
    public let health: ProviderHealth?

    public init(provider: ProviderID, health: ProviderHealth?) {
        self.provider = provider
        self.health = health
    }
}

public struct MenuBarSummary: Equatable, Hashable, Sendable {
    public let text: String
    public let accessibilityLabel: String
    public let severity: MenuBarSeverity
    public let indicators: [MenuBarProviderIndicator]

    public init(
        text: String,
        accessibilityLabel: String,
        severity: MenuBarSeverity,
        indicators: [MenuBarProviderIndicator] = []
    ) {
        self.text = text
        self.accessibilityLabel = accessibilityLabel
        self.severity = severity
        self.indicators = indicators
    }

    public static func make(
        mode: MenuBarDisplayMode,
        snapshots: [ProviderSnapshot],
        providerOrder: [ProviderID]
    ) -> MenuBarSummary {
        let byProvider = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.provider, $0) }
        )
        let order = normalizedOrder(providerOrder)

        switch mode {
        case .urgent:
            return urgent(snapshots: byProvider, order: order)
        case .active:
            return active(snapshots: byProvider, order: order)
        case .icons:
            let indicators = order.map {
                MenuBarProviderIndicator(
                    provider: $0,
                    health: byProvider[$0]?.health
                )
            }
            let states = indicators.map {
                "\($0.provider.displayName) \($0.health?.accessibilityName ?? "no data")"
            }.joined(separator: ", ")
            return MenuBarSummary(
                text: "",
                accessibilityLabel: "SessionLens, \(states)",
                severity: .neutral,
                indicators: indicators
            )
        case .minimal:
            return MenuBarSummary(
                text: "",
                accessibilityLabel: "SessionLens",
                severity: .neutral
            )
        }
    }

    private static func urgent(
        snapshots: [ProviderID: ProviderSnapshot],
        order: [ProviderID]
    ) -> MenuBarSummary {
        let exact = candidates(
            snapshots: snapshots,
            order: order,
            provenance: .exactProvider
        )
        let local = candidates(
            snapshots: snapshots,
            order: order,
            provenance: .localBudget
        )
        guard let selected = (exact.isEmpty ? local : exact).first else {
            return MenuBarSummary(
                text: "",
                accessibilityLabel: "SessionLens, quota unavailable",
                severity: .muted
            )
        }
        let rounded = Int(selected.percent.rounded())
        let provenance = selected.window.provenance == .localBudget
            ? "Local budget"
            : "Exact provider quota"
        return MenuBarSummary(
            text: "\(selected.provider.abbreviation) \(rounded)%",
            accessibilityLabel:
                "SessionLens, \(selected.provider.displayName), \(selected.window.label), \(rounded) percent, \(provenance)",
            severity: severity(for: selected.percent)
        )
    }

    private static func active(
        snapshots: [ProviderID: ProviderSnapshot],
        order: [ProviderID]
    ) -> MenuBarSummary {
        let orderIndex = Dictionary(
            uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
        )
        let selected = snapshots.values
            .filter { snapshot in
                snapshot.tokens != nil
                    || snapshot.quotaWindows.contains { $0.usedPercent != nil }
            }
            .sorted { left, right in
                if left.observedAt != right.observedAt {
                    return left.observedAt > right.observedAt
                }
                return (orderIndex[left.provider] ?? Int.max)
                    < (orderIndex[right.provider] ?? Int.max)
            }
            .first

        guard let selected else {
            return MenuBarSummary(
                text: "",
                accessibilityLabel: "SessionLens, no current usage data",
                severity: .muted
            )
        }
        guard selected.health == .ready else {
            return MenuBarSummary(
                text: "\(selected.provider.abbreviation) stale",
                accessibilityLabel:
                    "SessionLens, \(selected.provider.displayName), stale data",
                severity: .muted
            )
        }
        if let window = selected.quotaWindows.first(where: {
            ($0.provenance == .exactProvider || $0.provenance == .localBudget)
                && $0.usedPercent != nil
        }), let percent = window.usedPercent {
            let rounded = Int(percent.rounded())
            return MenuBarSummary(
                text: "\(selected.provider.abbreviation) \(rounded)%",
                accessibilityLabel:
                    "SessionLens, \(selected.provider.displayName), \(window.label), \(rounded) percent",
                severity: severity(for: percent)
            )
        }
        if let tokens = selected.tokens {
            return MenuBarSummary(
                text: "\(selected.provider.abbreviation) \(compact(tokens.total))",
                accessibilityLabel:
                    "SessionLens, \(selected.provider.displayName), \(tokens.total) tokens",
                severity: .neutral
            )
        }
        return MenuBarSummary(
            text: selected.provider.abbreviation,
            accessibilityLabel: "SessionLens, \(selected.provider.displayName)",
            severity: .neutral
        )
    }

    private static func candidates(
        snapshots: [ProviderID: ProviderSnapshot],
        order: [ProviderID],
        provenance: MetricProvenance
    ) -> [QuotaCandidate] {
        let orderIndex = Dictionary(
            uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) }
        )
        return order.flatMap { provider -> [QuotaCandidate] in
            guard let snapshot = snapshots[provider], snapshot.health == .ready else {
                return []
            }
            return snapshot.quotaWindows.compactMap { window in
                guard window.provenance == provenance,
                    let percent = window.usedPercent
                else {
                    return nil
                }
                return QuotaCandidate(
                    provider: provider,
                    window: window,
                    percent: percent
                )
            }
        }.sorted { left, right in
            if left.percent != right.percent {
                return left.percent > right.percent
            }
            return (orderIndex[left.provider] ?? Int.max)
                < (orderIndex[right.provider] ?? Int.max)
        }
    }

    private static func normalizedOrder(_ order: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        var result = order.filter { seen.insert($0).inserted }
        result.append(contentsOf: ProviderID.allCases.filter { seen.insert($0).inserted })
        return result
    }

    private static func severity(for percent: Double) -> MenuBarSeverity {
        if percent >= 90 { return .critical }
        if percent >= 70 { return .warning }
        return .neutral
    }

    private static func compact(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000 {
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        }
        if magnitude >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return String(value)
    }
}

private struct QuotaCandidate {
    let provider: ProviderID
    let window: QuotaWindow
    let percent: Double
}

private extension ProviderHealth {
    var accessibilityName: String {
        switch self {
        case .ready: "ready"
        case .setupRequired: "setup required"
        case .toolMissing: "tool missing"
        case .stale: "stale"
        case .malformedData: "data format changed"
        case .timedOut: "timed out"
        case .temporarilyUnavailable: "temporarily unavailable"
        }
    }
}
