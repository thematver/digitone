import XCTest
@testable import DigitoneAudio

final class AudioModuleTests: XCTestCase {
    func testPreferredRateMatchesDigitone() {
        XCTAssertEqual(DigitoneAudioModule.preferredSampleRate, 48_000)
    }
}
