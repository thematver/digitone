import Foundation

/// Suggested musical roles. Digitone plays the sound already assigned to the
/// lane's MIDI channel; these names do not imply a General MIDI drum kit.
public enum BeatRole: String, CaseIterable, Codable, Sendable {
    case kick, snare, hat, bass

    public var name: String {
        switch self { case .kick: "Kick"; case .snare: "Snare"; case .hat: "Hat"; case .bass: "Bass" }
    }
    public var pitch: Int {
        switch self { case .kick: 36; case .snare: 38; case .hat: 42; case .bass: 36 }
    }
    public var velocity: Int {
        switch self { case .kick: 112; case .snare: 102; case .hat: 74; case .bass: 96 }
    }
    public var duration: Int {
        switch self { case .kick, .snare: 12; case .hat: 6; case .bass: 42 }
    }
}

public enum BeatPreset: String, CaseIterable, Codable, Sendable {
    case house, breakbeat, minimal

    public var name: String {
        switch self { case .house: "House"; case .breakbeat: "Breakbeat"; case .minimal: "Minimal" }
    }
    public var tempo: Double {
        switch self { case .house: 124; case .breakbeat: 132; case .minimal: 116 }
    }
}

/// Local, editable beat drafts, shared by the step editor and agent tools.
public enum BeatSequence {
    public static func empty(name: String = "Новый паттерн", steps: Int = 16, tempo: Double = 120) -> NoteSequence {
        let count = min(128, max(1, steps))
        let bpm = tempo.isFinite ? min(999, max(20, tempo)) : 120
        return NoteSequence(name: name, tempo: bpm, length: count * MusicalTime.ticksPerStep,
                            lanes: BeatRole.allCases.enumerated().map {
            SequenceLane(name: $0.element.name, track: $0.offset, channel: $0.offset)
        })
    }

    public static func make(_ preset: BeatPreset, steps: Int = 16, tempo: Double? = nil) -> NoteSequence {
        var sequence = empty(name: preset.name, steps: steps, tempo: tempo ?? preset.tempo)
        for lane in sequence.lanes.indices {
            let role = BeatRole.allCases[lane]
            for step in 0..<sequence.stepCount {
                let position = step % 16
                guard let hit = hit(preset, role: role, step: position) else { continue }
                sequence.lanes[lane].notes.append(SequenceNote(pitch: role.pitch + hit.transpose,
                    velocity: hit.velocity, start: step * MusicalTime.ticksPerStep, duration: role.duration))
            }
        }
        return sequence
    }

    /// Adds a role's notes to an existing lane, preserving its mapping and name.
    /// Other lanes are untouched. Used for quick fills as one undoable edit.
    public static func fill(_ role: BeatRole, in sequence: NoteSequence, lane: Int, preset: BeatPreset = .house) -> NoteSequence {
        guard sequence.lanes.indices.contains(lane) else { return sequence }
        var result = sequence
        result.lanes[lane].notes = (0..<sequence.stepCount).compactMap { step in
            guard let hit = hit(preset, role: role, step: step % 16) else { return nil }
            return SequenceNote(pitch: role.pitch + hit.transpose, velocity: hit.velocity,
                                start: step * MusicalTime.ticksPerStep, duration: role.duration)
        }
        return result
    }

    private static func hit(_ preset: BeatPreset, role: BeatRole, step: Int) -> (velocity: Int, transpose: Int)? {
        let positions: [Int]
        switch (preset, role) {
        case (.house, .kick): positions = [0, 4, 8, 12]
        case (.house, .snare), (.breakbeat, .snare): positions = [4, 12]
        case (.house, .hat): positions = [2, 6, 10, 14]
        case (.house, .bass): positions = [0, 3, 6, 8, 11, 14]
        case (.breakbeat, .kick): positions = [0, 6, 10]
        case (.breakbeat, .hat): positions = [0, 2, 4, 6, 8, 10, 12, 14, 15]
        case (.breakbeat, .bass): positions = [0, 6, 8, 10, 14]
        case (.minimal, .kick): positions = [0, 8, 11]
        case (.minimal, .snare): positions = [4, 12]
        case (.minimal, .hat): positions = [2, 7, 10, 14]
        case (.minimal, .bass): positions = [0, 7, 10]
        }
        guard positions.contains(step) else { return nil }
        let velocity = role == .hat ? (step % 4 == 2 ? 86 : 58) : role.velocity
        let transpose = role == .bass ? (step >= 8 ? (step == 14 ? 10 : 7) : 0) : 0
        return (velocity, transpose)
    }
}

extension NoteSequence {
    /// Number of 1/16 cells needed to show the loop, including a partial cell.
    public var stepCount: Int {
        let ticks = min(Self.maximumLength, max(1, length))
        return (ticks - 1) / MusicalTime.ticksPerStep + 1
    }

    /// Notes starting in this cell. A sustained note occupies just its onset
    /// cell, and imported micro-timing and chords remain visible and editable.
    public func notes(atStep step: Int, lane: Int) -> [SequenceNote] {
        guard length > 0, length <= Self.maximumLength, lanes.indices.contains(lane), (0..<stepCount).contains(step) else { return [] }
        let tick = step * MusicalTime.ticksPerStep
        return lanes[lane].notes.filter { (tick..<min(length, tick + MusicalTime.ticksPerStep)).contains($0.start) }
            .sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    /// Toggles a cell as a group. Turning it off removes only onsets in that
    /// cell; neighboring sustained notes and notes in other lanes are kept.
    /// Returns the newly inserted note ID, or nil when the cell was removed.
    @discardableResult
    public mutating func toggleStep(lane: Int, step: Int, pitch: Int = 36, velocity: Int = 100,
                                    duration: Int = MusicalTime.ticksPerStep) -> UUID? {
        guard length > 0, length <= Self.maximumLength, lanes.indices.contains(lane), (0..<stepCount).contains(step) else { return nil }
        let tick = step * MusicalTime.ticksPerStep
        let upper = min(length, tick + MusicalTime.ticksPerStep)
        let existing = notes(atStep: step, lane: lane)
        if !existing.isEmpty {
            lanes[lane].notes.removeAll { (tick..<upper).contains($0.start) }
            return nil
        }
        let note = SequenceNote(pitch: min(127, max(0, pitch)), velocity: min(127, max(1, velocity)), start: tick,
                                duration: min(Self.maximumLength - tick, max(1, duration)))
        lanes[lane].notes.append(note)
        lanes[lane].notes.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        return note.id
    }
}
