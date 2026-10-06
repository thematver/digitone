import XCTest
@testable import DigitoneDSP

final class AnalysisTests: XCTestCase {
    func testPeaksSplitIntoBins() {
        let samples: [Float] = [0, 1, -1, 0.5, -0.5, 0, 0.25, -0.25]
        let peaks = WaveformPeaks.compute(samples, bins: 4)
        XCTAssertEqual(peaks.count, 4)
        XCTAssertEqual(peaks[0].max, 1)
        XCTAssertEqual(peaks[1].min, -1)
    }

    func testSilenceIsMinusInfinity() {
        let zeros = [Float](repeating: 0, count: 64)
        zeros.withUnsafeBufferPointer { XCTAssertEqual(LevelMeter.measure($0), .silent) }
    }
}
