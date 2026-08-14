import Foundation

public enum UsageChartRange: Int, CaseIterable, Codable, Hashable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    public var days: Int { rawValue }

    public func dateRange(
        endingAt end: Date,
        calendar: Calendar
    ) -> ClosedRange<Date> {
        let endDay = calendar.startOfDay(for: end)
        let start = calendar.date(
            byAdding: .day,
            value: -(days - 1),
            to: endDay
        ) ?? endDay
        return start...end
    }
}

public enum MenuBarDisplayMode: String, CaseIterable, Codable, Hashable, Sendable {
    case urgent
    case active
    case icons
    case minimal
}

public struct OpenCodeLocalBudget: Codable, Equatable, Hashable, Sendable {
    public var fiveHourUSD: Double?
    public var weeklyUSD: Double?

    public init(fiveHourUSD: Double? = nil, weeklyUSD: Double? = nil) {
        self.fiveHourUSD = Self.normalized(fiveHourUSD)
        self.weeklyUSD = Self.normalized(weeklyUSD)
    }

    public var isEmpty: Bool {
        fiveHourUSD == nil && weeklyUSD == nil
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHourUSD
        case weeklyUSD
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fiveHourUSD: try container.decodeIfPresent(Double.self, forKey: .fiveHourUSD),
            weeklyUSD: try container.decodeIfPresent(Double.self, forKey: .weeklyUSD)
        )
    }

    private static func normalized(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
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
    private var openCodeLocalBudgets: [String: OpenCodeLocalBudget]

    public init(
        refreshIntervalSeconds: Int = 60,
        chartRange: UsageChartRange = .sevenDays,
        providerOrder: [ProviderID] = ProviderID.allCases,
        notificationThresholds: [Int] = [70, 90],
        menuBarDisplayMode: MenuBarDisplayMode = .urgent,
        historyRetentionDays: Int = 365,
        notificationsEnabled: Bool = false,
        notifyOnReset: Bool = true,
        launchAtLogin: Bool = false,
        openCodeQuotaMappings: [String: ProviderID] = [:],
        openCodeLocalBudgets: [String: OpenCodeLocalBudget] = [:]
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
        self.openCodeLocalBudgets = Self.normalizedBudgets(openCodeLocalBudgets)
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

    public func localBudget(
        forOpenCodeProviderID providerID: String
    ) -> OpenCodeLocalBudget? {
        openCodeLocalBudgets[providerID]
    }

    public mutating func setLocalBudget(
        _ budget: OpenCodeLocalBudget?,
        forOpenCodeProviderID providerID: String
    ) {
        guard !providerID.isEmpty else { return }
        guard let budget, !budget.isEmpty else {
            openCodeLocalBudgets.removeValue(forKey: providerID)
            return
        }
        openCodeLocalBudgets[providerID] = budget
    }

    public var localBudgets: [String: OpenCodeLocalBudget] {
        openCodeLocalBudgets
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
        case openCodeLocalBudgets
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
            ) ?? [:],
            openCodeLocalBudgets: try container.decodeIfPresent(
                [String: OpenCodeLocalBudget].self,
                forKey: .openCodeLocalBudgets
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

    private static func normalizedBudgets(
        _ budgets: [String: OpenCodeLocalBudget]
    ) -> [String: OpenCodeLocalBudget] {
        budgets.compactMapValues { budget in
            let normalized = OpenCodeLocalBudget(
                fiveHourUSD: budget.fiveHourUSD,
                weeklyUSD: budget.weeklyUSD
            )
            return normalized.isEmpty ? nil : normalized
        }.filter { !$0.key.isEmpty }
    }
}
