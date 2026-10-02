import XCTest
@testable import DigitoneCore

final class PatternSnapshotTests: XCTestCase {
    // Synthetic fixture built from the documented v3 layout, not a recording
    // from the user's instrument. Hardware captures remain a separate check.
    // https://raw.githubusercontent.com/zooloo303/digi-roll/main/docs/dn2-pattern-format.md
    private func fixture() -> DumpMessage {
        var bytes = Array(repeating: UInt8(0), count: 99_840)
        write32(3, to: &bytes, at: 0)
        write32(0xbeefbace, to: &bytes, at: 89_088)
        write32(3, to: &bytes, at: 89_092)
        for track in 0..<16 {
            let base = 4 + track * 1187
            bytes[base + 1152] = 60
            bytes[base + 1153] = 100
            bytes[base + 1154] = 14
            bytes[base + 1164] = 0
            bytes[base + 1165] = 16
        }
        bytes.replaceSubrange(18_996..<68_148, with: repeatElement(UInt8(255), count: 49_152))
        bytes[5] = 1 // T1 step 1 sounding flag, uint16be.
        bytes[7] = 1 // T1 step 2 sounding flag.
        let records: [[UInt8]] = [
            [0, 0, 60, 255, 255, 255], // defaults + signed microtiming -1.
            [0, 0, 64, 30, 46, 1],
            [0, 0, 67, 90, 14, 0], // same step: retain every chord note.
            [0, 2, 72, 100, 14, 0], // no sounding flag: ignored.
            [255, 255, 255, 255, 9, 1], // deleted record leaves stray bytes.
            [0, 1, 255, 255, 255, 0] // default note/velocity/length.
        ]
        for (index, record) in records.enumerated() {
            let offset = 18_996 + index * 6
            bytes.replaceSubrange(offset..<(offset + 6), with: record)
        }
        bytes.replaceSubrange(88_788..<(88_788 + 6), with: Array("CHORDS".utf8))
        write32(14_400, to: &bytes, at: 88_804)
        bytes[88_812] = 28 // 78% swing.
        bytes[88_817] = 0xa5 // an unknown field must survive raw retention.
        let trackNameOffset = 89_088 + 60 + 12
        bytes.replaceSubrange(trackNameOffset..<(trackNameOffset + 5), with: [86, 111, 120, 32, 0x80]) // Windows-1252 €.
        return makeDump(bytes)
    }

    private func write32(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
        bytes.replaceSubrange(offset..<(offset + 4), with: [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }

    private func makeDump(_ payload: [UInt8], version: [UInt8] = [1, 1]) -> DumpMessage {
        let encoded = SevenBit.encode(payload)
        let checksum = encoded.reduce(0) { $0 + Int($1) } % 16_384
        let count = (encoded.count + 5) % 16_384
        let raw: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x50] + version + [0]
            + encoded + [UInt8(checksum >> 7), UInt8(checksum & 127), UInt8(count >> 7), UInt8(count & 127), 0xf7]
        return DumpMessage(family: 0x15, type: 0x50, version: version, index: 0, payload: payload, raw: raw)
    }

    func testChordNotesDefaultsSwingAndUnknownRawAreRetained() throws {
        let dump = fixture()
        let pattern = try PatternSnapshot(dump: dump)
        XCTAssertEqual(pattern.index, 0)
        XCTAssertEqual(pattern.name, "CHORDS")
        XCTAssertEqual(pattern.tempo, 120)
        XCTAssertEqual(pattern.swing, 78)
        XCTAssertEqual(pattern.trackLengths, Array(repeating: 16, count: 16))
        XCTAssertEqual(pattern.trackNames[0], "Vox €")
        XCTAssertEqual(pattern.notes.count, 4)
        XCTAssertEqual(pattern.notes.filter { $0.step == 0 }.map(\.note), [60, 64, 67])
        XCTAssertEqual(pattern.notes[0].velocity, 100)
        XCTAssertEqual(pattern.notes[0].lengthCode, 14)
        XCTAssertEqual(pattern.notes[0].microTiming, -1)
        XCTAssertEqual(pattern.notes[1].velocity, 30)
        XCTAssertEqual(pattern.notes[1].lengthCode, 46)
        XCTAssertEqual(pattern.notes[1].microTiming, 1)
        XCTAssertEqual(pattern.notes.last?.note, 60)
        XCTAssertEqual(pattern.raw, Data(dump.raw))
        guard case .dump(let rawAgain) = try ElektronProtocol.parse(Array(pattern.raw)) else { return XCTFail("Expected dump") }
        XCTAssertEqual(rawAgain.payload[88_817], 0xa5)
    }

    func testRefusesUnknownVersionsShortPayloadAndInvalidValues() throws {
        let dump = fixture()
        XCTAssertThrowsError(try PatternSnapshot(dump: makeDump(Array(dump.payload.dropLast()))))
        XCTAssertThrowsError(try PatternSnapshot(dump: makeDump(dump.payload, version: [1, 2])))
        for (offset, value) in [(3, UInt8(4)), (88_812, UInt8(31)), (18_996, UInt8(16)), (18_997, UInt8(128)), (18_998, UInt8(128)), (1169, UInt8(0))] {
            var payload = dump.payload
            payload[offset] = value
            XCTAssertThrowsError(try PatternSnapshot(dump: makeDump(payload)), "Offset \(offset)")
        }
    }

    func testSlotNamesAtBankBoundaries() {
        XCTAssertEqual(PatternSnapshot.slotName(0), "A01")
        XCTAssertEqual(PatternSnapshot.slotName(15), "A16")
        XCTAssertEqual(PatternSnapshot.slotName(16), "B01")
        XCTAssertEqual(PatternSnapshot.slotName(127), "H16")
    }
}
