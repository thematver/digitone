import Foundation
import Observation

/// Live list of audio devices, refreshed on hot-plug and default changes.
@MainActor
@Observable
public final class AudioDeviceCatalog {
    public private(set) var devices: [AudioDevice] = []
    public private(set) var defaultInputID: String?
    public private(set) var defaultOutputID: String?

    @ObservationIgnored private var listener: AnyObject?
    @ObservationIgnored private var observers: [UUID: @MainActor () -> Void] = [:]

    public init(observe: Bool = true) {
        refresh()
        if observe {
            listener = AudioDeviceDiscovery.observeChanges { [weak self] in self?.refresh() }
        }
    }

    public var inputs: [AudioDevice] { devices.filter(\.hasInput) }
    public var outputs: [AudioDevice] { devices.filter(\.hasOutput) }
    public var digitone: AudioDevice? { devices.first(where: \.isDigitone) }

    public var preferredInput: AudioDevice? {
        AudioDevice.preferred(in: devices, input: true, defaultID: defaultInputID)
    }

    public var preferredOutput: AudioDevice? {
        #if os(iOS)
        AudioRoutePolicy(followsSessionOutput: true).output(in: devices, defaultID: defaultOutputID)
        #else
        AudioDevice.preferred(in: devices, input: false, defaultID: defaultOutputID)
        #endif
    }

    public func device(id: String) -> AudioDevice? { devices.first { $0.id == id } }

    public func refresh() {
        let snapshot = AudioDeviceDiscovery.snapshot()
        let changed = snapshot.devices != devices
            || snapshot.defaultInputID != defaultInputID
            || snapshot.defaultOutputID != defaultOutputID
        devices = snapshot.devices
        defaultInputID = snapshot.defaultInputID
        defaultOutputID = snapshot.defaultOutputID
        if changed { observers.values.forEach { $0() } }
    }

    /// Internal hook for the engine to react to hot-plug.
    func onChange(_ handler: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func removeHandler(_ id: UUID) { observers[id] = nil }
}
