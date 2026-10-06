import XCTest
import DigitoneCore
@testable import DigitoneAgent

final class AgentProjectTests: XCTestCase {
    func testEveryCatalogParameterSurvivesStudioSnapshotConversion() throws {
        for machine in SynthMachine.allCases {
            let parameters = HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!).filter { $0.cc != nil || $0.nrpn != nil }
            for parameter in parameters {
                let sound = AgentSoundDraft(name: "Catalog", track: 0, midiChannel: 0, machine: machine,
                                            parameters: [parameter.id: AgentParameterRange.coarse(for: parameter).lowerBound])
                try sound.validate()
                XCTAssertEqual(sound.snapshot.parameters.count, 1, "Unmapped parameter: \(parameter.id)")
                XCTAssertEqual(sound.snapshot, sound.snapshot, "Repeated import must not regenerate createdAt")
            }
        }
    }

    func testRoundTripAllowsHighTempoAndCrossLoopTails() throws {
        let sequence = NoteSequence(name: "Tail", tempo: 400, length: 96, lanes: [
            SequenceLane(name: "Track", track: 0, channel: 7, notes: [SequenceNote(pitch: 60, start: 80, duration: 40)])
        ])
        let project = AgentProject(name: "Session", sequence: sequence)
        XCTAssertEqual(try AgentProject.read(project.data()), project)
    }

    func testRejectsMalformedRoutingDuplicateIDsAndUnknownVersions() throws {
        var project = AgentProject(); project.formatVersion = 2
        XCTAssertThrowsError(try project.validate())
        project = AgentProject(sequence: NoteSequence(name: "Invalid", lanes: [SequenceLane(name: "Invalid", track: 16, channel: 0)]))
        XCTAssertThrowsError(try project.validate())
        let lane = SequenceLane(name: "Duplicated", track: 0, channel: 0)
        project = AgentProject(sequence: NoteSequence(name: "Invalid", lanes: [lane, lane]))
        XCTAssertThrowsError(try project.validate())
        project = AgentProject(sequence: NoteSequence(name: "Invalid", length: 96, lanes: [
            SequenceLane(name: "Notes", channel: 0, notes: [SequenceNote(pitch: 60, start: 96, duration: 1)])
        ]))
        XCTAssertThrowsError(try project.validate())
    }

    func testLineReaderPreservesMessagesDrainsOversizedLinesAndEndsAtEOF() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("one\n123456789012345678901234567890\ntwo\nfinal".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let handle = try FileHandle(forReadingFrom: path); defer { try? handle.close() }
        let reader = MCPLineReader(handle: handle, maximumMessageBytes: 8)
        XCTAssertEqual(try reader.next(), Data("one".utf8))
        XCTAssertEqual(try reader.next()?.count, 9)
        XCTAssertEqual(try reader.next(), Data("two".utf8))
        XCTAssertEqual(try reader.next(), Data("final".utf8))
        XCTAssertNil(try reader.next())
    }
}
