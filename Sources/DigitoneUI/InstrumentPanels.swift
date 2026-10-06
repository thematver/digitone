import SwiftUI
import DigitoneDesign

struct ConnectionPanel: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Подключение").font(.system(size: 26, weight: .medium, design: .rounded)); Spacer(); Button("Готово") { dismiss() } }
                HStack(spacing: 20) {
                    Image(systemName: "laptopcomputer").font(.system(size: 36, weight: .light))
                    Rectangle().fill(model.connected ? InstrumentTheme.green : InstrumentTheme.line).frame(height: 2)
                    Image(systemName: "pianokeys").font(.system(size: 36, weight: .light))
                }.padding(.vertical, 20)
                if let identity = model.identity {
                    Text("\(identity.name) · OS \(identity.version) · \(identity.build)").font(.system(size: 13, weight: .medium, design: .monospaced))
                } else { Text("Подключи Digitone II по USB MIDI.").font(.system(size: 13)).foregroundStyle(InstrumentTheme.secondary) }
                Picker("Вход MIDI", selection: $model.sourceID) {
                    Text("Выбери вход").tag(UInt32(0)); ForEach(model.sources) { Text($0.name).tag($0.id) }
                }.disabled(model.busy || model.connected)
                Picker("Выход MIDI", selection: $model.destinationID) {
                    Text("Выбери выход").tag(UInt32(0)); ForEach(model.destinations) { Text($0.name).tag($0.id) }
                }.disabled(model.busy || model.connected)
                HStack {
                    Button(model.connected ? "Отключить" : "Подключить") {
                        if model.connected { model.disconnect() } else { Task { await model.connect() } }
                    }.buttonStyle(InstrumentButtonStyle(prominent: true)).disabled(model.busy)
                    Button("Обновить") { model.refreshEndpoints() }.buttonStyle(InstrumentButtonStyle()).disabled(model.busy)
                }
                if model.busy { ProgressView(model.busyText).font(.system(size: 12)) }
                if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(InstrumentTheme.record) }
                if let event = model.lastParameterText { Text(event).font(.system(size: 11, design: .monospaced)).foregroundStyle(InstrumentTheme.green) }
                Divider()
                DeviceSetupControls(control: ControlModel.attached(to: model))
                Divider()
                Text("СЕКВЕНСОР ПРИБОРА").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                Text("Выбор аппаратного паттерна и его транспорт. Партия из редактора запускается в разделе «Паттерн».")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                DeviceTransportBar(model: model, compact: false)
            }.padding(28)
        }.frame(minWidth: 320, idealWidth: 520, idealHeight: 640).background(InstrumentTheme.paper).tint(InstrumentTheme.green)
    }
}

struct SaveSoundPanel: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Сохранить звук").font(.system(size: 23, weight: .semibold))
            Text("\(model.machine.title) · \(model.knownCount) известных параметров").font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
            TextField("Название", text: $model.snapshotName).textFieldStyle(.roundedBorder)
            TextField("Теги через запятую", text: $model.snapshotTags).textFieldStyle(.roundedBorder)
            if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(InstrumentTheme.record) }
            Text("Это частичный снимок параметров редактора.").font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("В библиотеку") {
                    let count = model.snapshots.count
                    model.saveSnapshot()
                    if model.snapshots.count > count { dismiss() }
                }.buttonStyle(InstrumentButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(model.snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || !model.storageAvailable)
            }
        }.padding(28).frame(minWidth: 320, idealWidth: 440).background(InstrumentTheme.paper).tint(InstrumentTheme.green)
    }
}
