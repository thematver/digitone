import Foundation
import DigitoneCore

public struct AgentError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A partial sound draft. Unspecified parameters stay unknown; no hardware readback is implied.
public struct AgentSoundDraft: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Stored indices are 0-based. MCP tools use 1-based track and channel arguments.
    public var track: Int
    public var midiChannel: Int
    /// Declares the machine already selected on the hardware; MIDI cannot change it.
    public var machine: SynthMachine
    /// HardwareCatalog parameter IDs → coarse MIDI values, limited by each catalog range.
    public var parameters: [String: Int]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, track: Int, midiChannel: Int,
                machine: SynthMachine, parameters: [String: Int] = [:], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.track = track; self.midiChannel = midiChannel
        self.machine = machine; self.parameters = parameters; self.createdAt = createdAt
    }

    public func validate() throws {
        try AgentProject.validateName(name)
        guard (0..<16).contains(track), (0..<16).contains(midiChannel) else {
            throw AgentError("Sound track and MIDI channel must be in 1...16.")
        }
        let catalog = Dictionary(uniqueKeysWithValues: HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!).map { ($0.id, $0) })
        for (id, value) in parameters {
            guard let parameter = catalog[id], parameter.cc != nil || parameter.nrpn != nil else {
                throw AgentError("Unknown or unavailable parameter '\(id)' for \(machine.title). Discover digitone_parameter_catalog first.")
            }
            guard AgentParameterRange.coarse(for: parameter).contains(value) else {
                throw AgentError("\(id) must use a coarse MIDI value in \(AgentParameterRange.coarse(for: parameter)).")
            }
        }
    }

    /// A validated draft can join the app's existing library; legacy IDs are preserved.
    public var snapshot: SoundSnapshot {
        let catalog = HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!)
        var values: [String: Int] = [:]
        for (id, value) in parameters {
            guard let hardware = catalog.first(where: { $0.id == id }),
                  let definition = ParameterCatalog.definition(for: hardware, machine: machine) else { continue }
            values[definition.id] = value
        }
        return SoundSnapshot(id: id, name: name, machine: machine, channel: midiChannel, parameters: values, createdAt: createdAt, tags: ["Agent"])
    }
}

public enum AgentParameterRange {
    public static func coarse(for parameter: DNParameter) -> ClosedRange<Int> {
        switch parameter.format {
        case .number(let range, let offset):
            let lower = min(127, max(0, range.lowerBound - offset))
            return lower...min(127, max(lower, range.upperBound - offset))
        case .options(let labels) where !labels.isEmpty: return 0...min(127, labels.count - 1)
        default: return 0...127
        }
    }
}

/// Portable .digitone.json file exchanged between the app and an MCP session.
public struct AgentProject: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var name: String
    public var sequence: NoteSequence
    public var sounds: [AgentSoundDraft]
    public static let maximumFileSize = 8 * 1024 * 1024
    public static let maximumNotes = 16_384

    public init(name: String = "Agent session", sequence: NoteSequence = NoteSequence(name: "Pattern"),
                sounds: [AgentSoundDraft] = []) {
        formatVersion = 1; self.name = name; self.sequence = sequence; self.sounds = sounds
    }

    public func validate() throws {
        guard formatVersion == 1 else { throw AgentError("Unsupported Digitone project version \(formatVersion).") }
        try Self.validateName(name)
        try Self.validate(sequence)
        guard sounds.count <= 256, Set(sounds.map(\.id)).count == sounds.count else {
            throw AgentError("Project must have at most 256 sounds with distinct IDs.")
        }
        try sounds.forEach { try $0.validate() }
    }

    public static func validate(_ sequence: NoteSequence) throws {
        try validateName(sequence.name)
        guard sequence.tempo.isFinite, (20...999).contains(sequence.tempo),
              (1...NoteSequence.maximumLength).contains(sequence.length),
              (1...32).contains(sequence.timeSignature.beats), [1, 2, 4, 8, 16, 32, 64].contains(sequence.timeSignature.unit),
              sequence.lanes.count <= 16, sequence.noteCount <= maximumNotes else {
            throw AgentError("Pattern needs tempo 20...999, valid time signature, at most 16 lanes and \(maximumNotes) notes, and a bounded loop length.")
        }
        guard Set(sequence.lanes.map(\.id)).count == sequence.lanes.count else { throw AgentError("Lane IDs must be distinct.") }
        let notes = sequence.lanes.flatMap(\.notes)
        guard Set(notes.map(\.id)).count == notes.count else { throw AgentError("Note IDs must be distinct.") }
        let tracks = sequence.lanes.compactMap(\.track)
        guard Set(tracks).count == tracks.count else { throw AgentError("Each Digitone track may have only one lane.") }
        for lane in sequence.lanes {
            try validateName(lane.name)
            guard (0..<16).contains(lane.channel), lane.track.map({ (0..<16).contains($0) }) ?? true else {
                throw AgentError("Lane track and channel must be in 1...16.")
            }
            for note in lane.notes {
                guard (0...127).contains(note.pitch), (1...127).contains(note.velocity),
                      (0..<sequence.length).contains(note.start), note.duration > 0,
                      note.duration <= NoteSequence.maximumLength - note.start else {
                    throw AgentError("Notes need pitch 0...127, velocity 1...127, a start inside the loop and a bounded positive duration.")
                }
            }
        }
    }

    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 256 else {
            throw AgentError("Name must contain 1...256 UTF-8 bytes.")
        }
    }

    public static func read(_ data: Data) throws -> AgentProject {
        guard data.count <= maximumFileSize else { throw AgentError("Project exceeds 8 MiB.") }
        let project = try JSONDecoder().decode(AgentProject.self, from: data)
        try project.validate()
        return project
    }

    public func data() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw AgentError("Project exceeds 8 MiB.") }
        return data
    }
}
