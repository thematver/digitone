import SwiftUI
import DigitoneCore
import DigitoneDesign

struct SnapshotMetadataEditor: View {
    @ObservedObject var model: StudioModel
    let snapshot: SoundSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var tags: String

    init(model: StudioModel, snapshot: SoundSnapshot) {
        self.model = model
        self.snapshot = snapshot
        _name = State(initialValue: snapshot.name)
        _tags = State(initialValue: snapshot.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Название и теги").font(.system(size: 22, weight: .semibold))
            Text("\(snapshot.machine.title) · \(snapshot.parameters.count) параметров")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text("Название").font(.system(size: 12))
                TextField("Имя снимка", text: $name).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Теги через запятую").font(.system(size: 12))
                TextField("bass, soft, live", text: $tags).textFieldStyle(.roundedBorder)
            }
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") {
                    if model.updateSnapshot(snapshot.id, name: name, tags: tags) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || !model.storageAvailable)
            }
        }.padding(28).frame(idealWidth: 440).background(InstrumentTheme.paper)
            .tint(InstrumentTheme.green)
    }
}
