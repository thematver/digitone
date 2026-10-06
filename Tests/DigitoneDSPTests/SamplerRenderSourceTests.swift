import XCTest
import Dispatch
@testable import DigitoneDSP

final class SamplerRenderSourceTests: XCTestCase {
    private func assertSamples(_ actual: [Float], _ expected: [Float],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (value, truth) in zip(actual, expected) {
            XCTAssertEqual(value, truth, accuracy: 1e-6, file: file, line: line)
        }
    }
    private func render(_ source: SamplerRenderSource, count: Int, initial: Float = 0) -> [[Float]] {
        var left = [Float](repeating: initial, count: count)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                source.render(frameCount: count, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        return [left, right]
    }

    func testOneShotMixesStereoAndStopsAtEnd() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[0.1, 0.2, 0.3], [-0.1, -0.2, -0.3]]))
        source.prepare(sampleRate: 48_000, maximumFrames: 32)
        source.noteOn(note: 60, velocity: 127)
        source.noteOff(note: 60)
        let output = render(source, count: 5, initial: 0.25)
        assertSamples(output[0], [0.35, 0.45, 0.55, 0.25, 0.25])
        assertSamples(output[1], [0.15, 0.05, -0.05, 0.25, 0.25])
        XCTAssertEqual(render(source, count: 2), [[0, 0], [0, 0]])
    }

    func testMonoVelocityAndChromaticPitch() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[0, 0.1, 0.2, 0.3, 0.4, 0.5]]), interpolation: .linear)
        source.prepare(sampleRate: 48_000, maximumFrames: 16)
        source.noteOn(note: 72, velocity: 127)
        XCTAssertEqual(render(source, count: 4), [[0, 0.2, 0.4, 0], [0, 0.2, 0.4, 0]])
        source.noteOn(note: 60, velocity: 64)
        let output = render(source, count: 3)
        XCTAssertEqual(output[0][1], 0.1 * 64 / 127, accuracy: 1e-6)
        XCTAssertEqual(output[0], output[1])
    }

    func testRateConversionAndSlicesMapToPadNotes() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 24_000,
            channels: [[0, 0.2, 0.4, 0.6, 0.8, 1]]),
            slices: [0..<3, 3..<6], interpolation: .linear)
        source.prepare(sampleRate: 48_000, maximumFrames: 16)
        source.triggerSlice(1, velocity: 127)
        assertSamples(render(source, count: 6)[0], [0.6, 0.7, 0.8, 0.9, 1, 1])
        source.noteOn(note: 36, velocity: 127)
        XCTAssertEqual(render(source, count: 3)[0], [0, 0.1, 0.2])
    }

    func testLoopWrapsInterpolationInsideSliceAndStopsOnRelease() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 24_000,
            channels: [[-9, 0, 1, 9]]), slices: [1..<3], mode: .loop, interpolation: .linear)
        source.prepare(sampleRate: 48_000, maximumFrames: 16)
        source.noteOn(note: 36, velocity: 127)
        XCTAssertEqual(render(source, count: 8)[0], [0, 0.5, 1, 0.5, 0, 0.5, 1, 0.5])
        source.noteOff(note: 36)
        XCTAssertEqual(render(source, count: 2)[0], [0, 0])
    }

    func testPolyphonyAndAllNotesOffIncludingQueuedOnsets() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[1, 1, 1, 1]]), maximumVoices: 2)
        source.prepare(sampleRate: 48_000, maximumFrames: 16)
        source.noteOn(note: 60, velocity: 127)
        source.noteOn(note: 72, velocity: 127)
        XCTAssertEqual(render(source, count: 1)[0], [2])
        source.noteOn(note: 64, velocity: 127)
        source.allNotesOff()
        XCTAssertEqual(render(source, count: 2)[0], [0, 0])
        source.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(source, count: 1)[0], [1])
    }

    func testOldestVoiceIsStolenAndSameNoteRetriggers() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[0.1, 0.2, 0.3, 0.4]]), maximumVoices: 1)
        source.prepare(sampleRate: 48_000, maximumFrames: 16)
        source.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(source, count: 2)[0], [0.1, 0.2])
        source.noteOn(note: 72, velocity: 127)
        XCTAssertEqual(render(source, count: 2)[0], [0.1, 0.3])
        source.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(source, count: 1)[0], [0.1])
        source.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(source, count: 1)[0], [0.1])
    }

    func testEmptyBufferInvalidNotesAndEmptySliceRemainSilent() {
        let empty = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000, channels: [[]]))
        empty.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(empty, count: 2)[0], [0, 0])
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000, channels: [[1, 2]]),
            slices: [5..<8, 0..<2], maximumVoices: 1)
        source.noteOn(note: -1, velocity: 127)
        source.noteOn(note: 128, velocity: 127)
        source.triggerSlice(0, velocity: 127)
        source.triggerSlice(90)
        XCTAssertEqual(render(source, count: 2)[0], [0, 0])
        source.triggerSlice(1, velocity: 127)
        XCTAssertEqual(render(source, count: 2)[0], [1, 2])
    }

    func testPendingGateReleaseCoalescesAndNonFiniteAudioIsSanitized() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[.nan, .infinity, 0.25]]), mode: .gate)
        source.noteOn(note: 60, velocity: 127)
        source.noteOff(note: 60)
        XCTAssertEqual(render(source, count: 3)[0], [0, 0, 0])
        source.noteOn(note: 60, velocity: 127)
        XCTAssertEqual(render(source, count: 3)[0], [0, 0, 0.25])
    }

    func testNoteProducersCanRunConcurrentlyWithRender() {
        let source = SamplerRenderSource(sample: SampleBuffer(sampleRate: 48_000,
            channels: [[0.1, 0.2, -0.1, -0.2]]), mode: .loop)
        source.prepare(sampleRate: 48_000, maximumFrames: 32)
        let producers = DispatchGroup()
        for producer in 0..<4 {
            DispatchQueue.global().async(group: producers) {
                let note = 60 + producer
                for index in 0..<4_000 {
                    source.noteOn(note: note, velocity: 1 + index % 127)
                    if index % 3 == 0 { source.noteOff(note: note) }
                }
            }
        }
        for _ in 0..<256 {
            let output = render(source, count: 32)
            XCTAssertTrue(output[0].allSatisfy(\.isFinite))
            XCTAssertTrue(output[1].allSatisfy(\.isFinite))
        }
        producers.wait()
        source.allNotesOff()
        XCTAssertEqual(render(source, count: 32)[0], [Float](repeating: 0, count: 32))
    }
}
