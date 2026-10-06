import Foundation
import DigitoneCore

/// Step editor commands reuse the piano roll's sequence and undo history.
extension WorkspaceModel {
    func toggleBeatStep(lane: Int, step: Int, pitch: Int, velocity: Int, duration: Int) {
        guard sequence.lanes.indices.contains(lane) else { return }
        selectLane(lane)
        var next = sequence
        let id = next.toggleStep(lane: lane, step: step, pitch: pitch, velocity: velocity, duration: duration)
        apply(next, selecting: id.map { [$0] } ?? [])
    }

    func selectBeatStep(lane: Int, step: Int) {
        selectLane(lane)
        selection = Set(sequence.notes(atStep: step, lane: lane).prefix(1).map(\.id))
    }

    func editBeatNote(_ id: UUID, pitch: Int? = nil, velocity: Int? = nil, duration: Int? = nil, recordHistory: Bool = true) {
        guard sequence.lanes.indices.contains(laneIndex),
              let index = sequence.lanes[laneIndex].notes.firstIndex(where: { $0.id == id }) else { return }
        var next = sequence
        if let pitch { next.lanes[laneIndex].notes[index].pitch = min(127, max(0, pitch)) }
        if let velocity { next.lanes[laneIndex].notes[index].velocity = min(127, max(1, velocity)) }
        if let duration {
            next.lanes[laneIndex].notes[index].duration = min(NoteSequence.maximumLength - next.lanes[laneIndex].notes[index].start, max(1, duration))
        }
        if recordHistory { apply(next) } else { updateGesture(next) }
    }

    func setBeatLength(steps: Int) {
        var next = sequence
        next.setLength(min(128, max(1, steps)) * MusicalTime.ticksPerStep)
        apply(next)
    }

    func duplicateBeat() {
        var next = sequence
        guard next.duplicateLoop() else { return }
        apply(next)
    }

    func setBeatLaneName(_ name: String) {
        guard sequence.lanes.indices.contains(laneIndex) else { return }
        var next = sequence
        next.lanes[laneIndex].name = name
        apply(next)
    }

    func setBeatLaneTrack(_ track: Int?) {
        guard sequence.lanes.indices.contains(laneIndex), track.map({ (0..<16).contains($0) }) ?? true else { return }
        var next = sequence
        next.lanes[laneIndex].track = track
        apply(next)
    }

    func toggleBeatMute(_ lane: Int) {
        guard sequence.lanes.indices.contains(lane) else { return }
        var next = sequence
        next.lanes[lane].isMuted.toggle()
        apply(next)
    }

    func clearBeat(allLanes: Bool = false) {
        var next = sequence
        if allLanes {
            for index in next.lanes.indices { next.lanes[index].notes = [] }
        } else if next.lanes.indices.contains(laneIndex) {
            next.lanes[laneIndex].notes = []
        }
        apply(next, selecting: [])
    }

    func addBeatLane(_ role: BeatRole? = nil) {
        guard sequence.lanes.count < Self.laneLimit else { return }
        var next = sequence
        let usedTracks = Set(next.lanes.compactMap(\.track))
        let usedChannels = Set(next.lanes.map(\.channel))
        let index = next.lanes.count
        let track = (0..<16).first { !usedTracks.contains($0) } ?? index
        let channel = (0..<16).first { !usedChannels.contains($0) } ?? track
        next.lanes.append(SequenceLane(name: role?.name ?? "Track \(track + 1)", track: track, channel: channel))
        apply(next, selecting: [])
        laneIndex = index
    }

    func fillBeatLane(_ role: BeatRole, preset: BeatPreset = .house) {
        guard sequence.lanes.indices.contains(laneIndex) else { return }
        apply(BeatSequence.fill(role, in: sequence, lane: laneIndex, preset: preset), selecting: [])
    }
}
