import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
  case disabled
  case enabled
  case requiresApproval
  case notFound
}

@MainActor
public protocol LoginItemServicing: AnyObject {
  var status: LaunchAtLoginStatus { get }

  func register() throws
  func unregister() throws
}

@MainActor
public final class LaunchAtLoginController {
  private let service: any LoginItemServicing

  public convenience init() {
    self.init(service: MainAppLoginItemService())
  }

  init(service: any LoginItemServicing) {
    self.service = service
  }

  public var status: LaunchAtLoginStatus { service.status }

  public var isEnabled: Bool { status == .enabled }

  public func setEnabled(_ enabled: Bool) throws {
    switch (enabled, status) {
    case (true, .enabled), (false, .disabled), (false, .notFound):
      return
    case (true, _):
      try service.register()
    case (false, .enabled), (false, .requiresApproval):
      try service.unregister()
    }
  }
}

@MainActor
private final class MainAppLoginItemService: LoginItemServicing {
  private let service = SMAppService.mainApp

  var status: LaunchAtLoginStatus {
    switch service.status {
    case .notRegistered:
      .disabled
    case .enabled:
      .enabled
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .notFound
    @unknown default:
      .notFound
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }
}
