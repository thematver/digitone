import SwiftUI
import DigitoneUI

@main
struct DigitoneStudioApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Digitone Studio", id: "studio") {
            StudioView()
        }
        .defaultSize(width: 1160, height: 820)
        .windowStyle(.hiddenTitleBar)
        #else
        WindowGroup("Digitone Studio") {
            StudioView()
        }
        #endif
    }
}
