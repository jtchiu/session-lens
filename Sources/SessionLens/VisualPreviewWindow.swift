#if DEBUG
  import AppKit
  import SwiftUI

  @MainActor
  final class VisualPreviewWindowController {
    static let shared = VisualPreviewWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
      NSApplication.shared.setActivationPolicy(.regular)

      let showsSettings = ProcessInfo.processInfo.arguments.contains(
        "--visual-settings"
      )

      let controller = NSHostingController(
        rootView: AnyView(
          showsSettings
            ? AnyView(SettingsView(model: model))
            : AnyView(PopoverView(model: model))
        )
      )
      let contentSize =
        showsSettings
        ? NSSize(width: 760, height: 560)
        : NSSize(width: 390, height: 640)
      let window = NSWindow(
        contentRect: NSRect(
          origin: .zero,
          size: contentSize
        ),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.title =
        showsSettings
        ? "SessionLens Settings Preview"
        : "SessionLens Visual Preview"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      window.contentViewController = controller
      if ProcessInfo.processInfo.arguments.contains("--visual-light") {
        window.appearance = NSAppearance(named: .aqua)
      } else if ProcessInfo.processInfo.arguments.contains("--visual-dark") {
        window.appearance = NSAppearance(named: .darkAqua)
      }
      window.setContentSize(contentSize)
      window.center()

      self.window = window
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }
#endif
