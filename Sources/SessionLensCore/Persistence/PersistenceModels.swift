import CoreData
import Foundation

@objc(SnapshotRecord)
final class SnapshotRecord: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var providerRaw: String
    @NSManaged var observedAt: Date
    @NSManaged var healthRaw: String
    @NSManaged var tokenData: Data?
    @NSManaged var costKindRaw: String
    @NSManaged var costUSD: NSNumber?
    @NSManaged var costSampleData: Data?
    @NSManaged var quotaData: Data
}

@objc(DailyUsageRecord)
final class DailyUsageRecord: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var providerRaw: String
    @NSManaged var day: Date
    @NSManaged var tokens: Int64
    @NSManaged var costUSD: NSNumber?
    @NSManaged var observedAt: Date
}

@objc(SpendSampleRecord)
final class SpendSampleRecord: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var providerRaw: String
    @NSManaged var observedAt: Date
    @NSManaged var scopeID: String?
    @NSManaged var cumulativeCostUSD: NSNumber?
    @NSManaged var cumulativeTokens: NSNumber?
    @NSManaged var provenanceRaw: String
}

@objc(NotificationRecord)
final class NotificationRecord: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var createdAt: Date
}

@objc(SettingsRecord)
final class SettingsRecord: NSManagedObject {
    @NSManaged var key: String
    @NSManaged var settingsData: Data
    @NSManaged var updatedAt: Date
}

enum SessionLensPersistenceModel {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["SessionLens-1"]
        model.entities = [
            snapshotEntity(),
            dailyUsageEntity(),
            spendSampleEntity(),
            notificationEntity(),
            settingsEntity(),
        ]
        return model
    }

    private static func snapshotEntity() -> NSEntityDescription {
        entity(
            named: "SnapshotRecord",
            managedObjectClass: SnapshotRecord.self,
            attributes: [
                attribute("key", .stringAttributeType),
                attribute("providerRaw", .stringAttributeType),
                attribute("observedAt", .dateAttributeType),
                attribute("healthRaw", .stringAttributeType),
                attribute("tokenData", .binaryDataAttributeType, optional: true),
                attribute("costKindRaw", .stringAttributeType),
                attribute("costUSD", .doubleAttributeType, optional: true),
                attribute("costSampleData", .binaryDataAttributeType, optional: true),
                attribute("quotaData", .binaryDataAttributeType),
            ],
            uniqueBy: ["key"]
        )
    }

    private static func dailyUsageEntity() -> NSEntityDescription {
        entity(
            named: "DailyUsageRecord",
            managedObjectClass: DailyUsageRecord.self,
            attributes: [
                attribute("key", .stringAttributeType),
                attribute("providerRaw", .stringAttributeType),
                attribute("day", .dateAttributeType),
                attribute("tokens", .integer64AttributeType),
                attribute("costUSD", .doubleAttributeType, optional: true),
                attribute("observedAt", .dateAttributeType),
            ],
            uniqueBy: ["key"]
        )
    }

    private static func notificationEntity() -> NSEntityDescription {
        entity(
            named: "NotificationRecord",
            managedObjectClass: NotificationRecord.self,
            attributes: [
                attribute("key", .stringAttributeType),
                attribute("createdAt", .dateAttributeType),
            ],
            uniqueBy: ["key"]
        )
    }

    private static func spendSampleEntity() -> NSEntityDescription {
        entity(
            named: "SpendSampleRecord",
            managedObjectClass: SpendSampleRecord.self,
            attributes: [
                attribute("key", .stringAttributeType),
                attribute("providerRaw", .stringAttributeType),
                attribute("observedAt", .dateAttributeType),
                attribute("scopeID", .stringAttributeType, optional: true),
                attribute("cumulativeCostUSD", .doubleAttributeType, optional: true),
                attribute("cumulativeTokens", .integer64AttributeType, optional: true),
                attribute("provenanceRaw", .stringAttributeType),
            ],
            uniqueBy: ["key"]
        )
    }

    private static func settingsEntity() -> NSEntityDescription {
        entity(
            named: "SettingsRecord",
            managedObjectClass: SettingsRecord.self,
            attributes: [
                attribute("key", .stringAttributeType),
                attribute("settingsData", .binaryDataAttributeType),
                attribute("updatedAt", .dateAttributeType),
            ],
            uniqueBy: ["key"]
        )
    }

    private static func entity(
        named name: String,
        managedObjectClass: NSManagedObject.Type,
        attributes: [NSAttributeDescription],
        uniqueBy uniqueKeys: [String]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(managedObjectClass)
        entity.properties = attributes
        entity.uniquenessConstraints = [uniqueKeys]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

public enum PersistencePrivacyIntrospector {
    public static var persistedPropertyNames: Set<String> {
        Set(
            SessionLensPersistenceModel.makeModel().entities.flatMap { entity in
                entity.properties.map(\.name)
            }
        )
    }
}
