import Foundation
import XCTest
import DigitoneCore
import DigitoneDSP
@testable import DigitoneUI

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-workspace-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func clip() -> NoteSequence {
        NoteSequence(name: "Crossing loop", length: 384, lanes: [SequenceLane(name: "Bass", track: 0, channel: 0,
            notes: [SequenceNote(pitch: 60, velocity: 90, start: 360, duration: 96)])])
    }

    func testSequenceRoundTripPreservesIDsAndNotesAcrossLoopEnd() throws {
        try withDirectory { directory in
            let original = clip()
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            workspace.sequence = original
            workspace.saveSequence()
            XCTAssertNil(workspace.error)
            let restored = WorkspaceModel(directory: directory, startAudio: false)
            XCTAssertNil(restored.error)
            XCTAssertEqual(restored.sequence, original)
            XCTAssertEqual(restored.sequence.lanes[0].notes[0].duration, 96)
        }
    }

    func testPitchVelocityAndMoveEditsPreserveCrossBoundaryTail() throws {
        try withDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            workspace.sequence = clip()
            workspace.selectedNote = workspace.sequence.lanes[0].notes[0].id
            workspace.editSelected(velocity: 110)
            workspace.editSelected(pitch: 62)
            XCTAssertEqual(workspace.selected?.duration, 96)
            workspace.editSelected(start: 370)
            XCTAssertEqual(workspace.selected?.duration, 96)
            workspace.editSelected(duration: 72)
            XCTAssertEqual(workspace.selected?.duration, 72)
            XCTAssertEqual(workspace.selected?.velocity, 110)
            XCTAssertEqual(workspace.selected?.pitch, 62)
        }
    }

    func testInvalidRestoredDataIsNotShownOrOverwrittenBySave() throws {
        try withDirectory { directory in
            let original = clip()
            var invalid: [NoteSequence] = []
            var changed = original; changed.length = Int.min; invalid.append(changed)
            changed = original; changed.length = 0; invalid.append(changed)
            changed = original; changed.tempo = 19; invalid.append(changed)
            changed = original; changed.tempo = 1000; invalid.append(changed)
            changed = original; changed.lanes[0].channel = 16; invalid.append(changed)
            changed = original; changed.lanes[0].notes[0].pitch = 128; invalid.append(changed)
            changed = original; changed.lanes[0].notes[0].velocity = 0; invalid.append(changed)
            changed = original; changed.lanes[0].notes[0].start = -1; invalid.append(changed)
            changed = original; changed.lanes[0].notes[0].duration = Int.max; invalid.append(changed)
            changed = original; changed.lanes[0].notes.append(changed.lanes[0].notes[0]); invalid.append(changed)
            changed = original; changed.lanes.append(changed.lanes[0]); invalid.append(changed)
            let url = directory.appendingPathComponent("sequence.json")
            for malformed in invalid {
                let data = try JSONEncoder().encode(malformed)
                try data.write(to: url)
                let workspace = WorkspaceModel(directory: directory, startAudio: false)
                XCTAssertNotNil(workspace.error)
                XCTAssertEqual(workspace.sequence.name, "Новый паттерн")
                XCTAssertEqual(workspace.pageCount, 1)
                workspace.saveSequence()
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testSaveRejectsInvalidInMemoryNotesAndProtectsExternallyCorruptedFile() throws {
        try withDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            workspace.sequence = clip(); workspace.saveSequence()
            let url = directory.appendingPathComponent("sequence.json")
            let goodData = try Data(contentsOf: url)
            workspace.sequence.lanes[0].notes[0].velocity = -1
            XCTAssertNil(workspace.exportMIDI())
            workspace.saveSequence()
            XCTAssertEqual(try Data(contentsOf: url), goodData)
            workspace.sequence = clip()
            let corrupt = Data("{ broken JSON".utf8)
            try corrupt.write(to: url)
            workspace.saveSequence()
            XCTAssertNotNil(workspace.error)
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    func testMIDIImportReplacesDataOnlyAfterSuccessfulValidation() throws {
        try withDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            workspace.sequence = clip()
            let url = directory.appendingPathComponent("party.mid")
            try Data("invalid MIDI".utf8).write(to: url)
            workspace.importMIDI(url)
            XCTAssertNotNil(workspace.error)
            XCTAssertEqual(workspace.sequence.name, "Crossing loop")
            try MIDIFile.write(clip()).write(to: url)
            workspace.importMIDI(url)
            XCTAssertNil(workspace.error)
            XCTAssertEqual(workspace.sequence.noteCount, 1)
            XCTAssertEqual(workspace.sequence.lanes[0].notes[0].duration, 96)
        }
    }

    func testSupportedTempoBoundsArePreservedOnSaveAndExport() throws {
        try withDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            for tempo in [20.0, 999.0] {
                workspace.sequence = clip(); workspace.sequence.tempo = tempo
                workspace.saveSequence()
                XCTAssertNil(workspace.error)
                let restored = WorkspaceModel(directory: directory, startAudio: false)
                XCTAssertEqual(restored.sequence.tempo, tempo)
                let data = try XCTUnwrap(workspace.exportMIDI())
                let url = directory.appendingPathComponent("boundary.mid")
                try data.write(to: url)
                workspace.importMIDI(url)
                XCTAssertNil(workspace.error)
                XCTAssertEqual(workspace.sequence.tempo, tempo)
            }
        }
    }

    func testPadTrimAlwaysKeepsAValidNonemptyRegion() throws {
        try withDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            workspace.sample = SampleBuffer(sampleRate: 100, channels: [[Float](repeating: 0, count: 100)])
            workspace.chop(4)
            XCTAssertEqual(workspace.slices, [0..<25, 25..<50, 50..<75, 75..<100])
            workspace.trimPad(start: Int.max)
            XCTAssertEqual(workspace.slices[0], 24..<25)
            workspace.trimPad(end: Int.min)
            XCTAssertEqual(workspace.slices[0], 24..<25)
            workspace.trimPad(end: Int.max)
            XCTAssertEqual(workspace.slices[0], 24..<100)
        }
    }
}
