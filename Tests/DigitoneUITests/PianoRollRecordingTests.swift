import XCTest
import DigitoneCore
import DigitoneMIDI
@testable import DigitoneUI

final class PianoRollRecordingTests: XCTestCase {
    private let anchor: UInt64 = 10_000_000_000

    private func time(_ seconds: Double) -> UInt64 { HostClock.adding(seconds: seconds, to: anchor) }

    func testLiveNoteQuantizesAndPreservesTheTailAcrossTheLoopEnd() throws {
        var recorder = PianoRollRecorder()
        recorder.sync(playhead: 360, at: anchor, bpm: 120, length: 384)
        recorder.noteOn(pitch: 60, velocity: 99, at: anchor)
        let note = try XCTUnwrap(recorder.noteOff(pitch: 60, at: time(0.5), grid: 24))
        XCTAssertEqual(note.start, 360)
        XCTAssertEqual(note.duration, 96)
        XCTAssertEqual(note.velocity, 99)
        XCTAssertEqual(note.end, 456)
        XCTAssertTrue(recorder.pending.isEmpty)
    }

    func testTempoChangeDuringAHeldNoteIntegratesEachTempo() throws {
        var recorder = PianoRollRecorder()
        recorder.sync(playhead: 0, at: anchor, bpm: 120, length: 768)
        recorder.noteOn(pitch: 64, velocity: 100, at: anchor)
        // First second: 192 ticks. Second second at 60 BPM: 96 ticks.
        recorder.sync(playhead: 192, at: time(1), bpm: 60, length: 768)
        let note = try XCTUnwrap(recorder.noteOff(pitch: 64, at: time(2), grid: 1))
        XCTAssertEqual(note.duration, 288)
    }

    func testSamePitchOnDifferentMIDIChannelsRecordsIndependently() throws {
        var recorder = PianoRollRecorder()
        recorder.sync(playhead: 0, at: anchor, bpm: 120, length: 384)
        recorder.noteOn(pitch: 60, velocity: 70, at: anchor, channel: 0)
        recorder.noteOn(pitch: 60, velocity: 110, at: time(0.25), channel: 1)
        XCTAssertEqual(recorder.pending.count, 2)
        let first = try XCTUnwrap(recorder.noteOff(pitch: 60, at: time(0.5), grid: 24, channel: 0))
        XCTAssertEqual(first.start, 0)
        XCTAssertEqual(first.duration, 96)
        XCTAssertEqual(first.velocity, 70)
        XCTAssertEqual(recorder.pending.count, 1)
        let second = try XCTUnwrap(recorder.noteOff(pitch: 60, at: time(1), grid: 24, channel: 1))
        XCTAssertEqual(second.start, 48)
        XCTAssertEqual(second.duration, 144)
        XCTAssertEqual(second.velocity, 110)
    }

    func testQuantizationWrapsLoopEndAndFlushEndsAllHeldNotes() {
        var recorder = PianoRollRecorder()
        recorder.sync(playhead: 380, at: anchor, bpm: 120, length: 384)
        recorder.noteOn(pitch: 60, velocity: 0, at: anchor)
        recorder.noteOn(pitch: 67, velocity: 200, at: anchor, channel: 3)
        let notes = recorder.flush(at: time(0.01), grid: 24)
        XCTAssertEqual(notes.map(\.start), [0, 0])
        XCTAssertEqual(notes.map(\.duration), [24, 24])
        XCTAssertEqual(notes.map(\.velocity), [1, 127])
        XCTAssertTrue(recorder.pending.isEmpty)
        XCTAssertNil(recorder.noteOff(pitch: 60, at: time(1), grid: 24))
    }

    func testStepChordAdvancesOnlyOnceAfterEveryKeyIsReleased() {
        var step = StepInput()
        step.reset(to: 48)
        XCTAssertEqual(step.press(60), 48)
        XCTAssertEqual(step.press(64), 48)
        XCTAssertFalse(step.release(60, step: 24))
        XCTAssertEqual(step.cursor, 48)
        XCTAssertFalse(step.release(60, step: 24), "duplicate key-up")
        XCTAssertTrue(step.release(64, step: 24))
        XCTAssertEqual(step.cursor, 72)
        XCTAssertEqual(step.press(67), 72)
        step.releaseAll(step: 24)
        XCTAssertEqual(step.cursor, 96)
        XCTAssertTrue(step.held.isEmpty)
        step.releaseAll(step: 24)
        XCTAssertEqual(step.cursor, 96, "focus-loss release is idempotent")
    }

    func testIncomingNotesRouteToMatchingLaneAndAutoChannelToCurrentLane() {
        let lanes = [SequenceLane(name: "A", channel: 0), SequenceLane(name: "B", channel: 1), SequenceLane(name: "C", channel: 0)]
        XCTAssertEqual(PianoRollRouting.lane(forChannel: 0, lanes: lanes, current: 2), 2)
        XCTAssertEqual(PianoRollRouting.lane(forChannel: 1, lanes: lanes, current: 2), 1)
        XCTAssertEqual(PianoRollRouting.lane(forChannel: 9, lanes: lanes, current: 2), 2)
    }
}
