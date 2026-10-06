import Foundation

/// Why "listen to the Digitone" cannot run right now.
public enum MonitorBlock: Sendable, Equatable {
    /// No Digitone audio input: the device is unplugged or not in USB AUDIO/MIDI mode.
    case noDigitone
    /// Output and input are the same interface: USB IN → MAIN → USB OUT would loop.
    case sameDevice
    /// Audio input permission was refused.
    case permissionDenied
    /// No usable output is available.
    case noOutput
}

/// Device choice for the studio graph, independent of CoreAudio/AVAudioSession.
///
/// Input: a pinned device, else the Digitone, else the system default input.
/// Output: a pinned device, else the system default output (speakers or
/// headphones). The Digitone is never chosen as output automatically, so its
/// sound reaches the computer's speakers out of the box.
public struct AudioRoutePolicy: Sendable, Equatable {
    public var pinnedInputID: String?
    public var pinnedOutputID: String?
    /// iOS: any USB output next to a USB input is treated as the same box.
    public var treatUSBPairAsSameDevice: Bool
    /// iOS reports the session's actual output, which may be the USB interface.
    public var followsSessionOutput: Bool

    public init(pinnedInputID: String? = nil, pinnedOutputID: String? = nil, treatUSBPairAsSameDevice: Bool = false, followsSessionOutput: Bool = false) {
        self.pinnedInputID = pinnedInputID
        self.pinnedOutputID = pinnedOutputID
        self.treatUSBPairAsSameDevice = treatUSBPairAsSameDevice
        self.followsSessionOutput = followsSessionOutput
    }

    public func input(in devices: [AudioDevice], defaultID: String?) -> AudioDevice? {
        let capable = devices.filter(\.hasInput)
        if let pinnedInputID { return capable.first { $0.id == pinnedInputID } }
        return capable.first(where: \.isDigitone)
            ?? capable.first { $0.id == defaultID }
            ?? capable.first { $0.transport == .builtIn }
            ?? capable.first
    }

    public func output(in devices: [AudioDevice], defaultID: String?) -> AudioDevice? {
        let capable = devices.filter(\.hasOutput)
        if let pinnedOutputID { return capable.first { $0.id == pinnedOutputID } }
        return capable.first { $0.id == defaultID && (followsSessionOutput || !$0.isDigitone) }
            ?? capable.first { !$0.isDigitone && $0.transport == .builtIn }
            ?? capable.first { !$0.isDigitone }
    }

    /// True when `input` and `output` are one physical interface.
    public func isSameDevice(_ input: AudioDevice?, _ output: AudioDevice?) -> Bool {
        guard let input, let output else { return false }
        if input.id == output.id { return true }
        if input.name == output.name && input.transport == output.transport { return true }
        return treatUSBPairAsSameDevice && input.transport == .usb && output.transport == .usb
    }

    /// Monitoring needs a Digitone (or a deliberately pinned) input that does
    /// not loop back into itself. The built-in microphone is never monitored
    /// automatically: through the speakers it would howl.
    public func monitorBlock(input: AudioDevice?, output: AudioDevice?, permission: RecordPermission) -> MonitorBlock? {
        if permission == .denied { return .permissionDenied }
        guard let input, input.isDigitone || input.id == pinnedInputID else { return .noDigitone }
        guard output != nil else { return .noOutput }
        if isSameDevice(input, output) { return .sameDevice }
        return nil
    }
}
