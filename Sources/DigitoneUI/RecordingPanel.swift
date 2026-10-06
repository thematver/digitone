import SwiftUI
import DigitoneAudio
import DigitoneDSP
import DigitoneDesign

/// Audio capture is a utility of the instrument, available from every workspace.
struct RecordingPanel: View {
    @ObservedObject var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Запись Digitone").font(.system(size: 23, weight: .semibold))
                    Spacer()
                    Button("Готово") { dismiss() }.buttonStyle(InstrumentButtonStyle())
                }
                Text("Запиши исполнение в WAV, прослушай дубль и сохрани файл.")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                if let audio = workspace.audio { capture(audio) }
                else { Text("Аудиодвижок недоступен.").foregroundStyle(InstrumentTheme.secondary) }
                if let error = workspace.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(InstrumentTheme.record)
                }
                HStack {
                    Text("ДУБЛИ · \(workspace.takes.count)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Spacer()
                    if workspace.audio?.isPlaying == true {
                        Button("Стоп") { workspace.audio?.stopPlayback() }.buttonStyle(InstrumentButtonStyle())
                    }
                }
                if workspace.takes.isEmpty {
                    Text("После остановки записи дубль сохранится автоматически.")
                        .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                }
                ForEach(workspace.takes, id: \.self) { url in
                    HStack(spacing: 12) {
                        Button { Task { await workspace.playTake(url) } } label: {
                            Image(systemName: "play.fill").frame(width: 38, height: 38)
                        }.buttonStyle(.plain).accessibilityLabel("Прослушать \(url.lastPathComponent)")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text("WAV · аудиофайл").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up").frame(width: 38, height: 38) }
                            .accessibilityLabel("Экспортировать дубль")
                    }.padding(10).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                        .disabled(workspace.audio?.isRecording == true || workspace.loading)
                }
            }.padding(24)
        }.frame(minWidth: 320, idealWidth: 620, idealHeight: 600)
            .background(InstrumentTheme.paper).foregroundStyle(InstrumentTheme.ink).tint(InstrumentTheme.green)
    }

    private func capture(_ audio: StudioAudioEngine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Аудиовход", selection: Binding(get: { audio.inputDevice?.id ?? "" }, set: { id in
                Task { await workspace.selectAudioInput(audio.devices.inputs.first { $0.id == id }) }
            })) {
                Text("Автоматически · Digitone").tag("")
                ForEach(audio.devices.inputs) { Text($0.name).tag($0.id) }
            }.disabled(audio.isRecording || workspace.loading)
            Text("На приборе: USB CONFIG → USB AUDIO/MIDI. В USB OUT выбери нужный источник.")
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
            TimelineView(.animation(minimumInterval: 0.1, paused: !audio.isRecording)) { _ in
                VStack(spacing: 12) {
                    HStack {
                        Label(audio.isRecording ? "Идёт запись" : "Аудиовход", systemImage: audio.isRecording ? "record.circle.fill" : "waveform")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(audio.isRecording ? InstrumentTheme.record : InstrumentTheme.secondary)
                        Spacer()
                        Text(Self.time(audio.recordedDuration)).font(.system(size: 26, weight: .medium, design: .monospaced))
                    }
                    WaveformDrawing(peaks: audio.isRecording
                                    ? WaveformPeaks.compute(audio.meterSnapshot().scope, bins: 180).map { .init(low: $0.min, high: $0.max) }
                                    : (audio.lastRecording?.peaks ?? []).map { .init(low: $0.min, high: $0.max) },
                                    color: audio.isRecording ? InstrumentTheme.record : InstrumentTheme.green).frame(height: 90)
                }
            }
            Button { Task { await workspace.toggleRecording() } } label: {
                Label(audio.isRecording ? "Остановить и сохранить" : "Начать запись", systemImage: audio.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(InstrumentButtonStyle(prominent: true))
                .disabled(workspace.loading || (!audio.isRecording && audio.inputDevice == nil && !audio.devices.inputs.contains { $0.isDigitone }))
            if audio.inputDevice == nil && !audio.devices.inputs.contains(where: { $0.isDigitone }) {
                Text("Подключи USB-аудио Digitone или выбери аудиоинтерфейс выше.")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.orange)
            }
        }.padding(18).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private static func time(_ value: Double) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
