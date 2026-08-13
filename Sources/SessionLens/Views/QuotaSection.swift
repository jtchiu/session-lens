import SessionLensCore
import SwiftUI

struct QuotaSection: View {
    let snapshot: ProviderSnapshot

    private var windows: [QuotaWindow] {
        snapshot.quotaWindows.sorted { left, right in
            let leftDuration = left.durationMinutes ?? Int.max
            let rightDuration = right.durationMinutes ?? Int.max
            return leftDuration < rightDuration
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionLensSpacing.small) {
            if windows.isEmpty {
                QuotaRow(window: nil)
            } else {
                ForEach(windows) { window in
                    QuotaRow(window: window)
                    if window.id != windows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, SessionLensSpacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quota windows for " + snapshot.provider.displayName)
    }
}

private struct QuotaRow: View {
    let window: QuotaWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: SessionLensSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(window?.label ?? "Quota")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let reset = window?.resetsAt {
                    Text("resets \(reset.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let window,
                let usedPercent = window.usedPercent,
                let remainingPercent = window.remainingPercent
            {
                HStack(spacing: SessionLensSpacing.medium) {
                    Text(String(Int(remainingPercent.rounded())) + "%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SessionLensPalette.quotaColor(usedPercent))
                        .contentTransition(.numericText())
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(SessionLensPalette.quotaColor(usedPercent))
                                .frame(
                                    width: geometry.size.width
                                        * min(1, max(0, remainingPercent / 100))
                                )
                        }
                    }
                    .frame(height: 6)
                    .accessibilityLabel(window.label + " quota")
                    .accessibilityValue(
                        String(Int(remainingPercent.rounded())) + " percent remaining"
                    )
                }
                HStack(spacing: SessionLensSpacing.xSmall) {
                    Image(systemName: usedPercent > 0 ? "arrow.down.right" : "checkmark")
                        .accessibilityHidden(true)
                    Text(remainingPercent > 0 ? "Remaining" : "Depleted")
                    Spacer()
                    Text(provenance(window.provenance))
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: SessionLensSpacing.medium) {
                    Text("—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Quota unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func provenance(_ value: MetricProvenance) -> String {
        switch value {
        case .exactProvider: "Exact provider quota"
        case .localBudget: "Local budget"
        case .estimated: "Estimated"
        case .stale: "Stale value"
        case .exactLocalAggregate: "Local aggregate"
        case .unavailable: "Unavailable"
        }
    }
}
