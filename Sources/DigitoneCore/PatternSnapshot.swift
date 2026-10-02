import Foundation

public struct PatternNote: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let track: Int
    public let step: Int
    public let note: Int
    public let velocity: Int
    public let lengthCode: Int
    public let microTiming: Int
}

public struct PatternSnapshot: Codable, Equatable, Sendable {
    public let index: Int
    public let name: String
    public let tempo: Double
    public let swing: Int
    public let trackNames: [String]
    public let trackLengths: [Int]
    public let notes: [PatternNote]
    public let raw: Data

    public static func slotName(_ index: Int) -> String {
        let safe = min(127, max(0, index))
        return "\(String(UnicodeScalar(65 + safe / 16)!))\(String(format: "%02d", safe % 16 + 1))"
    }

    public init(dump: DumpMessage) throws {
        guard dump.family == 0x15, dump.type == 0x50, dump.version == [1, 1],
              dump.index < 128, dump.payload.count == 99840 else { throw ProtocolError.unsupported("Digitone II pattern-kit dump") }
        let bytes = dump.payload
        guard ElektronProtocol.u32(bytes, 0) == 3,
              ElektronProtocol.u32(bytes, 89088) == 0xbeefbace,
              ElektronProtocol.u32(bytes, 89092) == 3 else { throw ProtocolError.unsupported("pattern/kit struct version") }
        index = Int(dump.index)
        name = Self.name(bytes, at: 88788)
        tempo = Double(ElektronProtocol.u32(bytes, 88804)) / 120
        swing = 50 + Int(bytes[88812])
        guard (50...80).contains(swing), tempo > 0, tempo <= 1000 else { throw ProtocolError.malformed("pattern tempo/swing") }
        trackNames = (0..<16).map { Self.name(bytes, at: 89088 + 60 + $0 * 359 + 12) }
        trackLengths = try (0..<16).map { track in
            let length = Int(ElektronProtocol.u16(bytes, 4 + track * 1187 + 1152 + 12))
            guard (1...128).contains(length) else { throw ProtocolError.malformed("track length") }
            return length
        }
        var found: [PatternNote] = []
        for record in 0..<8192 {
            let offset = 18996 + record * 6
            let track = Int(bytes[offset])
            let step = Int(bytes[offset + 1])
            if track == 255 { continue }
            guard track < 16, step < 128 else { throw ProtocolError.malformed("note record") }
            let base = 4 + track * 1187
            if ElektronProtocol.u16(bytes, base + step * 2) & 1 == 0 { continue }
            let defaults = base + 1152
            let pitch = bytes[offset + 2] == 255 ? bytes[defaults] : bytes[offset + 2]
            let velocity = bytes[offset + 3] == 255 ? bytes[defaults + 1] : bytes[offset + 3]
            let length = bytes[offset + 4] == 255 ? bytes[defaults + 2] : bytes[offset + 4]
            guard pitch < 128, velocity < 128, length < 128 else { throw ProtocolError.malformed("note value") }
            found.append(PatternNote(id: record, track: track, step: step, note: Int(pitch), velocity: Int(velocity), lengthCode: Int(length), microTiming: Int(Int8(bitPattern: bytes[offset + 5]))))
        }
        notes = found
        raw = Data(dump.raw)
    }

    private static func name(_ bytes: [UInt8], at offset: Int) -> String {
        let slice = bytes[offset..<(offset + 16)].prefix(while: { $0 != 0 })
        return String(bytes: slice, encoding: .windowsCP1252) ?? ""
    }
}
