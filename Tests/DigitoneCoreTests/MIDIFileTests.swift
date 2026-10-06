import XCTest
@testable import DigitoneCore

final class MIDIFileTests: XCTestCase {
    // MARK: Fixtures

    private func smf(format: Int = 1, division: Int = 96, tracks: [[UInt8]], declaredTracks: Int? = nil) -> Data {
        var bytes = Array("MThd".utf8) + [0, 0, 0, 6] + be16(format) + be16(declaredTracks ?? tracks.count) + be16(division)
        for track in tracks { bytes += Array("MTrk".utf8) + be32(track.count) + track }
        return Data(bytes)
    }

    private func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    private func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value) }
    private let endOfTrack: [UInt8] = [0, 0xFF, 0x2F, 0]

    private struct PlainNote: Equatable, CustomStringConvertible {
        var pitch, velocity, start, duration: Int
        init(_ pitch: Int, _ velocity: Int, _ start: Int, _ duration: Int) {
            self.pitch = pitch; self.velocity = velocity; self.start = start; self.duration = duration
        }
        init(_ note: SequenceNote) { self.init(note.pitch, note.velocity, note.start, note.duration) }
        var description: String { "\(pitch)/\(velocity)@\(start)+\(duration)" }
    }

    private func plain(_ lane: SequenceLane) -> [PlainNote] { lane.notes.map(PlainNote.init) }

    private func assertThrows(_ data: Data, _ expected: MIDIFileError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try MIDIFile.read(data), file: file, line: line) { error in
            XCTAssertEqual(error as? MIDIFileError, expected, file: file, line: line)
            XCTAssertFalse((error as? LocalizedError)?.errorDescription?.isEmpty ?? true, file: file, line: line)
        }
    }

    // MARK: Writer and round trip

    func testRoundTripPreservesEverythingButIDsMuteAndTrackBinding() throws {
        let original = NoteSequence(name: "Тест €", tempo: 133.5, timeSignature: TimeSignature(beats: 7, unit: 8), length: 336 * 3, lanes: [
            SequenceLane(name: "Bass", track: 0, channel: 0, notes: [
                SequenceNote(pitch: 36, velocity: 100, start: 0, duration: 24),
                SequenceNote(pitch: 36, velocity: 90, start: 24, duration: 24), // off and on at tick 24.
                SequenceNote(pitch: 40, velocity: 1, start: 50, duration: 100),
                SequenceNote(pitch: 40, velocity: 127, start: 100, duration: 100), // overlap, FIFO order.
                SequenceNote(pitch: 127, velocity: 64, start: 900, duration: 108)
            ]),
            SequenceLane(name: "Drums", channel: 9, notes: [
                SequenceNote(pitch: 0, velocity: 80, start: 0, duration: 1),
                SequenceNote(pitch: 38, velocity: 80, start: 0, duration: 12)
            ], isMuted: true),
            SequenceLane(name: "Empty", channel: 15)
        ])
        let data = try MIDIFile.write(original)
        let decoded = try MIDIFile.read(data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.tempo, original.tempo)
        XCTAssertEqual(decoded.timeSignature, original.timeSignature)
        XCTAssertEqual(decoded.length, original.length)
        XCTAssertEqual(decoded.lanes.map(\.name), original.lanes.map(\.name))
        XCTAssertEqual(decoded.lanes.map(\.channel), original.lanes.map(\.channel))
        XCTAssertEqual(decoded.lanes.map(\.track), [nil, nil, nil])
        XCTAssertEqual(decoded.lanes.map(\.isMuted), [false, false, false])
        for (lane, source) in zip(decoded.lanes, original.lanes) {
            XCTAssertEqual(plain(lane), plain(source), lane.name)
        }
        XCTAssertEqual(try MIDIFile.write(decoded), data, "A decoded file re-encodes byte for byte")
    }

    func testWriterLayout() throws {
        let sequence = NoteSequence(name: "S", length: 384, lanes: [
            SequenceLane(name: "L", channel: 2, notes: [
                SequenceNote(pitch: 60, velocity: 100, start: 24, duration: 24),
                SequenceNote(pitch: 60, velocity: 90, start: 0, duration: 24),
                SequenceNote(pitch: 200, velocity: 0, start: -5, duration: 0) // clamped.
            ])
        ])
        let bytes = [UInt8](try MIDIFile.write(sequence))
        let header: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, 2, 0, 96]
        XCTAssertEqual(Array(bytes.prefix(14)), header)

        let conductor: [UInt8] = [0, 0xFF, 0x03, 1, 0x53,
                                  0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20,
                                  0, 0xFF, 0x58, 4, 4, 2, 24, 8,
                                  0x83, 0x00, 0xFF, 0x2F, 0]
        XCTAssertEqual(Array(bytes[14..<22]), Array("MTrk".utf8) + be32(conductor.count))
        XCTAssertEqual(Array(bytes[22..<(22 + conductor.count)]), conductor)

        let lane: [UInt8] = [0, 0xFF, 0x03, 1, 0x4C,
                             0, 0xFF, 0x20, 1, 2,
                             0, 0x92, 60, 90,
                             0, 0x92, 127, 1,
                             1, 0x82, 127, 0x40,
                             23, 0x82, 60, 0x40, // note-off before the note-on at the same tick.
                             0, 0x92, 60, 100,
                             24, 0x82, 60, 0x40,
                             0x82, 0x50, 0xFF, 0x2F, 0] // end of track at the loop end, 384 - 48.
        let laneStart = 22 + conductor.count
        XCTAssertEqual(Array(bytes[laneStart..<(laneStart + 8)]), Array("MTrk".utf8) + be32(lane.count))
        XCTAssertEqual(Array(bytes[(laneStart + 8)...]), lane)
    }

    func testVariableLengthQuantities() {
        XCTAssertEqual(MIDIFile.vlq(0), [0])
        XCTAssertEqual(MIDIFile.vlq(0x7F), [0x7F])
        XCTAssertEqual(MIDIFile.vlq(0x80), [0x81, 0])
        XCTAssertEqual(MIDIFile.vlq(0x3FFF), [0xFF, 0x7F])
        XCTAssertEqual(MIDIFile.vlq(0x20_0000), [0x81, 0x80, 0x80, 0])
        XCTAssertEqual(MIDIFile.vlq(0x0FFF_FFFF), [0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertEqual(MIDIFile.vlq(Int.max), [0xFF, 0xFF, 0xFF, 0x7F])
    }

    // MARK: Reader fixtures

    func testRunningStatusAndVelocityZeroNoteOff() throws {
        let track: [UInt8] = [0, 0x90, 60, 100,
                              24, 60, 0, // running status, velocity 0 ends the note.
                              0, 62, 80,
                              24, 0x80, 62, 64,
                              0, 61, 0, // running status 0x80: a stray note-off.
                              0, 0x90, 64, 70,
                              12, 64, 0] + endOfTrack
        let sequence = try MIDIFile.read(smf(format: 0, tracks: [track]), fallbackName: "Файл")
        XCTAssertEqual(sequence.name, "Файл")
        XCTAssertEqual(sequence.tempo, 120)
        XCTAssertEqual(sequence.timeSignature, TimeSignature())
        XCTAssertEqual(sequence.length, 384)
        XCTAssertEqual(sequence.lanes.count, 1)
        XCTAssertEqual(sequence.lanes[0].name, "Канал 1")
        XCTAssertNil(sequence.lanes[0].track)
        XCTAssertEqual(plain(sequence.lanes[0]), [PlainNote(60, 100, 0, 24), PlainNote(62, 80, 24, 24), PlainNote(64, 70, 48, 12)])
    }

    func testFormat0SplitsChannelsIntoLanes() throws {
        let track: [UInt8] = [0, 0xFF, 0x03, 4] + Array("Song".utf8)
            + [0, 0x99, 36, 127, 0, 0x90, 48, 90, 0, 0xC0, 5, 0, 0xB9, 7, 100, 0, 0xE0, 0, 64, 0, 0xD0, 30, 0, 0xA0, 48, 10,
               48, 0x89, 36, 0, 0, 0x80, 48, 0] + endOfTrack
        let sequence = try MIDIFile.read(smf(format: 0, tracks: [track]))
        XCTAssertEqual(sequence.name, "Song")
        XCTAssertEqual(sequence.lanes.map(\.name), ["Song · канал 1", "Song · канал 10"])
        XCTAssertEqual(sequence.lanes.map(\.channel), [0, 9])
        XCTAssertEqual(plain(sequence.lanes[0]), [PlainNote(48, 90, 0, 48)])
        XCTAssertEqual(plain(sequence.lanes[1]), [PlainNote(36, 127, 0, 48)])
    }

    func testMaximumVariableLengthDelta() throws {
        // 0x0FFFFFFF ticks at the largest PPQ stays within the sequence limit.
        let track: [UInt8] = [0, 0x90, 60, 100, 0xFF, 0xFF, 0xFF, 0x7F, 0x80, 60, 0] + endOfTrack
        let sequence = try MIDIFile.read(smf(format: 0, division: 0x7FFF, tracks: [track]))
        let expected = (0x0FFF_FFFF * 96 * 2 + 0x7FFF) / (0x7FFF * 2)
        XCTAssertEqual(sequence.lanes[0].notes.first?.duration, expected)
        XCTAssertEqual(sequence.length, (expected + 383) / 384 * 384)

        assertThrows(smf(format: 0, tracks: [[0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x90, 60, 100] + endOfTrack]),
                     .variableLengthOverflow(track: 0, offset: 22))
        assertThrows(smf(format: 0, division: 1, tracks: [[0, 0x90, 60, 100, 0xFF, 0xFF, 0xFF, 0x7F, 0x80, 60, 0] + endOfTrack]),
                     .tooLong)
    }

    func testRescalesTicksWithRoundingAndMinimumDuration() throws {
        let track: [UInt8] = [0, 0x90, 60, 100,
                              0x81, 0x71, 0x80, 60, 0, // at 241 → 48.2 → 48.
                              0, 0x90, 61, 100,
                              2, 0x80, 61, 0, // 241...243 → 48...49 (48.6 rounds up).
                              0, 0x90, 62, 100,
                              1, 0x80, 62, 0] + endOfTrack // one source tick → minimum 1.
        let sequence = try MIDIFile.read(smf(format: 0, division: 480, tracks: [track]))
        XCTAssertEqual(plain(sequence.lanes[0]), [PlainNote(60, 100, 0, 48), PlainNote(61, 100, 48, 1), PlainNote(62, 100, 49, 1)])
    }

    func testOverlappingNotesPairFIFOAndHangingNotesCloseAtTrackEnd() throws {
        let track: [UInt8] = [0, 0x80, 50, 0, // stray note-off is ignored.
                              0, 0x90, 60, 100,
                              10, 0x90, 60, 90,
                              10, 0x80, 60, 0,
                              10, 0x80, 60, 0,
                              10, 0x90, 64, 80,
                              10, 0x91, 64, 70,
                              0x60, 0xFF, 0x2F, 0, // end of track at 146.
                              0, 0x90, 70, 100] // bytes after the end of track are ignored.
        let sequence = try MIDIFile.read(smf(format: 0, tracks: [track]))
        XCTAssertEqual(sequence.lanes.count, 2)
        XCTAssertEqual(plain(sequence.lanes[0]), [PlainNote(60, 100, 0, 20), PlainNote(60, 90, 10, 20), PlainNote(64, 80, 40, 106)])
        XCTAssertEqual(plain(sequence.lanes[1]), [PlainNote(64, 70, 50, 96)])

        // A track without an end-of-track event closes notes at its last event.
        let unterminated = try MIDIFile.read(smf(format: 0, tracks: [[0, 0x90, 60, 100, 30, 0xB0, 1, 2]]))
        XCTAssertEqual(plain(unterminated.lanes[0]), [PlainNote(60, 100, 0, 30)])
    }

    func testMetaSysExAndUnknownChunks() throws {
        let conductor: [UInt8] = [0, 0xFF, 0x03, 5] + Array("Title".utf8)
            + [0, 0xFF, 0x01, 3] + Array("txt".utf8)
            + [0, 0xF0, 5, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
            + [0, 0xF7, 2, 0xF3, 0x01]
            + [10, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20] // 120 BPM at tick 10.
            + [0, 0xFF, 0x58, 4, 3, 2, 24, 8]
            + [10, 0xFF, 0x51, 3, 0x0F, 0x42, 0x40] // later 60 BPM: ignored.
            + endOfTrack
        let notes: [UInt8] = [0, 0xFF, 0x03, 4] + Array("Lead".utf8)
            + [0, 0xFF, 0x51, 3, 0x06, 0x1A, 0x80] // 150 BPM at tick 0 wins.
            + [0, 0x90, 60, 100, 0x82, 0x2C, 0x80, 60, 0] + endOfTrack // ends at 300.
        var data = smf(tracks: [conductor, notes])
        data += Array("XFIH".utf8) + [0, 0, 0, 3, 1, 2, 3]
        let sequence = try MIDIFile.read(data)
        XCTAssertEqual(sequence.name, "Title")
        XCTAssertEqual(sequence.tempo, 150)
        XCTAssertEqual(sequence.timeSignature, TimeSignature(beats: 3, unit: 4))
        XCTAssertEqual(sequence.length, 576, "Two bars of 3/4 cover tick 300")
        XCTAssertEqual(sequence.lanes.map(\.name), ["Lead"])
        XCTAssertEqual(plain(sequence.lanes[0]), [PlainNote(60, 100, 0, 300)])

        // Meta and SysEx events cancel running status.
        assertThrows(smf(format: 0, tracks: [[0, 0x90, 60, 100, 0, 0xFF, 0x01, 0, 0, 60, 0] + endOfTrack]),
                     .malformedEvent(track: 0, offset: 31))
    }

    func testEndOfTrackExtendsTheLoopToWholeBars() throws {
        let track: [UInt8] = [0, 0x90, 60, 100, 24, 0x80, 60, 0, 0x8B, 0x68, 0xFF, 0x2F, 0] // end at 24 + 1512.
        let sequence = try MIDIFile.read(smf(format: 0, tracks: [track]))
        XCTAssertEqual(sequence.length, 4 * 384)
    }

    func testRejectsUnsupportedAndMalformedFiles() throws {
        assertThrows(Data("RIFF....".utf8), .notMIDIFile)
        assertThrows(Data(), .notMIDIFile)
        assertThrows(smf(format: 2, tracks: [endOfTrack]), .unsupportedFormat(2))
        assertThrows(smf(division: 0xE728, tracks: [endOfTrack]), .smpteTiming)
        assertThrows(smf(division: 0, tracks: [endOfTrack]), .malformedHeader)
        assertThrows(Data(Array("MThd".utf8) + [0, 0, 0, 4, 0, 0, 0, 1]), .malformedHeader)
        assertThrows(Data(Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0]), .malformedHeader)

        var truncated = smf(tracks: [endOfTrack])
        truncated[21] = 9 // chunk claims 9 bytes, 4 present.
        assertThrows(truncated, .truncatedChunk(offset: 14))
        XCTAssertEqual(try MIDIFile.read(smf(tracks: [endOfTrack]) + Data([0, 0, 0])).lanes.count, 0, "Short padding is ignored")

        // Event offsets are absolute; the first track's events start at byte 22.
        assertThrows(smf(tracks: [[0, 0x90, 60]]), .malformedEvent(track: 0, offset: 25))
        assertThrows(smf(tracks: [[0, 0x90, 60, 0x80]]), .malformedEvent(track: 0, offset: 25))
        assertThrows(smf(tracks: [[0, 60, 100]]), .malformedEvent(track: 0, offset: 23))
        assertThrows(smf(tracks: [[0, 0xF8]]), .malformedEvent(track: 0, offset: 23))
        assertThrows(smf(tracks: [[0, 0xFF, 0x03, 10, 0x41]]), .malformedEvent(track: 0, offset: 26))
        assertThrows(smf(tracks: [[0x81]]), .malformedEvent(track: 0, offset: 23))
        assertThrows(smf(tracks: [endOfTrack, [0, 0x90]]), .malformedEvent(track: 1, offset: 36))
        assertThrows(Data(count: MIDIFile.maximumFileSize + 1), .tooLarge(bytes: MIDIFile.maximumFileSize + 1))
    }

    func testNoteAndLaneLimits() throws {
        let note: [UInt8] = [0, 60, 100, 0, 60, 0]
        var track: [UInt8] = [0, 0x90, 60, 100, 0, 60, 0]
        track.reserveCapacity(note.count * MIDIFile.maximumNoteCount + 8)
        for _ in 0..<(MIDIFile.maximumNoteCount - 1) { track += note }
        let atLimit = try MIDIFile.read(smf(format: 0, tracks: [track + endOfTrack]))
        XCTAssertEqual(atLimit.noteCount, MIDIFile.maximumNoteCount)
        assertThrows(smf(format: 0, tracks: [track + note + endOfTrack]), .tooManyNotes(limit: MIDIFile.maximumNoteCount))

        let laneTracks = (0..<(MIDIFile.maximumLaneCount / 16 + 1)).map { _ in
            (0..<16).flatMap { channel -> [UInt8] in [0, 0x90 | UInt8(channel), 60, 100, 1, 0x80 | UInt8(channel), 60, 0] } + endOfTrack
        }
        assertThrows(smf(tracks: laneTracks), .tooManyLanes(limit: MIDIFile.maximumLaneCount))
    }

    func testDeclaredTrackCountAndExcessivelyLongEmptyClipAreRejected() {
        assertThrows(smf(tracks: [endOfTrack], declaredTracks: 2), .malformedHeader)
        assertThrows(smf(format: 0, tracks: [endOfTrack, endOfTrack]), .malformedHeader)
        assertThrows(smf(tracks: [], declaredTracks: 0), .malformedHeader)
        assertThrows(smf(format: 0, tracks: [MIDIFile.vlq(NoteSequence.maximumLength + 1) + [0xFF, 0x2F, 0]]), .tooLong)
    }

    func testWriterRejectsOversizedNotesAndHandlesExtremeMetadataSafely() throws {
        let oversized = NoteSequence(name: "Too long", lanes: [SequenceLane(name: "L", channel: 0,
                                                                           notes: [SequenceNote(pitch: 60, start: 0, duration: Int.max)])])
        XCTAssertThrowsError(try MIDIFile.write(oversized)) { XCTAssertEqual($0 as? MIDIFileError, .tooLong) }
        let extremeMetadata = NoteSequence(name: "Safe", tempo: .leastNonzeroMagnitude,
                                           timeSignature: TimeSignature(beats: Int.max, unit: Int.min))
        let decoded = try MIDIFile.read(MIDIFile.write(extremeMetadata))
        XCTAssertTrue(decoded.tempo.isFinite)
        XCTAssertEqual(decoded.timeSignature, TimeSignature(beats: 255, unit: 1))
    }
}
