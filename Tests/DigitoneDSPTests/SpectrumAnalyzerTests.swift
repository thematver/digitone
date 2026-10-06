import XCTest
@testable import DigitoneDSP

final class SpectrumAnalyzerTests: XCTestCase {
    private func sine(frequency: Double, amplitude: Float = 1, count: Int, sampleRate: Double = 48_000) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func loudestBand(_ spectrum: Spectrum) -> Int {
        spectrum.magnitudes.indices.max { spectrum.magnitudes[$0] < spectrum.magnitudes[$1] } ?? -1
    }

    func testBandsAreLogSpacedWithinAudibleRange() {
        let analyzer = SpectrumAnalyzer(fftSize: 2048, bandCount: 32, sampleRate: 48_000)
        let frequencies = analyzer.bandFrequencies
        XCTAssertEqual(frequencies.count, 32)
        XCTAssertGreaterThan(frequencies[0], 20)
        XCTAssertLessThan(frequencies[31], 20_000)
        let ratio = frequencies[1] / frequencies[0]
        for index in 1..<frequencies.count {
            XCTAssertEqual(frequencies[index] / frequencies[index - 1], ratio, accuracy: 1e-3)
        }
        // Nyquist caps the range at low sample rates.
        let low = SpectrumAnalyzer(fftSize: 1024, bandCount: 16, sampleRate: 22_050)
        XCTAssertLessThan(low.bandFrequencies.last ?? 0, 11_025)
    }

    func testFullScaleSineReadsNearZeroDecibelsInMatchingBand() {
        let analyzer = SpectrumAnalyzer(fftSize: 4096, bandCount: 48, sampleRate: 48_000)
        for frequency in [100.0, 440.0, 1_000.0, 5_000.0, 12_000.0] {
            let samples = sine(frequency: frequency, count: 4096)
            let spectrum = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
            XCTAssertEqual(spectrum.magnitudes.count, 48)
            let band = loudestBand(spectrum)
            XCTAssertEqual(spectrum.magnitudes[band], 0, accuracy: 1.6, "peak level at \(frequency) Hz")
            // The loudest band brackets the tone (within one band of rounding).
            let centre = Double(spectrum.bandFrequencies[band])
            let ratio = Double(spectrum.bandFrequencies[1] / spectrum.bandFrequencies[0])
            XCTAssertLessThan(abs(log(centre / frequency)), log(ratio) * 1.01, "band for \(frequency) Hz")
            // Far-away bands are strongly attenuated.
            XCTAssertLessThan(spectrum.magnitudes[band > 24 ? 0 : 47], -60)
        }
    }

    func testHalfAmplitudeReadsMinusSixDecibels() {
        let analyzer = SpectrumAnalyzer(fftSize: 2048, bandCount: 64, sampleRate: 48_000)
        let samples = sine(frequency: 1_500, amplitude: 0.5, count: 2048)
        let spectrum = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(spectrum.magnitudes[loudestBand(spectrum)], -6.02, accuracy: 1.6)
    }

    func testSilenceReadsFloor() {
        let analyzer = SpectrumAnalyzer(fftSize: 1024, bandCount: 24, sampleRate: 44_100)
        let zeros = [Float](repeating: 0, count: 1024)
        let spectrum = zeros.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(spectrum.magnitudes, [Float](repeating: SpectrumAnalyzer.floorDecibels, count: 24))
        let empty = [Float]().withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(empty.magnitudes.count, 24)
        XCTAssertTrue(empty.magnitudes.allSatisfy { $0 == SpectrumAnalyzer.floorDecibels })
    }

    func testUsesMostRecentSamplesAndZeroPadsShortInput() {
        let analyzer = SpectrumAnalyzer(fftSize: 1024, bandCount: 32, sampleRate: 48_000)
        // Loud history followed by silence: only the last fftSize samples count.
        let samples = sine(frequency: 1_000, count: 4096) + [Float](repeating: 0, count: 1024)
        let spectrum = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertTrue(spectrum.magnitudes.allSatisfy { $0 == SpectrumAnalyzer.floorDecibels })
        let short = sine(frequency: 2_000, count: 512)
        let padded = short.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertTrue(padded.magnitudes.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(padded.magnitudes.max() ?? -200, -12)
    }

    func testEveryBandHasAValueWithSmallFFT() {
        // 64-point FFT at 48 kHz: 750 Hz bins, so most low bands contain no bin.
        let analyzer = SpectrumAnalyzer(fftSize: 64, bandCount: 64, sampleRate: 48_000)
        let samples = sine(frequency: 3_000, count: 64)
        let spectrum = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertEqual(spectrum.magnitudes.count, 64)
        XCTAssertTrue(spectrum.magnitudes.allSatisfy { $0.isFinite && $0 >= SpectrumAnalyzer.floorDecibels })
    }

    func testLowSampleRateNeverReportsBandsAboveNyquist() {
        let analyzer = SpectrumAnalyzer(fftSize: 64, bandCount: 16, sampleRate: 30)
        XCTAssertTrue(analyzer.bandFrequencies.allSatisfy { $0 > 0 && $0 < 15 })
        let spectrum = [Float](repeating: 0, count: 64).withUnsafeBufferPointer { analyzer.analyze($0) }
        XCTAssertTrue(spectrum.magnitudes.allSatisfy(\.isFinite))
    }
}
