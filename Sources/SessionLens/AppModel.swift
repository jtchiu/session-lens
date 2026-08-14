import AppKit
import Combine
import Foundation
import SessionLensCore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var snapshots: [ProviderID: ProviderSnapshot]
  @Published private(set) var spendSummary: SpendSummary
  @Published private(set) var pricingState: PricingCatalogState
  @Published private(set) var quotaHistory: [ProviderID: [QuotaHistoryPoint]]
  @Published var selectedProvider: ProviderID
  @Published private(set) var chartRange: UsageChartRange
  @Published private(set) var isRefreshing = false
  @Published private(set) var settings: AppSettings
  @Published private(set) var claudeBridgeStatus: ClaudeBridgeInstallStatus
  @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
  @Published private(set) var notificationPermissionStatus: NotificationPermissionStatus
  @Published private(set) var errorMessage: String?

  private let coordinator: UsageCoordinator
  private let repository: SnapshotRepository
  private let pricingCatalogClient: PricingCatalogClient
  private let codexModelID: String?
  private let notificationScheduler: any NotificationScheduling
  private let notificationEvaluator: NotificationEvaluator
  private let claudeBridgeInstaller: ClaudeBridgeInstaller?
  private let launchAtLoginController: LaunchAtLoginController
  private let automaticRefreshEnabled: Bool
  private var timerTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var pricingRefreshTask: Task<Void, Never>?
  private var pricingRefreshGeneration: UUID?

  init(
    coordinator: UsageCoordinator,
    repository: SnapshotRepository,
    notificationScheduler: any NotificationScheduling,
    settings: AppSettings,
    initialSnapshots: [ProviderID: ProviderSnapshot] = [:],
    initialSpendSummary: SpendSummary = .empty(),
    initialPricingState: PricingCatalogState = PricingCatalogState(
      source: .unavailable,
      catalog: nil
    ),
    pricingCatalogClient: PricingCatalogClient? = nil,
    codexModelID: String? = nil,
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
    self.pricingCatalogClient = pricingCatalogClient
      ?? Self.makePricingCatalogClient(repository: repository)
    self.codexModelID = codexModelID
      ?? CodexModelDetector.live(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
      )
    self.notificationScheduler = notificationScheduler
    self.settings = settings
    self.snapshots = initialSnapshots
    self.spendSummary = initialSpendSummary
    self.pricingState = initialPricingState
    self.quotaHistory = initialQuotaHistory
    self.selectedProvider = selectedProvider
    self.chartRange = settings.chartRange
    self.automaticRefreshEnabled = automaticRefreshEnabled
    self.claudeBridgeInstaller = claudeBridgeInstaller
    self.launchAtLoginController = launchAtLoginController
    self.claudeBridgeStatus = initialClaudeBridgeStatus
    self.launchAtLoginStatus = launchAtLoginController.status
    self.notificationPermissionStatus = .notDetermined
    self.notificationEvaluator = notificationEvaluator
  }

  var selectedSnapshot: ProviderSnapshot? {
    snapshots[selectedProvider]
  }

  var providerOrder: [ProviderID] { settings.providerOrder }

  var openCodeProviderIDs: [String] {
    let discovered = snapshots[.opencode]?.modelBreakdowns.compactMap {
      $0.providerID
    } ?? []
    let configured = Array(settings.quotaMappings.keys)
      + Array(settings.localBudgets.keys).filter { $0 != "*" }
    let values = Set(discovered + configured).filter { !$0.isEmpty }
    return values.sorted()
  }

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
    let initialSnapshots = (try? repository.latestSnapshots()) ?? [:]
    let initialHistory = loadQuotaHistory(
      repository: repository,
      snapshots: initialSnapshots,
      settings: settings
    )
    let initialSpendSummary = loadSpendSummary(
      repository: repository,
      snapshots: initialSnapshots,
      settings: settings,
      now: Date()
    )
    let providers = makeLiveProviders()
    let coordinator = UsageCoordinator(
      providers: providers,
      repository: repository,
      settings: settings,
      initialState: UsageState(snapshots: initialSnapshots)
    )
    return AppModel(
      coordinator: coordinator,
      repository: repository,
      notificationScheduler: NotificationScheduler(repository: repository),
      settings: settings,
      initialSnapshots: initialSnapshots,
      initialSpendSummary: initialSpendSummary,
      initialQuotaHistory: initialHistory,
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
      initialSpendSummary: PreviewFixtures.spendSummary,
      initialPricingState: PreviewFixtures.pricingState,
      pricingCatalogClient: PreviewFixtures.pricingCatalogClient,
      codexModelID: PreviewFixtures.codexModelID,
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
    pricingRefreshGeneration = nil
    pricingRefreshTask?.cancel()
    pricingRefreshTask = nil
    Task { await coordinator.shutdown() }
  }

  func refresh() {
    guard refreshTask == nil else { return }
    refreshPricing()
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await refreshNow()
      refreshTask = nil
    }
  }

  func refreshNow(at now: Date = Date()) async {
    refreshPricing(now: now)
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    let previous = snapshots
    let state = await coordinator.refresh(at: now)
    snapshots = state.snapshots
    if automaticRefreshEnabled {
      reloadQuotaHistory(now: now)
    }
    try? repository.prune(
      now: now,
      historyRetentionDays: settings.historyRetentionDays
    )
    reloadSpendSummary(now: now)
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

  func refreshPricingIfNeeded(now: Date = Date()) async {
    let client = pricingCatalogClient
    let cachedState = await client.state(now: now)
    guard !Task.isCancelled else { return }
    applyPricingState(cachedState, now: now)

    let refreshedState = await client.refreshIfNeeded(now: now)
    guard !Task.isCancelled else { return }
    applyPricingState(refreshedState, now: now)
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
    var updated = settings
    updated.chartRange = range
    applySettings(updated)
  }

  func applySettings(_ updated: AppSettings) {
    let chartRangeChanged = chartRange != updated.chartRange
    settings = updated
    chartRange = updated.chartRange
    Task { await coordinator.updateSettings(updated) }
    try? repository.prune(
      now: Date(),
      historyRetentionDays: updated.historyRetentionDays
    )
    reloadSpendSummary(now: Date())
    if chartRangeChanged {
      reloadQuotaHistory(now: Date())
    }
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

  func setOpenCodeLocalBudget(
    _ budget: OpenCodeLocalBudget?,
    for providerID: String
  ) {
    var updated = settings
    updated.setLocalBudget(budget, forOpenCodeProviderID: providerID)
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
    Task { @MainActor [weak self] in
      guard let self else { return }
      notificationPermissionStatus = await notificationScheduler.permissionStatus()
    }
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
        notificationPermissionStatus = await notificationScheduler.permissionStatus()
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
      notificationPermissionStatus = await notificationScheduler.permissionStatus()
    }
    applySettings(updated)
  }

  func openNotificationSettings() {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    ) else { return }
    NSWorkspace.shared.open(url)
  }

  func clearHistory() {
    do {
      try repository.clearHistory()
      snapshots = [:]
      reloadSpendSummary(now: Date())
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
        refresh()
      }
    }
  }

  private func refreshPricing(now: Date = Date()) {
    guard pricingRefreshTask == nil else { return }
    let generation = UUID()
    let client = pricingCatalogClient
    pricingRefreshGeneration = generation
    pricingRefreshTask = Task { [weak self, client] in
      let cachedState = await client.state(now: now)
      guard !Task.isCancelled else { return }
      if let self, self.pricingRefreshGeneration == generation {
        self.applyPricingState(cachedState, now: now)
      } else {
        return
      }

      let refreshedState = await client.refreshIfNeeded(now: now)
      guard !Task.isCancelled,
            let self,
            self.pricingRefreshGeneration == generation
      else { return }
      self.applyPricingState(refreshedState, now: now)
      self.finishPricingRefresh(generation: generation)
    }
  }

  private func applyPricingState(_ state: PricingCatalogState, now: Date) {
    pricingState = state
    reloadSpendSummary(now: now)
  }

  private func finishPricingRefresh(generation: UUID) {
    guard pricingRefreshGeneration == generation else { return }
    pricingRefreshTask = nil
    pricingRefreshGeneration = nil
  }

  private func reloadSpendSummary(now: Date) {
    spendSummary = Self.loadSpendSummary(
      repository: repository,
      snapshots: snapshots,
      settings: settings,
      pricingState: pricingState,
      codexModelID: codexModelID,
      now: now
    )
  }

  private func reloadQuotaHistory(now: Date) {
    let calendar = Calendar.current
    var refreshed: [ProviderID: [QuotaHistoryPoint]] = [:]
    let queries = QuotaHistoryQueryBuilder.rangeChange(
      snapshots: snapshots,
      chartRange: chartRange,
      endingAt: now,
      calendar: calendar
    )
    for query in queries {
      refreshed[query.provider] =
        (try? repository.dailyQuotaHistory(
          provider: query.provider,
          durationMinutes: query.durationMinutes,
          range: query.range,
          calendar: calendar
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

  private static func makePricingCatalogClient(
    repository: SnapshotRepository
  ) -> PricingCatalogClient {
    let cacheURL: URL
    if let storeURL = repository.storeURL {
      cacheURL = storeURL
        .deletingLastPathComponent()
        .appendingPathComponent("pricing-catalog.json")
    } else {
      let applicationSupportURL = (try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? FileManager.default.temporaryDirectory
      cacheURL = applicationSupportURL
        .appendingPathComponent("SessionLens", isDirectory: true)
        .appendingPathComponent("pricing-catalog.json")
    }
    return PricingCatalogClient(cacheURL: cacheURL)
  }

  private static func loadQuotaHistory(
    repository: SnapshotRepository,
    snapshots: [ProviderID: ProviderSnapshot],
    settings: AppSettings
  ) -> [ProviderID: [QuotaHistoryPoint]] {
    let now = Date()
    let calendar = Calendar.current
    var history: [ProviderID: [QuotaHistoryPoint]] = [:]
    let queries = QuotaHistoryQueryBuilder.launchHydration(
      snapshots: snapshots,
      settings: settings,
      endingAt: now,
      calendar: calendar
    )
    for query in queries {
      history[query.provider] = (try? repository.dailyQuotaHistory(
        provider: query.provider,
        durationMinutes: query.durationMinutes,
        range: query.range,
        calendar: calendar
      )) ?? []
    }
    return history
  }

  private static func loadSpendSummary(
    repository: SnapshotRepository,
    snapshots: [ProviderID: ProviderSnapshot],
    settings: AppSettings,
    pricingState: PricingCatalogState = PricingCatalogState(
      source: .unavailable,
      catalog: nil
    ),
    codexModelID: String? = nil,
    now: Date
  ) -> SpendSummary {
    var dailyBuckets: [ProviderID: [UsageBucket]] = [:]
    for provider in ProviderID.allCases {
      dailyBuckets[provider] = (try? repository.dailyUsage(
        provider: provider,
        range: Date.distantPast...Date.distantFuture
      )) ?? []
    }
    let samples = (try? repository.spendSamples()) ?? []
    return SpendSummaryLoader.makeSummary(
      now: now,
      historyRetentionDays: settings.historyRetentionDays,
      snapshots: snapshots,
      dailyBuckets: dailyBuckets,
      samples: samples,
      catalogState: pricingState,
      codexModelID: codexModelID
    )
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
      codex = MissingUsageProvider(
        id: .codex,
        health: .toolMissing,
        candidates: locator.candidates(.codex)
      )
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
  let candidates: [URL]

  func refresh(at now: Date) async -> ProviderSnapshot {
    .unavailable(
      provider: id,
      health: health,
      observedAt: now,
      diagnostic: candidates.isEmpty
        ? nil
        : "Checked: " + candidates.map(\.path).joined(separator: ", ")
    )
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
