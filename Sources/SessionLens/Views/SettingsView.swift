import AppKit
import SessionLensCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @State private var selection: SettingsPane = .providers
  @State private var confirmation: SettingsConfirmation?

  var body: some View {
    HStack(spacing: 0) {
      SettingsSidebar(selection: $selection)
        .frame(width: SettingsLayoutMetrics.sidebarWidth)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: SessionLensSpacing.large) {
          SettingsHeader(pane: selection)
          detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SessionLensSpacing.xLarge)
      }
      .scrollIndicators(.hidden)
    }
    .frame(width: 760, height: 560)
    .background(SessionLensPalette.window)
    .onAppear { model.refreshSettingsState() }
    .alert(
      confirmation?.title ?? "SessionLens",
      isPresented: Binding(
        get: { confirmation != nil },
        set: { if !$0 { confirmation = nil } }
      )
    ) {
      confirmationButtons
    } message: {
      Text(confirmation?.message ?? "")
    }
    .alert(
      "SessionLens",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.dismissError() } }
      )
    ) {
      Button("OK") { model.dismissError() }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  @ViewBuilder
  private var detail: some View {
    switch selection {
    case .general:
      GeneralSettingsView(model: model)
    case .providers:
      ProviderSettingsView(
        model: model,
        confirm: { confirmation = $0 },
        showPrivacy: { selection = .privacy }
      )
    case .menuBar:
      MenuBarSettingsView(model: model)
    case .notifications:
      NotificationSettingsView(model: model)
    case .privacy:
      PrivacySettingsView(
        model: model,
        confirmClearHistory: { confirmation = .clearHistory }
      )
    }
  }

  @ViewBuilder
  private var confirmationButtons: some View {
    switch confirmation {
    case .installBridge:
      Button("Install Bridge") {
        confirmation = nil
        model.installClaudeBridge()
      }
      Button("Cancel", role: .cancel) { confirmation = nil }
    case .uninstallBridge:
      Button("Uninstall Bridge", role: .destructive) {
        confirmation = nil
        model.uninstallClaudeBridge()
      }
      Button("Cancel", role: .cancel) { confirmation = nil }
    case .clearHistory:
      Button("Clear History", role: .destructive) {
        confirmation = nil
        model.clearHistory()
      }
      Button("Cancel", role: .cancel) { confirmation = nil }
    case nil:
      Button("Cancel", role: .cancel) { confirmation = nil }
    }
  }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
  case general = "General"
  case providers = "Providers"
  case menuBar = "Menu Bar"
  case notifications = "Notifications"
  case privacy = "Privacy"

  var id: Self { self }

  var icon: String {
    switch self {
    case .general: "gearshape"
    case .providers: "externaldrive.connected.to.line.below"
    case .menuBar: "menubar.rectangle"
    case .notifications: "bell"
    case .privacy: "lock"
    }
  }

  var subtitle: String {
    switch self {
    case .general: "App behavior and local history."
    case .providers: "Local, read-only usage sources."
    case .menuBar: "Choose what SessionLens shows at a glance."
    case .notifications: "Private alerts for quota thresholds and resets."
    case .privacy: "Inspect exactly what SessionLens reads and stores."
    }
  }
}

private enum SettingsConfirmation {
  case installBridge
  case uninstallBridge
  case clearHistory

  var title: String {
    switch self {
    case .installBridge: "Install the Claude bridge?"
    case .uninstallBridge: "Uninstall the Claude bridge?"
    case .clearHistory: "Clear SessionLens history?"
    }
  }

  var message: String {
    switch self {
    case .installBridge:
      "SessionLens will add a reversible statusLine command to ~/.claude/settings.json. Existing status-line settings are backed up and restored on uninstall."
    case .uninstallBridge:
      "SessionLens will restore the statusLine value saved during installation. If Claude settings changed since then, they will be left untouched."
    case .clearHistory:
      "This deletes only aggregate usage snapshots and notification history stored by SessionLens. Provider data and settings are not changed."
    }
  }
}

private struct SettingsSidebar: View {
  @Binding var selection: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.small) {
      HStack(spacing: SettingsLayoutMetrics.brandGap) {
        SessionLensMark(size: SettingsLayoutMetrics.brandMarkSize)
        Text("SessionLens")
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .frame(
            minWidth: SettingsLayoutMetrics.brandTitleMinimumWidth,
            alignment: .leading
          )
      }
      .padding(
        .horizontal,
        SettingsLayoutMetrics.brandHorizontalPadding
      )
      .padding(.vertical, SessionLensSpacing.xLarge)

      ForEach(SettingsPane.allCases) { pane in
        Button {
          selection = pane
        } label: {
          Label(pane.rawValue, systemImage: pane.icon)
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SessionLensSpacing.medium)
            .frame(height: 36)
            .foregroundStyle(selection == pane ? .white : .primary)
            .background(
              selection == pane ? Color.accentColor : Color.clear,
              in: RoundedRectangle(
                cornerRadius: SessionLensRadius.segment,
                style: .continuous
              )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == pane ? .isSelected : [])
      }

      Spacer()

      Text("Free · Local only")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(SessionLensSpacing.large)
    }
    .padding(.horizontal, SettingsLayoutMetrics.sidebarOuterPadding)
    .background(.regularMaterial)
  }
}

private struct SettingsHeader: View {
  let pane: SettingsPane

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
      Text(pane.rawValue)
        .font(.system(size: 26, weight: .bold, design: .rounded))
      Text(pane.subtitle)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    SettingsSurface {
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: {
            model.launchAtLoginStatus == .enabled
              || model.launchAtLoginStatus == .requiresApproval
          },
          set: { enabled in
            model.setLaunchAtLoginEnabled(enabled)
          }
        )
      )
      if model.launchAtLoginStatus == .requiresApproval {
        Text("Approval is required in System Settings → Login Items.")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      Divider()

      Picker(
        "Refresh interval",
        selection: Binding(
          get: { model.settings.refreshIntervalSeconds },
          set: { seconds in
            model.setRefreshInterval(seconds)
          }
        )
      ) {
        Text("30 seconds").tag(30)
        Text("1 minute").tag(60)
        Text("5 minutes").tag(300)
        Text("15 minutes").tag(900)
        Text("30 minutes").tag(1_800)
        Text("1 hour").tag(3_600)
      }

      Picker(
        "Default chart range",
        selection: Binding(
          get: { model.settings.chartRange },
          set: { range in
            model.setChartRange(range)
          }
        )
      ) {
        Text("7 days").tag(UsageChartRange.sevenDays)
        Text("30 days").tag(UsageChartRange.thirtyDays)
        Text("90 days").tag(UsageChartRange.ninetyDays)
      }

      Picker(
        "History retention",
        selection: Binding(
          get: { model.settings.historyRetentionDays },
          set: { days in
            model.setHistoryRetention(days)
          }
        )
      ) {
        Text("30 days").tag(30)
        Text("90 days").tag(90)
        Text("1 year").tag(365)
        Text("3 years").tag(1_095)
      }
    }
  }
}

private struct ProviderSettingsView: View {
  @ObservedObject var model: AppModel
  let confirm: (SettingsConfirmation) -> Void
  let showPrivacy: () -> Void
  @State private var showsMapping = false

  var body: some View {
    VStack(spacing: 0) {
      ProviderSettingsRow(
        provider: .opencode,
        status: status(for: .opencode),
        description: "Aggregate tokens and cost from the local session database.",
        source: "~/.local/share/opencode/opencode.db",
        actionTitle: showsMapping ? "Done" : "Configure Mapping",
        action: { showsMapping.toggle() }
      )

      if showsMapping {
        OpenCodeMappingView(model: model)
          .padding(.leading, 40)
          .padding(.bottom, SessionLensSpacing.medium)
      }

      Divider()

      ProviderSettingsRow(
        provider: .claude,
        status: claudeStatus,
        description: "Install a privacy bridge to receive usage and quota metadata.",
        source: "~/.claude/settings.json · explicit opt-in",
        actionTitle: model.claudeBridgeStatus == .installed
          ? "Uninstall Bridge"
          : "Install Bridge",
        action: {
          confirm(
            model.claudeBridgeStatus == .installed
              ? .uninstallBridge
              : .installBridge
          )
        }
      )

      Divider()

      ProviderSettingsRow(
        provider: .codex,
        status: status(for: .codex),
        description: "Exact account usage and rate limits through the local app-server.",
        source: codexQuotaSummary,
        actionTitle: "Refresh",
        action: model.refresh
      )
    }
    .padding(.horizontal, SessionLensSpacing.large)
    .background(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .fill(Color.primary.opacity(0.035))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .stroke(SessionLensPalette.separator.opacity(0.55))
    )

    Button(action: showPrivacy) {
      HStack(alignment: .top, spacing: SessionLensSpacing.medium) {
        Image(systemName: "shield")
          .font(.system(size: 27))
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
          Text(
            "Only aggregate usage metadata is stored. Prompts, source code, credentials, and project paths are never read."
          )
          .foregroundStyle(.primary)
          Text("Learn More")
            .foregroundStyle(.tint)
        }
        Spacer()
      }
      .font(.system(size: 12))
      .padding(SessionLensSpacing.large)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .fill(Color.primary.opacity(0.025))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .stroke(SessionLensPalette.separator.opacity(0.5))
    )
  }

  private var claudeStatus: ProviderSettingsStatus {
    switch model.claudeBridgeStatus {
    case .notInstalled: .neutral("Not installed")
    case .installed: .healthy("Connected")
    case .settingsChanged: .warning("Settings changed")
    }
  }

  private var codexQuotaSummary: String {
    guard
      let quota = model.snapshots[.codex]?.quotaWindows.first(where: {
        $0.durationMinutes == 10_080
      }), let percent = quota.usedPercent
    else {
      return "Local methods: account/usage/read and account/rateLimits/read"
    }
    return "Weekly · \(Int(percent.rounded()))% used"
  }

  private func status(for provider: ProviderID) -> ProviderSettingsStatus {
    guard let health = model.snapshots[provider]?.health else {
      return .neutral("Not detected")
    }
    return switch health {
    case .ready:
      .healthy(provider == .opencode ? "Detected" : "Connected")
    case .stale:
      .warning("Stale")
    case .setupRequired, .toolMissing:
      .neutral("Not installed")
    case .timedOut, .temporarilyUnavailable:
      .warning("Unavailable")
    case .malformedData:
      .warning("Incompatible data")
    }
  }
}

private enum ProviderSettingsStatus {
  case healthy(String)
  case warning(String)
  case neutral(String)

  var text: String {
    switch self {
    case .healthy(let text), .warning(let text), .neutral(let text): text
    }
  }

  var color: Color {
    switch self {
    case .healthy: .green
    case .warning: .orange
    case .neutral: .secondary
    }
  }
}

private struct ProviderSettingsRow: View {
  @Environment(\.colorScheme) private var colorScheme
  let provider: ProviderID
  let status: ProviderSettingsStatus
  let description: String
  let source: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: SessionLensSpacing.medium) {
      Circle()
        .fill(SessionLensPalette.accent(for: provider, scheme: colorScheme))
        .frame(width: 13, height: 13)
        .padding(.top, 5)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
        HStack(spacing: SessionLensSpacing.medium) {
          Text(provider.displayName)
            .font(.system(size: 16, weight: .semibold))
          Text(status.text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(status.color)
        }
        Text(description)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(source)
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: SessionLensSpacing.small)

      Button(actionTitle, action: action)
        .controlSize(.regular)
        .frame(minWidth: 116)
    }
    .padding(.vertical, SessionLensSpacing.large)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(provider.displayName), \(status.text)")
  }
}

private struct OpenCodeMappingView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.small) {
      Text("Map exact OpenCode provider IDs to an account quota source.")
        .font(.caption)
        .foregroundStyle(.secondary)

      mappingPicker(label: "openai", providerID: "openai")
      mappingPicker(label: "anthropic", providerID: "anthropic")
    }
    .padding(SessionLensSpacing.medium)
    .background(
      RoundedRectangle(cornerRadius: SessionLensRadius.segment)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private func mappingPicker(
    label: String,
    providerID: String
  ) -> some View {
    Picker(
      label,
      selection: Binding(
        get: {
          MappingChoice(
            model.settings.quotaProvider(
              forOpenCodeProviderID: providerID
            )
          )
        },
        set: {
          model.setOpenCodeQuotaProvider(
            $0.provider,
            for: providerID
          )
        }
      )
    ) {
      ForEach(MappingChoice.allCases) { choice in
        Text(choice.title).tag(choice)
      }
    }
  }
}

private enum MappingChoice: String, CaseIterable, Identifiable {
  case none
  case claude
  case codex

  init(_ provider: ProviderID?) {
    switch provider {
    case .claude: self = .claude
    case .codex: self = .codex
    default: self = .none
    }
  }

  var id: Self { self }
  var provider: ProviderID? {
    switch self {
    case .none: nil
    case .claude: .claude
    case .codex: .codex
    }
  }

  var title: String {
    switch self {
    case .none: "No quota mapping"
    case .claude: "Claude Code"
    case .codex: "Codex"
    }
  }
}

private struct MenuBarSettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    SettingsSurface {
      Picker(
        "Display",
        selection: Binding(
          get: { model.settings.menuBarDisplayMode },
          set: { mode in
            model.setMenuBarDisplayMode(mode)
          }
        )
      ) {
        ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      HStack {
        Text("Preview")
        Spacer()
        MenuBarLabel(summary: model.menuBarSummary)
          .padding(.horizontal, SessionLensSpacing.medium)
          .padding(.vertical, SessionLensSpacing.small)
          .background(.bar, in: Capsule())
      }

      Divider()

      Text("Provider order")
        .font(.headline)
      ForEach(Array(model.providerOrder.enumerated()), id: \.element) {
        index,
        provider in
        HStack {
          Text(provider.displayName)
          Spacer()
          Button {
            model.moveProvider(provider, by: -1)
          } label: {
            Image(systemName: "chevron.up")
          }
          .disabled(index == 0)
          .accessibilityLabel("Move \(provider.displayName) up")

          Button {
            model.moveProvider(provider, by: 1)
          } label: {
            Image(systemName: "chevron.down")
          }
          .disabled(index == model.providerOrder.count - 1)
          .accessibilityLabel("Move \(provider.displayName) down")
        }
      }
    }
  }
}

private struct NotificationSettingsView: View {
  @ObservedObject var model: AppModel
  @State private var customThreshold = 80

  var body: some View {
    SettingsSurface {
      Toggle(
        "Enable notifications",
        isOn: Binding(
          get: { model.settings.notificationsEnabled },
          set: { enabled in
            Task { await model.setNotificationsEnabled(enabled) }
          }
        )
      )
      Text("Permission is requested only when this setting is enabled.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Divider()

      Text("Quota thresholds")
        .font(.headline)

      ForEach(model.settings.notificationThresholds, id: \.self) { value in
        HStack {
          Label("\(value)% used", systemImage: "bell")
          Spacer()
          Button(role: .destructive) {
            model.setNotificationThreshold(value, enabled: false)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove \(value) percent threshold")
        }
      }

      HStack {
        Stepper(
          "Custom threshold: \(customThreshold)%",
          value: $customThreshold,
          in: 1...99
        )
        Spacer()
        Button("Add") {
          model.setNotificationThreshold(customThreshold, enabled: true)
        }
        .disabled(
          model.settings.notificationThresholds.contains(customThreshold)
        )
      }

      Toggle(
        "Notify when a quota window resets",
        isOn: Binding(
          get: { model.settings.notifyOnReset },
          set: { enabled in
            model.setNotifyOnReset(enabled)
          }
        )
      )
    }
  }
}

private struct PrivacySettingsView: View {
  @ObservedObject var model: AppModel
  let confirmClearHistory: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.medium) {
      SettingsSurface {
        PrivacyAllowlistRow(
          provider: "OpenCode",
          detail: "Read-only aggregate token and cost columns from the local session database."
        )
        Divider()
        PrivacyAllowlistRow(
          provider: "Claude Code",
          detail:
            "Allowlisted cost, context-window, and rate-limit fields supplied to the opt-in status line."
        )
        Divider()
        PrivacyAllowlistRow(
          provider: "Codex",
          detail:
            "Only initialize, account/usage/read, and account/rateLimits/read on the local app-server."
        )
      }

      SettingsSurface {
        Label(
          "No analytics, licensing, cloud sync, or app-owned backend.", systemImage: "network.slash"
        )
        Label(
          "Prompts, source code, credentials, and project paths are never stored.",
          systemImage: "lock.shield")

        LabeledContent("Local storage") {
          Text(storagePath)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Divider()

        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Aggregate history")
              .font(.headline)
            Text("Provider data and app settings are not changed.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Clear History", role: .destructive) {
            confirmClearHistory()
          }
        }
      }
    }
  }

  private var storagePath: String {
    guard let path = model.dataStoreURL?.path else {
      return "In-memory preview store"
    }
    return path.replacingOccurrences(
      of: FileManager.default.homeDirectoryForCurrentUser.path,
      with: "~"
    )
  }
}

private struct PrivacyAllowlistRow: View {
  let provider: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
      Text(provider)
        .font(.headline)
      Text(detail)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct SettingsSurface<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: SessionLensSpacing.medium) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(SessionLensSpacing.large)
    .background(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .fill(Color.primary.opacity(0.035))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SessionLensRadius.surface)
        .stroke(SessionLensPalette.separator.opacity(0.55))
    )
  }
}

extension MenuBarDisplayMode {
  fileprivate var title: String {
    switch self {
    case .urgent: "Urgent"
    case .active: "Active"
    case .icons: "Icons"
    case .minimal: "Minimal"
    }
  }
}
