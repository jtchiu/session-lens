import Testing

@testable import SessionLensCore

@Suite
struct SettingsLayoutMetricsTests {
  @Test
  func brandContentFitsTheFixedSidebarWithoutWrapping() {
    #expect(
      SettingsLayoutMetrics.brandContentWidth
        <= SettingsLayoutMetrics.brandAvailableWidth
    )
    #expect(SettingsLayoutMetrics.sidebarWidth == 196)
  }
}
