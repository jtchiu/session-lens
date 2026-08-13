import CoreData
import Foundation

public enum SnapshotRepositoryError: Error, Equatable {
    case corruptProvider(String)
    case corruptHealth(String)
    case corruptCostDisplay(String)
}

@MainActor
public protocol SnapshotPersisting: Sendable {
    func record(_ snapshot: ProviderSnapshot) throws
    func saveSettings(_ settings: AppSettings) throws
    func loadSettings() throws -> AppSettings?
}

@MainActor
public final class SnapshotRepository: SnapshotPersisting {
    private static let managedObjectModel = SessionLensPersistenceModel.makeModel()

    private let coordinator: NSPersistentStoreCoordinator
    private let context: NSManagedObjectContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public let storeURL: URL?

    private init(
        coordinator: NSPersistentStoreCoordinator,
        storeURL: URL?
    ) {
        self.coordinator = coordinator
        self.storeURL = storeURL
        self.context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        self.context.persistentStoreCoordinator = coordinator
        self.context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        self.context.undoManager = nil
    }

    public static func inMemory() throws -> SnapshotRepository {
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: managedObjectModel
        )
        _ = try coordinator.addPersistentStore(
            type: .inMemory,
            configuration: nil,
            at: URL(fileURLWithPath: "/dev/null")
        )
        return SnapshotRepository(coordinator: coordinator, storeURL: nil)
    }

    public static func persistent(
        applicationSupportURL: URL? = nil
    ) throws -> SnapshotRepository {
        let rootURL: URL
        if let applicationSupportURL {
            rootURL = applicationSupportURL
        } else {
            rootURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directoryURL = rootURL.appendingPathComponent(
            "SessionLens",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let storeURL = directoryURL.appendingPathComponent("usage.sqlite")
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: managedObjectModel
        )
        _ = try coordinator.addPersistentStore(
            type: .sqlite,
            configuration: nil,
            at: storeURL,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
            ]
        )
        return SnapshotRepository(coordinator: coordinator, storeURL: storeURL)
    }

    public func record(_ snapshot: ProviderSnapshot) throws {
        let tokenData = try snapshot.tokens.map { try encoder.encode($0) }
        let quotaData = try encoder.encode(snapshot.quotaWindows)
        let (costKindRaw, costUSD) = Self.persistenceCost(snapshot.costDisplay)
        let key = Self.snapshotKey(snapshot.provider, snapshot.observedAt)

        let record = try fetchSnapshot(key: key) ?? insertSnapshotRecord()
        record.key = key
        record.providerRaw = snapshot.provider.rawValue
        record.observedAt = snapshot.observedAt
        record.healthRaw = snapshot.health.rawValue
        record.tokenData = tokenData
        record.costKindRaw = costKindRaw
        record.costUSD = costUSD.map(NSNumber.init(value:))
        record.quotaData = quotaData

        for bucket in snapshot.dailyBuckets {
            try upsert(bucket, provider: snapshot.provider, observedAt: snapshot.observedAt)
        }

        try context.save()
    }

    public func latest(provider: ProviderID) throws -> ProviderSnapshot? {
        let request = SnapshotRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "providerRaw == %@",
            provider.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "observedAt", ascending: false)
        ]
        request.fetchLimit = 1
        guard let record = try context.fetch(request).first else { return nil }

        guard let storedProvider = ProviderID(rawValue: record.providerRaw) else {
            throw SnapshotRepositoryError.corruptProvider(record.providerRaw)
        }
        guard let health = ProviderHealth(rawValue: record.healthRaw) else {
            throw SnapshotRepositoryError.corruptHealth(record.healthRaw)
        }

        let tokens = try record.tokenData.map {
            try decoder.decode(TokenBreakdown.self, from: $0)
        }
        let quotas = try decoder.decode([QuotaWindow].self, from: record.quotaData)
        let costDisplay = try Self.domainCost(
            kind: record.costKindRaw,
            value: record.costUSD?.doubleValue
        )
        let dailyBuckets = try dailyUsage(
            provider: storedProvider,
            range: Date.distantPast...Date.distantFuture
        )

        return ProviderSnapshot(
            provider: storedProvider,
            observedAt: record.observedAt,
            health: health,
            tokens: tokens,
            costDisplay: costDisplay,
            dailyBuckets: dailyBuckets,
            quotaWindows: quotas,
            modelBreakdowns: []
        )
    }

    public func dailyUsage(
        provider: ProviderID,
        range: ClosedRange<Date>
    ) throws -> [UsageBucket] {
        let request = DailyUsageRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "providerRaw == %@ AND day >= %@ AND day <= %@",
            provider.rawValue,
            range.lowerBound as NSDate,
            range.upperBound as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "day", ascending: true)]
        return try context.fetch(request).map {
            UsageBucket(
                day: $0.day,
                tokens: Int($0.tokens),
                costUSD: $0.costUSD?.doubleValue
            )
        }
    }

    public func quotaHistory(
        provider: ProviderID,
        durationMinutes: Int?,
        range: ClosedRange<Date>
    ) throws -> [QuotaHistoryPoint] {
        let request = SnapshotRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "providerRaw == %@ AND observedAt >= %@ AND observedAt <= %@",
            provider.rawValue,
            range.lowerBound as NSDate,
            range.upperBound as NSDate
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "observedAt", ascending: true)
        ]

        return try context.fetch(request).compactMap { record in
            let windows = try decoder.decode(
                [QuotaWindow].self,
                from: record.quotaData
            )
            guard let window = windows.first(where: {
                $0.durationMinutes == durationMinutes
            }), let usedPercent = window.usedPercent else {
                return nil
            }
            return QuotaHistoryPoint(
                observedAt: record.observedAt,
                usedPercent: usedPercent,
                resetsAt: window.resetsAt,
                provenance: window.provenance
            )
        }
    }

    public func markNotification(_ key: String, at date: Date = Date()) throws {
        guard try fetchNotification(key: key) == nil else { return }
        let record = insertNotificationRecord()
        record.key = key
        record.createdAt = date
        try context.save()
    }

    public func hasNotification(_ key: String) throws -> Bool {
        try fetchNotification(key: key) != nil
    }

    public func prune(now: Date) throws {
        let calendar = Calendar(identifier: .gregorian)
        guard
            let snapshotCutoff = calendar.date(byAdding: .day, value: -90, to: now),
            let dailyCutoff = calendar.date(byAdding: .day, value: -365, to: now)
        else {
            return
        }

        try delete(
            SnapshotRecord.fetchRequest(),
            matching: NSPredicate(
                format: "observedAt < %@",
                snapshotCutoff as NSDate
            )
        )
        try delete(
            DailyUsageRecord.fetchRequest(),
            matching: NSPredicate(format: "day < %@", dailyCutoff as NSDate)
        )
        try context.save()
    }

    public func clearHistory() throws {
        try delete(SnapshotRecord.fetchRequest())
        try delete(DailyUsageRecord.fetchRequest())
        try delete(NotificationRecord.fetchRequest())
        try context.save()
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let key = "app-settings"
        let request = SettingsRecord.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        let record = try context.fetch(request).first ?? insertSettingsRecord()
        record.key = key
        record.settingsData = try encoder.encode(settings)
        record.updatedAt = Date()
        try context.save()
    }

    public func loadSettings() throws -> AppSettings? {
        let request = SettingsRecord.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", "app-settings")
        request.fetchLimit = 1
        guard let record = try context.fetch(request).first else { return nil }
        return try decoder.decode(AppSettings.self, from: record.settingsData)
    }

    func snapshotRecordCount() throws -> Int {
        try context.count(for: SnapshotRecord.fetchRequest())
    }

    func dailyUsageRecordCount() throws -> Int {
        try context.count(for: DailyUsageRecord.fetchRequest())
    }

    func notificationRecordCount() throws -> Int {
        try context.count(for: NotificationRecord.fetchRequest())
    }

    private func fetchSnapshot(key: String) throws -> SnapshotRecord? {
        let request = SnapshotRecord.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchNotification(key: String) throws -> NotificationRecord? {
        let request = NotificationRecord.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func upsert(
        _ bucket: UsageBucket,
        provider: ProviderID,
        observedAt: Date
    ) throws {
        let key = Self.dailyKey(provider, bucket.day)
        let request = DailyUsageRecord.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        let record = try context.fetch(request).first ?? insertDailyUsageRecord()
        guard record.isInserted || observedAt >= record.observedAt else { return }

        record.key = key
        record.providerRaw = provider.rawValue
        record.day = bucket.day
        record.tokens = Int64(bucket.tokens)
        record.costUSD = bucket.costUSD.map(NSNumber.init(value:))
        record.observedAt = observedAt
    }

    private func delete<Record: NSManagedObject>(
        _ request: NSFetchRequest<Record>,
        matching predicate: NSPredicate? = nil
    ) throws {
        request.predicate = predicate
        for record in try context.fetch(request) {
            context.delete(record)
        }
    }

    private func insertSnapshotRecord() -> SnapshotRecord {
        NSEntityDescription.insertNewObject(
            forEntityName: "SnapshotRecord",
            into: context
        ) as! SnapshotRecord
    }

    private func insertDailyUsageRecord() -> DailyUsageRecord {
        NSEntityDescription.insertNewObject(
            forEntityName: "DailyUsageRecord",
            into: context
        ) as! DailyUsageRecord
    }

    private func insertNotificationRecord() -> NotificationRecord {
        NSEntityDescription.insertNewObject(
            forEntityName: "NotificationRecord",
            into: context
        ) as! NotificationRecord
    }

    private func insertSettingsRecord() -> SettingsRecord {
        NSEntityDescription.insertNewObject(
            forEntityName: "SettingsRecord",
            into: context
        ) as! SettingsRecord
    }

    private static func snapshotKey(_ provider: ProviderID, _ date: Date) -> String {
        "\(provider.rawValue):\(date.timeIntervalSinceReferenceDate.bitPattern)"
    }

    private static func dailyKey(_ provider: ProviderID, _ day: Date) -> String {
        "\(provider.rawValue):\(day.timeIntervalSinceReferenceDate.bitPattern)"
    }

    private static func persistenceCost(_ cost: CostDisplay) -> (String, Double?) {
        switch cost {
        case let .exactUSD(value):
            ("exactUSD", value)
        case let .estimatedUSD(value):
            ("estimatedUSD", value)
        case .includedWithPlan:
            ("includedWithPlan", nil)
        case .unavailable:
            ("unavailable", nil)
        }
    }

    private static func domainCost(kind: String, value: Double?) throws -> CostDisplay {
        switch kind {
        case "exactUSD":
            guard let value else {
                throw SnapshotRepositoryError.corruptCostDisplay(kind)
            }
            return .exactUSD(value)
        case "estimatedUSD":
            guard let value else {
                throw SnapshotRepositoryError.corruptCostDisplay(kind)
            }
            return .estimatedUSD(value)
        case "includedWithPlan":
            return .includedWithPlan
        case "unavailable":
            return .unavailable
        default:
            throw SnapshotRepositoryError.corruptCostDisplay(kind)
        }
    }
}

private extension SnapshotRecord {
    static func fetchRequest() -> NSFetchRequest<SnapshotRecord> {
        NSFetchRequest(entityName: "SnapshotRecord")
    }
}

private extension DailyUsageRecord {
    static func fetchRequest() -> NSFetchRequest<DailyUsageRecord> {
        NSFetchRequest(entityName: "DailyUsageRecord")
    }
}

private extension NotificationRecord {
    static func fetchRequest() -> NSFetchRequest<NotificationRecord> {
        NSFetchRequest(entityName: "NotificationRecord")
    }
}

private extension SettingsRecord {
    static func fetchRequest() -> NSFetchRequest<SettingsRecord> {
        NSFetchRequest(entityName: "SettingsRecord")
    }
}
