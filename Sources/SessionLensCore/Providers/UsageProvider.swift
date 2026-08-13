import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func refresh(at now: Date) async -> ProviderSnapshot
}
