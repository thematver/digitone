import Foundation

/// Which notes an edit applies to: optionally limited to some lanes and/or
/// some note IDs. The default selects every note.
public struct NoteSelection: Hashable, Sendable {
    public var lanes: Set<UUID>?
    public var notes: Set<UUID>?

    public init(lanes: Set<UUID>? = nil, notes: Set<UUID>? = nil) {
        self.lanes = lanes
        self.notes = notes
    }

    public static let all = NoteSelection()
    public static func lanes(_ ids: Set<UUID>) -> NoteSelection { NoteSelection(lanes: ids) }
    public static func notes(_ ids: Set<UUID>) -> NoteSelection { NoteSelection(notes: ids) }

    public func includes(lane: UUID) -> Bool { lanes?.contains(lane) ?? true }
    public func includes(note: UUID, inLane lane: UUID) -> Bool {
        includes(lane: lane) && (notes?.contains(note) ?? true)
    }
}

extension TimeSignature {
    /// Bar length in ticks; meaningful for power-of-two units up to 64.
    public var ticksPerBar: Int { max(1, min(255, max(0, beats)) * MusicalTime.ticksPerQuarter * 4 / min(64, max(1, unit))) }
}

extension SequenceLane {
    /// Lowest and highest pitch, or nil for an empty lane.
    public var pitchRange: ClosedRange<Int>? {
        guard let low = notes.map(\.pitch).min(), let high = notes.map(\.pitch).max() else { return nil }
        return low...high
    }
}

/// Deterministic value edits without I/O. Starts stay within [0, length),
/// pitches within 0...127, velocities within 1...127 and durations at least 1.
/// Notes are not re-sorted; callers needing order sort by `start`.
extension NoteSequence {
    /// The largest loop length `duplicateLoop` produces: 4096 bars of 4/4.
    public static let maximumLength = MusicalTime.ticksPerBar * 4096

    /// Notes whose [start, end) overlaps `ticks` and whose pitch lies in `pitches`.
    public func notes(in ticks: Range<Int>, pitches: ClosedRange<Int> = 0...127, selection: NoteSelection = .all) -> [SequenceNote] {
        lanes.flatMap { lane in
            lane.notes.filter {
                selection.includes(note: $0.id, inLane: lane.id) && pitches.contains($0.pitch)
                    && $0.start < ticks.upperBound && $0.end > ticks.lowerBound
            }
        }
    }

    /// Moves starts toward the nearest multiple of `grid` by `strength` (0...1).
    /// A note pulled onto the loop end wraps to the loop start.
    public mutating func quantize(grid: Int, strength: Double = 1, selection: NoteSelection = .all) {
        guard grid > 0, strength.isFinite else { return }
        let amount = min(1, max(0, strength))
        let length = Self.clamp(self.length, 1, Self.maximumLength)
        editNotes(selection) { note in
            let source = Self.clamp(note.start, 0, Self.maximumLength)
            let target = Int(min(Double(Self.maximumLength), (Double(source) / Double(grid)).rounded() * Double(grid)))
            var start = source + Int((Double(target - source) * amount).rounded())
            if note.start < length, start >= length { start -= length }
            note.start = max(0, start)
        }
    }

    public mutating func transpose(semitones: Int, selection: NoteSelection = .all) {
        editNotes(selection) { $0.pitch = Self.clamp(Self.add($0.pitch, semitones), 0, 127) }
    }

    /// Moves the selection as a block. The offsets shrink so that notes that
    /// were inside the loop and pitch range stay inside; returns the applied offsets.
    @discardableResult
    public mutating func move(ticks: Int, semitones: Int = 0, selection: NoteSelection = .all) -> (ticks: Int, semitones: Int) {
        let selected = notes(in: Int.min..<Int.max, selection: selection)
        let length = Self.clamp(self.length, 1, Self.maximumLength)
        let inside = selected.filter { (0..<length).contains($0.start) }
        var dt = ticks, dp = semitones
        if let first = inside.map(\.start).min(), let last = inside.map(\.start).max() {
            dt = Self.clamp(dt, -first, max(-first, length - 1 - last))
        }
        if let low = selected.map({ Self.clamp($0.pitch, 0, 127) }).min(), let high = selected.map({ Self.clamp($0.pitch, 0, 127) }).max() {
            dp = Self.clamp(dp, -low, max(-low, 127 - high))
        }
        editNotes(selection) { note in
            note.start = note.start < length ? Self.clamp(Self.add(note.start, dt), 0, length - 1) : Self.clamp(Self.add(note.start, dt), 0, Self.maximumLength)
            note.pitch = Self.clamp(Self.add(note.pitch, dp), 0, 127)
        }
        return (dt, dp)
    }

    /// Adds `ticks` to every selected duration, keeping at least one tick.
    public mutating func resize(by ticks: Int, selection: NoteSelection = .all) {
        editNotes(selection) { $0.duration = Self.clamp(Self.add($0.duration, ticks), 1, Self.maximumLength) }
    }

    public mutating func setDuration(_ ticks: Int, selection: NoteSelection = .all) {
        editNotes(selection) { $0.duration = Self.clamp(ticks, 1, Self.maximumLength) }
    }

    /// Changes the loop length. Unless `keepNotesBeyond` is set, notes starting
    /// at or after the new end are removed; notes crossing it keep their duration.
    public mutating func setLength(_ ticks: Int, keepNotesBeyond: Bool = false) {
        length = Self.clamp(ticks, 1, Self.maximumLength)
        guard !keepNotesBeyond else { return }
        for index in lanes.indices { lanes[index].notes.removeAll { $0.start >= length } }
    }

    /// Doubles the loop, copying the notes that start inside it with new IDs.
    /// Returns false when the result would exceed `maximumLength`.
    @discardableResult
    public mutating func duplicateLoop() -> Bool {
        guard length > 0, length <= Self.maximumLength / 2 else { return false }
        let offset = length
        for index in lanes.indices {
            let copies = lanes[index].notes.filter { (0..<offset).contains($0.start) }.map {
                SequenceNote(pitch: $0.pitch, velocity: $0.velocity, start: $0.start + offset, duration: $0.duration)
            }
            lanes[index].notes += copies
        }
        length *= 2
        return true
    }

    public mutating func scaleVelocity(by factor: Double, selection: NoteSelection = .all) {
        guard factor.isFinite else { return }
        editNotes(selection) { $0.velocity = Int(min(127, max(1, (Double($0.velocity) * factor).rounded()))) }
    }

    public mutating func setVelocity(_ velocity: Int, selection: NoteSelection = .all) {
        editNotes(selection) { $0.velocity = Self.clamp(velocity, 1, 127) }
    }

    /// Extends each selected note to the next later selected start in its lane
    /// (chord notes share one target); the last notes extend to the loop end.
    public mutating func legato(selection: NoteSelection = .all) {
        for index in lanes.indices where selection.includes(lane: lanes[index].id) {
            let laneID = lanes[index].id
            let starts = Set(lanes[index].notes.filter { selection.includes(note: $0.id, inLane: laneID) && (0..<max(1, length)).contains($0.start) }.map(\.start)).sorted()
            for noteIndex in lanes[index].notes.indices {
                let note = lanes[index].notes[noteIndex]
                guard selection.includes(note: note.id, inLane: laneID) else { continue }
                let next = Self.firstGreater(than: note.start, in: starts) ?? length
                if next > note.start {
                    let duration = next.subtractingReportingOverflow(note.start)
                    lanes[index].notes[noteIndex].duration = min(Self.maximumLength, duration.overflow ? Self.maximumLength : duration.partialValue)
                }
            }
        }
    }

    public mutating func foldToScale(_ scale: Scale, selection: NoteSelection = .all) {
        editNotes(selection) { $0.pitch = scale.fold($0.pitch) }
    }

    @discardableResult
    public mutating func removeNotes(selection: NoteSelection) -> Int {
        var removed = 0
        for index in lanes.indices where selection.includes(lane: lanes[index].id) {
            let laneID = lanes[index].id
            let before = lanes[index].notes.count
            lanes[index].notes.removeAll { selection.includes(note: $0.id, inLane: laneID) }
            removed += before - lanes[index].notes.count
        }
        return removed
    }

    private mutating func editNotes(_ selection: NoteSelection, _ edit: (inout SequenceNote) -> Void) {
        for index in lanes.indices where selection.includes(lane: lanes[index].id) {
            let laneID = lanes[index].id
            for noteIndex in lanes[index].notes.indices where selection.includes(note: lanes[index].notes[noteIndex].id, inLane: laneID) {
                edit(&lanes[index].notes[noteIndex])
            }
        }
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(high, max(low, value)) }

    private static func add(_ value: Int, _ offset: Int) -> Int {
        let result = value.addingReportingOverflow(offset)
        return result.overflow ? (offset >= 0 ? .max : .min) : result.partialValue
    }

    /// Binary search in ascending `values`.
    private static func firstGreater(than value: Int, in values: [Int]) -> Int? {
        var low = 0, high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] > value { high = middle } else { low = middle + 1 }
        }
        return low < values.count ? values[low] : nil
    }
}
