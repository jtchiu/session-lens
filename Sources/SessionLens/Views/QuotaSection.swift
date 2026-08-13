import SessionLensCore
import SwiftUI

struct QuotaSection: View {
    let snapshot: ProviderSnapshot

    private var featuredWindow: QuotaWindow? {
        snapshot.quotaWindows.first(where: { $0.durationMinutes == 10_080 })
            ?? snapshot.quotaWindows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SessionLensSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(featuredWindow?.label ?? "Quota")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let reset = featuredWindow?.resetsAt {
                    Text("resets \(reset.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let window = featuredWindow, let percent = window.usedPercent {
                HStack(spacing: SessionLensSpacing.medium) {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SessionLensPalette.quotaColor(percent))
                        .contentTransition(.numericText())
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                            Capsule()
                                .fill(SessionLensPalette.quotaColor(percent))
                                .frame(
                                    width: geometry.size.width
                                        * min(1, max(0, percent / 100))
                                )
                        }
                    }
                    .frame(height: 6)
                        .accessibilityLabel("\(window.label) quota")
                        .accessibilityValue("\(Int(percent.rounded())) percent used")
                }
                HStack {
                    Text(provenance(window.provenance))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
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
        .padding(.vertical, SessionLensSpacing.small)
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
