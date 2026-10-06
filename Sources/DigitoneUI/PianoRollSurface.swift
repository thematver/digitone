import SwiftUI

/// Compatibility wrapper for the Notes editor.
struct PianoRollSurface: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    let compact: Bool

    var body: some View { PianoRollView(model: model, workspace: workspace, roll: workspace.roll, compact: compact) }
}
