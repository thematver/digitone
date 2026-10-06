import XCTest
import DigitoneCore
@testable import DigitoneUI

@MainActor
final class BeatWorkspaceTests: XCTestCase {
    private func workspace() -> WorkspaceModel {
        WorkspaceModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent("digitone-beat-tests-\(UUID())"), startAudio: false)
    }

    func testStepAndPianoRollCommandsShareSelectionAndUndo() throws {
        let model = workspace()
        model.sequence = BeatSequence.empty()
        model.toggleBeatStep(lane: 3, step: 14, pitch: 43, velocity: 93, duration: 42)
        let inserted = try XCTUnwrap(model.selected)
        XCTAssertEqual(model.laneIndex, 3)
        XCTAssertEqual(model.laneNotes.first?.id, inserted.id)
        model.transposeSelection(12)
        XCTAssertEqual(model.selected?.pitch, 55)
        model.undo()
        XCTAssertEqual(model.selected?.pitch, 43)
        model.undo()
        XCTAssertEqual(model.sequence.noteCount, 0)
        model.redo()
        XCTAssertEqual(model.sequence.lanes[3].notes.first?.id, inserted.id)
        model.selectBeatStep(lane: 3, step: 14)
        XCTAssertEqual(model.selectedNote, inserted.id)
        model.editBeatNote(inserted.id, velocity: 120)
        XCTAssertEqual(model.selected?.velocity, 120)
        model.undo()
        XCTAssertEqual(model.selected?.velocity, 93)
    }

    func testShortenAndClearRestoreEveryNoteAndMappingWithUndo() {
        let model = workspace()
        model.sequence = BeatSequence.make(.breakbeat, steps: 64)
        model.laneIndex = 1
        model.setLaneChannel(9)
        model.setBeatLaneTrack(7)
        let original = model.sequence
        model.setBeatLength(steps: 16)
        XCTAssertTrue(model.sequence.lanes.allSatisfy { $0.notes.allSatisfy { $0.start < 384 } })
        model.undo()
        XCTAssertEqual(model.sequence, original)
        model.clearBeat(allLanes: true)
        XCTAssertEqual(model.sequence.noteCount, 0)
        model.undo()
        XCTAssertEqual(model.sequence, original)
        model.fillBeatLane(.hat)
        XCTAssertEqual(model.sequence.lanes[1].channel, 9)
        XCTAssertEqual(model.sequence.lanes[1].track, 7)
        XCTAssertEqual(model.sequence.lanes[0], original.lanes[0])
        model.undo()
        XCTAssertEqual(model.sequence, original)
    }
}
