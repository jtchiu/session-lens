import SwiftUI

@main
@MainActor
struct SessionLensApp: App {
    @StateObject private var model: AppModel

    init() {
        let visualFixtureMode = ProcessInfo.processInfo.arguments.contains(
            "--visual-fixtures"
        )
        let selectedModel: AppModel = visualFixtureMode
            ? .visualFixtures()
            : .live()
        _model = StateObject(
            wrappedValue: selectedModel
        )
#if DEBUG
        if visualFixtureMode {
            DispatchQueue.main.async {
                VisualPreviewWindowController.shared.show(model: selectedModel)
            }
        }
#endif
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(summary: model.menuBarSummary)
        }
        .menuBarExtraStyle(.window)
    }
}
