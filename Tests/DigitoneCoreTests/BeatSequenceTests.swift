import XCTest
@testable import DigitoneCore

final class BeatSequenceTests: XCTestCase {
    func testPresetCreatesRepeatablePlayableLanesAndUniqueNotes() {
        for preset in BeatPreset.allCases {
            let beat = BeatSequence.make(preset, steps: 64)
            XCTAssertEqual(beat.stepCount, 64)
            XCTAssertEqual(beat.lanes.map(\.channel), [0, 1, 2, 3])
            XCTAssertEqual(beat.lanes.compactMap(\.track), [0, 1, 2, 3])
            XCTAssertEqual(beat.lanes.map(\.name), ["Kick", "Snare", "Hat", "Bass"])
            XCTAssertTrue(beat.lanes.allSatisfy { !$0.notes.isEmpty })
            XCTAssertEqual(Set(beat.lanes.flatMap { $0.notes.map(\.id) }).count, beat.noteCount)
            for lane in beat.lanes {
                XCTAssertTrue(lane.notes.allSatisfy { (0..<beat.length).contains($0.start) && (1...127).contains($0.velocity) && $0.duration > 0 })
                let first = lane.notes.filter { $0.start < MusicalTime.ticksPerBar }
                let second = lane.notes.filter { (MusicalTime.ticksPerBar..<(MusicalTime.ticksPerBar * 2)).contains($0.start) }
                XCTAssertEqual(first.map(\.pitch), second.map(\.pitch))
                XCTAssertEqual(first.map(\.start), second.map { $0.start - MusicalTime.ticksPerBar })
            }
        }
    }

    func testToggleCellPreservesSustainOtherLanesAndImportedMicroTiming() {
        let sustained = SequenceNote(pitch: 36, start: 0, duration: 200)
        let microtimed = SequenceNote(pitch: 38, start: 27, duration: 12)
        let chord = SequenceNote(pitch: 42, start: 28, duration: 12)
        let neighbor = SequenceNote(pitch: 50, start: 48, duration: 12)
        var beat = NoteSequence(name: "Imported", lanes: [
            SequenceLane(name: "Bass", channel: 0, notes: [sustained, microtimed, chord, neighbor]),
            SequenceLane(name: "Hat", channel: 1, notes: [SequenceNote(pitch: 42, start: 24, duration: 6)])
        ])
        XCTAssertEqual(beat.notes(atStep: 1, lane: 0).map(\.id), [microtimed.id, chord.id])
        XCTAssertNil(beat.toggleStep(lane: 0, step: 1))
        XCTAssertEqual(beat.lanes[0].notes.map(\.id), [sustained.id, neighbor.id])
        XCTAssertEqual(beat.lanes[1].notes.count, 1)
        let inserted = beat.toggleStep(lane: 0, step: 1, pitch: 200, velocity: 0, duration: -20)
        XCTAssertNotNil(inserted)
        XCTAssertEqual(beat.notes(atStep: 1, lane: 0).first?.pitch, 127)
        XCTAssertEqual(beat.notes(atStep: 1, lane: 0).first?.velocity, 1)
        XCTAssertEqual(beat.notes(atStep: 1, lane: 0).first?.duration, 1)
        XCTAssertEqual(beat.lanes[0].notes.first?.id, sustained.id)
    }

    func testPartialAndInvalidStepsDoNotWriteOutsideLoop() {
        var beat = BeatSequence.empty(steps: 0, tempo: .nan)
        XCTAssertEqual(beat.length, 24)
        XCTAssertEqual(beat.tempo, 120)
        beat.length = 25
        XCTAssertEqual(beat.stepCount, 2)
        XCTAssertNotNil(beat.toggleStep(lane: 0, step: 1, duration: .max))
        XCTAssertEqual(beat.lanes[0].notes.first?.start, 24)
        XCTAssertEqual(beat.lanes[0].notes.first?.duration, NoteSequence.maximumLength - 24)
        let before = beat
        XCTAssertNil(beat.toggleStep(lane: 0, step: .max))
        XCTAssertNil(beat.toggleStep(lane: -1, step: 0))
        XCTAssertEqual(beat, before)
        XCTAssertTrue(beat.notes(atStep: .max, lane: 0).isEmpty)
    }

    func testRoleFillPreservesMappingNameAndOtherLane() {
        var beat = BeatSequence.empty(steps: 32)
        beat.lanes[0].name = "My bass"
        beat.lanes[0].track = 7
        beat.lanes[0].channel = 10
        beat.lanes[1].notes = [SequenceNote(pitch: 64, start: 7, duration: 25)]
        let filled = BeatSequence.fill(.bass, in: beat, lane: 0)
        XCTAssertEqual(filled.lanes[0].id, beat.lanes[0].id)
        XCTAssertEqual(filled.lanes[0].name, "My bass")
        XCTAssertEqual(filled.lanes[0].track, 7)
        XCTAssertEqual(filled.lanes[0].channel, 10)
        XCTAssertEqual(filled.lanes[1], beat.lanes[1])
        XCTAssertEqual(filled.lanes[0].notes.count, 12)
        XCTAssertGreaterThan(Set(filled.lanes[0].notes.map(\.pitch)).count, 1)
    }
}
