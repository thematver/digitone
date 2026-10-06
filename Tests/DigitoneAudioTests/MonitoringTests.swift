import XCTest
@testable import DigitoneAudio

final class MonitoringTests: XCTestCase {
    private let digitone = AudioDevice(id: "dn", name: "Digitone II", inputChannels: 2, outputChannels: 2, nominalSampleRate: 48_000, transport: .usb)
    private let speakers = AudioDevice(id: "speakers", name: "MacBook Pro Speakers", inputChannels: 0, outputChannels: 2, transport: .builtIn)
    private let headphones = AudioDevice(id: "headphones", name: "Headphones", inputChannels: 0, outputChannels: 2, transport: .builtIn)
    private let microphone = AudioDevice(id: "mic", name: "MacBook Pro Microphone", inputChannels: 1, outputChannels: 0, transport: .builtIn)

    func testAutomaticRouteUsesDigitoneInputAndComputerOutputEvenWhenDigitoneIsSystemDefault() {
        let policy = AudioRoutePolicy()
        let devices = [digitone, microphone, speakers, headphones]
        XCTAssertEqual(policy.input(in: devices, defaultID: microphone.id), digitone)
        XCTAssertEqual(policy.output(in: devices, defaultID: digitone.id), speakers)
        XCTAssertEqual(policy.output(in: devices, defaultID: headphones.id), headphones)
        XCTAssertNil(policy.output(in: [digitone], defaultID: digitone.id))
        XCTAssertNil(policy.monitorBlock(input: digitone, output: speakers, permission: .granted))
        XCTAssertEqual(policy.monitorBlock(input: digitone, output: nil, permission: .granted), .noOutput)
    }

    func testExplicitInterfaceOutputIsBlockedAndBuiltinMicrophoneIsNeverAutomaticallyMonitored() {
        let policy = AudioRoutePolicy(pinnedOutputID: digitone.id)
        XCTAssertEqual(policy.output(in: [digitone, speakers], defaultID: speakers.id), digitone)
        XCTAssertEqual(policy.monitorBlock(input: digitone, output: digitone, permission: .granted), .sameDevice)
        XCTAssertEqual(policy.monitorBlock(input: microphone, output: speakers, permission: .granted), .noDigitone)
        XCTAssertEqual(policy.monitorBlock(input: digitone, output: speakers, permission: .denied), .permissionDenied)
        XCTAssertNil(AudioRoutePolicy(pinnedInputID: microphone.id).monitorBlock(input: microphone, output: headphones, permission: .granted))
    }

    func testIOSActualUSBOutputRemainsVisibleToFeedbackGuard() {
        let policy = AudioRoutePolicy(treatUSBPairAsSameDevice: true, followsSessionOutput: true)
        let output = AudioDevice(id: "dn-output", name: "Digitone II output", inputChannels: 0, outputChannels: 2, transport: .usb)
        XCTAssertEqual(policy.output(in: [output], defaultID: output.id), output)
        XCTAssertEqual(policy.monitorBlock(input: digitone, output: output, permission: .granted), .sameDevice)
    }

    func testSettingsPersistUserOffAndClampInvalidGain() throws {
        let suite = "digitone-monitor-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = MonitorSettings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.gain, 0.8)
        settings.isEnabled = false
        settings.gain = 2
        XCTAssertFalse(MonitorSettings(defaults: defaults).isEnabled)
        XCTAssertEqual(MonitorSettings(defaults: defaults).gain, 1)
        settings.gain = .nan
        XCTAssertEqual(settings.gain, MonitorSettings.defaultGain)
    }

    func testRingDuplicatesMonoAndDropsWholeBlockWhenFull() {
        let ring = MonitorRing(capacity: 64)
        let data = (0..<64).map(Float.init)
        data.withUnsafeBufferPointer { XCTAssertTrue(ring.write(left: $0.baseAddress!, right: nil, frames: $0.count)) }
        XCTAssertEqual(ring.written, 64)
        XCTAssertEqual(ring.sample(ring.left, at: 19), 19)
        XCTAssertEqual(ring.sample(ring.right, at: 19), 19)
        data.withUnsafeBufferPointer { XCTAssertFalse(ring.write(left: $0.baseAddress!, right: nil, frames: 1)) }
        XCTAssertEqual(ring.written, 64)
        XCTAssertEqual(ring.droppedWrites, 1)
        ring.release(upTo: 32)
        data.withUnsafeBufferPointer { XCTAssertTrue(ring.write(left: $0.baseAddress!, right: nil, frames: 32)) }
        XCTAssertEqual(ring.written, 96)
        XCTAssertEqual(ring.sample(ring.left, at: 80), 16)
    }

    func testMonitorNewSourceAndReprimeDiscardQueuedAudio() {
        let ring = MonitorRing()
        write(0.9, frames: 512, to: ring)
        let source = MonitorSource(ring: ring, sampleRate: 48_000)
        source.targetGain = 1
        XCTAssertEqual(render(source, frames: 64), [Float](repeating: 0, count: 64))
        write(0.25, frames: 512, to: ring)
        let fresh = render(source, frames: 64)
        XCTAssertGreaterThan(fresh.last!, 0)
        XCTAssertLessThan(fresh.max()!, 0.25)
        source.reprime()
        XCTAssertEqual(render(source, frames: 64), [Float](repeating: 0, count: 64))
        write(-0.25, frames: 512, to: ring)
        XCTAssertLessThan(render(source, frames: 64).last!, 0)
    }

    func testMonitorSilencesUnderrunThenRecoversAndCanBeMuted() {
        let ring = MonitorRing()
        let source = MonitorSource(ring: ring, sampleRate: 48_000, targetFill: 128)
        source.targetGain = 0.5
        write(1, frames: 256, to: ring)
        _ = render(source, frames: 64)
        XCTAssertEqual(render(source, frames: 64), [Float](repeating: 0, count: 64))
        XCTAssertEqual(source.underruns, 1)
        XCTAssertEqual(source.targetFill, 192)
        write(1, frames: 512, to: ring)
        XCTAssertGreaterThan(render(source, frames: 64).last!, 0)
        source.targetGain = 0
        write(1, frames: 128, to: ring)
        _ = render(source, frames: 64)
        write(1, frames: 128, to: ring)
        XCTAssertEqual(render(source, frames: 64), [Float](repeating: 0, count: 64))
    }

    func testDriftCorrectionTracksOppositeClockRatesWithinSmallPitchBound() {
        for drift in [-0.000_2, 0.000_2] {
            let rate = 48_000.0
            let block = 128
            var fill = 256.0
            var corrector = DriftCorrector(target: fill)
            for _ in 0..<Int(rate * 180 / Double(block)) {
                let ratio = corrector.update(fill: fill, frames: block, sampleRate: rate)
                XCTAssertLessThanOrEqual(abs(ratio - 1), DriftCorrector.maximumDeviation + 1e-10)
                fill += Double(block) * (1 + drift - ratio)
            }
            XCTAssertEqual(corrector.ratio, 1 + drift, accuracy: 0.000_01)
            XCTAssertEqual(fill, 256, accuracy: 10)
        }
    }

    func testMeterReportsPeakAndRMSThenDecaysAfterInputStops() {
        let meter = StereoMeter()
        _ = meter.read(now: 1)
        [Float](repeating: 0.5, count: 128).withUnsafeBufferPointer {
            meter.tap.accumulate(left: $0.baseAddress!, right: nil, frames: $0.count)
        }
        let first = meter.read(now: 1.05)
        XCTAssertEqual(first.left.peak, 0.5)
        XCTAssertEqual(first.right.peak, 0.5)
        XCTAssertGreaterThan(first.left.rms, 0.4)
        let silent = meter.read(now: 2)
        XCTAssertLessThan(silent.left.peak, 0.05)
        XCTAssertLessThan(silent.left.rms, first.left.rms)
        XCTAssertEqual(ChannelLevel.position(0), 0)
        XCTAssertEqual(ChannelLevel.position(1), 1)
        XCTAssertEqual(ChannelLevel.position(0.001), 0, accuracy: 0.0001)
    }

    private func write(_ value: Float, frames: Int, to ring: MonitorRing) {
        [Float](repeating: value, count: frames).withUnsafeBufferPointer {
            XCTAssertTrue(ring.write(left: $0.baseAddress!, right: nil, frames: frames))
        }
    }

    private func render(_ source: MonitorSource, frames: Int) -> [Float] {
        var left = [Float](repeating: 99, count: frames)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                source.render(frames: frames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        XCTAssertEqual(left, right)
        return left
    }
}
