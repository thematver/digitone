import Foundation
import DigitoneCore
import DigitoneMIDI

/// Live recording while the sequence plays: converts note host times to loop
/// ticks using the last observed playhead, then quantizes on note-off.
struct PianoRollRecorder: Equatable {
    struct Pending: Equatable {
        var channel: Int
        var pitch: Int
        var velocity: Int
        var hostTime: UInt64
        /// Loop tick of the note-on, unquantized.
        var tick: Double
        /// Unwrapped transport tick, including any tempo changes while held.
        var absoluteTick: Double
    }

    private(set) var anchorTick: Double = 0
    private(set) var anchorHostTime: UInt64 = 0
    private(set) var bpm: Double = 120
    private(set) var length = MusicalTime.ticksPerBar
    private(set) var pending: [Int: Pending] = [:]
    private var absoluteAnchor: Double = 0
    private var hasAnchor = false

    var ticksPerSecond: Double { bpm / 60 * Double(MusicalTime.ticksPerQuarter) }

    /// Called with every playhead update: `playhead` is the loop tick at `hostTime`.
    mutating func sync(playhead: Double, at hostTime: UInt64, bpm: Double, length: Int) {
        absoluteAnchor = hasAnchor ? absoluteTick(at: hostTime) : (playhead.isFinite ? playhead : 0)
        hasAnchor = true
        anchorTick = playhead.isFinite ? playhead : 0
        anchorHostTime = hostTime
        self.bpm = bpm.isFinite && bpm > 0 ? bpm : 120
        self.length = max(1, length)
    }

    /// Loop tick at a host time, wrapped into 0..<length.
    func tick(at hostTime: UInt64) -> Double {
        let raw = anchorTick + HostClock.seconds(from: anchorHostTime, to: hostTime) * ticksPerSecond
        let wrapped = raw.truncatingRemainder(dividingBy: Double(length))
        return wrapped < 0 ? wrapped + Double(length) : wrapped
    }

    static func key(channel: Int, pitch: Int) -> Int { channel * 128 + pitch }

    private func absoluteTick(at hostTime: UInt64) -> Double {
        absoluteAnchor + HostClock.seconds(from: anchorHostTime, to: hostTime) * ticksPerSecond
    }

    mutating func noteOn(pitch: Int, velocity: Int, at hostTime: UInt64, channel: Int = 0) {
        let key = Self.key(channel: channel, pitch: pitch)
        pending[key] = Pending(channel: channel, pitch: pitch, velocity: min(127, max(1, velocity)), hostTime: hostTime,
                               tick: tick(at: hostTime), absoluteTick: absoluteTick(at: hostTime))
    }

    /// The finished note, quantized to `grid`; nil for an unknown pitch.
    mutating func noteOff(pitch: Int, at hostTime: UInt64, grid: Int, channel: Int = 0) -> SequenceNote? {
        guard let started = pending.removeValue(forKey: Self.key(channel: channel, pitch: pitch)) else { return nil }
        let duration = max(0, absoluteTick(at: hostTime) - started.absoluteTick)
        let placed = Self.quantized(start: started.tick, duration: duration, grid: grid, length: length)
        return SequenceNote(pitch: started.pitch, velocity: started.velocity, start: placed.start, duration: placed.duration)
    }

    /// Ends every held note, e.g. when playback stops.
    mutating func flush(at hostTime: UInt64, grid: Int) -> [SequenceNote] {
        pending.values.sorted { ($0.channel, $0.pitch) < ($1.channel, $1.pitch) }
            .compactMap { noteOff(pitch: $0.pitch, at: hostTime, grid: grid, channel: $0.channel) }
    }

    /// Start rounds to the nearest grid line (a note pulled onto the loop end
    /// wraps to the start); duration rounds to whole grids, at least one.
    static func quantized(start: Double, duration: Double, grid: Int, length: Int) -> (start: Int, duration: Int) {
        let grid = max(1, grid), length = max(1, length)
        var tick = Int((start / Double(grid)).rounded()) * grid
        if tick >= length { tick -= length }
        tick = min(length - 1, max(0, tick))
        let ticks = grid > 1 ? max(grid, Int((duration / Double(grid)).rounded()) * grid) : max(1, Int(duration.rounded()))
        return (tick, min(ticks, NoteSequence.maximumLength - tick))
    }
}

/// Step input while stopped: notes go to the insertion cursor; the cursor
/// advances one step once every key of a chord is released.
struct StepInput: Equatable {
    var cursor = 0
    private(set) var held: Set<Int> = []
    private(set) var chordTick: Int?

    /// The tick for a newly pressed pitch; keys pressed together share it.
    mutating func press(_ pitch: Int) -> Int {
        if held.isEmpty || chordTick == nil { chordTick = cursor }
        held.insert(pitch)
        return chordTick ?? cursor
    }

    /// Returns true when the chord ended and the cursor moved on.
    @discardableResult
    mutating func release(_ pitch: Int, step: Int) -> Bool {
        guard held.remove(pitch) != nil else { return false }
        guard held.isEmpty else { return false }
        cursor = (chordTick ?? cursor) + max(1, step)
        chordTick = nil
        return true
    }

    mutating func reset(to tick: Int) {
        cursor = max(0, tick); held.removeAll(); chordTick = nil
    }

    mutating func releaseAll(step: Int) {
        guard !held.isEmpty else { return }
        cursor = (chordTick ?? cursor) + max(1, step)
        held.removeAll(); chordTick = nil
    }
}

enum PianoRollRouting {
    /// The lane a note arriving on `channel` belongs to: the current lane when
    /// its channel matches, else the first lane on that channel, else the current
    /// lane (the Digitone's auto channel plays whatever track is active).
    static func lane(forChannel channel: Int, lanes: [SequenceLane], current: Int) -> Int {
        if lanes.indices.contains(current), lanes[current].channel == channel { return current }
        return lanes.firstIndex { $0.channel == channel } ?? current
    }

    /// Pitches the playhead is sounding in a lane.
    static func sounding(_ notes: [SequenceNote], at tick: Double) -> Set<Int> {
        Set(notes.filter { Double($0.start) <= tick && tick < Double($0.end) }.map(\.pitch))
    }
}
