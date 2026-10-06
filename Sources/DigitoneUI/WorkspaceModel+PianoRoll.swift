import Foundation
import DigitoneCore

/// Undoable piano-roll edits of the current lane.
extension WorkspaceModel {
    static let laneLimit = 16

    var laneNotes: [SequenceNote] { lane?.notes ?? [] }
    var selectedNotes: [SequenceNote] { laneNotes.filter { selection.contains($0.id) } }

    // MARK: History

    /// Replaces the sequence as one undoable step and selects `selecting`.
    func apply(_ next: NoteSequence, selecting: Set<UUID>? = nil) {
        guard next != sequence else {
            if let selecting { selection = selecting }
            return
        }
        history.record(sequence)
        sequence = next
        if let selecting { selection = selecting }
        reconcileSelection()
    }

    /// A file or pattern opened in place of the current sequence; undo brings the old one back.
    func replaceSequence(_ next: NoteSequence) {
        history.record(sequence)
        sequence = next
        laneIndex = 0
        selection = []
        roll.resetView()
    }

    /// Starts a drag: the state before it becomes one undo step.
    func beginGesture() { history.record(sequence) }

    /// Live drag update; not recorded separately.
    func updateGesture(_ next: NoteSequence) { if next != sequence { sequence = next } }

    func undo() {
        guard let previous = history.undo(from: sequence) else { return }
        sequence = previous
        reconcileSelection()
    }

    func redo() {
        guard let next = history.redo(from: sequence) else { return }
        sequence = next
        reconcileSelection()
    }

    private func reconcileSelection() {
        if !sequence.lanes.indices.contains(laneIndex) { laneIndex = max(0, sequence.lanes.count - 1) }
        let ids = Set(laneNotes.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
    }

    // MARK: Lanes

    /// Shows lane `index`, creating empty lanes up to it (track n on MIDI channel n).
    func selectLane(_ index: Int) {
        guard (0..<Self.laneLimit).contains(index) else { return }
        var next = sequence
        while next.lanes.count <= index {
            let number = next.lanes.count
            next.lanes.append(SequenceLane(name: "Track \(number + 1)", track: number, channel: number))
        }
        apply(next)
        if laneIndex != index { selection = [] }
        laneIndex = index
    }

    func addLane() { selectLane(sequence.lanes.count) }

    func setLaneChannel(_ channel: Int) {
        guard sequence.lanes.indices.contains(laneIndex), (0..<16).contains(channel) else { return }
        var next = sequence
        next.lanes[laneIndex].channel = channel
        apply(next)
    }

    // MARK: Selection

    func selectAll() { selection = Set(laneNotes.map(\.id)) }
    func deselectAll() { selection = [] }

    func deleteSelection() {
        guard !selection.isEmpty, sequence.lanes.indices.contains(laneIndex) else { return }
        var next = sequence
        next.lanes[laneIndex].notes.removeAll { selection.contains($0.id) }
        apply(next, selecting: [])
    }

    func deleteSelected() { deleteSelection() }

    func deleteNote(_ id: UUID) {
        guard sequence.lanes.indices.contains(laneIndex) else { return }
        var next = sequence
        next.lanes[laneIndex].notes.removeAll { $0.id == id }
        apply(next, selecting: selection.subtracting([id]))
    }

    func copySelection() {
        let notes = selectedNotes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        if !notes.isEmpty { clipboard = notes }
    }

    func cutSelection() { copySelection(); deleteSelection() }

    func paste(at tick: Int) {
        guard !clipboard.isEmpty else { return }
        let (next, ids) = PianoRollEdit.pasted(sequence, lane: laneIndex, notes: clipboard, at: max(0, tick))
        apply(next, selecting: ids)
    }

    func duplicateSelection(snap: PianoRollSnap) {
        guard !selection.isEmpty else { return }
        let (next, ids) = PianoRollEdit.duplicated(sequence, lane: laneIndex, ids: selection, snap: snap)
        apply(next, selecting: ids)
    }

    func transposeSelection(_ semitones: Int) {
        let notes = selectedNotes
        guard !notes.isEmpty else { return }
        let delta = PianoRollEdit.moveDelta(anchor: notes[0], rawTicks: 0, rawPitch: semitones, snap: .off,
                                            selection: notes, length: sequence.length)
        apply(PianoRollEdit.moved(sequence, lane: laneIndex, ids: selection, ticks: 0, pitch: delta.pitch))
    }

    func nudgeSelection(by ticks: Int) {
        let notes = selectedNotes
        guard let anchor = notes.min(by: { $0.start < $1.start }) else { return }
        let delta = PianoRollEdit.moveDelta(anchor: anchor, rawTicks: Double(ticks), rawPitch: 0, snap: .off,
                                            selection: notes, length: sequence.length)
        apply(PianoRollEdit.moved(sequence, lane: laneIndex, ids: selection, ticks: delta.ticks, pitch: 0))
    }

    /// Quantizes the selection, or the whole lane when nothing is selected.
    func quantizeSelection(grid: Int) {
        guard let lane, grid > 1 else { return }
        var next = sequence
        next.quantize(grid: grid, selection: NoteSelection(lanes: [lane.id], notes: selection.isEmpty ? nil : selection))
        apply(next)
    }

    // MARK: Notes

    @discardableResult
    func addNote(pitch: Int, start: Int, duration: Int, velocity: Int = 100) -> UUID? {
        guard sequence.lanes.indices.contains(laneIndex), (0..<sequence.length).contains(start) else { return nil }
        let note = SequenceNote(pitch: min(127, max(0, pitch)), velocity: min(127, max(1, velocity)), start: start,
                                duration: min(max(1, duration), NoteSequence.maximumLength - start))
        var next = sequence
        next.lanes[laneIndex].notes.append(note)
        apply(next, selecting: [note.id])
        return note.id
    }

    /// A recorded or step-input note into `lane`. `newStep` starts an undo step;
    /// later notes of the same take join it.
    func record(_ note: SequenceNote, lane index: Int, newStep: Bool = true) {
        let next = PianoRollEdit.merged(sequence, lane: index, note: note)
        if newStep { apply(next) } else { updateGesture(next) }
    }

    func setLoop(bars: Int) { apply(PianoRollEdit.withLoop(sequence, bars: bars)) }

    func setTempo(_ bpm: Double) {
        guard bpm.isFinite else { return }
        let value = min(999, max(20, bpm.rounded()))
        guard value != sequence.tempo else { return }
        sequence.tempo = value
    }
}
