import SessionLensCore
import SwiftUI

struct SpendSummaryView: View {
  let summary: SpendSummary
  let providerOrder: [ProviderID]

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Spend & effectiveness")
            .font(.system(size: 13, weight: .semibold))
          Text(pricingStatus)
            .font(.system(size: 9))
            .foregroundStyle(pricingStatusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityLabel(pricingStatus)
        }
        Spacer()
        Text("Retained (summary.retentionDays)d")
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, SessionLensSpacing.xSmall)

      headerRow
      Divider()

      ForEach(rows, id: \.provider) { row in
        providerRow(row)
        Divider()
      }

      combinedRow
    }
    .font(.system(size: 10))
    .accessibilityElement(children: .contain)
  }

  private var headerRow: some View {
    HStack(spacing: SessionLensSpacing.xSmall) {
      Text("Provider")
        .frame(maxWidth: .infinity, alignment: .leading)
      periodHeader("This week")
      periodHeader("This month")
      periodHeader("Total")
    }
    .foregroundStyle(.secondary)
    .font(.system(size: 9))
    .padding(.bottom, SessionLensSpacing.xSmall)
  }

  private var rows: [ProviderSpendSummary] {
    let order = providerOrder.isEmpty ? ProviderID.allCases : providerOrder
    return order.map { provider in
      summary.providers[provider]
        ?? ProviderSpendSummary(
          provider: provider,
          periods: .unavailable
        )
    }
  }

  private func providerRow(_ row: ProviderSpendSummary) -> some View {
    let apiEquivalent = summary.apiEquivalent.providers[row.provider] ?? .unavailable
    return HStack(spacing: SessionLensSpacing.xSmall) {
      providerLabel(row.provider)
      spendCell(
        row.provider.displayName,
        period: "This week",
        value: row.week,
        apiEquivalent: apiEquivalent.week
      )
      spendCell(
        row.provider.displayName,
        period: "This month",
        value: row.month,
        apiEquivalent: apiEquivalent.month
      )
      spendCell(
        row.provider.displayName,
        period: "Total retained",
        value: row.retained,
        apiEquivalent: apiEquivalent.retained
      )
    }
    .frame(minHeight: 57)
  }

  private var combinedRow: some View {
    let apiEquivalent = summary.apiEquivalent.combined
    return HStack(spacing: SessionLensSpacing.xSmall) {
      providerLabel("Combined", color: .primary)
      spendCell(
        "Combined",
        period: "This week",
        value: summary.combined.week,
        apiEquivalent: apiEquivalent.week
      )
      spendCell(
        "Combined",
        period: "This month",
        value: summary.combined.month,
        apiEquivalent: apiEquivalent.month
      )
      spendCell(
        "Combined",
        period: "Total retained",
        value: summary.combined.retained,
        apiEquivalent: apiEquivalent.retained
      )
    }
    .font(.system(size: 10, weight: .semibold))
    .frame(minHeight: 57)
  }

  private func providerLabel(
    _ provider: ProviderID,
    color: Color? = nil
  ) -> some View {
    HStack(spacing: SessionLensSpacing.xSmall) {
      Circle()
        .fill(SessionLensPalette.accent(for: provider, scheme: colorScheme))
        .frame(width: 6, height: 6)
      Text(provider.displayName)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(color ?? .primary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func providerLabel(
    _ name: String,
    color: Color? = nil
  ) -> some View {
    Text(name)
      .lineLimit(1)
      .foregroundStyle(color ?? .primary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func periodHeader(_ title: String) -> some View {
    Text(title)
      .frame(width: 76, alignment: .trailing)
  }

  private func spendCell(
    _ provider: String,
    period: String,
    value: SpendValue,
    apiEquivalent: ApiEquivalentValue
  ) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(SpendFormatting.costText(value))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .monospacedDigit()
      Text(SpendFormatting.apiEquivalentText(apiEquivalent))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .monospacedDigit()
      Text(tokenLineText(value: value))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .monospacedDigit()
    }
    .frame(width: 76, alignment: .trailing)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      SpendFormatting.comparisonAccessibilityLabel(
        provider: provider,
        period: period,
        actual: value,
        apiEquivalent: apiEquivalent
      )
    )
  }

  private func tokenLineText(
    value: SpendValue
  ) -> String {
    let tokenText = SpendFormatting.tokenText(value.tokens)
    let efficiency = SpendFormatting.efficiencyText(value)
    guard efficiency != "—" else { return tokenText }
    return "\(tokenText) · \(efficiency)"
  }

  private var pricingStatus: String {
    let state = summary.apiEquivalent.catalogState
    let source = switch state.source {
    case .live: "Live pricing"
    case .cached: "Cached pricing"
    case .unavailable: "Pricing unavailable"
    }
    guard let ratesAsOf = state.ratesAsOf else { return source }
    return "\(source) · Rates as of \(ratesAsOf.formatted(date: .abbreviated, time: .omitted))"
  }

  private var pricingStatusColor: Color {
    switch summary.apiEquivalent.catalogState.source {
    case .live: return .secondary
    case .cached: return .orange
    case .unavailable: return .secondary
    }
  }
}
