import XCTest
@testable import DigitoneCore

final class NoteSequenceEditingTests: XCTestCase {
    func testExtremeEditInputsDoNotOverflowAndRemainInMusicalRanges() {
        var value = NoteSequence(name: "Bounds", lanes: [SequenceLane(name: "Lane", channel: 0,
            notes: [SequenceNote(pitch: 127, start: 0, duration: 24)])])
        value.transpose(semitones: Int.max)
        value.resize(by: Int.max)
        value.scaleVelocity(by: .greatestFiniteMagnitude)
        value.quantize(grid: Int.max)
        XCTAssertEqual(value.lanes[0].notes[0].pitch, 127)
        XCTAssertEqual(value.lanes[0].notes[0].duration, NoteSequence.maximumLength)
        XCTAssertEqual(value.lanes[0].notes[0].velocity, 127)
        XCTAssertEqual(value.lanes[0].notes[0].start, 0)
        value.transpose(semitones: Int.min)
        XCTAssertEqual(value.lanes[0].notes[0].pitch, 0)
        XCTAssertEqual(NoteLength.code(nearestTicks: Int.min), 0)
        XCTAssertEqual(NoteLength.code(nearestTicks: Int.max), 126)
        XCTAssertTrue(Scale(root: Int.min, kind: .chromatic).isInScale(Int.max))
    }
    private func sequence(_ lanes: [[SequenceNote]], length: Int = 384) -> NoteSequence {
        NoteSequence(name: "T", length: length, lanes: lanes.enumerated().map { SequenceLane(name: "L\($0)", channel: $0, notes: $1) })
    }

    private func note(_ pitch: Int, _ start: Int, _ duration: Int = 24, velocity: Int = 100) -> SequenceNote {
        SequenceNote(pitch: pitch, velocity: velocity, start: start, duration: duration)
    }

    func testQuantizeStrengthSelectionAndWrap() {
        var full = sequence([[note(60, 5), note(62, 13), note(64, 380), note(65, 500)]])
        full.quantize(grid: 24)
        XCTAssertEqual(full.lanes[0].notes.map(\.start), [0, 24, 0, 504], "380 snaps to the loop end and wraps; 500 stays beyond")

        var half = sequence([[note(60, 10), note(62, 30)]])
        half.quantize(grid: 24, strength: 0.5)
        XCTAssertEqual(half.lanes[0].notes.map(\.start), [5, 27])

        var subset = sequence([[note(60, 10), note(62, 30)], [note(64, 10)]])
        let target = subset.lanes[0].notes[1].id
        subset.quantize(grid: 24, strength: 2, selection: .notes([target]))
        XCTAssertEqual(subset.lanes.map { $0.notes.map(\.start) }, [[10, 24], [10]])

        var lanes = sequence([[note(60, 10)], [note(64, 10)]])
        lanes.quantize(grid: 24, selection: .lanes([lanes.lanes[1].id]))
        XCTAssertEqual(lanes.lanes.map { $0.notes.map(\.start) }, [[10], [0]])

        var untouched = sequence([[note(60, 10)]])
        untouched.quantize(grid: 0)
        untouched.quantize(grid: 24, strength: .nan)
        XCTAssertEqual(untouched.lanes[0].notes[0].start, 10)
    }

    func testTransposeClampsPitch() {
        var value = sequence([[note(0, 0), note(120, 0)]])
        value.transpose(semitones: 12)
        XCTAssertEqual(value.lanes[0].notes.map(\.pitch), [12, 127])
        value.transpose(semitones: -100)
        XCTAssertEqual(value.lanes[0].notes.map(\.pitch), [0, 27])
    }

    func testMoveKeepsTheBlockInsideLoopAndPitchRange() {
        var value = sequence([[note(60, 24), note(70, 300)], [note(50, 0)]])
        let laneID = value.lanes[0].id
        var applied = value.move(ticks: 200, semitones: 100, selection: .lanes([laneID]))
        XCTAssertEqual(applied.ticks, 83)
        XCTAssertEqual(applied.semitones, 57)
        XCTAssertEqual(value.lanes[0].notes.map(\.start), [107, 383])
        XCTAssertEqual(value.lanes[0].notes.map(\.pitch), [117, 127])
        XCTAssertEqual(value.lanes[1].notes[0].start, 0)

        applied = value.move(ticks: -1000, semitones: -1000, selection: .lanes([laneID]))
        XCTAssertEqual(applied.ticks, -107)
        XCTAssertEqual(applied.semitones, -117)
        XCTAssertEqual(value.lanes[0].notes.map(\.start), [0, 276])
        XCTAssertEqual(value.lanes[0].notes.map(\.pitch), [0, 10])

        // A note kept beyond the loop moves freely but never before tick 0.
        var beyond = sequence([[note(60, 10), note(60, 500)]])
        beyond.move(ticks: 1000)
        XCTAssertEqual(beyond.lanes[0].notes.map(\.start), [383, 873])
    }

    func testResizeAndSetDurationKeepOneTick() {
        var value = sequence([[note(60, 0, 10), note(62, 0, 30)]])
        value.resize(by: -20)
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [1, 10])
        value.resize(by: 5, selection: .notes([value.lanes[0].notes[1].id]))
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [1, 15])
        value.setDuration(0)
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [1, 1])
        value.setDuration(48)
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [48, 48])
    }

    func testSetLengthTruncatesOrKeepsNotes() {
        var truncated = sequence([[note(60, 0, 300), note(62, 192), note(64, 200)]])
        truncated.setLength(192)
        XCTAssertEqual(truncated.length, 192)
        XCTAssertEqual(truncated.lanes[0].notes.map(\.pitch), [60])
        XCTAssertEqual(truncated.lanes[0].notes[0].duration, 300, "A note crossing the end keeps its duration")

        var kept = sequence([[note(60, 0), note(62, 200)]])
        kept.setLength(96, keepNotesBeyond: true)
        XCTAssertEqual(kept.length, 96)
        XCTAssertEqual(kept.noteCount, 2)

        kept.setLength(0)
        XCTAssertEqual(kept.length, 1)
        kept.setLength(.max)
        XCTAssertEqual(kept.length, NoteSequence.maximumLength)
    }

    func testDuplicateLoopCopiesNotesWithNewIDs() {
        var value = sequence([[note(60, 0), note(62, 380, 48)], [note(64, 400)]])
        XCTAssertTrue(value.duplicateLoop())
        XCTAssertEqual(value.length, 768)
        XCTAssertEqual(value.lanes[0].notes.map(\.start), [0, 380, 384, 764])
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [24, 48, 24, 48])
        XCTAssertEqual(value.lanes[1].notes.map(\.start), [400], "Notes beyond the loop are not copied")
        XCTAssertEqual(Set(value.lanes[0].notes.map(\.id)).count, 4)

        var huge = sequence([[note(60, 0)]], length: NoteSequence.maximumLength)
        XCTAssertFalse(huge.duplicateLoop())
        XCTAssertEqual(huge.length, NoteSequence.maximumLength)
        XCTAssertEqual(huge.noteCount, 1)
    }

    func testVelocityScaleAndSetClamp() {
        var value = sequence([[note(60, 0, velocity: 100), note(62, 0, velocity: 10)]])
        value.scaleVelocity(by: 1.5)
        XCTAssertEqual(value.lanes[0].notes.map(\.velocity), [127, 15])
        value.scaleVelocity(by: 0)
        XCTAssertEqual(value.lanes[0].notes.map(\.velocity), [1, 1])
        value.scaleVelocity(by: .infinity)
        XCTAssertEqual(value.lanes[0].notes.map(\.velocity), [1, 1])
        value.setVelocity(300)
        XCTAssertEqual(value.lanes[0].notes.map(\.velocity), [127, 127])
        value.setVelocity(-3, selection: .notes([value.lanes[0].notes[0].id]))
        XCTAssertEqual(value.lanes[0].notes.map(\.velocity), [1, 127])
    }

    func testLegatoExtendsToNextStartAndLoopEnd() {
        var value = sequence([[note(60, 96, 10), note(64, 0, 10), note(67, 0, 5), note(72, 500, 10)], [note(50, 0, 10)]])
        value.legato(selection: .lanes([value.lanes[0].id]))
        XCTAssertEqual(value.lanes[0].notes.map(\.duration), [288, 96, 96, 10])
        XCTAssertEqual(value.lanes[1].notes[0].duration, 10)

        var subset = sequence([[note(60, 0, 10), note(62, 48, 10), note(64, 96, 10)]])
        let ids: Set<UUID> = [subset.lanes[0].notes[0].id, subset.lanes[0].notes[2].id]
        subset.legato(selection: .notes(ids))
        XCTAssertEqual(subset.lanes[0].notes.map(\.duration), [96, 10, 288])
    }

    func testQueriesAndRemoval() {
        var value = sequence([[note(60, 0, 24), note(72, 48, 24), note(48, 90, 6)], [note(64, 20, 10)]])
        XCTAssertEqual(value.notes(in: 24..<48).map(\.pitch), [64], "End ticks are exclusive; the other lane's overlapping tail is included")
        XCTAssertEqual(value.notes(in: 23..<49).map(\.pitch), [60, 72, 64])
        XCTAssertEqual(value.notes(in: 0..<384, pitches: 60...70).map(\.pitch), [60, 64])
        XCTAssertEqual(value.notes(in: 0..<384, selection: .lanes([value.lanes[1].id])).map(\.pitch), [64])
        XCTAssertEqual(value.lanes[0].pitchRange, 48...72)
        XCTAssertNil(SequenceLane(name: "", channel: 0).pitchRange)

        let removed = value.removeNotes(selection: NoteSelection(lanes: [value.lanes[0].id], notes: [value.lanes[0].notes[1].id, value.lanes[1].notes[0].id]))
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(value.lanes.map { $0.notes.map(\.pitch) }, [[60, 48], [64]])
        XCTAssertEqual(value.removeNotes(selection: .all), 3)
        XCTAssertEqual(value.noteCount, 0)
    }

    func testFoldToScaleAndBarLength() {
        var value = sequence([[note(61, 0), note(66, 0), note(127, 0)]])
        value.foldToScale(Scale(root: 0, kind: .major))
        XCTAssertEqual(value.lanes[0].notes.map(\.pitch), [60, 65, 127])

        XCTAssertEqual(TimeSignature().ticksPerBar, 384)
        XCTAssertEqual(TimeSignature(beats: 7, unit: 8).ticksPerBar, 336)
        XCTAssertEqual(TimeSignature(beats: 3, unit: 4).ticksPerBar, 288)
        XCTAssertEqual(TimeSignature(beats: 0, unit: 0).ticksPerBar, 1)
    }
}
