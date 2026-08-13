import Foundation
import UserNotifications

public enum NotificationPermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol NotificationDelivering: AnyObject {
    func requestAuthorization() async throws -> Bool
    func permissionStatus() async -> NotificationPermissionStatus
    func deliver(_ event: NotificationEvent) async throws
}

public extension NotificationDelivering {
    func permissionStatus() async -> NotificationPermissionStatus {
        .notDetermined
    }
}

@MainActor
public protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async throws -> Bool
    func permissionStatus() async -> NotificationPermissionStatus
    func schedule(_ event: NotificationEvent) async throws
}

@MainActor
public final class UNNotificationScheduler: NotificationScheduling {
    private let repository: SnapshotRepository
    private let delivery: any NotificationDelivering
    private var inFlightKeys = Set<String>()

    public init(
        repository: SnapshotRepository,
        delivery: any NotificationDelivering = UserNotificationCenterDelivery()
    ) {
        self.repository = repository
        self.delivery = delivery
    }

    public func requestAuthorization() async throws -> Bool {
        try await delivery.requestAuthorization()
    }

    public func permissionStatus() async -> NotificationPermissionStatus {
        await delivery.permissionStatus()
    }

    public func schedule(_ event: NotificationEvent) async throws {
        guard !inFlightKeys.contains(event.key),
            try !repository.hasNotification(event.key)
        else {
            return
        }
        inFlightKeys.insert(event.key)
        defer { inFlightKeys.remove(event.key) }

        try await delivery.deliver(event)
        try repository.markNotification(event.key)
    }
}

public typealias NotificationScheduler = UNNotificationScheduler

@MainActor
public final class UserNotificationCenterDelivery: NotificationDelivering {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func permissionStatus() async -> NotificationPermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    public func deliver(_ event: NotificationEvent) async throws {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        try await center.add(
            UNNotificationRequest(
                identifier: event.key,
                content: content,
                trigger: nil
            )
        )
    }
}
