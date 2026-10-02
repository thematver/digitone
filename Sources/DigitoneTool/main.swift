import Foundation
import DigitoneCore
import DigitoneMIDI

@main
struct DigitoneTool {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.first == "--help" || args.first == "help" {
                print("Commands: list, identify, capture SLOT OUTPUT.syx, inspect INPUT.syx")
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
                throw ProtocolError.malformed("Commands: list, identify, capture SLOT OUTPUT.syx, inspect INPUT.syx")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func printSummary(_ snapshot: PatternSnapshot) {
        print("\(PatternSnapshot.slotName(snapshot.index)) · \(snapshot.name) · \(snapshot.tempo) BPM · swing \(snapshot.swing)%")
        for track in 0..<16 {
            print("  T\(track + 1): \(snapshot.trackNames[track]) · \(snapshot.trackLengths[track]) steps · \(snapshot.notes.filter { $0.track == track }.count) notes")
        }
    }
}
