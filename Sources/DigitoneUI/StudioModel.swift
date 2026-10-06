import Foundation
import Combine
import DigitoneCore
import DigitoneMIDI

enum ParameterOrigin: String {
    case draft = "Черновик"
    case sent = "Отправлено"
    case received = "Получено"
}

struct KnownParameter: Equatable {
    var value: Int
    var origin: ParameterOrigin
}

enum SnapshotSort: String, CaseIterable, Identifiable {
    case newest = "Сначала новые"
    case name = "По имени"
    var id: Self { self }
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var machine: SynthMachine = .fmTone {
        didSet { if machine != oldValue { clearObservedValues(channel: channel) } }
    }
    @Published var channel = 0
    @Published var sources: [MIDIEndpoint] = []
    @Published var destinations: [MIDIEndpoint] = []
    @Published var sourceID: UInt32 = 0
    @Published var destinationID: UInt32 = 0
    @Published var identity: DeviceIdentity?
    @Published var lastParameterChannel: Int?
    @Published var lastParameterText: String?
    @Published var busy = false
    @Published var busyText = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var values: [String: [String: KnownParameter]] = [:]
    @Published var snapshots: [SoundSnapshot] = []
    @Published var search = ""
    @Published var libraryMachine: SynthMachine?
    @Published var libraryTag = ""
    @Published var favoritesOnly = false
    @Published var snapshotSort: SnapshotSort = .newest
    @Published var snapshotName = ""
    @Published var snapshotTags = ""
    @Published var pattern: PatternSnapshot?
    @Published var rawPatternData: Data?
    @Published var rawPatternIndex: Int?
    @Published var patternIndex = 0
    @Published var patternTrack = 0
    @Published var patternPage = 0
    @Published var log: [String] = []
    @Published var checkpointA: [String: Int]?
    @Published var checkpointB: [String: Int]?
    @Published var storageAvailable = true
    @Published private(set) var isSequencePlaying = false
    @Published private(set) var sequencePlayhead = 0.0
    private let sequencePlayer = SequencePlayer()
    /// Every incoming note, program change, clock and transport message while connected.
    let midiInput = PassthroughSubject<MIDIInputEvent, Never>()
    /// Every incoming CC/NRPN parameter change while connected.
    let parameterInput = PassthroughSubject<ParameterEvent, Never>()
    fileprivate var heldNotes = Set<HeldNote>()
    /// Off after an explicit disconnect until the user connects again.
    var autoConnectEnabled = true
    private var playerObservers = Set<AnyCancellable>()
    private var checkpointsRoute: String?
    private var transport: MIDITransport?
    private var session: DigitoneSession?
    private var connectionGeneration = 0
    private let store: SnapshotStore

    init(directory suppliedDirectory: URL? = nil, startMIDI: Bool = true) {
        let directory: URL
        if let suppliedDirectory {
            directory = suppliedDirectory
        } else if let override = ProcessInfo.processInfo.environment["DIGITONE_STUDIO_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DigitoneStudio", isDirectory: true)
        }
        store = SnapshotStore(directory: directory)
        do { snapshots = try store.load() }
        catch {
            storageAvailable = false
            self.error = "Не удалось открыть библиотеку. Исходные файлы сохранены: \(error.localizedDescription)"
        }
        if startMIDI { createTransport() }
        sequencePlayer.$isPlaying.sink { [weak self] in self?.isSequencePlaying = $0 }.store(in: &playerObservers)
        sequencePlayer.$playhead.sink { [weak self] in self?.sequencePlayhead = $0 }.store(in: &playerObservers)
        sequencePlayer.onError = { [weak self] in self?.error = $0.localizedDescription }
    }

    var route: String { "\(channel):\(machine.id)" }
    var parameters: [ParameterDefinition] { ParameterCatalog.parameters(for: machine) }
    var sections: [String] {
        parameters.reduce(into: [String]()) { result, parameter in
            if !result.contains(parameter.section) { result.append(parameter.section) }
        }
    }
    var known: [String: KnownParameter] { values[route] ?? [:] }
    var connected: Bool { identity?.isDigitoneII == true }
    var knownCount: Int { known.count }
    var supportedCount: Int { parameters.count }
    var filteredSnapshots: [SoundSnapshot] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = snapshots.filter { snapshot in
            (libraryMachine == nil || snapshot.machine == libraryMachine) &&
            (!favoritesOnly || snapshot.isFavorite) &&
            (libraryTag.isEmpty || snapshot.tags.contains { $0.localizedCaseInsensitiveCompare(libraryTag) == .orderedSame }) &&
            (query.isEmpty || snapshot.name.localizedCaseInsensitiveContains(query) ||
             snapshot.tags.contains { $0.localizedCaseInsensitiveContains(query) } ||
             snapshot.machine.title.localizedCaseInsensitiveContains(query))
        }
        return result.sorted {
            if snapshotSort == .name {
                let order = $0.name.localizedStandardCompare($1.name)
                if order != .orderedSame { return order == .orderedAscending }
            }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var libraryTags: [String] {
        snapshots.flatMap(\.tags).reduce(into: [String]()) { result, tag in
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) { result.append(tag) }
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var hasLibraryFilters: Bool { !search.isEmpty || libraryMachine != nil || favoritesOnly || !libraryTag.isEmpty }
    var canApply: Bool { connected && !busy && parameters.contains { known[$0.id]?.origin == .draft } }

    func resetLibraryFilters() {
        search = ""; libraryMachine = nil; libraryTag = ""; favoritesOnly = false
    }

    private func createTransport() {
        do {
            let transport = try MIDITransport()
            self.transport = transport
            let session = DigitoneSession(transport: transport)
            self.session = session
            transport.onEndpointsChanged = { [weak self] in self?.updateEndpoints() }
            session.onParameter = { [weak self] in self?.receive($0) }
            session.onLog = { [weak self] in self?.appendLog($0) }
            session.onDisconnect = { [weak self] in self?.connectionEnded() }
            transport.onTimedMessages = { [weak self] messages, hostTime in
                guard let self, self.connected else { return }
                for message in messages {
                    if let event = MIDIInputEvent(message, hostTime: hostTime) { self.midiInput.send(event) }
                }
            }
            updateEndpoints()
        } catch { self.error = error.localizedDescription }
    }

    func refreshEndpoints() {
        guard !busy else { return }
        if transport == nil { createTransport() } else { transport?.refresh() }
    }

    private func updateEndpoints() {
        sources = transport?.sources ?? []
        destinations = transport?.destinations ?? []
        defer { autoConnectIfNeeded() }
        if !sources.contains(where: { $0.id == sourceID }) {
            sourceID = sources.first(where: { $0.isElektron })?.id ?? sources.first?.id ?? 0
        }
        if !destinations.contains(where: { $0.id == destinationID }) {
            destinationID = destinations.first(where: { $0.isElektron })?.id ?? destinations.first?.id ?? 0
        }
    }

    func connect() async {
        guard !connected else { return }
        autoConnectEnabled = true
        guard !busy, let transport, let session,
              let source = sources.first(where: { $0.id == sourceID }),
              let destination = destinations.first(where: { $0.id == destinationID }) else {
            error = "Выбери MIDI-вход и MIDI-выход."; return
        }
        busy = true; busyText = "Определяем прибор…"; error = nil; notice = nil
        defer { busy = false; busyText = "" }
        do {
            try transport.connect(source: source, destination: destination)
            let originalGeneration = connectionGeneration
            let result = try await session.identify()
            guard connectionGeneration == originalGeneration, transport.source == source, transport.destination == destination else {
                throw MIDIConnectionError.disconnected
            }
            identity = result
            connectionGeneration += 1
            notice = "Подключён \(result.name), OS \(result.version), сборка \(result.build). Значения обновятся по мере получения MIDI."
        } catch {
            transport.disconnect()
            self.error = error.localizedDescription
        }
    }

    func disconnect() { autoConnectEnabled = false; releaseAllNotes(); stopSequence(); transport?.disconnect() }

    func toggleSequence(_ sequence: NoteSequence) {
        if isSequencePlaying { stopSequence(); return }
        guard connected, !busy, let session else { return }
        do { try sequencePlayer.start(sequence: sequence, session: session) }
        catch { self.error = error.localizedDescription }
    }

    func stopSequence() { sequencePlayer.stop() }

    /// Pushes live edits to the running player; the next look-ahead window uses them.
    func updatePlayingSequence(_ sequence: NoteSequence) {
        guard isSequencePlaying else { return }
        sequencePlayer.update(sequence: sequence)
        sequencePlayer.setTempo(sequence.tempo)
    }

    private func connectionEnded() {
        heldNotes.removeAll()
        stopSequence()
        identity = nil
        lastParameterChannel = nil
        lastParameterText = nil
        connectionGeneration += 1
        for key in Array(values.keys) {
            values[key] = values[key]?.filter { $0.value.origin == .draft }
        }
        notice = "Соединение завершено. Локальные черновики сохранены."
    }

    private func receive(_ event: ParameterEvent) {
        guard connected else { return }
        parameterInput.send(event)
        lastParameterChannel = event.channel
        let address = event.nrpn.map { "NRPN \($0)" } ?? event.cc.map { "CC \($0)" } ?? "Параметр"
        lastParameterText = "MIDI-канал \(event.channel + 1) · \(address) · значение \(event.value)"
        // The complete control model resolves AUTO/FX/track channels before
        // publishing snapshot values. The legacy channel-only resolver below
        // would interpret global FX addresses as track parameters.
        if ControlModel.existing(for: self) != nil { return }
        let catalog = event.channel == channel ? parameters : ParameterCatalog.common
        guard let parameter = catalog.first(where: {
            if let nrpn = event.nrpn { return $0.nrpn == nrpn }
            return event.cc != nil && $0.cc == event.cc
        }) else { return }
        let coarse = event.resolution == 16383 ? event.value >> 7 : event.value
        let update = KnownParameter(value: min(127, max(0, coarse)), origin: .received)
        if ParameterCatalog.common.contains(where: { $0.id == parameter.id }) {
            for label in SynthMachine.allCases {
                let target = "\(event.channel):\(label.id)"
                // A loaded draft is an intentional local edit, so MIDI received
                // on another route should not silently replace that draft.
                if target == route || values[target]?[parameter.id]?.origin != .draft {
                    values[target, default: [:]][parameter.id] = update
                }
            }
        } else {
            values[route, default: [:]][parameter.id] = update
        }
    }

    func change(_ parameter: ParameterDefinition, to value: Int) {
        guard !busy else { return }
        let safe = min(127, max(0, value))
        var origin: ParameterOrigin = .draft
        if connected, let session {
            do {
                if let cc = parameter.cc { try session.sendCC(channel: channel, controller: cc, value: safe) }
                else { try session.sendNRPN(channel: channel, parameter: parameter.nrpn, value: safe << 7) }
                origin = .sent
            }
            catch { self.error = error.localizedDescription }
        }
        values[route, default: [:]][parameter.id] = KnownParameter(value: safe, origin: origin)
    }

    func audition(note: Int = 60) async {
        guard connected, !busy, let session else { return }
        busy = true; busyText = "Прослушивание…"
        defer { busy = false; busyText = "" }
        do { try await session.audition(channel: channel, note: note) }
        catch { self.error = error.localizedDescription }
    }

    func apply() async {
        guard canApply, let session else { return }
        let originalGeneration = connectionGeneration
        let originalChannel = channel
        let originalRoute = route
        let control = ControlModel.existing(for: self)
        let changes = parameters.compactMap { parameter -> (ParameterDefinition, Int, Int?)? in
            guard let knownValue = known[parameter.id], knownValue.origin == .draft else { return nil }
            var fineValue: Int?
            if let hardware = ParameterCatalog.hardwareParameter(for: parameter, machine: machine),
               hardware.isHighResolution, hardware.nrpn != nil,
               control?.channel(for: hardware.page) == originalChannel,
               let edited = control?.value(hardware), edited.origin == .draft {
                fineValue = edited.value
            }
            return (parameter, knownValue.value, fineValue)
        }
        busy = true; error = nil
        defer { busy = false; busyText = "" }
        do {
            for (index, change) in changes.enumerated() {
                guard connected, connectionGeneration == originalGeneration else { throw MIDIConnectionError.disconnected }
                busyText = "Параметры: \(index + 1) / \(changes.count)"
                if let fine = change.2 { try session.sendNRPN(channel: originalChannel, parameter: change.0.nrpn, value: fine) }
                else if let cc = change.0.cc { try session.sendCC(channel: originalChannel, controller: cc, value: change.1) }
                else { try session.sendNRPN(channel: originalChannel, parameter: change.0.nrpn, value: change.1 << 7) }
                values[originalRoute, default: [:]][change.0.id] = KnownParameter(value: change.1, origin: .sent)
                try await Task.sleep(for: .milliseconds(30))
            }
            notice = "Отправлено \(changes.count) параметров в MIDI-канал \(originalChannel + 1). Изменена только эта часть текущего звука."
        } catch { self.error = error.localizedDescription }
    }

    func saveSnapshot() {
        guard storageAvailable, !busy, !known.isEmpty else { return }
        let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Дай снимку имя."; return }
        let tags = SoundSnapshot.normalizedTags(from: snapshotTags)
        let snapshot = SoundSnapshot(name: name, machine: machine, channel: channel, parameters: known.mapValues(\.value), tags: tags)
        var updated = snapshots; updated.insert(snapshot, at: 0)
        do { try store.save(updated); snapshots = updated; notice = "Снимок «\(name)» сохранён локально: \(snapshot.parameters.count) известных параметров."; snapshotName = "" }
        catch { self.error = "Не удалось сохранить библиотеку: \(error.localizedDescription)" }
    }

    func load(_ snapshot: SoundSnapshot) {
        guard !busy else { return }
        channel = snapshot.channel; machine = snapshot.machine
        ControlModel.existing(for: self)?.prepareSoundDraftReplacement()
        values[route] = snapshot.parameters.mapValues { KnownParameter(value: $0, origin: .draft) }
        notice = "«\(snapshot.name)» открыт как черновик. Для отправки нажми «Применить параметры»."
    }

    func delete(_ snapshot: SoundSnapshot) {
        guard storageAvailable, !busy else { return }
        let updated = snapshots.filter { $0.id != snapshot.id }
        do { try store.save(updated); snapshots = updated; reconcileTagFilter() }
        catch { self.error = error.localizedDescription }
    }

    func toggleFavorite(_ snapshot: SoundSnapshot) {
        guard storageAvailable, !busy, let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return }
        var updated = snapshots
        updated[index].isFavorite.toggle()
        do { try store.save(updated); snapshots = updated; error = nil }
        catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func updateSnapshot(_ id: UUID, name: String, tags: String) -> Bool {
        guard storageAvailable, !busy, let index = snapshots.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { error = "Дай снимку имя."; return false }
        var updated = snapshots
        updated[index].name = trimmedName
        updated[index].tags = SoundSnapshot.normalizedTags(from: tags)
        do {
            try store.save(updated); snapshots = updated; reconcileTagFilter(); error = nil
            notice = "Название и теги снимка обновлены."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func duplicate(_ snapshot: SoundSnapshot) {
        guard storageAvailable, !busy else { return }
        let copy = SoundSnapshot(name: "\(snapshot.name) — копия", machine: snapshot.machine, channel: snapshot.channel,
                                 parameters: snapshot.parameters, tags: snapshot.tags, isFavorite: snapshot.isFavorite)
        var updated = snapshots; updated.insert(copy, at: 0)
        do { try store.save(updated); snapshots = updated; error = nil; notice = "Копия снимка сохранена в библиотеку." }
        catch { self.error = error.localizedDescription }
    }

    func exportSnapshots(_ selection: [SoundSnapshot]? = nil) -> Data? {
        do { return try SnapshotArchive.encode(selection ?? snapshots) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func importSnapshots(_ data: Data) {
        guard storageAvailable, !busy else { return }
        do {
            guard data.count <= 10_000_000 else { throw SnapshotStoreError.invalidSnapshot("слишком большой файл библиотеки") }
            let imported = try SnapshotArchive.decode(data)
            let result = try SnapshotArchive.merge(imported, into: snapshots)
            if result.addedCount > 0 { try store.save(result.snapshots); snapshots = result.snapshots }
            error = nil
            notice = "Импорт: добавлено \(result.addedCount), уже в библиотеке \(result.skippedCount)." +
                (result.copiedCount > 0 ? " Различающиеся версии сохранены как копии: \(result.copiedCount)." : "")
        } catch { self.error = "Не удалось импортировать библиотеку: \(error.localizedDescription)" }
    }

    func importSnapshots(_ url: URL) {
        guard storageAvailable, !busy else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { importSnapshots(try Data(contentsOf: url, options: .mappedIfSafe)) }
        catch { self.error = "Не удалось открыть файл библиотеки: \(error.localizedDescription)" }
    }

    private func reconcileTagFilter() {
        if !libraryTag.isEmpty {
            libraryTag = libraryTags.first(where: { $0.localizedCaseInsensitiveCompare(libraryTag) == .orderedSame }) ?? ""
        }
    }

    func checkpoint(_ side: String) {
        guard !busy else { return }
        if checkpointsRoute != route { checkpointA = nil; checkpointB = nil; checkpointsRoute = route }
        let copy = known.mapValues(\.value)
        if side == "A" { checkpointA = copy } else { checkpointB = copy }
        notice = "Вариант \(side) сохранён в памяти приложения."
    }

    func useCheckpoint(_ side: String) {
        guard !busy, checkpointsRoute == route, let copy = side == "A" ? checkpointA : checkpointB else { return }
        ControlModel.existing(for: self)?.prepareSoundDraftReplacement()
        values[route] = copy.mapValues { KnownParameter(value: $0, origin: .draft) }
        notice = "Вариант \(side) открыт как черновик. Прибор обновится после применения параметров."
    }

    func hasCheckpoint(_ side: String) -> Bool {
        checkpointsRoute == route && (side == "A" ? checkpointA : checkpointB) != nil
    }

    func clearObservedValues(channel: Int? = nil) {
        let affected = channel ?? self.channel
        for label in SynthMachine.allCases {
            let target = "\(affected):\(label.id)"
            values[target] = values[target]?.filter { $0.value.origin == .draft }
        }
    }

    func clearCurrentValues() {
        guard !busy else { return }
        values[route] = [:]
        notice = "Значения редактора очищены. Поверни ручки на приборе, чтобы получить новые."
    }

    func readPattern() async {
        guard connected, !busy, let session else { return }
        busy = true; busyText = "Читаем \(PatternSnapshot.slotName(patternIndex))…"; error = nil; notice = nil
        defer { busy = false; busyText = "" }
        do {
            let dump = try await session.fetchPattern(index: patternIndex)
            try openDump(dump)
            notice = "Паттерн прочитан. Ноты показаны только для просмотра; raw SysEx можно сохранить."
        } catch { self.error = error.localizedDescription }
    }

    func importPattern(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 2_000_000 else { throw ProtocolError.unsupported("слишком большой SysEx-файл") }
            guard case .dump(let dump) = try ElektronProtocol.parse(Array(data)) else { throw ProtocolError.unsupported("ожидается один дамп паттерна") }
            guard dump.family == ElektronProtocol.digitoneFamily, dump.type == 0x50, dump.index < 128 else {
                throw ProtocolError.unsupported("ожидается дамп паттерна Digitone II")
            }
            error = nil; notice = nil
            try openDump(dump)
            notice = "Архив открыт локально. Данные в прибор не отправлялись."
        } catch { self.error = error.localizedDescription }
    }

    private func openDump(_ dump: DumpMessage) throws {
        // Retain a verified transfer even when this firmware's payload layout
        // cannot yet be interpreted. Never let Export silently point at an
        // older pattern after a successful new transfer.
        rawPatternData = Data(dump.raw)
        rawPatternIndex = Int(dump.index)
        pattern = nil
        patternIndex = Int(dump.index)
        patternPage = 0
        pattern = try PatternSnapshot(dump: dump)
    }

    func appendLog(_ message: String) {
        log.append(message)
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }
}

// MARK: - Shared live MIDI for the instrument surfaces

private struct HeldNote: Hashable { let channel: Int; let note: Int }

extension StudioModel {
    /// The connected session, or nil while no Digitone II is identified.
    var midiSession: DigitoneSession? { connected ? session : nil }

    /// Starts a note that sounds until `noteOff`. Used by on-screen and
    /// computer-keyboard playing; held notes are released on disconnect.
    func noteOn(channel: Int, note: Int, velocity: Int) {
        guard let session = midiSession, (0..<16).contains(channel), (0..<128).contains(note) else { return }
        let held = HeldNote(channel: channel, note: note)
        do {
            if heldNotes.contains(held) { try session.transport.send(MIDIBytes.note(channel: channel, number: note, velocity: 0, on: false)) }
            try session.transport.send(MIDIBytes.note(channel: channel, number: note, velocity: min(127, max(1, velocity)), on: true))
            heldNotes.insert(held)
        } catch { self.error = error.localizedDescription }
    }

    func noteOff(channel: Int, note: Int) {
        let held = HeldNote(channel: channel, note: note)
        guard heldNotes.remove(held) != nil, let session = midiSession else { return }
        try? session.transport.send(MIDIBytes.note(channel: channel, number: note, velocity: 0, on: false))
    }

    func releaseAllNotes() {
        let notes = heldNotes
        heldNotes.removeAll()
        guard let session = midiSession else { return }
        for held in notes {
            try? session.transport.send(MIDIBytes.note(channel: held.channel, number: held.note, velocity: 0, on: false))
        }
    }

    /// Connects by itself when a Digitone appears (hot-plug), without a picker.
    fileprivate func autoConnectIfNeeded() {
        guard autoConnectEnabled, !connected, !busy,
              sources.contains(where: \.isElektron), destinations.contains(where: \.isElektron) else { return }
        sourceID = sources.first(where: \.isElektron)?.id ?? sourceID
        destinationID = destinations.first(where: \.isElektron)?.id ?? destinationID
        Task { await connect() }
    }
}
