import Foundation
import DigitoneCore

/// Pure piano-roll edits on one lane of a sequence. Every function returns a
/// new sequence; drags recompute from the state captured at mouse-down so a
/// gesture never accumulates rounding. Starts stay inside the loop, pitches
/// in 0...127, velocities in 1...127 and durations at least one tick.
enum PianoRollEdit {
    /// The longest loop the roll grows to by itself (duplicate, paste, step input).
    static let maximumBars = 128
    static func maximumLoopTicks(_ sequence: NoteSequence) -> Int {
        min(NoteSequence.maximumLength, maximumBars * sequence.barTicks)
    }

    // MARK: Move and copy

    /// Snapped offsets for dragging `anchor` by a raw amount: the anchor's start
    /// lands on the grid (Logic-style absolute snap) and the whole selection
    /// keeps inside the loop and the MIDI range.
    static func moveDelta(anchor: SequenceNote, rawTicks: Double, rawPitch: Int, snap: PianoRollSnap,
                          selection: [SequenceNote], length: Int) -> (ticks: Int, pitch: Int) {
        var ticks = snap.round(Double(anchor.start) + rawTicks) - anchor.start
        if let first = selection.map(\.start).min(), let last = selection.map(\.start).max() {
            ticks = min(max(ticks, -first), max(-first, length - 1 - last))
        }
        var pitch = rawPitch
        if let low = selection.map(\.pitch).min(), let high = selection.map(\.pitch).max() {
            pitch = min(max(pitch, -low), 127 - high)
        }
        return (ticks, pitch)
    }

    /// Moves `ids` by the offsets. With `copies` (original → new ID) the
    /// originals stay and moved copies are added instead.
    static func moved(_ sequence: NoteSequence, lane: Int, ids: Set<UUID>, ticks: Int, pitch: Int,
                      copies: [UUID: UUID]? = nil) -> NoteSequence {
        guard sequence.lanes.indices.contains(lane) else { return sequence }
        var result = sequence
        let length = max(1, sequence.length)
        func shifted(_ note: SequenceNote, id: UUID) -> SequenceNote {
            var copy = note
            copy.id = id
            copy.start = min(length - 1, max(0, note.start + ticks))
            copy.pitch = min(127, max(0, note.pitch + pitch))
            copy.duration = min(copy.duration, NoteSequence.maximumLength - copy.start)
            return copy
        }
        if let copies {
            let added = sequence.lanes[lane].notes.compactMap { note in copies[note.id].map { shifted(note, id: $0) } }
            result.lanes[lane].notes += added
        } else {
            result.lanes[lane].notes = sequence.lanes[lane].notes.map { ids.contains($0.id) ? shifted($0, id: $0.id) : $0 }
        }
        return result
    }

    // MARK: Resize

    /// Snapped duration change for dragging the anchor's right edge: its end
    /// lands on the grid; every selected note keeps at least one grid (or tick).
    static func resizeDelta(anchor: SequenceNote, rawTicks: Double, snap: PianoRollSnap, selection: [SequenceNote]) -> Int {
        let minimum = max(1, snap.grid)
        var delta = snap.round(Double(anchor.end) + rawTicks) - anchor.end
        let shortest = selection.map(\.duration).min() ?? anchor.duration
        delta = max(delta, min(0, minimum - shortest))
        return delta
    }

    static func resized(_ sequence: NoteSequence, lane: Int, ids: Set<UUID>, by delta: Int) -> NoteSequence {
        guard sequence.lanes.indices.contains(lane) else { return sequence }
        var result = sequence
        for index in result.lanes[lane].notes.indices where ids.contains(result.lanes[lane].notes[index].id) {
            let note = result.lanes[lane].notes[index]
            result.lanes[lane].notes[index].duration = min(NoteSequence.maximumLength - note.start, max(1, note.duration + delta))
        }
        return result
    }

    // MARK: Velocity

    /// Sets the anchor's velocity to `value` and offsets the other `originals` by the same amount.
    static func withVelocity(_ sequence: NoteSequence, lane: Int, originals: [UUID: Int], anchor: UUID, value: Int) -> NoteSequence {
        guard sequence.lanes.indices.contains(lane), let base = originals[anchor] else { return sequence }
        let delta = min(127, max(1, value)) - base
        var result = sequence
        for index in result.lanes[lane].notes.indices {
            guard let original = originals[result.lanes[lane].notes[index].id] else { continue }
            result.lanes[lane].notes[index].velocity = min(127, max(1, original + delta))
        }
        return result
    }

    // MARK: Insert

    /// Places `notes` (positions relative to their earliest start) at `tick`
    /// with new IDs, growing the loop by whole bars when needed.
    static func pasted(_ sequence: NoteSequence, lane: Int, notes: [SequenceNote], at tick: Int) -> (NoteSequence, Set<UUID>) {
        guard sequence.lanes.indices.contains(lane), let first = notes.map(\.start).min() else { return (sequence, []) }
        var result = sequence
        var ids = Set<UUID>()
        let maximum = maximumLoopTicks(sequence)
        for note in notes {
            let start = max(0, tick + note.start - first)
            guard start < maximum else { continue }
            let copy = SequenceNote(pitch: note.pitch, velocity: note.velocity, start: start,
                                    duration: min(note.duration, NoteSequence.maximumLength - start))
            result.lanes[lane].notes.append(copy)
            ids.insert(copy.id)
        }
        growLoop(&result, toInclude: result.lanes[lane].notes.filter { ids.contains($0.id) }.map(\.start).max())
        return (result, ids)
    }

    /// Repeats the selection right after itself (Logic ⌘D): the offset is the
    /// selection span rounded up to the grid.
    static func duplicated(_ sequence: NoteSequence, lane: Int, ids: Set<UUID>, snap: PianoRollSnap) -> (NoteSequence, Set<UUID>) {
        guard sequence.lanes.indices.contains(lane) else { return (sequence, []) }
        let selected = sequence.lanes[lane].notes.filter { ids.contains($0.id) }
        guard let first = selected.map(\.start).min(), let last = selected.map(\.end).max() else { return (sequence, []) }
        let span = max(1, last - first)
        let offset = (span + snap.grid - 1) / snap.grid * snap.grid
        return pasted(sequence, lane: lane, notes: selected, at: first + offset)
    }

    /// Adds a recorded or step-input note. A note already at the same pitch and
    /// start is replaced (overdub without stacking duplicates).
    static func merged(_ sequence: NoteSequence, lane: Int, note: SequenceNote) -> NoteSequence {
        guard sequence.lanes.indices.contains(lane), (0..<maximumLoopTicks(sequence)).contains(note.start) else { return sequence }
        var result = sequence
        result.lanes[lane].notes.removeAll { $0.pitch == note.pitch && $0.start == note.start }
        result.lanes[lane].notes.append(note)
        growLoop(&result, toInclude: note.start)
        return result
    }

    /// Sets the loop to whole bars; notes starting after the new end are removed.
    static func withLoop(_ sequence: NoteSequence, bars: Int) -> NoteSequence {
        var result = sequence
        result.setLength(min(maximumBars, max(1, bars)) * sequence.barTicks)
        return result
    }

    static func growLoop(_ sequence: inout NoteSequence, toInclude start: Int?) {
        guard let start, start >= sequence.length else { return }
        let bars = min(maximumBars, start / sequence.barTicks + 1)
        sequence.length = min(NoteSequence.maximumLength, max(sequence.length, bars * sequence.barTicks))
    }
}

/// Snapshot undo stack of the sequence (Logic ⌘Z / ⌘⇧Z).
struct PianoRollHistory {
    static let limit = 200
    private(set) var undoStack: [NoteSequence] = []
    private(set) var redoStack: [NoteSequence] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the state before an edit and clears the redo branch.
    mutating func record(_ state: NoteSequence) {
        if undoStack.last != state { undoStack.append(state) }
        if undoStack.count > Self.limit { undoStack.removeFirst(undoStack.count - Self.limit) }
        redoStack.removeAll()
    }

    mutating func undo(from current: NoteSequence) -> NoteSequence? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(from current: NoteSequence) -> NoteSequence? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
