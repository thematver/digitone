import XCTest
import DigitoneCore
@testable import DigitoneUI

final class PianoRollEditingTests: XCTestCase {
    private let a = SequenceNote(pitch: 60, velocity: 100, start: 0, duration: 24)
    private let b = SequenceNote(pitch: 64, velocity: 80, start: 48, duration: 48)
    private let c = SequenceNote(pitch: 67, velocity: 60, start: 120, duration: 12)

    private func sequence(length: Int = 384) -> NoteSequence {
        NoteSequence(name: "Test", length: length, lanes: [
            SequenceLane(name: "Lead", track: 0, channel: 0, notes: [a, b, c]),
            SequenceLane(name: "Bass", track: 1, channel: 1, notes: [SequenceNote(pitch: 36, start: 0, duration: 96)])
        ])
    }

    private func note(_ id: UUID, in sequence: NoteSequence, lane: Int = 0) -> SequenceNote? {
        sequence.lanes[lane].notes.first { $0.id == id }
    }

    func testMoveSnapsTheAnchorStartAndKeepsTheSelectionInside() {
        // 30 raw ticks from start 48 lands on 72 with a 1/16 grid.
        var delta = PianoRollEdit.moveDelta(anchor: b, rawTicks: 30, rawPitch: 2, snap: .sixteenth, selection: [a, b], length: 384)
        XCTAssertEqual(delta.ticks, 24); XCTAssertEqual(delta.pitch, 2)
        // An unsnapped anchor snaps absolutely: start 120 + 5 → 120 (nearest 1/16).
        delta = PianoRollEdit.moveDelta(anchor: c, rawTicks: 5, rawPitch: 0, snap: .sixteenth, selection: [c], length: 384)
        XCTAssertEqual(delta.ticks, 0)
        delta = PianoRollEdit.moveDelta(anchor: c, rawTicks: 5, rawPitch: 0, snap: .off, selection: [c], length: 384)
        XCTAssertEqual(delta.ticks, 5)
        // Clamped at the loop start, loop end and MIDI range.
        delta = PianoRollEdit.moveDelta(anchor: b, rawTicks: -500, rawPitch: -100, snap: .sixteenth, selection: [a, b], length: 384)
        XCTAssertEqual(delta.ticks, 0); XCTAssertEqual(delta.pitch, -60)
        delta = PianoRollEdit.moveDelta(anchor: a, rawTicks: 1000, rawPitch: 100, snap: .sixteenth, selection: [a, b], length: 384)
        XCTAssertEqual(delta.ticks, 335); XCTAssertEqual(delta.pitch, 63)
    }

    func testMovedChangesOnlySelectedNotesOfTheLane() {
        let original = sequence()
        let moved = PianoRollEdit.moved(original, lane: 0, ids: [a.id, b.id], ticks: 24, pitch: -1)
        XCTAssertEqual(note(a.id, in: moved)?.start, 24)
        XCTAssertEqual(note(a.id, in: moved)?.pitch, 59)
        XCTAssertEqual(note(b.id, in: moved)?.start, 72)
        XCTAssertEqual(note(c.id, in: moved), c)
        XCTAssertEqual(moved.lanes[1], original.lanes[1])
    }

    func testOptionDragCopiesAndLeavesOriginals() {
        let copies = [a.id: UUID(), b.id: UUID()]
        let copied = PianoRollEdit.moved(sequence(), lane: 0, ids: [a.id, b.id], ticks: 96, pitch: 12, copies: copies)
        XCTAssertEqual(copied.lanes[0].notes.count, 5)
        XCTAssertEqual(note(a.id, in: copied), a)
        XCTAssertEqual(note(b.id, in: copied), b)
        let copyA = try? XCTUnwrap(note(copies[a.id]!, in: copied))
        XCTAssertEqual(copyA?.start, 96); XCTAssertEqual(copyA?.pitch, 72); XCTAssertEqual(copyA?.velocity, 100)
        XCTAssertEqual(note(copies[b.id]!, in: copied)?.start, 144)
        // Recomputing from the same original keeps the copy IDs stable during a drag.
        let again = PianoRollEdit.moved(sequence(), lane: 0, ids: [a.id, b.id], ticks: 120, pitch: 12, copies: copies)
        XCTAssertEqual(note(copies[a.id]!, in: again)?.start, 120)
    }

    func testResizeSnapsTheEndAndKeepsAMinimumLength() {
        // b ends at 96; +20 raw → 120 (nearest 1/16 to 116).
        XCTAssertEqual(PianoRollEdit.resizeDelta(anchor: b, rawTicks: 20, snap: .sixteenth, selection: [b]), 24)
        // Shrinking stops at one grid for the shortest selected note.
        XCTAssertEqual(PianoRollEdit.resizeDelta(anchor: b, rawTicks: -200, snap: .sixteenth, selection: [a, b]), 0)
        XCTAssertEqual(PianoRollEdit.resizeDelta(anchor: b, rawTicks: -200, snap: .sixteenth, selection: [b]), -24)
        XCTAssertEqual(PianoRollEdit.resizeDelta(anchor: c, rawTicks: -200, snap: .off, selection: [c]), -11)
        let resized = PianoRollEdit.resized(sequence(), lane: 0, ids: [a.id, b.id], by: 24)
        XCTAssertEqual(note(a.id, in: resized)?.duration, 48)
        XCTAssertEqual(note(b.id, in: resized)?.duration, 72)
        XCTAssertEqual(note(c.id, in: resized)?.duration, 12)
    }

    func testVelocityDragOffsetsTheSelectionRelativeToTheAnchor() {
        let originals = [a.id: 100, b.id: 80]
        var edited = PianoRollEdit.withVelocity(sequence(), lane: 0, originals: originals, anchor: b.id, value: 110)
        XCTAssertEqual(note(b.id, in: edited)?.velocity, 110)
        XCTAssertEqual(note(a.id, in: edited)?.velocity, 127, "clamped")
        XCTAssertEqual(note(c.id, in: edited)?.velocity, 60, "not selected")
        edited = PianoRollEdit.withVelocity(sequence(), lane: 0, originals: originals, anchor: a.id, value: -5)
        XCTAssertEqual(note(a.id, in: edited)?.velocity, 1)
        XCTAssertEqual(note(b.id, in: edited)?.velocity, 1)
    }

    func testPasteAndDuplicateGrowTheLoopByWholeBars() {
        let (pasted, ids) = PianoRollEdit.pasted(sequence(), lane: 0, notes: [b, a], at: 360)
        XCTAssertEqual(ids.count, 2)
        let placed = pasted.lanes[0].notes.filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
        XCTAssertEqual(placed.map(\.start), [360, 408])
        XCTAssertEqual(placed.map(\.pitch), [60, 64])
        XCTAssertEqual(pasted.length, 768)
        // ⌘D repeats right after the selection span (0...96 → +96).
        let (duplicated, copies) = PianoRollEdit.duplicated(sequence(), lane: 0, ids: [a.id, b.id], snap: .sixteenth)
        XCTAssertEqual(duplicated.lanes[0].notes.filter { copies.contains($0.id) }.map(\.start).sorted(), [96, 144])
        XCTAssertEqual(duplicated.length, 384)
        // A one-tick-off span rounds up to the grid.
        let (odd, oddIDs) = PianoRollEdit.duplicated(sequence(), lane: 0, ids: [c.id], snap: .sixteenth)
        XCTAssertEqual(odd.lanes[0].notes.first { oddIDs.contains($0.id) }?.start, 144)
    }

    func testMergeReplacesTheSameStepInsteadOfStacking() {
        var merged = PianoRollEdit.merged(sequence(), lane: 0, note: SequenceNote(pitch: 60, velocity: 30, start: 0, duration: 96))
        XCTAssertEqual(merged.lanes[0].notes.count, 3)
        XCTAssertEqual(merged.lanes[0].notes.first { $0.pitch == 60 }?.velocity, 30)
        merged = PianoRollEdit.merged(merged, lane: 0, note: SequenceNote(pitch: 72, start: 400, duration: 24))
        XCTAssertEqual(merged.length, 768)
        XCTAssertEqual(merged.lanes[0].notes.count, 4)
    }

    func testLoopLengthInBarsDropsNotesBeyondTheEnd() {
        var long = sequence(length: 768)
        long.lanes[0].notes.append(SequenceNote(pitch: 50, start: 500, duration: 24))
        let short = PianoRollEdit.withLoop(long, bars: 1)
        XCTAssertEqual(short.length, 384)
        XCTAssertEqual(short.lanes[0].notes.count, 3)
        XCTAssertEqual(PianoRollEdit.withLoop(long, bars: 0).length, 384)
        XCTAssertEqual(PianoRollEdit.withLoop(long, bars: 999).length, PianoRollEdit.maximumBars * 384)
    }

    func testUndoStackKeepsAtLeastAHundredLevelsAndClearsRedoOnEdit() {
        var history = PianoRollHistory()
        XCTAssertGreaterThanOrEqual(PianoRollHistory.limit, 100)
        var current = sequence()
        for step in 0..<(PianoRollHistory.limit + 30) {
            history.record(current)
            current.tempo = Double(21 + step)
        }
        XCTAssertEqual(history.undoStack.count, PianoRollHistory.limit)
        var undone = 0
        while let previous = history.undo(from: current) { current = previous; undone += 1 }
        XCTAssertEqual(undone, PianoRollHistory.limit)
        XCTAssertEqual(current.tempo, 50, "the oldest 30 states fell off")
        XCTAssertTrue(history.canRedo)
        let redone = history.redo(from: current)
        XCTAssertEqual(redone?.tempo, 51)
        history.record(redone!)
        XCTAssertFalse(history.canRedo)
        // Recording the same state twice adds one step.
        var fresh = PianoRollHistory()
        fresh.record(current); fresh.record(current)
        XCTAssertEqual(fresh.undoStack.count, 1)
    }
    func testAutomaticLoopGrowthRespectsTheStorageLimitInUnusualMeters() {
        var long = sequence()
        long.timeSignature = TimeSignature(beats: 255, unit: 1)
        let start = NoteSequence.maximumLength - 1
        let source = SequenceNote(pitch: 60, start: 0, duration: 24)
        let (pasted, ids) = PianoRollEdit.pasted(long, lane: 0, notes: [source], at: start)
        XCTAssertEqual(pasted.length, NoteSequence.maximumLength)
        let placed = pasted.lanes[0].notes.first { ids.contains($0.id) }
        XCTAssertEqual(placed?.start, start)
        XCTAssertEqual(placed?.duration, 1)
        let (beyond, skipped) = PianoRollEdit.pasted(long, lane: 0, notes: [source], at: NoteSequence.maximumLength)
        XCTAssertEqual(beyond, long)
        XCTAssertTrue(skipped.isEmpty)
    }

}
