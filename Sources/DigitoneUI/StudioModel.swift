import Foundation
import Combine
import DigitoneCore
import DigitoneMIDI

enum ParameterOrigin: String {
    case draft = "Черновик"
    case sent = "Отправлено"
    case received = "Получено"
}

struct KnownParameter {
    var value: Int
    var origin: ParameterOrigin
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
    private var checkpointsRoute: String?
    private var transport: MIDITransport?
    private var session: DigitoneSession?
    private var connectionGeneration = 0
    private let store: SnapshotStore

    init() {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["DIGITONE_STUDIO_DATA_DIR"], !override.isEmpty {
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
        createTransport()
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
        guard !query.isEmpty else { return snapshots }
        return snapshots.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ||
            $0.machine.title.localizedCaseInsensitiveContains(query)
        }
    }
    var canApply: Bool { connected && !busy && parameters.contains { known[$0.id] != nil } }

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
        if !sources.contains(where: { $0.id == sourceID }) {
            sourceID = sources.first(where: { $0.isElektron })?.id ?? sources.first?.id ?? 0
        }
        if !destinations.contains(where: { $0.id == destinationID }) {
            destinationID = destinations.first(where: { $0.isElektron })?.id ?? destinations.first?.id ?? 0
        }
    }

    func connect() async {
        guard !busy, let transport, let session,
              let source = sources.first(where: { $0.id == sourceID }),
              let destination = destinations.first(where: { $0.id == destinationID }) else {
            error = "Выбери MIDI-вход и MIDI-выход."; return
        }
        busy = true; busyText = "Определяем прибор…"; error = nil; notice = nil
        defer { busy = false; busyText = "" }
        do {
            try transport.connect(source: source, destination: destination)
            let result = try await session.identify()
            identity = result
            connectionGeneration += 1
            notice = "Подключён \(result.name), OS \(result.version), сборка \(result.build). Значения обновятся по мере получения MIDI."
        } catch {
            transport.disconnect()
            self.error = error.localizedDescription
        }
    }

    func disconnect() { transport?.disconnect() }

    private func connectionEnded() {
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
        lastParameterChannel = event.channel
        let address = event.nrpn.map { "NRPN \($0)" } ?? event.cc.map { "CC \($0)" } ?? "Параметр"
        lastParameterText = "MIDI-канал \(event.channel + 1) · \(address) · значение \(event.value)"
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

    func audition() async {
        guard connected, !busy, let session else { return }
        busy = true; busyText = "Прослушивание…"
        defer { busy = false; busyText = "" }
        do { try await session.audition(channel: channel) }
        catch { self.error = error.localizedDescription }
    }

    func apply() async {
        guard canApply, let session else { return }
        let originalGeneration = connectionGeneration
        let originalChannel = channel
        let originalRoute = route
        let changes = parameters.compactMap { parameter -> (ParameterDefinition, Int)? in
            guard let value = known[parameter.id]?.value else { return nil }
            return (parameter, value)
        }
        busy = true; error = nil
        defer { busy = false; busyText = "" }
        do {
            for (index, change) in changes.enumerated() {
                guard connected, connectionGeneration == originalGeneration else { throw MIDIConnectionError.disconnected }
                busyText = "Параметры: \(index + 1) / \(changes.count)"
                if let cc = change.0.cc { try session.sendCC(channel: originalChannel, controller: cc, value: change.1) }
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
        let tags = snapshotTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let snapshot = SoundSnapshot(name: name, machine: machine, channel: channel, parameters: known.mapValues(\.value), tags: tags)
        var updated = snapshots; updated.insert(snapshot, at: 0)
        do { try store.save(updated); snapshots = updated; notice = "Снимок «\(name)» сохранён локально: \(snapshot.parameters.count) известных параметров."; snapshotName = "" }
        catch { self.error = "Не удалось сохранить библиотеку: \(error.localizedDescription)" }
    }

    func load(_ snapshot: SoundSnapshot) {
        guard !busy else { return }
        machine = snapshot.machine; channel = snapshot.channel
        values[route] = snapshot.parameters.mapValues { KnownParameter(value: $0, origin: .draft) }
        notice = "«\(snapshot.name)» открыт как черновик. Для отправки нажми «Применить параметры»."
    }

    func delete(_ snapshot: SoundSnapshot) {
        guard storageAvailable, !busy else { return }
        let updated = snapshots.filter { $0.id != snapshot.id }
        do { try store.save(updated); snapshots = updated }
        catch { self.error = error.localizedDescription }
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
