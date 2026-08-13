import Foundation
import Testing

@testable import SessionLensCore

@Suite
@MainActor
struct LaunchAtLoginControllerTests {
  @Test
  func enablingRegistersMainApp() throws {
    let service = FakeLoginItemService(status: .disabled)
    let controller = LaunchAtLoginController(service: service)

    try controller.setEnabled(true)

    #expect(service.registerCount == 1)
    #expect(service.unregisterCount == 0)
    #expect(controller.isEnabled)
  }

  @Test
  func enablingAlreadyRegisteredAppIsIdempotent() throws {
    let service = FakeLoginItemService(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    try controller.setEnabled(true)

    #expect(service.registerCount == 0)
    #expect(controller.status == .enabled)
  }

  @Test
  func disablingUnregistersEnabledApp() throws {
    let service = FakeLoginItemService(status: .enabled)
    let controller = LaunchAtLoginController(service: service)

    try controller.setEnabled(false)

    #expect(service.unregisterCount == 1)
    #expect(!controller.isEnabled)
  }

  @Test
  func disablingAppAwaitingApprovalRemovesRegistration() throws {
    let service = FakeLoginItemService(status: .requiresApproval)
    let controller = LaunchAtLoginController(service: service)

    try controller.setEnabled(false)

    #expect(service.unregisterCount == 1)
    #expect(controller.status == .disabled)
  }

  @Test
  func registrationFailureLeavesReportedStateUnchanged() {
    let service = FakeLoginItemService(
      status: .disabled,
      registerError: FakeFailure.registration
    )
    let controller = LaunchAtLoginController(service: service)

    #expect(throws: FakeFailure.registration) {
      try controller.setEnabled(true)
    }

    #expect(service.registerCount == 1)
    #expect(controller.status == .disabled)
  }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
  private(set) var status: LaunchAtLoginStatus
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private let registerError: (any Error)?

  init(
    status: LaunchAtLoginStatus,
    registerError: (any Error)? = nil
  ) {
    self.status = status
    self.registerError = registerError
  }

  func register() throws {
    registerCount += 1
    if let registerError { throw registerError }
    status = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    status = .disabled
  }
}

private enum FakeFailure: Error {
  case registration
}
