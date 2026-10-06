import XCTest
@testable import DigitoneDSP

final class SampleMathTests: XCTestCase {
    private func mono(_ samples: [Float], rate: Double = 48_000) -> SampleBuffer {
        SampleBuffer(sampleRate: rate, channels: [samples])
    }

    private func sine(_ frequency: Double, count: Int, rate: Double, amplitude: Float = 1) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    func testNormalizeAndGain() {
        let buffer = SampleBuffer(sampleRate: 48_000, channels: [[0.1, -0.25, 0.2], [0, 0.05, -0.1]])
        let normalized = SampleMath.normalize(buffer, peakDecibels: 0)
        XCTAssertEqual(SampleMath.peak(normalized), 1, accuracy: 1e-6)
        XCTAssertEqual(normalized.channels[0][1], -1, accuracy: 1e-6)
        XCTAssertEqual(normalized.channels[1][2], -0.4, accuracy: 1e-6)
        let quieter = SampleMath.normalize(buffer, peakDecibels: -6)
        XCTAssertEqual(SampleMath.peak(quieter), 0.501, accuracy: 1e-3)
        XCTAssertEqual(SampleMath.gain(buffer, decibels: 20).channels[0][0], 1, accuracy: 1e-5)
        let silence = mono([0, 0, 0])
        XCTAssertEqual(SampleMath.normalize(silence), silence)
    }

    func testTrimSilenceKeepsLoudRegion() {
        let buffer = SampleBuffer(sampleRate: 48_000, channels: [
            [0, 0.0001, 0.5, 0.2, 0, 0],
            [0, 0, 0, 0, 0.3, 0.00001]
        ])
        let trimmed = SampleMath.trimSilence(buffer, thresholdDecibels: -40)
        XCTAssertEqual(trimmed.channels, [[0.5, 0.2, 0], [0, 0, 0.3]])
        let empty = SampleMath.trimSilence(mono([0, 0.001]), thresholdDecibels: -40)
        XCTAssertEqual(empty.frameCount, 0)
        XCTAssertEqual(empty.channelCount, 1)
    }

    func testFadesReverseAndSlice() {
        let ones = mono([Float](repeating: 1, count: 8))
        let fadedIn = SampleMath.fadeIn(ones, frames: 4)
        XCTAssertEqual(fadedIn.channels[0], [0, 0.25, 0.5, 0.75, 1, 1, 1, 1])
        let fadedOut = SampleMath.fadeOut(ones, frames: 3)
        XCTAssertEqual(fadedOut.channels[0], [1, 1, 1, 1, 1, 1, 0.5, 0])
        let equalPower = SampleMath.fadeIn(ones, frames: 2, curve: .equalPower)
        XCTAssertEqual(equalPower.channels[0][1], sin(.pi / 4), accuracy: 1e-6)
        XCTAssertEqual(SampleMath.fadeIn(ones, frames: 100).channels[0][7], 0.875)

        let ramp = mono([1, 2, 3, 4, 5])
        XCTAssertEqual(SampleMath.reverse(ramp).channels[0], [5, 4, 3, 2, 1])
        XCTAssertEqual(SampleMath.slice(ramp, 1..<3).channels[0], [2, 3])
        XCTAssertEqual(SampleMath.slice(ramp, -4..<99).channels[0], [1, 2, 3, 4, 5])
        XCTAssertEqual(SampleMath.slice(ramp, 7..<9).frameCount, 0)
    }

    func testChannelConversion() {
        let stereo = SampleBuffer(sampleRate: 44_100, channels: [[1, 0], [0, 1]])
        XCTAssertEqual(SampleMath.toMono(stereo).channels, [[0.5, 0.5]])
        let mono = mono([0.25, -0.5])
        XCTAssertEqual(SampleMath.toStereo(mono).channels, [[0.25, -0.5], [0.25, -0.5]])
        XCTAssertEqual(SampleMath.toStereo(stereo), stereo)
        let surround = SampleBuffer(sampleRate: 48_000, channels: [[1], [2], [3]])
        XCTAssertEqual(SampleMath.toStereo(surround).channels, [[1], [2]])
    }

    func testResampleKeepsDurationAndPitch() {
        let source = mono(sine(440, count: 44_100, rate: 44_100, amplitude: 0.8), rate: 44_100)
        for quality in SampleMath.ResampleQuality.allCases {
            let output = SampleMath.resample(source, to: 48_000, quality: quality)
            XCTAssertEqual(output.sampleRate, 48_000)
            XCTAssertEqual(output.frameCount, 48_000)
            // Compare against an ideal 440 Hz sine at the new rate, away from the edges.
            let expected = sine(440, count: 48_000, rate: 48_000, amplitude: 0.8)
            var worst: Float = 0
            for index in 100..<47_900 { worst = max(worst, abs(output.channels[0][index] - expected[index])) }
            XCTAssertLessThan(worst, 0.01, "\(quality)")
        }
    }

    func testSincDownsamplingRejectsContentAboveNewNyquist() {
        // 15 kHz at 48 kHz must not alias into a 16 kHz-rate result.
        let source = mono(sine(15_000, count: 48_000, rate: 48_000), rate: 48_000)
        let output = SampleMath.resample(source, to: 16_000, quality: .sinc)
        XCTAssertEqual(output.frameCount, 16_000)
        let body = SampleBuffer(sampleRate: 16_000, channels: [Array(output.channels[0][200..<15_800])])
        XCTAssertLessThan(SampleMath.peak(body), 0.05)
    }

    func testConcatenateMatchesRateAndChannels() {
        let a = mono([1, 2], rate: 48_000)
        let b = SampleBuffer(sampleRate: 48_000, channels: [[3], [4]])
        let joined = SampleMath.concatenate([a, b])
        XCTAssertEqual(joined?.channels, [[1, 2, 3], [1, 2, 4]])
        let c = mono([Float](repeating: 0.5, count: 2_400), rate: 24_000)
        let mixed = SampleMath.concatenate([a, c])
        XCTAssertEqual(mixed?.sampleRate, 48_000)
        XCTAssertEqual(mixed?.frameCount, 2 + 4_800)
        XCTAssertNil(SampleMath.concatenate([]))
    }

    func testEmptyEditedBuffersCanBeMeasuredAndResampled() {
        let empty = SampleMath.trimSilence(mono([0, 0, 0]))
        XCTAssertEqual(SampleMath.peak(empty), 0)
        XCTAssertEqual(SampleMath.normalize(empty), empty)
        let converted = SampleMath.resample(empty, to: 44_100)
        XCTAssertEqual(converted.frameCount, 0)
        XCTAssertEqual(converted.sampleRate, 44_100)
        XCTAssertEqual(SampleMath.trimSilence(mono([0, 0]), thresholdDecibels: -.infinity).frameCount, 0)
        XCTAssertEqual(SampleMath.resample(mono([1, 2]), to: .nan), mono([1, 2]))
        XCTAssertEqual(SampleMath.resample(mono([1, 2]), to: .infinity), mono([1, 2]))
    }
}
