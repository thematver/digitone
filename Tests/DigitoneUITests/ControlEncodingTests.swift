import XCTest
import DigitoneCore
@testable import DigitoneUI

/// Pure value encoding, clamping and rate limiting of the device control surface.
final class ControlEncodingTests: XCTestCase {
    private let attack = DNParameter(id: "t.atk", page: .fltr1, slot: 0, label: "ATK", name: "Attack", cc: 20, nrpn: 128 + 16)
    private let frequency = DNParameter(id: "t.freq", page: .fltr1, slot: 4, label: "FREQ", name: "Frequency",
                                        cc: 16, nrpn: 128 + 20, isHighResolution: true)
    private let filterTrig = DNParameter(id: "t.fltt", page: .trig, slot: 5, label: "FLT.T", name: "Filter Trig",
                                         cc: 13, nrpn: nil, format: .toggle)
    private let mode = DNParameter(id: "t.mode", page: .amp, slot: 5, label: "MODE", name: "Mode", cc: 91, nrpn: 128 + 40,
                                   format: .options(["AHD", "ADSR"]))
    private let multiplier = DNParameter(id: "t.mult", page: .mod1, slot: 1, label: "MULT", name: "Multiplier", cc: 103,
                                         nrpn: 128 + 43, format: .number(1...16, offset: 1))

    func testParameterWithoutNRPNSendsCoarseCC() {
        let message = ControlEncoding.message(for: filterTrig, value14: 127 << 7, channel: 3)
        XCTAssertEqual(message, .cc(channel: 3, controller: 13, value: 127))
        XCTAssertEqual(message?.bytes, [0xb3, 13, 127])
    }

    func testLowResolutionNRPNSendsCoarseMSBAndZeroLSB() {
        let message = ControlEncoding.message(for: attack, value14: 100 << 7 | 55, channel: 0)
        XCTAssertEqual(message, .nrpn(channel: 0, parameter: 144, value: 100 << 7))
        XCTAssertEqual(message?.bytes, [0xb0, 99, 1, 0xb0, 98, 16, 0xb0, 6, 100, 0xb0, 38, 0])
    }

    func testHighResolutionNRPNSendsFineLSB() {
        let message = ControlEncoding.message(for: frequency, value14: 64 << 7 | 33, channel: 15)
        XCTAssertEqual(message, .nrpn(channel: 15, parameter: 148, value: 64 << 7 | 33))
        XCTAssertEqual(message?.bytes, [0xbf, 99, 1, 0xbf, 98, 20, 0xbf, 6, 64, 0xbf, 38, 33])
    }

    func testValuesClampToTheParameterRangeAndSevenBits() {
        XCTAssertEqual(ControlEncoding.clamp(20_000, for: frequency), 16383)
        XCTAssertEqual(ControlEncoding.clamp(-5, for: attack), 0)
        XCTAssertEqual(ControlEncoding.clamp(127 << 7 | 99, for: attack), 127 << 7, "7-bit parameters drop fine bits")
        XCTAssertEqual(ControlEncoding.clamp(5 << 7, for: mode), 1 << 7, "two options: 0...1")
        XCTAssertEqual(multiplier.rawRange, 0...15)
        XCTAssertEqual(ControlEncoding.clamp(127 << 7, for: multiplier), 15 << 7)
        XCTAssertEqual(ControlEncoding.message(for: filterTrig, value14: 300 << 7, channel: 0), .cc(channel: 0, controller: 13, value: 127))
        XCTAssertNil(ControlEncoding.message(for: attack, value14: 0, channel: 16), "no channel 17")
        XCTAssertEqual(ControlMessage.cc(channel: 20, controller: 200, value: -3).bytes, [0xbf, 127, 0])
    }

    func testFractionsRoundTripAndRespectResolution() {
        XCTAssertEqual(attack.value14(atFraction: 0.5), 64 << 7)
        XCTAssertEqual(attack.fraction(of: 127 << 7), 1)
        XCTAssertEqual(frequency.value14(atFraction: 1), 127 << 7, "top of the range is the top coarse value")
        let fine = frequency.value14(atFraction: 0.501)
        XCTAssertNotEqual(fine & 127, 0, "high-resolution keeps fine steps")
        XCTAssertEqual(mode.value14(atFraction: 0.9), 1 << 7)
        XCTAssertEqual(multiplier.fraction(of: 15 << 7), 1)
        XCTAssertEqual(frequency.display(64 << 7 | 64), "64.50")
        XCTAssertEqual(mode.display(1 << 7), "ADSR")
    }

    func testIncomingResolutionBecomesFourteenBits() throws {
        var decoder = NRPNDecoder()
        let cc = try XCTUnwrap(decoder.receive(channel: 0, cc: 16, value: 100))
        XCTAssertEqual(ControlEncoding.value14(of: cc), 100 << 7)
        _ = decoder.receive(channel: 0, cc: 99, value: 1)
        _ = decoder.receive(channel: 0, cc: 98, value: 20)
        _ = decoder.receive(channel: 0, cc: 6, value: 64)
        let nrpn = try XCTUnwrap(decoder.receive(channel: 0, cc: 38, value: 9))
        XCTAssertEqual(ControlEncoding.value14(of: nrpn), 64 << 7 | 9)
    }

    func testProgramChangeMath() {
        XCTAssertEqual(ControlEncoding.program(bank: 0, pattern: 0), 0)
        XCTAssertEqual(ControlEncoding.program(bank: 2, pattern: 4), 36)
        XCTAssertEqual(ControlEncoding.program(bank: 7, pattern: 15), 127)
        XCTAssertEqual(ControlEncoding.program(bank: 9, pattern: -1), 112, "clamped to H01")
        XCTAssertEqual(PatternSnapshot.slotName(36), "C05")
        XCTAssertEqual(ControlMessage.programChange(channel: 9, program: 36).bytes, [0xc9, 36])
    }

    func testMuteIsCC94() {
        XCTAssertEqual(ControlEncoding.mute(true, channel: 4).bytes, [0xb4, 94, 127])
        XCTAssertEqual(ControlEncoding.mute(false, channel: 4).bytes, [0xb4, 94, 0])
        XCTAssertEqual(ControlMessage.start.bytes, [0xfa])
        XCTAssertEqual(ControlMessage.stop.bytes, [0xfc])
    }

    func testThrottleSendsFirstQueuesNewestAndReleasesFinalValue() {
        var throttle = SendThrottle<String, Int>(interval: 1.0 / 60)
        XCTAssertEqual(throttle.offer(1, for: "freq", at: 0), 1)
        XCTAssertNil(throttle.offer(2, for: "freq", at: 0.005))
        XCTAssertNil(throttle.offer(3, for: "freq", at: 0.010))
        XCTAssertEqual(throttle.offer(9, for: "other", at: 0.010), 9, "keys are limited independently")
        XCTAssertTrue(throttle.due(at: 0.012).isEmpty, "slot not reached")
        XCTAssertEqual(throttle.nextDue ?? 0, 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(throttle.due(at: 0.02).map(\.payload), [3], "only the newest value goes out")
        XCTAssertNil(throttle.offer(4, for: "freq", at: 0.025))
        XCTAssertEqual(throttle.flush("freq", at: 0.026), 4, "gesture end releases immediately")
        XCTAssertNil(throttle.flush("freq", at: 0.027))
        XCTAssertTrue(throttle.pending.isEmpty)
    }
}
