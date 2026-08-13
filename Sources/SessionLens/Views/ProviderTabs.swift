import SessionLensCore
import SwiftUI

struct ProviderTabs: View {
    @Binding var selection: ProviderID
    let snapshots: [ProviderID: ProviderSnapshot]
    let refresh: () -> Void
    let isRefreshing: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SessionLensSpacing.small) {
            HStack(spacing: 0) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Button {
                        selection = provider
                    } label: {
                        HStack(spacing: SessionLensSpacing.small) {
                            Circle()
                                .fill(statusColor(provider))
                                .frame(width: 9, height: 9)
                            Text(provider == .claude ? "Claude" : provider.displayName)
                                .font(.system(size: 12, weight: selection == provider ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(selection == provider ? accent(provider) : .primary)
                        .background {
                            if selection == provider {
                                RoundedRectangle(cornerRadius: SessionLensRadius.segment)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(provider))

                    if provider != ProviderID.allCases.last {
                        Divider().frame(height: 18)
                    }
                }
            }
            .padding(2)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: SessionLensRadius.segment))

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        reduceMotion ? .linear(duration: 0.1) : .easeInOut(duration: 0.35),
                        value: isRefreshing
                    )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "Refreshing usage" : "Refresh usage")
        }
    }

    private func statusColor(_ provider: ProviderID) -> Color {
        guard let health = snapshots[provider]?.health else {
            return SessionLensPalette.tertiaryText
        }
        switch health {
        case .ready:
            return accent(provider)
        case .stale:
            return .orange
        case .setupRequired, .toolMissing:
            return SessionLensPalette.tertiaryText
        case .malformedData, .timedOut, .temporarilyUnavailable:
            return .red
        }
    }

    private func accent(_ provider: ProviderID) -> Color {
        SessionLensPalette.accent(for: provider, scheme: colorScheme)
    }

    private func accessibilityLabel(_ provider: ProviderID) -> String {
        let state: String
        switch snapshots[provider]?.health {
        case .ready: state = "available"
        case .stale: state = "stale"
        case .setupRequired: state = "setup required"
        case .toolMissing: state = "not installed"
        case .malformedData: state = "data format changed"
        case .timedOut: state = "timed out"
        case .temporarilyUnavailable: state = "temporarily unavailable"
        case nil: state = "no data"
        }
        return "\(provider.displayName), \(state)"
    }
}

struct ProviderHeader: View {
    let snapshot: ProviderSnapshot?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: SessionLensSpacing.small) {
            Circle()
                .fill(accent)
                .frame(width: 11, height: 11)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot?.provider.displayName ?? "SessionLens")
                    .font(.system(size: 16, weight: .semibold))
                Text(freshness)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if snapshot?.health == .stale {
                Label("Stale", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        guard let provider = snapshot?.provider else {
            return SessionLensPalette.tertiaryText
        }
        return SessionLensPalette.accent(for: provider, scheme: colorScheme)
    }

    private var freshness: String {
        guard let snapshot else { return "No usage data yet" }
        let interval = Date().timeIntervalSince(snapshot.observedAt)
        if abs(interval) < 60 { return "Updated just now" }
        return "Updated \(snapshot.observedAt.formatted(.relative(presentation: .named)))"
    }
}
