import XCTest
@testable import DigitoneCore

final class PatternSequenceTests: XCTestCase {
    private struct Note: Encodable {
        var id: Int
        var track: Int
        var step: Int
        var note: Int
        var velocity = 100
        var lengthCode = 14
        var microTiming = 0
    }

    private struct Fields: Encodable {
        var index = 5
        var name = "GROOVE"
        var tempo = 121.5
        var swing = 50
        var trackNames = Array(repeating: "", count: 16)
        var trackLengths = Array(repeating: 16, count: 16)
        var notes: [Note] = []
        var raw = Data()
    }

    /// PatternSnapshot only has a dump initializer; Codable builds arbitrary field values.
    private func pattern(_ fields: Fields) throws -> PatternSnapshot {
        try JSONDecoder().decode(PatternSnapshot.self, from: JSONEncoder().encode(fields))
    }

    func testLanesNamesTimingAndLengths() throws {
        var fields = Fields()
        fields.trackNames[0] = "BASS "
        fields.trackLengths[1] = 32
        fields.notes = [
            Note(id: 0, track: 0, step: 0, note: 36, microTiming: -1), // wraps to the end of track 1.
            Note(id: 1, track: 0, step: 1, note: 38, velocity: 0, lengthCode: 46, microTiming: 5),
            Note(id: 2, track: 1, step: 2, note: 60, lengthCode: 127), // INF chord ends at the next start.
            Note(id: 3, track: 1, step: 2, note: 64, lengthCode: 127, microTiming: 99), // micro clamps to 23.
            Note(id: 4, track: 1, step: 5, note: 67, lengthCode: 127), // INF until the track end.
            Note(id: 5, track: 0, step: 16, note: 40), // beyond the 16-step track: not played.
            Note(id: 6, track: 2, step: 3, note: 50, lengthCode: 200), // unknown code: one step.
            Note(id: 7, track: 16, step: 0, note: 50) // invalid track.
        ]
        let sequence = try pattern(fields).noteSequence()

        XCTAssertEqual(sequence.name, "GROOVE")
        XCTAssertEqual(sequence.tempo, 121.5)
        XCTAssertEqual(sequence.length, 32 * 24)
        XCTAssertEqual(sequence.lanes.count, 16)
        XCTAssertEqual(sequence.lanes.map(\.track), Array(0..<16))
        XCTAssertEqual(sequence.lanes.map(\.channel), Array(0..<16))
        XCTAssertEqual(sequence.lanes[0].name, "BASS")
        XCTAssertEqual(sequence.lanes[1].name, "Трек 2")
        XCTAssertEqual(sequence.noteCount, 6)

        let bass = sequence.lanes[0].notes
        XCTAssertEqual(bass.map(\.pitch), [38, 36])
        XCTAssertEqual(bass.map(\.start), [29, 383])
        XCTAssertEqual(bass.map(\.duration), [96, 24])
        XCTAssertEqual(bass[0].velocity, 1)

        let chords = sequence.lanes[1].notes
        XCTAssertEqual(chords.map(\.pitch), [60, 64, 67])
        XCTAssertEqual(chords.map(\.start), [48, 71, 120])
        XCTAssertEqual(chords.map(\.duration), [23, 49, 768 - 120])
        XCTAssertEqual(sequence.lanes[2].notes.map(\.duration), [24])
    }

    func testRepeatingShorterTracksFillsTheLongestTrack() throws {
        var fields = Fields()
        fields.trackLengths[3] = 64
        fields.trackLengths[0] = 24
        fields.notes = [Note(id: 0, track: 0, step: 0, note: 36), Note(id: 1, track: 0, step: 20, note: 37)]
        let once = try pattern(fields).noteSequence()
        XCTAssertEqual(once.lanes[0].notes.map(\.start), [0, 480])

        let repeated = try pattern(fields).noteSequence(repeatingShorterTracks: true)
        XCTAssertEqual(repeated.length, 64 * 24)
        XCTAssertEqual(repeated.lanes[0].notes.map(\.start), [0, 480, 576, 1056, 1152])
        XCTAssertEqual(Set(repeated.lanes[0].notes.map(\.id)).count, 5)
    }

    func testEmptyNameFallsBackToSlot() throws {
        var fields = Fields()
        fields.name = " "
        fields.trackNames = []
        fields.trackLengths = []
        let sequence = try pattern(fields).noteSequence()
        XCTAssertEqual(sequence.name, "A06")
        XCTAssertEqual(sequence.length, MusicalTime.ticksPerBar)
        XCTAssertEqual(sequence.lanes.last?.name, "Трек 16")
    }

    func testHardwareCaptureConverts() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("captures/hardware/DN2-1.10D-0049-A01.syx")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("Hardware capture not present: \(url.path)") }
        guard case .dump(let dump) = try ElektronProtocol.parse([UInt8](data)) else { return XCTFail("Expected a dump") }
        let pattern = try PatternSnapshot(dump: dump)
        let sequence = pattern.noteSequence()

        XCTAssertEqual(sequence.lanes.count, 16)
        XCTAssertEqual(sequence.length, (pattern.trackLengths.max() ?? 0) * 24)
        XCTAssertEqual(sequence.tempo, pattern.tempo)
        let playable = pattern.notes.filter { $0.step < pattern.trackLengths[$0.track] }
        XCTAssertEqual(sequence.noteCount, playable.count)
        for lane in sequence.lanes {
            for note in lane.notes {
                XCTAssertTrue((0..<sequence.length).contains(note.start))
                XCTAssertGreaterThanOrEqual(note.duration, 1)
                XCTAssertTrue((1...127).contains(note.velocity))
            }
        }
        XCTAssertEqual(sequence.lanes.map(\.name), pattern.trackNames.enumerated().map { $1.isEmpty ? "Трек \($0 + 1)" : $1 })
        // The checked-in A01 export is an empty pattern with named presets.
        XCTAssertEqual(sequence.lanes.first?.name, "KICK_SHARP")
    }
}
