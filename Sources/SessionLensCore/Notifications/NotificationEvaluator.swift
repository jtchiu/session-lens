import Foundation

public enum NotificationEventKind: Equatable, Hashable, Sendable {
    case threshold(Int)
    case reset

    fileprivate var keyComponent: String {
        switch self {
        case let .threshold(value): "threshold-\(value)"
        case .reset: "reset"
        }
    }
}

public struct NotificationEvent: Equatable, Hashable, Sendable, Identifiable {
    public let key: String
    public let provider: ProviderID
    public let quotaID: String
    public let kind: NotificationEventKind
    public let provenance: MetricProvenance
    public let title: String
    public let body: String

    public var id: String { key }
}

public struct NotificationEvaluator: Sendable {
    public init() {}

    public func events(
        provider: ProviderID,
        accountScopeHash: String? = nil,
        previous: ProviderSnapshot?,
        current: ProviderSnapshot,
        thresholds: [Int]
    ) -> [NotificationEvent] {
        guard current.health == .ready else { return [] }
        let previousByID = Dictionary(
            uniqueKeysWithValues: (previous?.quotaWindows ?? []).map { ($0.id, $0) }
        )
        return current.quotaWindows.flatMap { currentWindow in
            events(
                provider: provider,
                accountScopeHash: accountScopeHash,
                previous: previousByID[currentWindow.id],
                current: currentWindow,
                thresholds: thresholds
            )
        }
    }

    public func events(
        provider: ProviderID,
        accountScopeHash: String? = nil,
        previous: QuotaWindow?,
        current: QuotaWindow,
        thresholds: [Int]
    ) -> [NotificationEvent] {
        guard Self.mayNotify(current.provenance),
            let currentPercent = current.usedPercent,
            let previous,
            Self.mayNotify(previous.provenance),
            let previousPercent = previous.usedPercent
        else {
            return []
        }

        var result: [NotificationEvent] = []
        if let previousReset = previous.resetsAt,
            let currentReset = current.resetsAt,
            previousReset != currentReset,
            previousPercent > 0,
            currentPercent < previousPercent
        {
            result.append(
                event(
                    provider: provider,
                    accountScopeHash: accountScopeHash,
                    window: current,
                    kind: .reset
                )
            )
        }

        let normalizedThresholds = Array(
            Set(thresholds.filter { (1...99).contains($0) })
        ).sorted()
        for threshold in normalizedThresholds
        where previousPercent < Double(threshold)
            && currentPercent >= Double(threshold)
        {
            result.append(
                event(
                    provider: provider,
                    accountScopeHash: accountScopeHash,
                    window: current,
                    kind: .threshold(threshold)
                )
            )
        }
        return result
    }

    private func event(
        provider: ProviderID,
        accountScopeHash: String?,
        window: QuotaWindow,
        kind: NotificationEventKind
    ) -> NotificationEvent {
        let scope = accountScopeHash ?? "default"
        let epoch = window.resetsAt.map {
            String(Int64($0.timeIntervalSince1970.rounded(.down)))
        } ?? "none"
        let prefix = window.provenance == .localBudget
            ? "Local budget"
            : provider.displayName
        let title: String
        let body: String
        switch kind {
        case let .threshold(value):
            title = "\(prefix) \(window.label) reached \(value)%"
            body = window.resetsAt.map {
                "Usage is \(Int((window.usedPercent ?? 0).rounded()))%. Resets \($0.formatted(.relative(presentation: .named)))."
            } ?? "Usage is \(Int((window.usedPercent ?? 0).rounded()))%."
        case .reset:
            title = "\(prefix) \(window.label) reset"
            body = "The usage window has started a new quota period."
        }

        return NotificationEvent(
            key: [
                provider.rawValue,
                scope,
                window.id,
                kind.keyComponent,
                epoch,
            ].joined(separator: ":"),
            provider: provider,
            quotaID: window.id,
            kind: kind,
            provenance: window.provenance,
            title: title,
            body: body
        )
    }

    private static func mayNotify(_ provenance: MetricProvenance) -> Bool {
        provenance == .exactProvider || provenance == .localBudget
    }
}
