import Foundation
import Combine
import DigitoneCore
import DigitoneAgent
import DigitoneAudio
import DigitoneDSP
import DigitoneDesign

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var sequence = BeatSequence.empty()
    @Published var laneIndex = 0
    /// Selected notes of the current lane.
    @Published var selection: Set<UUID> = []
    /// Undo/redo snapshots of `sequence`.
    @Published var history = PianoRollHistory()
    /// Piano-roll view state; kept here so it survives switching modes.
    let roll = PianoRollState()
    var clipboard: [SequenceNote] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var loading = false
    @Published var sample: SampleBuffer?
    @Published var sampleName = ""
    @Published var samplePeaks: [WaveformDrawing.PeakPoint] = []
    @Published var slices: [Range<Int>] = []
    @Published var selectedPad = 0
    @Published var loopSample = false
    @Published var pitch = 0.0
    @Published var takes: [URL] = []
    @Published var archives: [SysExBankArchive] = []
    /// Retain sounds from the current agent document for lossless re-export.
    var importedAgentSounds: [AgentSoundDraft] = []
    var agentSoundBaseline: [ControlKey: ControlValue]?
    let audio: StudioAudioEngine?
    private var sampler: SamplerRenderSource?
    private let directory: URL
    private var sequenceStorageAvailable = true

    init(directory supplied: URL? = nil, startAudio: Bool = true) {
        if let supplied {
            directory = supplied
        } else if let override = ProcessInfo.processInfo.environment["DIGITONE_STUDIO_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DigitoneStudio", isDirectory: true)
        }
        audio = startAudio ? StudioAudioEngine() : nil
        let sequenceURL = directory.appendingPathComponent("sequence.json")
        if FileManager.default.fileExists(atPath: sequenceURL.path) {
            do {
                let restored = try JSONDecoder().decode(NoteSequence.self, from: Data(contentsOf: sequenceURL))
                try Self.validateSequence(restored)
                sequence = restored
            } catch {
                sequenceStorageAvailable = false
                self.error = "Не удалось открыть сохранённую партию: \(error.localizedDescription) Исходный файл сохранён."
            }
        }
        let takesDirectory = directory.appendingPathComponent("takes", isDirectory: true)
        takes = ((try? FileManager.default.contentsOfDirectory(at: takesDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        do { archives = try SysExBankStore(directory: directory.appendingPathComponent("banks")).load() }
        catch { self.error = error.localizedDescription }
        audio?.onRecordingFinished = { [weak self] recording in
            guard let self else { return }
            if !self.takes.contains(recording.url) { self.takes.insert(recording.url, at: 0) }
        }
        audio?.onError = { [weak self] in self?.error = $0.localizedDescription }
    }

    var lane: SequenceLane? { sequence.lanes.indices.contains(laneIndex) ? sequence.lanes[laneIndex] : nil }
    /// The single selected note, if exactly one is selected.
    var selectedNote: UUID? {
        get { selection.count == 1 ? selection.first : nil }
        set { selection = newValue.map { [$0] } ?? [] }
    }
    var selected: SequenceNote? { lane?.notes.first { $0.id == selectedNote } }
    var pageCount: Int { max(1, (sequence.length + MusicalTime.ticksPerBar - 1) / MusicalTime.ticksPerBar) }

    func importMIDI(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= MIDIFile.maximumFileSize else { throw WorkspaceError.fileTooLarge }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            var imported = try MIDIFile.read(data, fallbackName: url.deletingPathExtension().lastPathComponent)
            // SMF stores an integer number of microseconds per quarter note.
            // Accept its sub-0.01 BPM rounding at our transport boundaries.
            if imported.tempo < 20, imported.tempo >= 19.99 { imported.tempo = 20 }
            if imported.tempo > 999, imported.tempo <= 999.01 { imported.tempo = 999 }
            try Self.validateSequence(imported)
            replaceSequence(imported)
            error = nil; notice = "MIDI открыт: \(imported.noteCount) нот."
        } catch { self.error = error.localizedDescription }
    }

    func exportMIDI() -> Data? {
        do { try Self.validateSequence(sequence); return try MIDIFile.write(sequence) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func copyPattern(_ pattern: PatternSnapshot) {
        do {
            let copied = pattern.noteSequence()
            try Self.validateSequence(copied)
            replaceSequence(copied)
            notice = "Паттерн открыт как локальная партия."
        } catch { self.error = error.localizedDescription }
    }

    func saveSequence(announce: Bool = true) {
        do {
            guard sequenceStorageAvailable else { throw WorkspaceError.invalidSequence("сохранённая партия повреждена; исходный файл сохранён") }
            try Self.validateSequence(sequence)
            let url = directory.appendingPathComponent("sequence.json")
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try JSONDecoder().decode(NoteSequence.self, from: Data(contentsOf: url))
                try Self.validateSequence(existing)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(sequence).write(to: url, options: .atomic)
            if announce { error = nil; notice = "Паттерн сохранён на этом устройстве." }
        } catch { self.error = error.localizedDescription }
    }

    func editSelected(pitch: Int? = nil, start: Int? = nil, duration: Int? = nil, velocity: Int? = nil) {
        guard let id = selectedNote, sequence.lanes.indices.contains(laneIndex),
              let index = sequence.lanes[laneIndex].notes.firstIndex(where: { $0.id == id }),
              (1...NoteSequence.maximumLength).contains(sequence.length) else { return }
        var note = sequence.lanes[laneIndex].notes[index]
        if let pitch { note.pitch = min(127, max(0, pitch)) }
        if let start {
            note.start = min(sequence.length - 1, max(0, start))
            note.duration = min(note.duration, NoteSequence.maximumLength - note.start)
        }
        if let duration { note.duration = min(max(1, duration), NoteSequence.maximumLength - note.start) }
        if let velocity { note.velocity = min(127, max(1, velocity)) }
        sequence.lanes[laneIndex].notes[index] = note
    }


    func loadAudio(_ url: URL) async {
        guard !loading, audio?.isRecording != true else { return }
        loading = true; defer { loading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 200_000_000 else { throw WorkspaceError.fileTooLarge }
            let buffer = try await Task.detached { try AudioFileIO.load(url) }.value
            guard buffer.frameCount > 0 else { throw WorkspaceError.emptyAudio }
            sample = buffer; sampleName = url.deletingPathExtension().lastPathComponent
            samplePeaks = WaveformPeaks.compute(buffer.channels[0], bins: 300).map { .init(low: $0.min, high: $0.max) }
            equalChop(16); error = nil
        } catch { self.error = error.localizedDescription }
    }

    func chop(_ count: Int, transients: Bool = false) {
        guard let sample, count > 0, !loading, audio?.isRecording != true else { return }
        if transients {
            loading = true
            Task {
                let ranges = await Task.detached {
                    let starts = Array(([0] + TransientDetector().detect(in: sample).filter { $0 > 0 }).prefix(min(count, sample.frameCount)))
                    return TransientDetector.ranges(from: starts, frameCount: sample.frameCount)
                }.value
                slices = ranges; selectedPad = 0; rebuildSampler(); loading = false
            }
        } else {
            equalChop(count)
        }
    }

    private func equalChop(_ count: Int) {
        guard let sample, count > 0, sample.frameCount > 0 else { return }
        let actual = min(count, sample.frameCount)
        slices = (0..<actual).map { ($0 * sample.frameCount / actual)..<(($0 + 1) * sample.frameCount / actual) }
        selectedPad = 0; rebuildSampler()
    }

    func trimPad(start: Int? = nil, end: Int? = nil) {
        guard let sample, slices.indices.contains(selectedPad) else { return }
        let original = slices[selectedPad]
        let lower = min(original.upperBound - 1, max(0, start ?? original.lowerBound))
        let upper = max(lower + 1, min(sample.frameCount, end ?? original.upperBound))
        slices[selectedPad] = lower..<upper
    }

    func rebuildSampler() {
        guard let sample else { return }
        if let sampler { sampler.allNotesOff(); audio?.detach(sampler) }
        let source = SamplerRenderSource(sample: sample, slices: slices, mode: loopSample ? .loop : .oneShot,
                                         pitchSemitones: pitch)
        sampler = source; audio?.attach(source)
    }

    func triggerPad(_ index: Int) async {
        guard let audio, let sampler, slices.indices.contains(index) else { return }
        do {
            try await audio.start(enableInput: false)
            selectedPad = index; sampler.triggerSlice(index)
        } catch { self.error = error.localizedDescription }
    }

    func stopSample() { sampler?.allNotesOff(); audio?.stopPlayback() }

    /// Finalizes a take and releases audio when the window closes or the app
    /// enters the background. A permission prompt or ordinary inactivity does
    /// not call this; starting sound again remains an explicit user action.
    func suspend() {
        sampler?.allNotesOff()
        audio?.stop()
    }

    func toggleRecording() async {
        guard let audio, !loading else { return }
        loading = true; defer { loading = false }
        do {
            if audio.isRecording {
                if let recording = try audio.stopRecording(), !takes.contains(recording.url) { takes.insert(recording.url, at: 0) }
            } else {
                stopSample()
                try await audio.start(enableInput: true)
                let folder = directory.appendingPathComponent("takes", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("Take-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).wav")
                try audio.startRecording(to: url)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func playTake(_ url: URL) async {
        guard let audio, !audio.isRecording else { return }
        do { try await audio.start(enableInput: false); try await audio.play(contentsOf: url) }
        catch { self.error = error.localizedDescription }
    }

    func importBank(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let store = SysExBankStore(directory: directory.appendingPathComponent("banks"))
            let archive = try store.importFile(url)
            archives = try store.load(); notice = "Архив сохранён: \(archive.messageCount) сообщений."; error = nil
        } catch { self.error = error.localizedDescription }
    }

    func bankData(_ archive: SysExBankArchive) -> Data? {
        do { return try SysExBankStore(directory: directory.appendingPathComponent("banks")).data(for: archive) }
        catch { self.error = error.localizedDescription; return nil }
    }

    static func validateSequence(_ sequence: NoteSequence) throws {
        guard (1...NoteSequence.maximumLength).contains(sequence.length) else {
            throw WorkspaceError.invalidSequence("длина вне допустимого диапазона")
        }
        guard sequence.tempo.isFinite, (20...999).contains(sequence.tempo) else {
            throw WorkspaceError.invalidSequence("темп должен быть от 20 до 999 BPM")
        }
        guard (1...255).contains(sequence.timeSignature.beats), [1, 2, 4, 8, 16, 32, 64].contains(sequence.timeSignature.unit) else {
            throw WorkspaceError.invalidSequence("некорректный размер")
        }
        guard sequence.lanes.count <= MIDIFile.maximumLaneCount else { throw WorkspaceError.invalidSequence("слишком много дорожек") }
        var laneIDs = Set<UUID>(), noteIDs = Set<UUID>()
        for lane in sequence.lanes {
            guard laneIDs.insert(lane.id).inserted, (0..<16).contains(lane.channel),
                  lane.track.map({ (0..<16).contains($0) }) ?? true else {
                throw WorkspaceError.invalidSequence("некорректная дорожка или MIDI-канал")
            }
            for note in lane.notes {
                guard noteIDs.count < MIDIFile.maximumNoteCount, noteIDs.insert(note.id).inserted,
                      (0..<128).contains(note.pitch), (1..<128).contains(note.velocity),
                      (0..<sequence.length).contains(note.start), note.duration > 0,
                      note.duration <= NoteSequence.maximumLength - note.start else {
                    throw WorkspaceError.invalidSequence("некорректная нота или повторяющийся идентификатор")
                }
            }
        }
    }
}

enum WorkspaceError: Error, LocalizedError {
    case fileTooLarge, emptyAudio
    case invalidSequence(String)
    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "Файл слишком большой для этой операции."
        case .emptyAudio: "В аудиофайле нет звука."
        case .invalidSequence(let reason): "Некорректная партия: \(reason)."
        }
    }
}
