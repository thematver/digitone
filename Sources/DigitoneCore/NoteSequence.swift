import Foundation

/// Musical time is measured in ticks. 96 ticks per quarter note gives exactly
/// 24 ticks per 1/16 sequencer step, so one Digitone micro-timing unit
/// (1/384 of a whole note) is one tick.
public enum MusicalTime {
    public static let ticksPerQuarter = 96
    public static let ticksPerStep = 24
    public static let stepsPerBar = 16
    public static var ticksPerBar: Int { ticksPerStep * stepsPerBar }
}

public struct SequenceNote: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// MIDI note number, 0...127.
    public var pitch: Int
    /// MIDI velocity, 1...127.
    public var velocity: Int
    /// Start position in ticks from the beginning of the sequence.
    public var start: Int
    /// Duration in ticks, at least 1.
    public var duration: Int

    public init(id: UUID = UUID(), pitch: Int, velocity: Int = 100, start: Int, duration: Int) {
        self.id = id
        self.pitch = pitch
        self.velocity = velocity
        self.start = start
        self.duration = duration
    }

    public var end: Int {
        let result = start.addingReportingOverflow(duration)
        return result.overflow ? (duration >= 0 ? .max : .min) : result.partialValue
    }
}

/// One horizontal lane of notes, normally bound to one Digitone track.
public struct SequenceLane: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Digitone track index 0...15, or nil for a free lane (e.g. imported MIDI).
    public var track: Int?
    /// MIDI channel index 0...15 used for playback.
    public var channel: Int
    public var notes: [SequenceNote]
    public var isMuted: Bool

    public init(id: UUID = UUID(), name: String, track: Int? = nil, channel: Int,
                notes: [SequenceNote] = [], isMuted: Bool = false) {
        self.id = id
        self.name = name
        self.track = track
        self.channel = channel
        self.notes = notes
        self.isMuted = isMuted
    }
}

public struct TimeSignature: Codable, Hashable, Sendable {
    public var beats: Int
    public var unit: Int
    public init(beats: Int = 4, unit: Int = 4) { self.beats = beats; self.unit = unit }
}

/// The app's editable note data. Independent of the hardware pattern format:
/// a decoded Digitone pattern, a Standard MIDI File and a live recording all
/// become a NoteSequence.
public struct NoteSequence: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Beats per minute.
    public var tempo: Double
    public var timeSignature: TimeSignature
    /// Loop length in ticks.
    public var length: Int
    public var lanes: [SequenceLane]

    public init(id: UUID = UUID(), name: String, tempo: Double = 120, timeSignature: TimeSignature = TimeSignature(),
                length: Int = MusicalTime.ticksPerBar, lanes: [SequenceLane] = []) {
        self.id = id
        self.name = name
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.length = length
        self.lanes = lanes
    }

    public var noteCount: Int { lanes.reduce(0) { $0 + $1.notes.count } }
}
