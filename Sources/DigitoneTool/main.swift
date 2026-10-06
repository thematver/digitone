import Foundation
import DigitoneCore
import DigitoneMIDI
import DigitoneAudio

@main
struct DigitoneTool {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.first == "--help" || args.first == "help" {
                print("Commands: list, audio-list, audio-monitor [SECONDS], identify, capture SLOT OUTPUT.syx, inspect INPUT.syx")
                return
            }
            if args.first == "audio-list" {
                guard args.count == 1 else { throw ProtocolError.malformed("Usage: digitone-tool audio-list") }
                listAudio()
                return
            }
            if args.first == "audio-monitor" {
                guard args.count <= 2 else { throw ProtocolError.malformed("Usage: digitone-tool audio-monitor [SECONDS]") }
                let duration = args.count == 2 ? Double(args[1]) : 10
                guard let duration, duration.isFinite, (1...60).contains(duration) else {
                    throw ProtocolError.malformed("SECONDS must be between 1 and 60")
                }
                try await monitorAudio(seconds: duration)
                return
            }
            if args.first == "inspect" {
                guard args.count == 2 else { throw ProtocolError.malformed("Usage: digitone-tool inspect INPUT.syx") }
                let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
                guard data.count <= 2_000_000, case .dump(let dump) = try ElektronProtocol.parse(Array(data)) else {
                    throw ProtocolError.unsupported("one pattern-kit dump required")
                }
                let snapshot = try PatternSnapshot(dump: dump)
                printSummary(snapshot)
                return
            }
            let transport = try MIDITransport()
            defer { transport.close() }
            guard args.first != nil, args.first != "list" else {
                print("MIDI inputs:")
                for endpoint in transport.sources { print("  \(endpoint.uniqueID): \(endpoint.name)") }
                print("MIDI outputs:")
                for endpoint in transport.destinations { print("  \(endpoint.uniqueID): \(endpoint.name)") }
                return
            }
            guard let source = transport.sources.first(where: \.isElektron),
                  let destination = transport.destinations.first(where: \.isElektron) else {
                throw MIDIConnectionError.disconnected
            }
            let session = DigitoneSession(transport: transport)
            session.onLog = { print($0) }
            try transport.connect(source: source, destination: destination)
            let identity = try await session.identify()
            print("Identity: \(identity.name), \(identity.version), build \(identity.build), product \(identity.productID)")
            if args.first == "capture" {
                guard args.count == 3, let slot = Int(args[1]), (0..<128).contains(slot) else {
                    throw ProtocolError.malformed("Usage: digitone-tool capture SLOT OUTPUT.syx")
                }
                let dump = try await session.fetchPattern(index: slot)
                let url = URL(fileURLWithPath: args[2])
                try Data(dump.raw).write(to: url, options: .atomic)
                print("Saved \(dump.raw.count) bytes to \(url.path)")
                do { printSummary(try PatternSnapshot(dump: dump)) }
                catch { print("Raw capture preserved; structured decoding unavailable: \(error.localizedDescription)") }
            } else if args.first != "identify" {
                throw ProtocolError.malformed("Commands: list, audio-list, audio-monitor [SECONDS], identify, capture SLOT OUTPUT.syx, inspect INPUT.syx")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor private static func listAudio() {
        let catalog = AudioDeviceCatalog()
        print("Audio devices:")
        for device in catalog.devices {
            let labels = [device.id == catalog.defaultInputID ? "default input" : nil,
                          device.id == catalog.defaultOutputID ? "default output" : nil].compactMap { $0 }
            let rate = device.nominalSampleRate.map { " · \(Int($0)) Hz" } ?? ""
            print("  \(device.name) · in \(device.inputChannels) / out \(device.outputChannels)\(rate)\(labels.isEmpty ? "" : " · " + labels.joined(separator: ", "))")
            print("    UID: \(device.id)")
        }
        let policy = AudioRoutePolicy()
        print("Automatic monitor route: \(policy.input(in: catalog.devices, defaultID: catalog.defaultInputID)?.name ?? "none") → \(policy.output(in: catalog.devices, defaultID: catalog.defaultOutputID)?.name ?? "none")")
    }

    /// Runs only the audio path, without opening any MIDI transport or sending
    /// note, parameter or SysEx messages. Monitoring always uses a safe output.
    @MainActor private static func monitorAudio(seconds: Double) async throws {
        let catalog = AudioDeviceCatalog()
        guard catalog.inputs.contains(where: \.isDigitone) else { throw AudioEngineError.deviceMissing("Digitone USB audio") }
        let audio = StudioAudioEngine(devices: catalog, settings: .inMemory(),
                                      options: .init(requiresUsageDescription: false))
        defer { audio.stop() }
        try await audio.start(enableInput: true)
        print("Monitoring: \(audio.inputDevice?.name ?? "none") → \(audio.outputDevice?.name ?? "none")")
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < end {
            try await Task.sleep(for: .seconds(1))
            audio.refreshLatency()
            let levels = audio.inputLevels()
            let diagnostics = audio.diagnostics()
            print(String(format: "L %.3f / R %.3f · %@ · in %lld / out %lld · underruns %lld · resyncs %lld · drift %.1f ppm",
                         levels.left.peak, levels.right.peak, audio.monitorLatency?.label ?? "latency unknown",
                         diagnostics.inputFrames, diagnostics.outputFrames, diagnostics.underruns,
                         diagnostics.resyncs, diagnostics.correctionPPM))
        }
        let diagnostics = audio.diagnostics()
        guard diagnostics.inputFrames > 0, diagnostics.outputFrames > 0 else { throw AudioEngineError.notRunning }
    }

    private static func printSummary(_ snapshot: PatternSnapshot) {
        print("\(PatternSnapshot.slotName(snapshot.index)) · \(snapshot.name) · \(snapshot.tempo) BPM · swing \(snapshot.swing)%")
        for track in 0..<16 {
            print("  T\(track + 1): \(snapshot.trackNames[track]) · \(snapshot.trackLengths[track]) steps · \(snapshot.notes.filter { $0.track == track }.count) notes")
        }
    }
}
