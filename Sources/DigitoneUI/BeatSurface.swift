import SwiftUI
import DigitoneCore
import DigitoneDesign

/// Beat-first editing of the same NoteSequence used by the piano roll and MIDI
/// player. All creation and editing works before a device is connected.
struct BeatSurface: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    let compact: Bool
    @State private var page = 0
    @State private var selectedStep: Int?
    @State private var insertionPitch = 36
    @State private var insertionVelocity = 112
    @State private var insertionDuration = 12
    @State private var editingVelocity = false

    private var pages: Int { max(1, (workspace.sequence.stepCount + 15) / 16) }
    private var visiblePage: Int { min(max(0, page), pages - 1) }
    private var playingStep: Int? {
        guard model.isSequencePlaying, model.sequencePlayhead.isFinite else { return nil }
        return Int(min(Double(NoteSequence.maximumLength), max(0, model.sequencePlayhead))) / MusicalTime.ticksPerStep
    }
    private var selected: SequenceNote? { workspace.selected }
    private var laneColor: Color { PianoRollPalette.lane(workspace.laneIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            transport
            patternTools
            if workspace.sequence.noteCount == 0 { starter }
            grid
            if workspace.lane != nil { inspector }
            hardwarePattern
        }
        .onAppear {
            resetInsertion()
            if let selected {
                selectedStep = selected.start / MusicalTime.ticksPerStep
                page = selected.start / MusicalTime.ticksPerBar
            }
        }
        .onChange(of: workspace.laneIndex) { _, _ in resetInsertion() }
        .onChange(of: workspace.sequence.id) { _, _ in page = 0; selectedStep = nil; resetInsertion() }
        .onChange(of: workspace.selectedNote) { _, _ in
            if let selected { selectedStep = selected.start / MusicalTime.ticksPerStep }
        }
        .onChange(of: workspace.sequence.length) { _, _ in
            page = min(page, pages - 1)
            if let selectedStep, selectedStep >= workspace.sequence.stepCount { self.selectedStep = nil }
        }
        .onChange(of: workspace.sequence) { _, sequence in model.updatePlayingSequence(sequence) }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { model.toggleSequence(workspace.sequence) } label: {
                    Label(model.isSequencePlaying ? "Стоп" : "Играть", systemImage: model.isSequencePlaying ? "stop.fill" : "play.fill")
                        .frame(minWidth: compact ? 66 : 82)
                }
                .buttonStyle(BeatActionStyle(prominent: true))
                .disabled(!model.isSequencePlaying && (!model.connected || model.busy || workspace.sequence.noteCount == 0))
                .help("Играть локальную партию через MIDI на Digitone")
                BeatTempo(tempo: workspace.sequence.tempo) { workspace.setTempo($0) }
                Spacer(minLength: 0)
                Button { workspace.saveSequence() } label: {
                    Label(compact ? "Сохранить" : "Сохранить партию", systemImage: "square.and.arrow.down")
                }.buttonStyle(BeatActionStyle())
            }
            if !model.connected {
                Label("Можно писать бит сейчас. Для прослушивания подключите Digitone.", systemImage: "cable.connector")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Играет с компьютера через MIDI. Звук — с дорожек Digitone.")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
            }
        }
    }

    private var patternTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Имя паттерна", text: Binding(get: { workspace.sequence.name }, set: { workspace.sequence.name = $0 }))
                    .font(.system(size: 17, weight: .semibold)).textFieldStyle(.plain)
                    .accessibilityLabel("Имя локальной партии")
                Spacer(minLength: 0)
                Menu {
                    Button("Пустой паттерн · 4 дорожки") { newPattern() }
                    Divider()
                    ForEach(BeatPreset.allCases, id: \.self) { preset in
                        Button("\(preset.name) · \(Int(preset.tempo)) BPM") { loadPreset(preset) }
                    }
                } label: { Label("Новый", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl("+ Новый")
                    .font(.system(size: 12, weight: .medium)).help("Новая партия; текущую можно вернуть через Отменить")
            }
            HStack(spacing: 8) {
                Text("Шагов").font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                ForEach([16, 32, 64], id: \.self) { steps in
                    Button("\(steps)") { workspace.setBeatLength(steps: steps) }
                        .buttonStyle(BeatChipStyle(active: workspace.sequence.stepCount == steps))
                        .accessibilityLabel("Длина \(steps) шагов")
                        .help("При сокращении лишние ноты убираются; Отменить вернёт их")
                }
                if ![16, 32, 64].contains(workspace.sequence.stepCount) {
                    Text("\(workspace.sequence.stepCount)").font(.system(size: 12, design: .monospaced))
                }
                Spacer(minLength: 0)
                Button { workspace.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(BeatIconStyle()).disabled(!workspace.history.canUndo)
                    .accessibilityLabel("Отменить изменение").help("Отменить")
                    .keyboardShortcut("z", modifiers: .command)
                Button { workspace.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(BeatIconStyle()).disabled(!workspace.history.canRedo)
                    .accessibilityLabel("Повторить изменение").help("Повторить")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Menu {
                    Button("Удвоить партию") { workspace.duplicateBeat() }
                        .disabled(workspace.sequence.length > NoteSequence.maximumLength / 2)
                    Button("Очистить дорожку \(workspace.lane?.name ?? "")") { workspace.clearBeat() }
                    Button("Очистить все шаги") { workspace.clearBeat(allLanes: true) }
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl("•••", chevron: false)
                    .accessibilityLabel("Удвоить или очистить партию")
            }
        }
    }

    private var starter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Начните с ритма или включите шаги вручную")
                .font(.system(size: 13, weight: .medium))
            HStack(spacing: 8) {
                ForEach(BeatPreset.allCases, id: \.self) { preset in
                    Button(preset.name) { loadPreset(preset) }.buttonStyle(BeatActionStyle())
                }
            }
            Text("Kick, Snare, Hat и Bass — роли дорожек. Назначьте им подходящие звуки на Digitone.")
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(InstrumentTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var grid: some View {
        VStack(spacing: 0) {
            gridHeader
            Divider().overlay(InstrumentTheme.line)
            if workspace.sequence.lanes.isEmpty {
                Text("Добавьте дорожку, чтобы поставить первые ноты.")
                    .font(.system(size: 13)).foregroundStyle(InstrumentTheme.secondary).padding(24)
            } else {
                VStack(spacing: compact ? 16 : 7) {
                    ForEach(Array(workspace.sequence.lanes.enumerated()), id: \.element.id) { index, lane in
                        laneRow(index, lane: lane)
                    }
                }.padding(compact ? 12 : 14)
            }
            Divider().overlay(InstrumentTheme.line)
            HStack(spacing: 10) {
                Menu {
                    Button("Пустая дорожка") { workspace.addBeatLane() }
                    ForEach(BeatRole.allCases, id: \.self) { role in
                        Button(role.name) { workspace.addBeatLane(role) }
                    }
                } label: { Label("Дорожка", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl("+ Дорожка")
                    .disabled(workspace.sequence.lanes.count >= WorkspaceModel.laneLimit)
                Spacer(minLength: 0)
                Text(compact ? "Тап — вкл/выкл · удержание — править" : "Нажмите шаг — вкл/выкл · контекстное меню — править")
                    .foregroundStyle(InstrumentTheme.secondary).lineLimit(2)
            }.font(.system(size: 11)).padding(14)
        }
        .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(InstrumentTheme.line, lineWidth: 1))
    }

    private var gridHeader: some View {
        HStack(spacing: 10) {
            Text("\(visiblePage * 16 + 1)–\(min(workspace.sequence.stepCount, (visiblePage + 1) * 16))")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Text("1/16").font(.system(size: 11, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
            Spacer(minLength: 0)
            Button { page = max(0, visiblePage - 1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(BeatIconStyle()).disabled(visiblePage == 0).accessibilityLabel("Предыдущие 16 шагов")
            Text("\(visiblePage + 1) / \(pages)").font(.system(size: 12, design: .monospaced))
            Button { page = min(pages - 1, visiblePage + 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(BeatIconStyle()).disabled(visiblePage + 1 >= pages).accessibilityLabel("Следующие 16 шагов")
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private func laneRow(_ index: Int, lane: SequenceLane) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 7) {
                laneHeader(index, lane: lane)
                VStack(spacing: 4) {
                    stepRow(index, lane: lane, positions: 0..<8)
                    stepRow(index, lane: lane, positions: 8..<16)
                }
            }
        } else {
            HStack(spacing: 14) {
                laneHeader(index, lane: lane).frame(width: 156)
                stepRow(index, lane: lane, positions: 0..<16)
            }
        }
    }

    private func laneHeader(_ index: Int, lane: SequenceLane) -> some View {
        HStack(spacing: 8) {
            Button { selectLane(index) } label: {
                HStack(spacing: 7) {
                    Circle().fill(PianoRollPalette.lane(index)).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lane.name.isEmpty ? "Дорожка \(index + 1)" : lane.name)
                            .font(.system(size: 12, weight: workspace.laneIndex == index ? .semibold : .medium)).lineLimit(1)
                        Text("\(lane.track.map { "T\($0 + 1)" } ?? "MIDI") · MIDI \(lane.channel + 1)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 5).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Править дорожку \(lane.name), MIDI \(lane.channel + 1)")
                .accessibilityAddTraits(workspace.laneIndex == index ? .isSelected : [])
            Button { workspace.toggleBeatMute(index) } label: {
                Image(systemName: lane.isMuted ? "speaker.slash.fill" : "speaker.wave.1")
                    .font(.system(size: 11)).frame(width: compact ? 40 : 28, height: 36)
                    .foregroundStyle(lane.isMuted ? InstrumentTheme.orange : InstrumentTheme.secondary)
            }.buttonStyle(.plain).accessibilityLabel(lane.isMuted ? "Включить \(lane.name)" : "Заглушить \(lane.name)")
        }
    }

    private func stepRow(_ laneIndex: Int, lane: SequenceLane, positions: Range<Int>) -> some View {
        HStack(spacing: compact ? 4 : 3) {
            ForEach(Array(positions), id: \.self) { position in
                let step = visiblePage * 16 + position
                stepButton(laneIndex, lane: lane, step: step)
                    .padding(.leading, position % 4 == 0 && position != positions.lowerBound ? (compact ? 3 : 5) : 0)
            }
        }
    }

    private func stepButton(_ index: Int, lane: SequenceLane, step: Int) -> some View {
        let notes = workspace.sequence.notes(atStep: step, lane: index)
        let active = !notes.isEmpty
        let color = PianoRollPalette.lane(index)
        let editing = workspace.laneIndex == index && selectedStep == step
        let playing = playingStep == step && !lane.isMuted
        return Button { toggle(index, step: step) } label: {
            VStack(spacing: 3) {
                Text("\(step + 1)").font(.system(size: 9, weight: .medium, design: .monospaced))
                    .opacity(active ? 0.85 : 0.6)
                if let note = notes.first {
                    Text(PianoRollNames.name(note.pitch) + (notes.count > 1 ? "+\(notes.count - 1)" : "")).font(.system(size: compact ? 10 : 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Capsule().fill(active ? InstrumentTheme.panel.opacity(0.8) : color)
                        .frame(width: CGFloat(max(4, note.velocity / 6)), height: 3)
                } else {
                    Circle().fill(InstrumentTheme.secondary.opacity(0.2)).frame(width: 4, height: 4)
                    Color.clear.frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity).frame(height: compact ? 44 : 48)
            .foregroundStyle(active ? InstrumentTheme.panel : InstrumentTheme.secondary)
            .background(active ? color.opacity(lane.isMuted ? 0.35 : 1) : (step % 4 == 0 ? InstrumentTheme.line.opacity(0.45) : InstrumentTheme.paper.opacity(0.7)), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(playing ? InstrumentTheme.ink : editing ? color : Color.clear, lineWidth: playing ? 3 : 2))
            .opacity(step < workspace.sequence.stepCount ? 1 : 0.2)
        }
        .buttonStyle(.plain).disabled(step >= workspace.sequence.stepCount)
        .accessibilityLabel("\(lane.name), шаг \(step + 1), \(active ? "включён" : "выключен")\(notes.first.map { ", нота \(PianoRollNames.name($0.pitch)), velocity \($0.velocity)" } ?? "")")
        .accessibilityAction(named: "Править шаг") { edit(index, step: step) }
        .contextMenu {
            Button("Править шаг \(step + 1)") { edit(index, step: step) }
            if active { Button("Выключить шаг") { toggle(index, step: step) } }
            else { Button("Включить шаг") { toggle(index, step: step) } }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(laneColor).frame(width: 7, height: 7)
                Text(selectedStep.map { "Шаг \($0 + 1)" } ?? "Новые шаги")
                    .font(.system(size: 13, weight: .semibold))
                if selected == nil {
                    Text("параметры вставки").font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                }
                Spacer(minLength: 0)
                if let selectedStep {
                    let stepNotes = workspace.sequence.notes(atStep: selectedStep, lane: workspace.laneIndex)
                    if stepNotes.count > 1 {
                        Menu {
                            ForEach(stepNotes) { note in
                                Button("\(PianoRollNames.name(note.pitch)) · velocity \(note.velocity)") { workspace.selectedNote = note.id }
                            }
                        } label: { Text("\(stepNotes.count) нот") }
                            .menuStyle(.borderlessButton).fixedSize().snapshotControl("\(stepNotes.count) нот")
                            .font(.system(size: 11)).accessibilityLabel("Выбрать ноту аккорда для редактирования")
                    } else {
                        Button("Править") { workspace.selectBeatStep(lane: workspace.laneIndex, step: selectedStep) }
                            .font(.system(size: 11)).disabled(stepNotes.isEmpty)
                            .accessibilityLabel("Выбрать ноту для редактирования")
                    }
                }
            }
            if compact {
                VStack(alignment: .leading, spacing: 14) { pitchControl; velocityControl; lengthControl }
            } else {
                HStack(spacing: 24) { pitchControl.frame(maxWidth: .infinity); velocityControl.frame(maxWidth: .infinity); lengthControl.frame(maxWidth: .infinity) }
            }
            Divider().overlay(InstrumentTheme.line)
            laneSettings
        }
        .padding(compact ? 14 : 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(InstrumentTheme.line, lineWidth: 1))
    }

    private var pitchControl: some View {
        Stepper(value: pitchBinding, in: 0...127) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Нота").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                Text("\(PianoRollNames.name(pitchBinding.wrappedValue)) · \(pitchBinding.wrappedValue)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }.accessibilityLabel("Нота шага")
    }

    private var velocityControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Velocity").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                Spacer()
                Text("\(Int(velocityBinding.wrappedValue))").font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            Slider(value: velocityBinding, in: 1...127, step: 1) { editing in
                if editing, selected != nil { workspace.beginGesture() }
                editingVelocity = editing
            }.tint(laneColor).accessibilityLabel("Velocity шага")
        }
    }

    private var lengthControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Длина ноты").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                Menu {
                    ForEach([6, 12, 24, 48, 96, 192, 384], id: \.self) { ticks in
                        Button(lengthName(ticks)) { setDuration(ticks) }
                    }
                } label: { Text(lengthName(selected?.duration ?? insertionDuration)) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .snapshotControl(lengthName(selected?.duration ?? insertionDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            Spacer(minLength: 0)
            if let selected { Button { workspace.deleteNote(selected.id) } label: { Image(systemName: "trash") }.buttonStyle(BeatIconStyle()).accessibilityLabel("Удалить выбранную ноту") }
        }
    }

    private var laneSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                TextField("Имя дорожки", text: Binding(get: { workspace.lane?.name ?? "" }, set: { workspace.setBeatLaneName($0) }))
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .medium)).frame(maxWidth: compact ? 110 : 160, alignment: .leading)
                    .accessibilityLabel("Имя дорожки")
                Menu {
                    ForEach(0..<16, id: \.self) { track in Button("Трек \(track + 1)") { workspace.setBeatLaneTrack(track) } }
                    Button("Свободная MIDI-дорожка") { workspace.setBeatLaneTrack(nil) }
                } label: { Text(workspace.lane?.track.map { "T\($0 + 1)" } ?? "MIDI") }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl(workspace.lane?.track.map { "T\($0 + 1)" } ?? "MIDI")
                    .accessibilityLabel("Назначение дорожки Digitone")
                Menu {
                    ForEach(0..<16, id: \.self) { channel in Button("MIDI \(channel + 1)") { workspace.setLaneChannel(channel) } }
                } label: { Text("MIDI \((workspace.lane?.channel ?? 0) + 1)") }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl("MIDI \((workspace.lane?.channel ?? 0) + 1)")
                    .accessibilityLabel("Канал воспроизведения дорожки")
                Spacer(minLength: 0)
            }.font(.system(size: 11, design: .monospaced))
            HStack(spacing: 12) {
                Menu {
                    ForEach(BeatRole.allCases, id: \.self) { role in
                        Button(role.name) { workspace.fillBeatLane(role) }
                    }
                } label: { Label("Заполнить дорожку", systemImage: "wand.and.stars") }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl("Заполнить дорожку")
                Spacer(minLength: 0)
                Text("\(workspace.lane?.notes.count ?? 0) нот").foregroundStyle(InstrumentTheme.secondary)
            }.font(.system(size: 11))
            Text("MIDI-канал должен совпадать с каналом трека в настройках Digitone. Номер T — метка назначения.")
                .font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hardwarePattern: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Паттерн Digitone").font(.system(size: 12, weight: .medium))
                Menu {
                    ForEach(0..<8, id: \.self) { bank in
                        Menu(String(UnicodeScalar(65 + bank)!)) {
                            ForEach(0..<16, id: \.self) { slot in
                                Button(PatternSnapshot.slotName(bank * 16 + slot)) { model.patternIndex = bank * 16 + slot }
                            }
                        }
                    }
                } label: { Text(PatternSnapshot.slotName(model.patternIndex)) }
                    .menuStyle(.borderlessButton).fixedSize().snapshotControl(PatternSnapshot.slotName(model.patternIndex))
                Spacer(minLength: 0)
                Button("Прочитать") { Task { await model.readPattern() } }
                    .buttonStyle(BeatActionStyle()).disabled(!model.connected || model.busy || model.isSequencePlaying)
            }
            if let pattern = model.pattern {
                Button {
                    model.stopSequence(); workspace.copyPattern(pattern); selectedStep = nil
                } label: { Label("Открыть копию \(PatternSnapshot.slotName(pattern.index)) · \(pattern.notes.count) нот", systemImage: "arrow.down.to.line") }
                    .buttonStyle(BeatActionStyle())
            }
            Text("Партия хранится в Studio. «Прочитать» получает копию с устройства; воспроизведение отправляет ноты по MIDI.")
                .font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12))
    }

    private var pitchBinding: Binding<Int> {
        Binding(get: { selected?.pitch ?? insertionPitch }, set: { value in
            insertionPitch = value
            if let selected { workspace.editBeatNote(selected.id, pitch: value) }
        })
    }

    private var velocityBinding: Binding<Double> {
        Binding(get: { Double(selected?.velocity ?? insertionVelocity) }, set: { value in
            insertionVelocity = Int(value)
            if let selected {
                workspace.editBeatNote(selected.id, velocity: Int(value), recordHistory: !editingVelocity)
            }
        })
    }

    private func setDuration(_ ticks: Int) {
        insertionDuration = ticks
        if let selected { workspace.editBeatNote(selected.id, duration: ticks) }
    }

    private func selectLane(_ index: Int) {
        workspace.selectLane(index)
        selectedStep = nil
        workspace.deselectAll()
    }

    private func resetInsertion() {
        let role = BeatRole.allCases.first { $0.name.lowercased() == workspace.lane?.name.lowercased() }
            ?? BeatRole.allCases[min(3, max(0, workspace.laneIndex))]
        insertionPitch = workspace.lane?.notes.first?.pitch ?? role.pitch
        insertionVelocity = role.velocity
        insertionDuration = role.duration
    }

    private func toggle(_ lane: Int, step: Int) {
        if lane != workspace.laneIndex { workspace.selectLane(lane); resetInsertion() }
        workspace.toggleBeatStep(lane: lane, step: step, pitch: insertionPitch, velocity: insertionVelocity, duration: insertionDuration)
        selectedStep = step
    }

    private func edit(_ lane: Int, step: Int) {
        workspace.selectBeatStep(lane: lane, step: step)
        selectedStep = step
        if let note = selected {
            insertionPitch = note.pitch; insertionVelocity = note.velocity; insertionDuration = note.duration
        }
    }

    private func newPattern() {
        model.stopSequence()
        workspace.replaceSequence(BeatSequence.empty(tempo: workspace.sequence.tempo))
        page = 0; selectedStep = nil; resetInsertion()
    }

    private func loadPreset(_ preset: BeatPreset) {
        model.stopSequence()
        let steps = [16, 32, 64].contains(workspace.sequence.stepCount) ? workspace.sequence.stepCount : 16
        workspace.replaceSequence(BeatSequence.make(preset, steps: steps))
        page = 0; selectedStep = nil; resetInsertion()
    }

    private func lengthName(_ ticks: Int) -> String {
        switch ticks {
        case 6: "1/64"; case 12: "1/32"; case 24: "1/16"; case 48: "1/8"
        case 96: "1/4"; case 192: "1/2"; case 384: "1 такт"
        default: "\(ticks) ticks"
        }
    }
}

private struct BeatActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).frame(minHeight: 40)
            .foregroundStyle(prominent ? InstrumentTheme.panel : InstrumentTheme.ink)
            .background(prominent ? InstrumentTheme.green : InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? Color.clear : InstrumentTheme.line, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

private struct BeatChipStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium, design: .monospaced))
            .frame(width: 38, height: 36)
            .foregroundStyle(active ? InstrumentTheme.panel : InstrumentTheme.ink)
            .background(active ? InstrumentTheme.ink : InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct BeatIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).frame(width: 36, height: 36)
            .foregroundStyle(InstrumentTheme.ink).background(InstrumentTheme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 7))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
    }
}

/// Tempo is a text field so a target BPM can be entered in one action.
private struct BeatTempo: View {
    var tempo: Double
    var change: (Double) -> Void
    var body: some View {
        HStack(spacing: 4) {
            TextField("BPM", value: Binding(get: { tempo }, set: { change($0) }),
                      format: .number.precision(.fractionLength(0)))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 40)
                .accessibilityLabel("Темп в BPM")
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text("BPM").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
        }.padding(.horizontal, 9).frame(height: 40)
            .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(InstrumentTheme.line, lineWidth: 1))
            .snapshotControl("\(Int(tempo)) BPM", chevron: false)
            .accessibilityAdjustableAction { direction in change(tempo + (direction == .increment ? 1 : -1)) }
    }
}
