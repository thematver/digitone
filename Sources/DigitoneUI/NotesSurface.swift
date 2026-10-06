import SwiftUI
import DigitoneCore
import DigitoneDesign

/// Step editing and piano roll share one sequence, transport and undo history.
struct NotesSurface: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    var compact: Bool
    @Binding private var editor: Editor

    enum Editor: String, CaseIterable { case steps = "Шаги", pianoRoll = "Ноты" }

    init(model: StudioModel, workspace: WorkspaceModel, compact: Bool, editor: Binding<Editor>) {
        _model = ObservedObject(wrappedValue: model)
        _workspace = ObservedObject(wrappedValue: workspace)
        self.compact = compact
        _editor = editor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Picker("Редактор партии", selection: $editor) {
                    ForEach(Editor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: compact ? 190 : 220)
                    .snapshotControl(editor == .steps ? "▦ Шаги  /  Ноты" : "Шаги  /  ♫ Ноты", chevron: false)
                Spacer(minLength: 0)
                if !compact {
                    Text("\(workspace.sequence.lanes.count) дорожки · \(workspace.sequence.noteCount) нот")
                        .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                }
            }
            if editor == .steps {
                BeatSurface(model: model, workspace: workspace, compact: compact)
            } else {
                PianoRollView(model: model, workspace: workspace, roll: workspace.roll, compact: compact)
            }
        }
    }
}

/// Piano-roll states rendered by DigitoneSnapshots: empty, a melody with a
/// selection, recording, and keys lit while playing.
enum NotesSurfaceSnapshots {
    @MainActor static func scenes() -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        for device in [SnapshotScene.Device.mac, .phone] {
            for scheme in [ColorScheme.light, .dark] {
                for state in State.allCases {
                    let (model, workspace) = make(state)
                    scenes.append(SnapshotScene("Ноты-\(state.rawValue)", device: device, colorScheme: scheme) {
                        StudioView(model: model, workspace: workspace, mode: .notes,
                                   notesEditor: state == .empty || state == .beat ? .steps : .pianoRoll)
                    })
                }
            }
        }
        return scenes
    }

    enum State: String, CaseIterable { case empty = "пусто", beat = "бит", melody = "мелодия", recording = "запись", playing = "игра" }

    @MainActor static func make(_ state: State) -> (StudioModel, WorkspaceModel) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-preview-unwritten-\(UUID())")
        let model = StudioModel(directory: directory, startMIDI: false)
        let workspace = WorkspaceModel(directory: directory, startAudio: false)
        guard state != .empty else { return (model, workspace) }
        if state == .beat {
            workspace.sequence = BeatSequence.make(.house, steps: 32)
            return (model, workspace)
        }
        var sequence = NoteSequence(name: "Sunday sketch", tempo: 112, length: MusicalTime.ticksPerBar * 2, lanes: [
            SequenceLane(name: "Bells", track: 0, channel: 0, notes: melody()),
            SequenceLane(name: "Bass", track: 1, channel: 1, notes: [
                SequenceNote(pitch: 45, velocity: 96, start: 0, duration: 168), SequenceNote(pitch: 41, velocity: 90, start: 192, duration: 168),
                SequenceNote(pitch: 43, velocity: 92, start: 384, duration: 168), SequenceNote(pitch: 48, velocity: 104, start: 576, duration: 168)
            ]),
            SequenceLane(name: "Pad", track: 2, channel: 2, notes: [
                SequenceNote(pitch: 64, velocity: 60, start: 0, duration: 384), SequenceNote(pitch: 69, velocity: 60, start: 0, duration: 384),
                SequenceNote(pitch: 65, velocity: 58, start: 384, duration: 384), SequenceNote(pitch: 72, velocity: 58, start: 384, duration: 384)
            ]),
            SequenceLane(name: "Perc", track: 3, channel: 3, notes: (0..<8).map { SequenceNote(pitch: 38, velocity: 70 + $0 * 6, start: $0 * 96, duration: 24) })
        ])
        sequence.lanes[0].notes.sort { $0.start < $1.start }
        workspace.sequence = sequence
        let notes = workspace.sequence.lanes[0].notes
        switch state {
        case .melody:
            workspace.selection = Set(notes.filter { (288..<480).contains($0.start) }.map(\.id))
            workspace.roll.step.reset(to: 288)
        case .recording:
            workspace.roll.isRecording = true
            workspace.roll.demoPlayhead = 610
            workspace.roll.recorder.sync(playhead: 610, at: 0, bpm: 112, length: workspace.sequence.length)
            workspace.roll.recorder.noteOn(pitch: 74, velocity: 110, at: 0)
            workspace.roll.pending = workspace.roll.recorder.pending
            workspace.roll.pendingLane[74] = 0
            workspace.roll.pending[74]?.tick = 528
        case .playing:
            workspace.roll.demoPlayhead = 300
            workspace.roll.incoming = [55]
            workspace.roll.pointerPitch = 79
        case .empty, .beat:
            break
        }
        return (model, workspace)
    }

    private static func melody() -> [SequenceNote] {
        let phrase: [(Int, Int, Int, Int)] = [
            (69, 0, 48, 104), (72, 48, 24, 82), (76, 72, 72, 118), (74, 144, 24, 70), (72, 168, 48, 96),
            (69, 240, 24, 64), (67, 264, 24, 76), (69, 288, 96, 112), (64, 384, 48, 88), (67, 432, 24, 72),
            (69, 456, 48, 100), (72, 528, 24, 84), (71, 552, 24, 60), (69, 576, 96, 120), (60, 576, 96, 52), (64, 672, 72, 90)
        ]
        return phrase.map { SequenceNote(pitch: $0.0, velocity: $0.3, start: $0.1, duration: $0.2) }
    }
}
