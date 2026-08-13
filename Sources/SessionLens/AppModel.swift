import AppKit
import Combine
import Foundation
import SessionLensCore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshots: [ProviderID: ProviderSnapshot]
  @Published private(set) var quotaHistory: [ProviderID: [QuotaHistoryPoint]]
  @Published var selectedProvider: ProviderID
  @Published private(set) var chartRange: UsageChartRange
  @Published private(set) var isRefreshing = false
  @Published private(set) var settings: AppSettings
  @Published private(set) var claudeBridgeStatus: ClaudeBridgeInstallStatus
  @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
  @Published private(set) var errorMessage: String?

  private let coordinator: UsageCoordinator
  private let repository: SnapshotRepository
  private let notificationScheduler: any NotificationScheduling
  private let notificationEvaluator: NotificationEvaluator
  private let claudeBridgeInstaller: ClaudeBridgeInstaller?
  private let launchAtLoginController: LaunchAtLoginController
  private let automaticRefreshEnabled: Bool
  private var timerTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?

  init(
    coordinator: UsageCoordinator,
    repository: SnapshotRepository,
    notificationScheduler: any NotificationScheduling,
    settings: AppSettings,
    initialSnapshots: [ProviderID: ProviderSnapshot] = [:],
    initialQuotaHistory: [ProviderID: [QuotaHistoryPoint]] = [:],
    selectedProvider: ProviderID = .codex,
    automaticRefreshEnabled: Bool = true,
    claudeBridgeInstaller: ClaudeBridgeInstaller? = nil,
    launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
    initialClaudeBridgeStatus: ClaudeBridgeInstallStatus = .notInstalled,
    notificationEvaluator: NotificationEvaluator = NotificationEvaluator()
  ) {
    self.coordinator = coordinator
    self.repository = repository
    self.notificationScheduler = notificationScheduler
    self.settings = settings
    self.snapshots = initialSnapshots
    self.quotaHistory = initialQuotaHistory
    self.selectedProvider = selectedProvider
    self.chartRange = settings.chartRange
    self.automaticRefreshEnabled = automaticRefreshEnabled
    self.claudeBridgeInstaller = claudeBridgeInstaller
    self.launchAtLoginController = launchAtLoginController
    self.claudeBridgeStatus = initialClaudeBridgeStatus
    self.launchAtLoginStatus = launchAtLoginController.status
    self.notificationEvaluator = notificationEvaluator
  }

  var selectedSnapshot: ProviderSnapshot? {
    snapshots[selectedProvider]
  }

  var providerOrder: [ProviderID] { settings.providerOrder }

  var dataStoreURL: URL? { repository.storeURL }

  var menuBarSummary: MenuBarSummary {
    MenuBarSummary.make(
      mode: settings.menuBarDisplayMode,
      snapshots: Array(snapshots.values),
      providerOrder: settings.providerOrder
    )
  }

  static func live() -> AppModel {
    let repository = makeRepository()
    let settings = (try? repository.loadSettings()) ?? .defaults
    let providers = makeLiveProviders()
    let coordinator = UsageCoordinator(
      providers: providers,
      repository: repository,
      settings: settings
    )
    return AppModel(
      coordinator: coordinator,
      repository: repository,
      notificationScheduler: NotificationScheduler(repository: repository),
      settings: settings,
      claudeBridgeInstaller: ClaudeBridgeInstaller(
        helperSource: packagedClaudeBridgeHelperURL()
      )
    )
  }

  static func visualFixtures() -> AppModel {
    let repository: SnapshotRepository
    do {
      repository = try .inMemory()
    } catch {
      preconditionFailure("SessionLens could not create its preview store")
    }
    let fixtureSnapshots = PreviewFixtures.snapshots
    let providers: [any UsageProvider] = fixtureSnapshots.values.map {
      PreviewUsageProvider(snapshot: $0)
    }
    let settings = PreviewFixtures.settings
    return AppModel(
      coordinator: UsageCoordinator(
        providers: providers,
        repository: repository,
        settings: settings
      ),
      repository: repository,
      notificationScheduler: NotificationScheduler(
        repository: repository,
        delivery: PreviewNotificationDelivery()
      ),
      settings: settings,
      initialSnapshots: fixtureSnapshots,
      initialQuotaHistory: PreviewFixtures.quotaHistory,
      selectedProvider: .codex,
      automaticRefreshEnabled: false
    )
  }

  func start() {
    guard automaticRefreshEnabled, timerTask == nil else { return }
    refresh()
    restartTimer()
  }

  func stop() {
    timerTask?.cancel()
    timerTask = nil
    refreshTask?.cancel()
    refreshTask = nil
  }

  func refresh() {
    guard refreshTask == nil else { return }
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await refreshNow()
      refreshTask = nil
    }
  }

  func refreshNow(at now: Date = Date()) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let previous = snapshots
    let state = await coordinator.refresh(at: now)
    snapshots = state.snapshots
    if automaticRefreshEnabled {
      reloadQuotaHistory(now: now)
    }
    guard settings.notificationsEnabled else { return }

    for provider in settings.providerOrder {
      guard let current = snapshots[provider] else { continue }
      let events = notificationEvaluator.events(
        provider: provider,
        previous: previous[provider],
        current: current,
        thresholds: settings.notificationThresholds
      ).filter { event in
        settings.notifyOnReset || event.kind != .reset
      }
      for event in events {
        do {
          try await notificationScheduler.schedule(event)
        } catch {
          errorMessage = "A local notification could not be delivered."
        }
      }
    }
  }

  func popoverDidOpen(now: Date = Date()) {
    guard automaticRefreshEnabled else { return }
    guard let newest = snapshots.values.map(\.observedAt).max() else {
      refresh()
      return
    }
    guard now.timeIntervalSince(newest) > 15 else { return }
    refresh()
  }

  func selectProvider(_ provider: ProviderID) {
    selectedProvider = provider
  }

  func setChartRange(_ range: UsageChartRange) {
    chartRange = range
    var updated = settings
    updated.chartRange = range
    applySettings(updated)
  }

  func applySettings(_ updated: AppSettings) {
    settings = updated
    chartRange = updated.chartRange
    Task { await coordinator.updateSettings(updated) }
    if automaticRefreshEnabled {
      restartTimer()
    }
  }

  func setRefreshInterval(_ seconds: Int) {
    var updated = settings
    updated.refreshIntervalSeconds = seconds
    applySettings(updated)
  }

  func setHistoryRetention(_ days: Int) {
    var updated = settings
    updated.historyRetentionDays = days
    applySettings(updated)
  }

  func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
    var updated = settings
    updated.menuBarDisplayMode = mode
    applySettings(updated)
  }

  func moveProvider(_ provider: ProviderID, by offset: Int) {
    guard let index = settings.providerOrder.firstIndex(of: provider) else {
      return
    }
    let destination = index + offset
    guard settings.providerOrder.indices.contains(destination) else { return }
    var updated = settings
    updated.providerOrder.swapAt(index, destination)
    applySettings(updated)
  }

  func setOpenCodeQuotaProvider(
    _ quotaProvider: ProviderID?,
    for providerID: String
  ) {
    var updated = settings
    updated.setQuotaProvider(quotaProvider, forOpenCodeProviderID: providerID)
    applySettings(updated)
  }

  func setNotificationThreshold(_ threshold: Int, enabled: Bool) {
    var values = settings.notificationThresholds.filter { $0 != threshold }
    if enabled { values.append(threshold) }
    var updated = settings
    updated.notificationThresholds = values.sorted()
    applySettings(updated)
  }

  func setNotifyOnReset(_ enabled: Bool) {
    var updated = settings
    updated.notifyOnReset = enabled
    applySettings(updated)
  }

  func setLaunchAtLoginEnabled(_ enabled: Bool) {
    do {
      try launchAtLoginController.setEnabled(enabled)
      launchAtLoginStatus = launchAtLoginController.status
      var updated = settings
      updated.launchAtLogin =
        launchAtLoginStatus == .enabled
        || launchAtLoginStatus == .requiresApproval
      applySettings(updated)
      if launchAtLoginStatus == .requiresApproval {
        errorMessage = "Allow SessionLens in System Settings under Login Items."
      }
    } catch {
      launchAtLoginStatus = launchAtLoginController.status
      errorMessage = "Launch at login could not be changed."
    }
  }

  func refreshSettingsState() {
    launchAtLoginStatus = launchAtLoginController.status
    guard let claudeBridgeInstaller else {
      claudeBridgeStatus = .notInstalled
      return
    }
    do {
      claudeBridgeStatus = try claudeBridgeInstaller.status()
    } catch {
      errorMessage = "The Claude bridge state could not be read."
    }
  }

  func installClaudeBridge() {
    guard let claudeBridgeInstaller else {
      errorMessage = "The packaged Claude bridge helper is unavailable."
      return
    }
    do {
      try claudeBridgeInstaller.install()
      claudeBridgeStatus = try claudeBridgeInstaller.status()
      refresh()
    } catch {
      errorMessage = Self.claudeBridgeErrorMessage(error, installing: true)
    }
  }

  func uninstallClaudeBridge() {
    guard let claudeBridgeInstaller else {
      errorMessage = "The Claude bridge is not installed."
      return
    }
    do {
      try claudeBridgeInstaller.uninstall()
      claudeBridgeStatus = .notInstalled
      refresh()
    } catch {
      errorMessage = Self.claudeBridgeErrorMessage(error, installing: false)
    }
  }

  func setNotificationsEnabled(_ enabled: Bool) async {
    var updated = settings
    if enabled {
      do {
        let granted = try await notificationScheduler.requestAuthorization()
        updated.notificationsEnabled = granted
        if !granted {
          errorMessage = "Notifications are disabled in System Settings."
        }
      } catch {
        updated.notificationsEnabled = false
        errorMessage = "Notification permission could not be requested."
      }
    } else {
      updated.notificationsEnabled = false
    }
    applySettings(updated)
  }

  func clearHistory() {
    do {
      try repository.clearHistory()
      snapshots = [:]
      quotaHistory = [:]
      errorMessage = nil
    } catch {
      errorMessage = "SessionLens history could not be cleared."
    }
  }

  func dismissError() {
    errorMessage = nil
  }

  func openSettings() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.sendAction(
      Selector(("showSettingsWindow:")),
      to: nil,
      from: nil
    )
  }

  func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func restartTimer() {
    timerTask?.cancel()
    guard automaticRefreshEnabled else {
      timerTask = nil
      return
    }
    let interval = settings.refreshIntervalSeconds
    timerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled, let self else { return }
        await refreshNow()
      }
    }
  }

  private func reloadQuotaHistory(now: Date) {
    let start = now.addingTimeInterval(-5 * 3_600)
    var refreshed: [ProviderID: [QuotaHistoryPoint]] = [:]
    for (provider, snapshot) in snapshots {
      let window =
        snapshot.quotaWindows.first(where: {
          $0.durationMinutes == 10_080
        }) ?? snapshot.quotaWindows.first
      guard let duration = window?.durationMinutes else { continue }
      refreshed[provider] =
        (try? repository.quotaHistory(
          provider: provider,
          durationMinutes: duration,
          range: start...now
        )) ?? []
    }
    quotaHistory = refreshed
  }

  private static func makeRepository() -> SnapshotRepository {
    do {
      return try .persistent()
    } catch {
      do {
        return try .inMemory()
      } catch {
        preconditionFailure("SessionLens could not create a local aggregate store")
      }
    }
  }

  private static func makeLiveProviders() -> [any UsageProvider] {
    let locator = ExecutableLocator()
    let process = FoundationProcessRunner(
      stderrLimit: 4_096,
      stdoutLimit: 16 * 1_024 * 1_024
    )
    let home = FileManager.default.homeDirectoryForCurrentUser
    let openCode = OpenCodeProvider(
      databaseURL: home.appendingPathComponent(
        ".local/share/opencode/opencode.db"
      ),
      process: process,
      sqliteURL: locator.resolve(.sqlite3)
        ?? URL(fileURLWithPath: "/usr/bin/sqlite3")
    )
    let claude = ClaudeProvider()
    let codex: any UsageProvider
    if let executable = locator.resolve(.codex) {
      codex = CodexProvider(
        client: CodexAppServerClient(
          transport: FoundationJSONLTransport(executable: executable)
        )
      )
    } else {
      codex = MissingUsageProvider(id: .codex, health: .toolMissing)
    }
    return [openCode, claude, codex]
  }

  private static func packagedClaudeBridgeHelperURL() -> URL {
    let bundled = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Helpers/SessionLensClaudeBridge"
    )
    if FileManager.default.fileExists(atPath: bundled.path) {
      return bundled
    }
    return Bundle.main.executableURL?
      .deletingLastPathComponent()
      .appendingPathComponent("SessionLensClaudeBridge")
      ?? bundled
  }

  private static func claudeBridgeErrorMessage(
    _ error: any Error,
    installing: Bool
  ) -> String {
    guard let error = error as? ClaudeBridgeInstallError else {
      return installing
        ? "The Claude bridge could not be installed."
        : "The Claude bridge could not be uninstalled."
    }
    switch error {
    case .invalidSettings, .invalidStatusLine:
      return "Claude settings are not in a supported format and were left unchanged."
    case .alreadyInstalled:
      return "The Claude bridge is already installed."
    case .notInstalled:
      return "The Claude bridge is not installed."
    case .missingHelper:
      return "The packaged Claude bridge helper is unavailable."
    case .invalidMetadata:
      return "SessionLens bridge metadata is invalid; Claude settings were left unchanged."
    case .settingsChangedAfterInstall:
      return "Claude settings changed after installation, so SessionLens left them unchanged."
    }
  }
}

private struct MissingUsageProvider: UsageProvider {
  let id: ProviderID
  let health: ProviderHealth

  func refresh(at now: Date) async -> ProviderSnapshot {
    .unavailable(provider: id, health: health, observedAt: now)
  }
}

private struct PreviewUsageProvider: UsageProvider {
  let snapshot: ProviderSnapshot
  var id: ProviderID { snapshot.provider }

  func refresh(at now: Date) async -> ProviderSnapshot { snapshot }
}

@MainActor
private final class PreviewNotificationDelivery: NotificationDelivering {
  func requestAuthorization() async throws -> Bool { false }
  func deliver(_ event: NotificationEvent) async throws {}
}
