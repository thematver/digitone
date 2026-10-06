import XCTest
import DigitoneCore
import DigitoneAgent
@testable import DigitoneUI

@MainActor
final class AgentProjectWorkflowTests: XCTestCase {
    private func inDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-agent-ui-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testAgentImportMakesAnEditablePatternAndLocalSoundLibrary() throws {
        try inDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            let studio = StudioModel(directory: directory, startMIDI: false)
            let original = workspace.sequence
            let sequence = BeatSequence.make(.house, steps: 32)
            let frequency = try XCTUnwrap(HardwareCatalog.parameters(for: .fmTone).first { $0.cc == 16 && $0.page == .fltr1 })
            let sound = AgentSoundDraft(name: "Agent bass", track: 3, midiChannel: 5,
                                       machine: .fmTone, parameters: [frequency.id: 74])
            let project = AgentProject(name: "House draft", sequence: sequence, sounds: [sound])
            let url = directory.appendingPathComponent("test.digitone.json")
            try project.data().write(to: url)
            workspace.importAgentProject(url, studio: studio)
            XCTAssertNil(workspace.error)
            XCTAssertNil(studio.error)
            XCTAssertEqual(workspace.sequence, sequence)
            XCTAssertEqual(studio.snapshots, [sound.snapshot])
            XCTAssertFalse(studio.connected)
            XCTAssertTrue(studio.known.isEmpty, "Import must not silently replace the current sound")
            workspace.undo()
            XCTAssertEqual(workspace.sequence, original)
            let restored = StudioModel(directory: directory, startMIDI: false)
            XCTAssertEqual(restored.snapshots, [sound.snapshot])
        }
    }

    func testInvalidProjectImportPreservesSequenceAndLibrary() throws {
        try inDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            let studio = StudioModel(directory: directory, startMIDI: false)
            let original = workspace.sequence
            var invalid = AgentProject(sequence: BeatSequence.make(.house))
            invalid.sequence.lanes[0].channel = 99
            let url = directory.appendingPathComponent("broken.json")
            try JSONEncoder().encode(invalid).write(to: url)
            workspace.importAgentProject(url, studio: studio)
            XCTAssertNotNil(workspace.error)
            XCTAssertEqual(workspace.sequence, original)
            XCTAssertTrue(studio.snapshots.isEmpty)
        }
    }

    func testProjectExportPreservesExplicitSoundTrackAndChannel() throws {
        try inDirectory { directory in
            let workspace = WorkspaceModel(directory: directory, startAudio: false)
            let studio = StudioModel(directory: directory, startMIDI: false)
            let control = ControlModel(output: SilentControlOutput(isAvailable: false), defaults: nil)
            ControlModel.attach(control, to: studio)
            control.selectTrack(3)
            control.setTrackChannel(5, track: 3)
            let frequency = try XCTUnwrap(HardwareCatalog.parameters(for: .fmTone).first { $0.cc == 16 && $0.page == .fltr1 })
            control.stage([frequency: 74 << 7])
            let data = try XCTUnwrap(workspace.exportAgentProject(studio: studio))
            let project = try AgentProject.read(data)
            XCTAssertEqual(project.sequence, workspace.sequence)
            let sound = try XCTUnwrap(project.sounds.first)
            XCTAssertEqual(sound.track, 3)
            XCTAssertEqual(sound.midiChannel, 5)
            XCTAssertEqual(sound.parameters[frequency.id], 74)
        }
    }
}
