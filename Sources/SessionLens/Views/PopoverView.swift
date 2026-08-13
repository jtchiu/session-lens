import SessionLensCore
import SwiftUI

struct PopoverView: View {
  @ObservedObject var model: AppModel
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(spacing: 0) {
      brandRow
        .padding(.horizontal, SessionLensSpacing.large)
        .padding(.top, SessionLensSpacing.medium)
        .padding(.bottom, SessionLensSpacing.small)

      ProviderTabs(
        selection: Binding(
          get: { model.selectedProvider },
          set: { model.selectProvider($0) }
        ),
        snapshots: model.snapshots,
        refresh: model.refresh,
        isRefreshing: model.isRefreshing
      )
      .padding(.horizontal, SessionLensSpacing.large)

      ProviderHeader(snapshot: model.selectedSnapshot)
        .padding(.horizontal, SessionLensSpacing.large)
        .padding(.vertical, SessionLensSpacing.small)
        .sessionLensHairline()

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      PopoverFooter(
        lastUpdated: model.selectedSnapshot?.observedAt,
        openSettings: showSettings,
        quit: model.quit
      )
    }
    .frame(width: 390, height: 640)
    .background(reduceTransparency ? SessionLensPalette.window : Color.clear)
    .onAppear {
      model.start()
      model.popoverDidOpen()
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

  private func showSettings() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()
  }

  private var brandRow: some View {
    HStack(spacing: SessionLensSpacing.small) {
      SessionLensMark(size: 25)
      Text("SessionLens")
        .font(.system(size: 19, weight: .bold, design: .rounded))
      Spacer()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("SessionLens usage monitor")
  }

  @ViewBuilder
  private var content: some View {
    if let snapshot = model.selectedSnapshot,
      snapshot.health == .ready || snapshot.health == .stale
    {
      ScrollView {
        VStack(spacing: SessionLensSpacing.small) {
          QuotaSection(snapshot: snapshot)
          Divider()
          UsageRateChart(
            points: model.quotaHistory[snapshot.provider] ?? [],
            provider: snapshot.provider
          )
          Divider()
          DailyUsageChart(
            snapshot: snapshot,
            range: Binding(
              get: { model.chartRange },
              set: { model.setChartRange($0) }
            )
          )
          Divider()
          TokenSummaryView(snapshot: snapshot)
        }
        .padding(.horizontal, SessionLensSpacing.large)
        .padding(.vertical, SessionLensSpacing.xSmall)
      }
      .scrollIndicators(.hidden)
    } else {
      ProviderStateView(
        snapshot: model.selectedSnapshot,
        refresh: model.refresh
      )
    }
  }
}

struct PopoverFooter: View {
  let lastUpdated: Date?
  let openSettings: () -> Void
  let quit: () -> Void

  var body: some View {
    HStack(spacing: SessionLensSpacing.small) {
      Text(freshness)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
      Button(action: openSettings) {
        Label("Settings", systemImage: "gearshape")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      Divider().frame(height: 18)
      Button("Quit", action: quit)
        .buttonStyle(.plain)
        .keyboardShortcut("q")
        .accessibilityLabel("Quit SessionLens")
    }
    .frame(minHeight: 36)
    .padding(.horizontal, SessionLensSpacing.large)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
  }

  private var freshness: String {
    guard let lastUpdated else { return "Not updated yet" }
    if abs(Date().timeIntervalSince(lastUpdated)) < 60 {
      return "Updated just now"
    }
    return "Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
  }
}

struct MenuBarLabel: View {
  let summary: MenuBarSummary

  var body: some View {
    HStack(spacing: 4) {
      SessionLensMark(size: 15, colorful: false)
      if !summary.text.isEmpty {
        Text(summary.text)
          .monospacedDigit()
      }
      ForEach(summary.indicators, id: \.provider) { indicator in
        Circle()
          .fill(indicatorColor(indicator.health))
          .frame(width: 5, height: 5)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary.accessibilityLabel)
  }

  private func indicatorColor(_ health: ProviderHealth?) -> Color {
    switch health {
    case .ready: .primary
    case .stale: .orange
    case .malformedData, .timedOut, .temporarilyUnavailable: .red
    default: .secondary.opacity(0.55)
    }
  }
}
