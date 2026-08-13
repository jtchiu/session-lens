import Foundation
import UserNotifications

@MainActor
public protocol NotificationDelivering: AnyObject {
    func requestAuthorization() async throws -> Bool
    func deliver(_ event: NotificationEvent) async throws
}

@MainActor
public protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async throws -> Bool
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
