import Foundation

private let patternTrackCount = 16

extension PatternSnapshot {
    /// Converts the decoded pattern to an editable sequence with one lane per
    /// Digitone track (lane channel = track index, a playback default only:
    /// the real track channels are set on the instrument).
    ///
    /// A note starts at `step * 24 + microTiming`; micro-timing is clamped to
    /// the instrument's -23...23 and a note nudged before step 1 wraps to the
    /// end of its track, where the looping sequencer plays it. Steps at or
    /// beyond the track length are not played by the instrument and are
    /// dropped. Durations come from `NoteLength`; an INF note lasts until the
    /// next later note of its track, or the end of the track.
    ///
    /// The sequence length is the longest track. With `repeatingShorterTracks`
    /// shorter tracks (PER TRACK scale mode) repeat to fill it, as they loop on
    /// the instrument; otherwise each pattern note appears exactly once.
    /// Swing is not applied.
    public func noteSequence(repeatingShorterTracks: Bool = false) -> NoteSequence {
        let steps = (0..<patternTrackCount).map { track in
            trackLengths.indices.contains(track) ? min(128, max(1, trackLengths[track])) : MusicalTime.stepsPerBar
        }
        let length = (steps.max() ?? MusicalTime.stepsPerBar) * MusicalTime.ticksPerStep
        let lanes = (0..<patternTrackCount).map { track in
            let trackTicks = steps[track] * MusicalTime.ticksPerStep
            let placed = notes.filter { $0.track == track && (0..<steps[track]).contains($0.step) }.map { note in
                let micro = min(23, max(-23, note.microTiming))
                let start = (note.step * MusicalTime.ticksPerStep + micro + trackTicks) % trackTicks
                return (note: note, start: start)
            }
            let starts = Set(placed.map(\.start)).sorted()
            var laneNotes = placed.map { item in
                let duration = NoteLength.ticks(code: item.note.lengthCode)
                    ?? max(1, (starts.first { $0 > item.start } ?? trackTicks) - item.start)
                return SequenceNote(pitch: min(127, max(0, item.note.note)), velocity: min(127, max(1, item.note.velocity)),
                                    start: item.start, duration: duration)
            }
            if repeatingShorterTracks {
                let cycle = laneNotes
                for offset in stride(from: trackTicks, to: length, by: trackTicks) {
                    laneNotes += cycle.compactMap { note in
                        guard note.start + offset < length else { return nil }
                        return SequenceNote(pitch: note.pitch, velocity: note.velocity, start: note.start + offset, duration: note.duration)
                    }
                }
            }
            laneNotes.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
            return SequenceLane(name: laneName(track), track: track, channel: track, notes: laneNotes)
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        return NoteSequence(name: title.isEmpty ? Self.slotName(index) : title, tempo: tempo, length: length, lanes: lanes)
    }

    private func laneName(_ track: Int) -> String {
        let name = trackNames.indices.contains(track) ? trackNames[track].trimmingCharacters(in: .whitespaces) : ""
        return name.isEmpty ? "Трек \(track + 1)" : name
    }
}
