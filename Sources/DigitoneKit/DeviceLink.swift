import Foundation
import Observation
import DigitoneCore
import DigitoneMIDI

/// The connection to the Digitone II. Finds the device by itself: when MIDI
/// endpoints named "Digitone" appear, it connects and identifies over SysEx
/// without a port picker. Manual selection stays available for unusual setups.
@MainActor
@Observable
public final class DeviceLink {
    public enum Status: Equatable {
        /// CoreMIDI could not be started.
        case unavailable(String)
        /// No Digitone endpoints are visible.
        case searching
        case connecting
        case connected(DeviceIdentity)
        /// Endpoints exist but the handshake failed. Retries on the next endpoint change or `retry()`.
        case failed(String)

        public var isConnected: Bool { if case .connected = self { true } else { false } }
    }

    public private(set) var status: Status = .searching
    public private(set) var sources: [MIDIEndpoint] = []
    public private(set) var destinations: [MIDIEndpoint] = []
    /// Most recent activity per MIDI channel 0...15, for activity lamps.
    public private(set) var channelActivity: [Int: Date] = [:]
    /// Channel of the most recent incoming parameter change.
    public private(set) var lastParameterChannel: Int?
    /// Monotonic counters that drive the cable animation.
    public private(set) var incomingCount = 0
    public private(set) var outgoingCount = 0
    public private(set) var log: [String] = []

    public var identity: DeviceIdentity? { if case .connected(let identity) = status { identity } else { nil } }
    public var isConnected: Bool { status.isConnected }

    /// Parameter changes from hardware knobs (CC or NRPN).
    @ObservationIgnored public var onParameter: ((ParameterEvent) -> Void)?
    @ObservationIgnored public var onConnectionChange: ((Bool) -> Void)?

    @ObservationIgnored public private(set) var session: DigitoneSession?
    @ObservationIgnored private var transport: MIDITransport?
    @ObservationIgnored private var autoConnect = true
    @ObservationIgnored private var pendingScan: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0

    public init(startMIDI: Bool = true) {
        if startMIDI { start() }
    }

    public func start() {
        guard transport == nil else { return }
        do {
            let transport = try MIDITransport()
            let session = DigitoneSession(transport: transport)
            self.transport = transport
            self.session = session
            transport.onEndpointsChanged = { [weak self] in self?.endpointsChanged() }
            session.onParameter = { [weak self] event in self?.received(event) }
            session.onLog = { [weak self] line in self?.appendLog(line) }
            session.onDisconnect = { [weak self] in self?.disconnected() }
            endpointsChanged()
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    /// Re-scans endpoints and tries to connect again.
    public func retry() {
        autoConnect = true
        if transport == nil { start() } else { transport?.refresh() }
        scheduleAutoConnect(delay: .zero)
    }

    /// Manual connection to specific endpoints. Disables auto-connect until `retry()`.
    public func connect(source: MIDIEndpoint, destination: MIDIEndpoint) async {
        autoConnect = false
        await handshake(source: source, destination: destination)
    }

    public func disconnect() {
        autoConnect = false
        transport?.disconnect()
    }

    /// Records outgoing traffic for the activity display. Feature code calls
    /// this after sending through `session`.
    public func noteOutgoing(channel: Int?) {
        outgoingCount &+= 1
        if let channel { channelActivity[channel] = Date() }
    }

    private func endpointsChanged() {
        sources = transport?.sources ?? []
        destinations = transport?.destinations ?? []
        if !isConnected { scheduleAutoConnect(delay: .milliseconds(350)) }
    }

    private func scheduleAutoConnect(delay: Duration) {
        guard autoConnect else { return }
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            // Debounce: CoreMIDI reports sources and destinations separately when a device is plugged in.
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.autoConnectIfPossible()
        }
    }

    private func autoConnectIfPossible() async {
        guard autoConnect, !isConnected, status != .connecting else { return }
        guard let source = sources.first(where: \.isElektron),
              let destination = destinations.first(where: \.isElektron) else {
            if case .unavailable = status { return }
            status = .searching
            return
        }
        await handshake(source: source, destination: destination)
    }

    private func handshake(source: MIDIEndpoint, destination: MIDIEndpoint) async {
        guard let transport, let session else { return }
        attempt += 1
        let current = attempt
        status = .connecting
        do {
            try transport.connect(source: source, destination: destination)
            let identity = try await session.identify()
            guard current == attempt, transport.source == source, transport.destination == destination else { return }
            status = .connected(identity)
            onConnectionChange?(true)
        } catch {
            guard current == attempt else { return }
            transport.disconnect()
            status = .failed(error.localizedDescription)
        }
    }

    private func disconnected() {
        let wasConnected = isConnected
        channelActivity = [:]
        lastParameterChannel = nil
        if case .connected = status { status = .searching }
        if wasConnected { onConnectionChange?(false) }
        if autoConnect { scheduleAutoConnect(delay: .milliseconds(500)) }
    }

    private func received(_ event: ParameterEvent) {
        incomingCount &+= 1
        channelActivity[event.channel] = Date()
        lastParameterChannel = event.channel
        onParameter?(event)
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 120 { log.removeFirst(log.count - 120) }
    }
}
