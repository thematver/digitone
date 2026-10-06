import Foundation

/// An audio interface or port, the same model on macOS (CoreAudio device) and
/// iOS (AVAudioSession port).
public struct AudioDevice: Identifiable, Hashable, Sendable {
    public enum Transport: String, Sendable {
        case usb, builtIn, bluetooth, airPlay, hdmi, thunderbolt, virtual, aggregate, other
    }

    /// Persistent identifier: the CoreAudio device UID or the AVAudioSession port UID.
    public let id: String
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    /// Nil when the platform does not report it (iOS ports).
    public let nominalSampleRate: Double?
    public let transport: Transport
    /// CoreAudio `AudioObjectID` on macOS, 0 on iOS.
    public let systemID: UInt32

    public init(id: String, name: String, inputChannels: Int, outputChannels: Int,
                nominalSampleRate: Double? = nil, transport: Transport = .other, systemID: UInt32 = 0) {
        self.id = id
        self.name = name
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.nominalSampleRate = nominalSampleRate
        self.transport = transport
        self.systemID = systemID
    }

    public var isDigitone: Bool { name.localizedCaseInsensitiveContains("Digitone") }
    public var hasInput: Bool { inputChannels > 0 }
    public var hasOutput: Bool { outputChannels > 0 }
}

extension AudioDevice {
    /// Digitone-first input and a computer output, avoiding automatic USB feedback.
    public static func preferred(in devices: [AudioDevice], input: Bool, defaultID: String?) -> AudioDevice? {
        let policy = AudioRoutePolicy()
        return input ? policy.input(in: devices, defaultID: defaultID) : policy.output(in: devices, defaultID: defaultID)
    }

    /// Joins iOS input and output ports that belong to one physical interface
    /// (same name and transport), so a USB box appears once with both directions.
    public static func merged(_ ports: [AudioDevice]) -> [AudioDevice] {
        var result: [AudioDevice] = []
        for port in ports {
            if let index = result.firstIndex(where: {
                $0.name == port.name && $0.transport == port.transport
                    && ($0.hasInput != port.hasInput || $0.hasOutput != port.hasOutput)
                    && !($0.hasInput && port.hasInput) && !($0.hasOutput && port.hasOutput)
            }) {
                let existing = result[index]
                result[index] = AudioDevice(
                    id: existing.hasInput ? existing.id : port.id,
                    name: existing.name,
                    inputChannels: max(existing.inputChannels, port.inputChannels),
                    outputChannels: max(existing.outputChannels, port.outputChannels),
                    nominalSampleRate: existing.nominalSampleRate ?? port.nominalSampleRate,
                    transport: existing.transport,
                    systemID: existing.systemID
                )
            } else {
                result.append(port)
            }
        }
        return result
    }
}

/// Platform device enumeration. Implemented per platform.
enum AudioDeviceDiscovery {}
