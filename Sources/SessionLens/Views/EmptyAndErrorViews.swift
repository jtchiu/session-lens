import SessionLensCore
import SwiftUI

struct ProviderStateView: View {
    let snapshot: ProviderSnapshot?
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: SessionLensSpacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
            Button("Refresh", action: refresh)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SessionLensSpacing.xLarge)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch snapshot?.health {
        case .setupRequired:
            snapshot?.provider == .claude ? "Install the Claude bridge" : "Setup required"
        case .toolMissing: "Command not available"
        case .malformedData: "Provider data changed"
        case .timedOut: "Refresh timed out"
        case .temporarilyUnavailable: "Temporarily unavailable"
        case .stale: "Usage data is stale"
        case .ready: "Ready"
        case nil: "No usage data yet"
        }
    }

    private var message: String {
        switch snapshot?.health {
        case .setupRequired where snapshot?.provider == .claude:
            "Install the privacy bridge from Settings to receive aggregate usage and quota metadata."
        case .setupRequired:
            "The local aggregate usage source was not found."
        case .toolMissing:
            snapshot?.diagnostic
                ?? "SessionLens could not find this provider's local command."
        case .malformedData:
            "The provider's aggregate schema no longer matches the tested allowlist."
        case .timedOut:
            "The provider did not respond before the local timeout."
        case .temporarilyUnavailable:
            "The provider could not be refreshed. Other providers remain available."
        case .stale:
            "The last known aggregate remains visible until a refresh succeeds."
        case .ready:
            "Aggregate usage is available."
        case nil:
            "Refresh to read local aggregate usage sources."
        }
    }

    private var symbol: String {
        switch snapshot?.health {
        case .setupRequired, .toolMissing: "externaldrive.badge.questionmark"
        case .malformedData, .timedOut, .temporarilyUnavailable, .stale:
            "exclamationmark.triangle"
        case .ready: "checkmark.circle"
        case nil: "chart.xyaxis.line"
        }
    }

    private var symbolColor: Color {
        switch snapshot?.health {
        case .malformedData, .timedOut, .temporarilyUnavailable: .red
        case .stale: .orange
        default: .secondary
        }
    }
}
