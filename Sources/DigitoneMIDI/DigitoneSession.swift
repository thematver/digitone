import Foundation
import DigitoneCore

@MainActor
public final class DigitoneSession {
    public let transport: MIDITransport
    public private(set) var identity: DeviceIdentity?
    public var onParameter: ((ParameterEvent) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onDisconnect: (() -> Void)?
    private var nrpn = NRPNDecoder()
    private var nextID: UInt16 = 20000
    private struct PlayingNote: Hashable { let channel: Int; let number: Int }
    private var playingNotes: Set<PlayingNote> = []
    private struct Pending {
        let opcode: UInt8
        let continuation: CheckedContinuation<[UInt8], Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [UInt16: Pending] = [:]
    private struct PendingDump {
        let index: UInt8
        let continuation: CheckedContinuation<DumpMessage, Error>
        let timeout: Task<Void, Never>
    }
    private var dump: PendingDump?

    public init(transport: MIDITransport) {
        self.transport = transport
        transport.onMessages = { [weak self] messages in self?.receive(messages) }
        transport.onDisconnect = { [weak self] in self?.reset() }
        transport.onWillDisconnect = { [weak self] in self?.releaseNotes() }
    }

    public func identify() async throws -> DeviceIdentity {
        identity = nil
        let device = try await request(opcode: 1)
        let version = try await request(opcode: 2)
        let result = try DeviceIdentity(deviceReply: device, versionReply: version)
        guard result.isDigitoneII else { throw MIDIConnectionError.wrongDevice(result.name) }
        identity = result
        onLog?("\(result.name) · OS \(result.version) · build \(result.build)")
        return result
    }

    public func fetchPattern(index: Int) async throws -> DumpMessage {
        guard identity?.isDigitoneII == true else { throw MIDIConnectionError.disconnected }
        guard (0..<128).contains(index), dump == nil else { throw ProtocolError.unsupported("pattern request in progress or slot out of range") }
        let bytes = try ElektronProtocol.dumpRequest(index: UInt8(index))
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, let current = self.dump else { return }
                self.dump = nil
                current.continuation.resume(throwing: MIDIConnectionError.timeout("чтение паттерна"))
            }
            dump = PendingDump(index: UInt8(index), continuation: continuation, timeout: timer)
            do { try transport.send(bytes); onLog?("Чтение \(PatternSnapshot.slotName(index))…") }
            catch { timer.cancel(); dump = nil; continuation.resume(throwing: error) }
        }
    }

    public func sendCC(channel: Int, controller: Int, value: Int) throws {
        guard identity?.isDigitoneII == true else { throw MIDIConnectionError.disconnected }
        try transport.send(MIDIBytes.cc(channel: channel, controller: controller, value: value))
    }

    public func sendNRPN(channel: Int, parameter: Int, value: Int) throws {
        guard identity?.isDigitoneII == true else { throw MIDIConnectionError.disconnected }
        try transport.send(MIDIBytes.nrpn(channel: channel, parameter: parameter, value: value))
    }

    public func audition(channel: Int, note: Int = 60) async throws {
        guard identity?.isDigitoneII == true else { throw MIDIConnectionError.disconnected }
        // Hold the original destination: a delayed note-off must never reach a newly selected device.
        let destination = transport.destination
        let playing = PlayingNote(channel: channel, number: note)
        try transport.send(MIDIBytes.note(channel: channel, number: note, velocity: 90, on: true))
        playingNotes.insert(playing)
        try? await Task.sleep(for: .milliseconds(450))
        if destination == transport.destination, playingNotes.remove(playing) != nil {
            try transport.send(MIDIBytes.note(channel: channel, number: note, velocity: 0, on: false))
        }
    }

    public func reset() {
        identity = nil
        playingNotes.removeAll()
        nrpn = NRPNDecoder()
        let requests = pending.values
        pending.removeAll()
        for request in requests { request.timeout.cancel(); request.continuation.resume(throwing: MIDIConnectionError.disconnected) }
        if let dump { dump.timeout.cancel(); self.dump = nil; dump.continuation.resume(throwing: MIDIConnectionError.disconnected) }
        onDisconnect?()
    }

    private func releaseNotes() {
        for note in playingNotes {
            if let bytes = try? MIDIBytes.note(channel: note.channel, number: note.number, velocity: 0, on: false) {
                try? transport.send(bytes)
            }
        }
        playingNotes.removeAll()
    }

    private func request(opcode: UInt8) async throws -> [UInt8] {
        let id = nextID
        nextID = nextID == .max ? 20000 : nextID + 1
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, let request = self.pending.removeValue(forKey: id) else { return }
                request.continuation.resume(throwing: MIDIConnectionError.timeout(opcode == 1 ? "определение устройства" : "версия прошивки"))
            }
            pending[id] = Pending(opcode: opcode, continuation: continuation, timeout: timeout)
            do { try transport.send(APIMessage(messageID: id, opcode: opcode).bytes) }
            catch { pending.removeValue(forKey: id); timeout.cancel(); continuation.resume(throwing: error) }
        }
    }

    private func receive(_ messages: [MIDIMessage]) {
        for message in messages {
            switch message {
            case .channel(let status, let bytes) where status & 0xf0 == 0xb0 && bytes.count == 2:
                if let event = nrpn.receive(channel: Int(status & 15), cc: Int(bytes[0]), value: Int(bytes[1])) { onParameter?(event) }
            case .sysEx(let raw):
                guard raw.count >= 4, Array(raw[1..<4]) == [0, 0x20, 0x3c] else { continue }
                do {
                    switch try ElektronProtocol.parse(raw) {
                    case .api(let reply):
                        guard let request = pending[reply.responseID], reply.opcode == request.opcode | 0x80 else { continue }
                        pending.removeValue(forKey: reply.responseID)
                        request.timeout.cancel()
                        request.continuation.resume(returning: reply.arguments)
                    case .dump(let reply):
                        guard let request = dump, reply.family == 0x15, reply.type == 0x50, reply.index == request.index else { continue }
                        dump = nil; request.timeout.cancel(); request.continuation.resume(returning: reply)
                    }
                } catch {
                    onLog?(error.localizedDescription)
                    if raw.count >= 10, raw[4] == 0x15, raw[6] == 0x50,
                       let request = dump, raw[9] == request.index {
                        dump = nil; request.timeout.cancel(); request.continuation.resume(throwing: error)
                    }
                }
            default: break
            }
        }
    }
}
