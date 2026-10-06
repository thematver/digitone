import XCTest
@testable import DigitoneDSP

final class TransientDetectorTests: XCTestCase {
    private let rate = 48_000.0

    /// Short decaying noise-like clicks (deterministic) at the given frames.
    private func clickTrain(at positions: [Int], count: Int, amplitudes: [Float]? = nil) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        var seed: UInt32 = 12_345
        for (index, position) in positions.enumerated() {
            let amplitude = amplitudes?[index] ?? 0.9
            for offset in 0..<240 where position + offset < count {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Float(seed >> 8) / Float(1 << 24) * 2 - 1
                samples[position + offset] += amplitude * noise * exp(-Float(offset) / 40)
            }
        }
        return samples
    }

    /// Exponentially decaying sine tones (piano-like) starting at the given frames.
    private func decayingTones(at positions: [Int], frequencies: [Double], count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        for (position, frequency) in zip(positions, frequencies) {
            for offset in 0..<(count - position) {
                let time = Double(offset) / rate
                samples[position + offset] += Float(0.7 * exp(-time * 6) * sin(2 * .pi * frequency * time))
            }
        }
        return samples
    }

    private func assertOnsets(_ found: [Int], match expected: [Int], tolerance: Int = 96,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(found.count, expected.count, "found \(found)", file: file, line: line)
        for (detected, truth) in zip(found, expected) {
            XCTAssertLessThanOrEqual(abs(detected - truth), tolerance, "detected \(detected), expected \(truth)", file: file, line: line)
        }
    }

    func testClickTrainOnsets() {
        let positions = [0, 12_000, 24_000, 30_000, 45_500]
        let samples = clickTrain(at: positions, count: 52_000)
        let onsets = TransientDetector().detect(samples, sampleRate: rate)
        assertOnsets(onsets, match: positions, tolerance: 8)
    }

    func testDecayingTonesOverlappingTails() {
        let positions = [4_800, 28_800, 48_000, 60_000]
        let samples = decayingTones(at: positions, frequencies: [220, 330, 440, 261.6], count: 80_000)
        let onsets = TransientDetector().detect(samples, sampleRate: rate)
        assertOnsets(onsets, match: positions)
    }

    func testSensitivityControlsQuietHits() {
        let positions = [2_000, 14_000, 26_000, 38_000]
        let samples = clickTrain(at: positions, count: 48_000, amplitudes: [0.9, 0.03, 0.9, 0.03])
        let strict = TransientDetector(sensitivity: 0).detect(samples, sampleRate: rate)
        let loose = TransientDetector(sensitivity: 1).detect(samples, sampleRate: rate)
        assertOnsets(strict, match: [2_000, 26_000], tolerance: 8)
        assertOnsets(loose, match: positions, tolerance: 8)
    }

    func testMinimumGapMergesCloseHits() {
        let samples = clickTrain(at: [1_000, 2_200, 20_000], count: 30_000)
        let merged = TransientDetector(sensitivity: 1, minimumGap: 0.1).detect(samples, sampleRate: rate)
        assertOnsets(merged, match: [1_000, 20_000], tolerance: 8)
        let separate = TransientDetector(sensitivity: 1, minimumGap: 0.01).detect(samples, sampleRate: rate)
        assertOnsets(separate, match: [1_000, 2_200, 20_000], tolerance: 8)
    }

    func testSilenceAndStereoInput() {
        XCTAssertEqual(TransientDetector().detect([Float](repeating: 0, count: 10_000), sampleRate: rate), [])
        let mono = clickTrain(at: [5_000], count: 12_000)
        let stereo = SampleBuffer(sampleRate: rate, channels: [mono, [Float](repeating: 0, count: 12_000)])
        assertOnsets(TransientDetector().detect(in: stereo), match: [5_000], tolerance: 8)
    }

    func testEqualSlicesAndRanges() {
        XCTAssertEqual(TransientDetector.equalSlices(frameCount: 100, count: 4), [0, 25, 50, 75])
        XCTAssertEqual(TransientDetector.equalSlices(frameCount: 10, count: 3), [0, 3, 6])
        XCTAssertEqual(TransientDetector.equalSlices(frameCount: 2, count: 8), [0, 1])
        XCTAssertEqual(TransientDetector.equalSlices(frameCount: 0, count: 8), [])
        XCTAssertEqual(TransientDetector.ranges(from: [50, 0, 50, 120], frameCount: 100), [0..<50, 50..<100])
    }

    func testOnsetInPartialFinalRefinementBlock() {
        var samples = [Float](repeating: 0, count: 5_009)
        samples[5_008] = 1
        assertOnsets(TransientDetector(sensitivity: 1).detect(samples, sampleRate: rate), match: [5_008], tolerance: 0)
    }

    func testInvalidConfigurationDoesNotTrap() {
        let samples = clickTrain(at: [2_000], count: 6_000)
        XCTAssertEqual(TransientDetector().detect(samples, sampleRate: .infinity), [])
        XCTAssertEqual(TransientDetector().detect(samples, sampleRate: .nan), [])
        assertOnsets(TransientDetector(sensitivity: .nan, minimumGap: .nan).detect(samples, sampleRate: rate),
                     match: [2_000], tolerance: 8)
    }
}
