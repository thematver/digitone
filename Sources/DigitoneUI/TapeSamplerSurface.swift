import SwiftUI
import DigitoneAudio
import DigitoneDSP
import DigitoneDesign

struct TapeSurface: View {
    @ObservedObject var workspace: WorkspaceModel
    let openAudio: () -> Void
    let sampleTake: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstrumentPanel {
                VStack(spacing: 24) {
                    TimelineView(.animation(minimumInterval: 0.1, paused: workspace.audio?.isRecording != true)) { _ in
                        let recording = workspace.audio?.isRecording == true
                        let snapshot = workspace.audio?.meterSnapshot() ?? .empty
                        VStack(spacing: 24) {
                            HStack(spacing: 24) {
                                reel(recording: recording)
                                VStack(spacing: 8) {
                                    Text(recording ? "ЗАПИСЬ" : "ГОТОВ К ЗАПИСИ").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                                        .foregroundStyle(recording ? InstrumentTheme.record : InstrumentTheme.secondary)
                                    Text(time(workspace.audio?.recordedDuration ?? 0)).font(.system(size: 36, weight: .light, design: .monospaced))
                                }.frame(maxWidth: .infinity)
                                reel(recording: recording)
                            }
                            WaveformDrawing(peaks: recording ? WaveformPeaks.compute(snapshot.scope, bins: 200).map { .init(low: $0.min, high: $0.max) } : lastPeaks,
                                            color: recording ? InstrumentTheme.record : InstrumentTheme.green).frame(height: 110)
                            HStack(spacing: 12) {
                                Button { Task { await workspace.toggleRecording() } } label: {
                                    Label(recording ? "Завершить" : "Записать", systemImage: recording ? "stop.fill" : "record.circle")
                                        .font(.system(size: 13, weight: .medium)).padding(.horizontal, 22).padding(.vertical, 13)
                                        .background(InstrumentTheme.record, in: Capsule()).foregroundStyle(.white)
                                }.buttonStyle(.plain).disabled(workspace.loading)
                                if workspace.loading { ProgressView().controlSize(.small) }
                                Button(action: openAudio) { Image(systemName: "folder").frame(width: 42, height: 42) }.buttonStyle(.plain).disabled(recording || workspace.loading)
                                    .accessibilityLabel("Открыть аудиофайл")
                            }
                        }
                    }
                    if let audio = workspace.audio {
                        audioInput(audio)
                        Text("Записывается выбранный вход. Настрой USB OUT на Digitone для нужного источника.")
                            .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            if !workspace.takes.isEmpty {
                Text("ДУБЛИ").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(InstrumentTheme.secondary)
                ForEach(Array(workspace.takes.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 16) {
                        Button { Task { await workspace.playTake(url) } } label: { Image(systemName: "play.fill").frame(width: 38, height: 38).background(InstrumentTheme.panel, in: Circle()) }.buttonStyle(.plain)
                        Text("Дубль \(workspace.takes.count - index)").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button { sampleTake(url) } label: { Label("Нарезать", systemImage: "scissors") }.buttonStyle(.plain).font(.system(size: 12))
                    }.disabled(workspace.audio?.isRecording == true || workspace.loading)
                }
                Button("Остановить воспроизведение") { workspace.audio?.stopPlayback() }.buttonStyle(.plain).font(.system(size: 12))
            } else {
                Text("Первый дубль появится здесь. Он сохраняется сразу после записи.").font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
            }
            if workspace.sample != nil {
                Button("Прослушать открытое аудио") {
                    Task {
                        guard let audio = workspace.audio, let sample = workspace.sample else { return }
                        do { try await audio.start(enableInput: false); try audio.play(sample) }
                        catch { workspace.error = error.localizedDescription }
                    }
                }.buttonStyle(InstrumentButtonStyle()).disabled(workspace.audio?.isRecording == true)
            }
        }
    }

    private var lastPeaks: [WaveformDrawing.PeakPoint] {
        if let recording = workspace.audio?.lastRecording { return recording.peaks.map { .init(low: $0.min, high: $0.max) } }
        return workspace.samplePeaks
    }

    private func audioInput(_ audio: StudioAudioEngine) -> some View {
        VStack(spacing: 10) {
            Picker("Вход", selection: Binding(get: { audio.inputDevice?.id ?? "" }, set: { id in
                do { try audio.selectInput(audio.devices.inputs.first { $0.id == id }) } catch { workspace.error = error.localizedDescription }
            })) {
                Text("Автоматически").tag("")
                ForEach(audio.devices.inputs) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).disabled(audio.isRecording)
            Picker("Выход", selection: Binding(get: { audio.outputDevice?.id ?? "" }, set: { id in
                do { try audio.selectOutput(audio.devices.outputs.first { $0.id == id }) } catch { workspace.error = error.localizedDescription }
            })) {
                Text("Системный выход").tag("")
                ForEach(audio.devices.outputs) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).disabled(audio.isRecording)
        }.font(.system(size: 12))
    }

    private func reel(recording: Bool) -> some View {
        ZStack {
            Circle().stroke(InstrumentTheme.line, lineWidth: 1)
            Circle().stroke(InstrumentTheme.ink.opacity(0.15), lineWidth: 12).padding(10)
            ForEach(0..<3) { index in Capsule().fill(InstrumentTheme.panel).frame(width: 10, height: 25).offset(y: -17).rotationEffect(.degrees(Double(index) * 120)) }
            Circle().fill(recording ? InstrumentTheme.record : InstrumentTheme.ink).frame(width: 8, height: 8)
        }.frame(width: 72, height: 72)
    }

    private func time(_ seconds: Double) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct SamplerSurface: View {
    @ObservedObject var workspace: WorkspaceModel
    var compact: Bool
    let openAudio: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InstrumentPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workspace.sampleName.isEmpty ? "Начни с одного звука" : workspace.sampleName).font(.system(size: 16, weight: .medium))
                            if let sample = workspace.sample { Text("\(sample.duration, specifier: "%.1f") сек · \(workspace.slices.count) срезов").font(.system(size: 11, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary) }
                        }
                        Spacer()
                        Button(action: openAudio) { Image(systemName: "folder").frame(width: 36, height: 36) }.buttonStyle(.plain).disabled(workspace.loading || workspace.audio?.isRecording == true).accessibilityLabel("Загрузить сэмпл")
                    }
                    WaveformDrawing(peaks: workspace.samplePeaks, cuts: workspace.slices.dropFirst().map { Double($0.lowerBound) / Double(max(1, workspace.sample?.frameCount ?? 1)) }).frame(height: compact ? 95 : 120)
                    HStack(spacing: 12) {
                        Menu {
                            ForEach([4, 8, 16], id: \.self) { count in Button("\(count) равных срезов") { workspace.chop(count) } }
                            Button("По транзиентам") { workspace.chop(16, transients: true) }
                        } label: { Label("Нарезать", systemImage: "scissors") }.disabled(workspace.sample == nil || workspace.loading || workspace.audio?.isRecording == true).snapshotControl("Нарезать")
                        Spacer()
                        Button("Стоп") { workspace.stopSample() }.disabled(workspace.sample == nil)
                    }.font(.system(size: 12)).buttonStyle(.plain)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 8 : 12), count: 4), spacing: compact ? 8 : 12) {
                ForEach(0..<16) { index in
                    Button { Task { await workspace.triggerPad(index) } } label: {
                        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                            HStack { Text(String(format: "%02d", index + 1)).font(.system(size: 12, design: .monospaced)); Spacer(); Circle().fill(workspace.slices.indices.contains(index) ? InstrumentTheme.green : InstrumentTheme.line).frame(width: 4, height: 4) }
                            if workspace.slices.indices.contains(index) {
                                let range = workspace.slices[index]
                                Text("\(Double(range.count) / max(1, workspace.sample?.sampleRate ?? 1), specifier: "%.2f")s").font(.system(size: 10, design: .monospaced))
                            } else { Text("—").font(.system(size: 10)) }
                        }.padding(compact ? 10 : 14).frame(maxWidth: .infinity, alignment: .leading).frame(height: compact ? 61 : 72)
                            .background(index == workspace.selectedPad && workspace.sample != nil ? InstrumentTheme.green : InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 15))
                            .foregroundStyle(index == workspace.selectedPad && workspace.sample != nil ? InstrumentTheme.panel : InstrumentTheme.secondary)
                    }.buttonStyle(.plain).disabled(!workspace.slices.indices.contains(index) || workspace.loading || workspace.audio?.isRecording == true)
                        .accessibilityLabel("Срез \(index + 1)")
                }
            }
            if let sample = workspace.sample, workspace.slices.indices.contains(workspace.selectedPad) {
                InstrumentPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("СРЕЗ \(workspace.selectedPad + 1)").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                        Stepper("Высота \(workspace.pitch, specifier: "%+.0f")", value: $workspace.pitch, in: -24...24)
                            .onChange(of: workspace.pitch) { workspace.rebuildSampler() }
                            .snapshotControl("Высота \(Int(workspace.pitch))", chevron: false)
                        Toggle("Петля", isOn: $workspace.loopSample).onChange(of: workspace.loopSample) { workspace.rebuildSampler() }.snapshotControl(workspace.loopSample ? "● Петля" : "○ Петля", chevron: false)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Начало").foregroundStyle(InstrumentTheme.secondary)
                            Slider(value: Binding(get: { Double(workspace.slices[workspace.selectedPad].lowerBound) }, set: { workspace.trimPad(start: Int($0)) }), in: 0...Double(max(1, sample.frameCount - 1)), onEditingChanged: { editing in if !editing { workspace.rebuildSampler() } })
                                .snapshotControl("● ─────────────────", chevron: false)
                            Text("Конец").foregroundStyle(InstrumentTheme.secondary)
                            Slider(value: Binding(get: { Double(workspace.slices[workspace.selectedPad].upperBound) }, set: { workspace.trimPad(end: Int($0)) }), in: 1...Double(max(2, sample.frameCount)), onEditingChanged: { editing in if !editing { workspace.rebuildSampler() } })
                                .snapshotControl("──────────────── ●", chevron: false)
                        }
                    }.font(.system(size: 12))
                }
            } else {
                Text("Открой аудиофайл или отправь сюда дубль из «Ленты». Сэмплер звучит в приложении.").font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
            }
        }
    }
}
