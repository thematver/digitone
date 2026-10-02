import SwiftUI
import DigitoneUI

@main
struct DigitoneStudioApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Digitone Studio", id: "studio") {
            StudioView()
        }
        .defaultSize(width: 1260, height: 860)
        #else
        WindowGroup {
            StudioView()
        }
        #endif
    }
}
