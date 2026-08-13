import Foundation

public enum UsageChartRange: Int, CaseIterable, Codable, Hashable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    public var days: Int { rawValue }
}

public enum MenuBarDisplayMode: String, CaseIterable, Codable, Hashable, Sendable {
    case urgent
    case active
    case icons
    case minimal
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaults = AppSettings()

    public var refreshIntervalSeconds: Int
    public var chartRange: UsageChartRange
    public var providerOrder: [ProviderID]
    public var notificationThresholds: [Int]
    public var menuBarDisplayMode: MenuBarDisplayMode
    public var historyRetentionDays: Int
    public var notificationsEnabled: Bool
    public var notifyOnReset: Bool
    public var launchAtLogin: Bool

    private var openCodeQuotaMappings: [String: ProviderID]

    public init(
        refreshIntervalSeconds: Int = 300,
        chartRange: UsageChartRange = .sevenDays,
        providerOrder: [ProviderID] = ProviderID.allCases,
        notificationThresholds: [Int] = [70, 90],
        menuBarDisplayMode: MenuBarDisplayMode = .urgent,
        historyRetentionDays: Int = 365,
        notificationsEnabled: Bool = false,
        notifyOnReset: Bool = true,
        launchAtLogin: Bool = false,
        openCodeQuotaMappings: [String: ProviderID] = [:]
    ) {
        self.refreshIntervalSeconds = min(3_600, max(30, refreshIntervalSeconds))
        self.chartRange = chartRange
        self.providerOrder = Self.normalizedProviderOrder(providerOrder)
        self.notificationThresholds = Array(
            Set(notificationThresholds.filter { (1...99).contains($0) })
        ).sorted()
        self.menuBarDisplayMode = menuBarDisplayMode
        self.historyRetentionDays = min(3_650, max(7, historyRetentionDays))
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnReset = notifyOnReset
        self.launchAtLogin = launchAtLogin
        self.openCodeQuotaMappings = Self.normalizedMappings(
            openCodeQuotaMappings
        )
    }

    public func quotaProvider(
        forOpenCodeProviderID providerID: String
    ) -> ProviderID? {
        openCodeQuotaMappings[providerID]
    }

    public mutating func setQuotaProvider(
        _ provider: ProviderID?,
        forOpenCodeProviderID providerID: String
    ) {
        guard !providerID.isEmpty else { return }
        guard let provider else {
            openCodeQuotaMappings.removeValue(forKey: providerID)
            return
        }
        guard provider == .claude || provider == .codex else {
            openCodeQuotaMappings.removeValue(forKey: providerID)
            return
        }
        openCodeQuotaMappings[providerID] = provider
    }

    public var quotaMappings: [String: ProviderID] {
        openCodeQuotaMappings
    }

    private enum CodingKeys: String, CodingKey {
        case refreshIntervalSeconds
        case chartRange
        case providerOrder
        case notificationThresholds
        case menuBarDisplayMode
        case historyRetentionDays
        case notificationsEnabled
        case notifyOnReset
        case launchAtLogin
        case openCodeQuotaMappings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            refreshIntervalSeconds: try container.decodeIfPresent(
                Int.self,
                forKey: .refreshIntervalSeconds
            ) ?? Self.defaults.refreshIntervalSeconds,
            chartRange: try container.decodeIfPresent(
                UsageChartRange.self,
                forKey: .chartRange
            ) ?? Self.defaults.chartRange,
            providerOrder: try container.decodeIfPresent(
                [ProviderID].self,
                forKey: .providerOrder
            ) ?? Self.defaults.providerOrder,
            notificationThresholds: try container.decodeIfPresent(
                [Int].self,
                forKey: .notificationThresholds
            ) ?? Self.defaults.notificationThresholds,
            menuBarDisplayMode: try container.decodeIfPresent(
                MenuBarDisplayMode.self,
                forKey: .menuBarDisplayMode
            ) ?? Self.defaults.menuBarDisplayMode,
            historyRetentionDays: try container.decodeIfPresent(
                Int.self,
                forKey: .historyRetentionDays
            ) ?? Self.defaults.historyRetentionDays,
            notificationsEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .notificationsEnabled
            ) ?? Self.defaults.notificationsEnabled,
            notifyOnReset: try container.decodeIfPresent(
                Bool.self,
                forKey: .notifyOnReset
            ) ?? Self.defaults.notifyOnReset,
            launchAtLogin: try container.decodeIfPresent(
                Bool.self,
                forKey: .launchAtLogin
            ) ?? Self.defaults.launchAtLogin,
            openCodeQuotaMappings: try container.decodeIfPresent(
                [String: ProviderID].self,
                forKey: .openCodeQuotaMappings
            ) ?? [:]
        )
    }

    private static func normalizedProviderOrder(
        _ order: [ProviderID]
    ) -> [ProviderID] {
        var seen = Set<ProviderID>()
        var result = order.filter { seen.insert($0).inserted }
        result.append(contentsOf: ProviderID.allCases.filter { seen.insert($0).inserted })
        return result
    }

    private static func normalizedMappings(
        _ mappings: [String: ProviderID]
    ) -> [String: ProviderID] {
        mappings.filter { key, value in
            !key.isEmpty && (value == .claude || value == .codex)
        }
    }
}
