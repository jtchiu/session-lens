#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class VisualPreviewWindowController {
    static let shared = VisualPreviewWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        NSApplication.shared.setActivationPolicy(.regular)

        let controller = NSHostingController(
            rootView: PopoverView(model: model)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SessionLens Visual Preview"
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
        window.setContentSize(NSSize(width: 390, height: 640))
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif
