#if os(iOS)
import AVFoundation

extension AudioDeviceDiscovery {
    struct Snapshot {
        var devices: [AudioDevice]
        var defaultInputID: String?
        var defaultOutputID: String?
    }

    static func snapshot() -> Snapshot {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        var ports = (session.availableInputs ?? []).map { device($0, input: true) }
        ports += route.outputs.map { device($0, input: false) }
        let devices = AudioDevice.merged(ports)
        // A merged USB port retains the input UID. Map the session's output
        // UID back to that physical device so its real output remains visible.
        func identifier(_ port: AVAudioSessionPortDescription?, input: Bool) -> String? {
            guard let port else { return nil }
            return devices.first { device in
                (input ? device.hasInput : device.hasOutput)
                    && (device.id == port.uid || (device.name == port.portName && device.transport == transport(port.portType)))
            }?.id
        }
        return Snapshot(devices: devices,
                        defaultInputID: identifier(route.inputs.first, input: true),
                        defaultOutputID: identifier(route.outputs.first, input: false))
    }

    static func port(forID id: String) -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?.first { $0.uid == id }
    }

    /// Calls `onChange` on the main queue on route changes. Release the token to stop.
    static func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> AnyObject {
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
        return ObserverToken(observer)
    }

    private final class ObserverToken {
        let observer: NSObjectProtocol
        init(_ observer: NSObjectProtocol) { self.observer = observer }
        deinit { NotificationCenter.default.removeObserver(observer) }
    }

    private static func device(_ port: AVAudioSessionPortDescription, input: Bool) -> AudioDevice {
        let channels = max(port.channels?.count ?? 0, 1)
        return AudioDevice(
            id: port.uid,
            name: port.portName,
            inputChannels: input ? channels : 0,
            outputChannels: input ? 0 : channels,
            transport: transport(port.portType)
        )
    }

    private static func transport(_ type: AVAudioSession.Port) -> AudioDevice.Transport {
        switch type {
        case .usbAudio: .usb
        case .builtInMic, .builtInSpeaker, .builtInReceiver, .headsetMic, .headphones, .lineIn, .lineOut: .builtIn
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: .bluetooth
        case .airPlay: .airPlay
        case .HDMI: .hdmi
        case .carAudio: .other
        default: .other
        }
    }
}
#endif
