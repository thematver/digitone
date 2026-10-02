import XCTest
@testable import DigitoneCore

final class ElektronProtocolTests: XCTestCase {
    // Literal vectors derived from the published Elektron packing diagram:
    // header bit 6 = first byte's MSB, bit 0 = seventh byte's MSB.
    // https://raw.githubusercontent.com/zooloo303/digi-roll/main/docs/elektron-sysex-protocol.md
    func testPublishedSevenBitLayout() throws {
        let vectors: [([UInt8], [UInt8])] = [
            ([], []),
            ([0x80], [0x40, 0]),
            ([0xff, 0x80, 1], [0x60, 0x7f, 0, 1]),
            ([0x80, 0, 0x80, 0, 0x80, 0, 0x80], [0x55, 0, 0, 0, 0, 0, 0, 0]),
            ([0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x80], [0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x40, 0])
        ]
        for (plain, wire) in vectors {
            XCTAssertEqual(SevenBit.encode(plain), wire)
            XCTAssertEqual(try SevenBit.decode(wire), plain)
        }
    }

    func testPackingRejectsLoneHeadersHighBytesAndUnusedBits() {
        let malformed: [[UInt8]] = [[0], [0, 128], [1, 0], [0, 1, 2, 3, 4, 5, 6, 7, 0]]
        for wire in malformed {
            XCTAssertThrowsError(try SevenBit.decode(wire))
        }
    }

    func testAPIRequestAgainstIndependentBytes() throws {
        let bytes: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x10, 0, 0, 0x4e, 0x20, 0, 0, 1, 0xf7]
        XCTAssertEqual(APIMessage(messageID: 20000, opcode: 1).bytes, bytes)
        XCTAssertEqual(try ElektronProtocol.parse(bytes), .api(APIMessage(messageID: 20000, opcode: 1)))
    }

    func testAPIResponseHighBitOpcodeAndResponseID() throws {
        // Decoded body: 00 07 4E 20 81 2B 00. The opcode's MSB belongs
        // in bit 2 of the packing header, not in the wire opcode byte.
        let bytes: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x10, 0, 4, 0, 7, 0x4e, 0x20, 1, 43, 0, 0xf7]
        let reply = APIMessage(messageID: 7, responseID: 20000, opcode: 0x81, arguments: [43, 0])
        XCTAssertEqual(try ElektronProtocol.parse(bytes), .api(reply))
        XCTAssertEqual(reply.bytes, bytes)
    }

    func testReadRequestHasNoWritePayload() throws {
        XCTAssertEqual(try ElektronProtocol.dumpRequest(index: 127),
                       [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x60, 1, 1, 127, 0, 0, 0, 5, 0xf7])
        XCTAssertThrowsError(try ElektronProtocol.dumpRequest(type: 0x50, index: 0))
        XCTAssertThrowsError(try ElektronProtocol.dumpRequest(index: 128))
    }

    func testDumpChecksumCountsEncodedBytesAndKeepsRaw() throws {
        // Encoded 40 7F 00 => payload FF 00; checksum BF; count 3+5=8.
        let bytes: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x50, 1, 1, 7, 0x40, 0x7f, 0, 1, 0x3f, 0, 8, 0xf7]
        guard case .dump(let result) = try ElektronProtocol.parse(bytes) else { return XCTFail("Expected dump") }
        XCTAssertEqual(result.family, 0x15)
        XCTAssertEqual(result.type, 0x50)
        XCTAssertEqual(result.version, [1, 1])
        XCTAssertEqual(result.index, 7)
        XCTAssertEqual(result.payload, [0xff, 0])
        XCTAssertEqual(result.raw, bytes)
        var changed = bytes
        changed[11] = 0x7e
        XCTAssertThrowsError(try ElektronProtocol.parse(changed)) { XCTAssertEqual($0 as? ProtocolError, .checksum) }
        changed = bytes
        changed[16] = 7
        XCTAssertThrowsError(try ElektronProtocol.parse(changed)) { XCTAssertEqual($0 as? ProtocolError, .checksum) }
    }

    func testLargeDumpLengthAndChecksumWrapAtFourteenBits() throws {
        // Complete static packing groups. Neither encoding nor parsing code
        // under test is used to generate this wire fixture.
        let group: [UInt8] = [0x55, 1, 2, 3, 4, 5, 6, 7]
        let encoded = (0..<15_000).flatMap { _ in group }
        let checksum = (113 * 15_000) % 16_384
        let count = (120_000 + 5) % 16_384
        let bytes = [UInt8](arrayLiteral: 0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x50, 1, 1, 0)
            + encoded + [UInt8(checksum >> 7), UInt8(checksum & 127), UInt8(count >> 7), UInt8(count & 127), 0xf7]
        guard case .dump(let result) = try ElektronProtocol.parse(bytes) else { return XCTFail("Expected dump") }
        XCTAssertEqual(result.payload.count, 105_000)
        XCTAssertEqual(Array(result.payload.prefix(7)), [129, 2, 131, 4, 133, 6, 135])
        XCTAssertEqual(Array(result.payload.suffix(7)), [129, 2, 131, 4, 133, 6, 135])
    }

    func testMalformedAndTruncatedFramesFailWithoutReadingPastBounds() {
        let valid: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x10, 0, 0, 0x4e, 0x20, 0, 0, 1, 0xf7]
        for count in 0..<valid.count { XCTAssertThrowsError(try ElektronProtocol.parse(Array(valid.prefix(count)))) }
        let malformed: [[UInt8]] = [
            [0xf0, 0, 0x20, 0x3c, 0x10, 0, 0, 0xf7],
            [0xf0, 0, 0x20, 0x3d, 0x10, 0, 0, 1, 2, 3, 4, 5, 0xf7],
            [0xf0, 0, 0x20, 0x3c, 0x10, 0, 0x80, 1, 2, 3, 4, 5, 0xf7]
        ]
        for bytes in malformed { XCTAssertThrowsError(try ElektronProtocol.parse(bytes)) }
    }

    func testIdentityCapabilitiesStringsAndFirmwareGate() throws {
        let identity = try DeviceIdentity(deviceReply: [43, 2, 1, 2] + Array("Digitone II".utf8) + [0],
                                          versionReply: Array("0049".utf8) + [0] + Array("1.10D".utf8) + [0])
        XCTAssertEqual(identity.name, "Digitone II")
        XCTAssertEqual(identity.supportedOpcodes, [1, 2])
        XCTAssertTrue(identity.hasKnownPatternFormat)
        XCTAssertThrowsError(try DeviceIdentity(deviceReply: [43, 5, 1], versionReply: [0]))
        XCTAssertThrowsError(try DeviceIdentity(deviceReply: [43, 0, 65], versionReply: [0]))
        XCTAssertThrowsError(try DeviceIdentity(deviceReply: [43, 0, 0], versionReply: Array("0049".utf8)))
    }
}
