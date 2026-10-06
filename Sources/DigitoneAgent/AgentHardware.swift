import Foundation
import DigitoneCore
import DigitoneMIDI

/// A narrow hardware boundary. Tests use a fake and never create a CoreMIDI client.
@MainActor
public protocol AgentHardware: AnyObject {
    func listDevices() throws -> JSONValue
    func status() -> JSONValue
    func connect(sourceID: Int32, destinationID: Int32) async throws -> JSONValue
    func disconnect()
    func send(parameter: DNParameter, coarseValue: Int, channel: Int) throws
    func play(sequence: NoteSequence, sendsClock: Bool) throws
    func stop()
    func shutdown()
}

/// Lazily opens MIDI only when a device operation is requested.
@MainActor
public final class CoreMIDIAgentHardware: AgentHardware {
    private var transport: MIDITransport?
    private var session: DigitoneSession?
    private let player = SequencePlayer()
    private let offline: Bool

    public init(offline: Bool = false) { self.offline = offline }

    private func prepare() throws -> (MIDITransport, DigitoneSession) {
        guard !offline else { throw AgentError("Server is in --offline mode. Hardware operations are disabled.") }
        if let transport, let session { return (transport, session) }
        let transport = try MIDITransport()
        let session = DigitoneSession(transport: transport)
        session.onDisconnect = { [weak self] in self?.player.stop() }
        self.transport = transport; self.session = session
        return (transport, session)
    }

    public func listDevices() throws -> JSONValue {
        if offline { return .object(["inputs": .array([]), "outputs": .array([]), "offline": .bool(true)]) }
        let (transport, _) = try prepare(); transport.refresh()
        func endpoint(_ value: MIDIEndpoint) -> JSONValue {
            .object(["id": .integer(Int(value.uniqueID)), "name": .string(value.name), "isDigitone": .bool(value.isElektron)])
        }
        return .object(["inputs": .array(transport.sources.map(endpoint)), "outputs": .array(transport.destinations.map(endpoint))])
    }

    public func status() -> JSONValue {
        var result: [String: JSONValue] = ["connected": .bool(session?.identity?.isDigitoneII == true),
                                          "playing": .bool(player.isPlaying), "offline": .bool(offline)]
        if let source = transport?.source { result["input"] = .string(source.name); result["sourceID"] = .integer(Int(source.uniqueID)) }
        if let destination = transport?.destination { result["output"] = .string(destination.name); result["destinationID"] = .integer(Int(destination.uniqueID)) }
        if let identity = session?.identity {
            result["device"] = .string(identity.name); result["osVersion"] = .string(identity.version)
        }
        if let error = player.lastError { result["playbackError"] = .string(error) }
        return .object(result)
    }

    public func connect(sourceID: Int32, destinationID: Int32) async throws -> JSONValue {
        let (transport, session) = try prepare()
        player.stop(); transport.refresh()
        guard let source = transport.sources.first(where: { $0.uniqueID == sourceID }),
              let destination = transport.destinations.first(where: { $0.uniqueID == destinationID }) else {
            throw AgentError("Requested MIDI endpoint is missing. Call digitone_list_devices and use its exact endpoint IDs.")
        }
        try transport.connect(source: source, destination: destination)
        do { _ = try await session.identify() }
        catch { transport.disconnect(); throw error }
        return status()
    }

    public func disconnect() { player.stop(); transport?.disconnect() }
    public func send(parameter: DNParameter, coarseValue: Int, channel: Int) throws {
        guard let session else { throw MIDIConnectionError.disconnected }
        if let nrpn = parameter.nrpn { try session.sendNRPN(channel: channel, parameter: nrpn, value: coarseValue << 7) }
        else if let cc = parameter.cc { try session.sendCC(channel: channel, controller: cc, value: coarseValue) }
        else { throw AgentError("Parameter has no published MIDI address.") }
    }
    public func play(sequence: NoteSequence, sendsClock: Bool) throws {
        guard let session else { throw MIDIConnectionError.disconnected }
        try player.start(sequence: sequence, session: session, sendsClock: sendsClock)
    }
    public func stop() { player.stop() }
    public func shutdown() { disconnect(); transport?.close(); transport = nil; session = nil }
}
