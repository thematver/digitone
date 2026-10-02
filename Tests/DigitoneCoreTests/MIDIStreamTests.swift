import XCTest
@testable import DigitoneCore

final class MIDIStreamTests: XCTestCase {
    func testFragmentedSysExWithInterleavedRealtime() {
        var decoder = MIDIStreamDecoder()
        XCTAssertEqual(decoder.feed([0xf0, 0, 0x20, 0xf8]), [.realtime(0xf8)])
        XCTAssertEqual(decoder.feed([0x3c, 0x15]), [])
        XCTAssertEqual(decoder.feed([0xfa, 0, 1, 0xf7]), [.realtime(0xfa), .sysEx([0xf0, 0, 0x20, 0x3c, 0x15, 0, 1, 0xf7])])
    }

    func testLargeFragmentedSysExKeepsExactFrameAndRealtimeOrder() {
        let encoded = (0..<15_000).flatMap { _ in [UInt8](arrayLiteral: 0x55, 1, 2, 3, 4, 5, 6, 7) }
        let checksum = (113 * 15_000) % 16_384
        let count = (encoded.count + 5) % 16_384
        let frame: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x50, 1, 1, 0] + encoded
            + [UInt8(checksum >> 7), UInt8(checksum & 127), UInt8(count >> 7), UInt8(count & 127), 0xf7]
        var decoder = MIDIStreamDecoder()
        var actual: [MIDIMessage] = []
        var realtime: [MIDIMessage] = []
        // CoreMIDI packets can split anywhere, including inside packing groups.
        // Mixed real-time statuses must survive without entering the SysEx data.
        for (packet, offset) in stride(from: 0, to: frame.count, by: 227).enumerated() {
            var fragment = Array(frame[offset..<min(offset + 227, frame.count)])
            if packet % 17 == 0 {
                let byte = [UInt8](arrayLiteral: 0xf8, 0xfa, 0xfe)[packet % 3]
                fragment.insert(byte, at: fragment.count / 2)
                realtime.append(.realtime(byte))
            }
            actual += decoder.feed(fragment)
        }
        XCTAssertEqual(actual, realtime + [.sysEx(frame)])
        XCTAssertEqual(decoder.feed([7, 100]), []) // SysEx cancels running status.
        XCTAssertEqual(decoder.feed([0x90, 60, 100]), [.channel(status: 0x90, data: [60, 100])])
    }

    func testRunningStatusAcrossPacketsAndRealtime() {
        var decoder = MIDIStreamDecoder()
        XCTAssertEqual(decoder.feed([0x92, 60]), [])
        XCTAssertEqual(decoder.feed([0xf8, 100, 64, 90]), [.realtime(0xf8), .channel(status: 0x92, data: [60, 100]), .channel(status: 0x92, data: [64, 90])])
        XCTAssertEqual(decoder.feed([0xc2, 5, 7]), [.channel(status: 0xc2, data: [5]), .channel(status: 0xc2, data: [7])])
    }

    func testSystemCommonCancelsChannelRunningStatus() {
        var decoder = MIDIStreamDecoder()
        XCTAssertEqual(decoder.feed([0xb0, 7, 100, 0xf2, 1, 2, 7, 20]),
                       [.channel(status: 0xb0, data: [7, 100]), .system(status: 0xf2, data: [1, 2])])
        XCTAssertEqual(decoder.feed([0xf6]), [.system(status: 0xf6, data: [])])
        XCTAssertEqual(decoder.feed([0xf0, 1, 0xf0, 2, 0xf7]), [.sysEx([0xf0, 2, 0xf7])])
    }

    func testNewChannelStatusAbortsIncompleteSysExAndIsProcessed() {
        var decoder = MIDIStreamDecoder()
        XCTAssertEqual(decoder.feed([0xf0, 1, 2, 0x90, 60, 100]), [.channel(status: 0x90, data: [60, 100])])
    }

    func testUndefinedSystemCommonDoesNotBecomeADataMessage() {
        var decoder = MIDIStreamDecoder()
        XCTAssertEqual(decoder.feed([0xf4, 1, 0xf5, 2, 0xf7]), [])
    }

    func testNRPNSelectionAndValuesAreIsolatedPerChannel() {
        var decoder = NRPNDecoder()
        XCTAssertNil(decoder.receive(channel: 0, cc: 99, value: 1))
        XCTAssertNil(decoder.receive(channel: 0, cc: 98, value: 73))
        XCTAssertNil(decoder.receive(channel: 3, cc: 99, value: 2))
        XCTAssertNil(decoder.receive(channel: 3, cc: 98, value: 9))
        XCTAssertEqual(decoder.receive(channel: 0, cc: 6, value: 4), ParameterEvent(channel: 0, nrpn: 201, cc: nil, value: 512, resolution: 16383))
        XCTAssertNil(decoder.receive(channel: 3, cc: 38, value: 8))
        XCTAssertEqual(decoder.receive(channel: 3, cc: 6, value: 10), ParameterEvent(channel: 3, nrpn: 265, cc: nil, value: 1280, resolution: 16383))
        XCTAssertEqual(decoder.receive(channel: 0, cc: 38, value: 5), ParameterEvent(channel: 0, nrpn: 201, cc: nil, value: 517, resolution: 16383))
        XCTAssertEqual(decoder.receive(channel: 0, cc: 16, value: 100), ParameterEvent(channel: 0, nrpn: nil, cc: 16, value: 100, resolution: 127))
    }

    func testRPNSelectionAndNullNRPNInvalidateDataEntry() {
        var decoder = NRPNDecoder()
        _ = decoder.receive(channel: 0, cc: 99, value: 1)
        _ = decoder.receive(channel: 0, cc: 98, value: 20)
        _ = decoder.receive(channel: 0, cc: 6, value: 80)
        _ = decoder.receive(channel: 0, cc: 101, value: 0)
        XCTAssertNil(decoder.receive(channel: 0, cc: 6, value: 81))
        XCTAssertNil(decoder.receive(channel: 0, cc: 38, value: 40))
        _ = decoder.receive(channel: 0, cc: 99, value: 1)
        XCTAssertNil(decoder.receive(channel: 0, cc: 6, value: 82))
        _ = decoder.receive(channel: 0, cc: 98, value: 20)
        _ = decoder.receive(channel: 0, cc: 100, value: 0)
        XCTAssertNil(decoder.receive(channel: 0, cc: 6, value: 83))
        _ = decoder.receive(channel: 0, cc: 99, value: 127)
        _ = decoder.receive(channel: 0, cc: 98, value: 127)
        XCTAssertNil(decoder.receive(channel: 0, cc: 6, value: 84))
        XCTAssertNil(decoder.receive(channel: 0, cc: 38, value: 1))
    }

    func testNRPNBytesAgainstIndependentMIDIWireSequence() throws {
        XCTAssertEqual(try MIDIBytes.nrpn(channel: 15, parameter: 201, value: 8193),
                       [0xbf, 99, 1, 0xbf, 98, 73, 0xbf, 6, 64, 0xbf, 38, 1])
        XCTAssertThrowsError(try MIDIBytes.nrpn(channel: 16, parameter: 201, value: 1))
        XCTAssertThrowsError(try MIDIBytes.nrpn(channel: 0, parameter: 16384, value: 1))
        XCTAssertThrowsError(try MIDIBytes.nrpn(channel: 0, parameter: 201, value: -1))
        var decoder = NRPNDecoder()
        XCTAssertNil(decoder.receive(channel: -1, cc: 16, value: 3))
        XCTAssertNil(decoder.receive(channel: 16, cc: 16, value: 3))
        XCTAssertNil(decoder.receive(channel: 0, cc: 128, value: 3))
        XCTAssertNil(decoder.receive(channel: 0, cc: 16, value: 128))
    }
}
