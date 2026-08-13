import CoreGraphics

public enum SettingsLayoutMetrics {
  public static let sidebarWidth: CGFloat = 196
  public static let sidebarOuterPadding: CGFloat = 8
  public static let brandHorizontalPadding: CGFloat = 8
  public static let brandMarkSize: CGFloat = 32
  public static let brandGap: CGFloat = 8
  public static let brandTitleMinimumWidth: CGFloat = 104

  public static var brandAvailableWidth: CGFloat {
    sidebarWidth
      - 2 * sidebarOuterPadding
      - 2 * brandHorizontalPadding
  }

  public static var brandContentWidth: CGFloat {
    brandMarkSize + brandGap + brandTitleMinimumWidth
  }
}
