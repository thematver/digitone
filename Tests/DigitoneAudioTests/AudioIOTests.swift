import AVFoundation
import Foundation
import os
import XCTest
import DigitoneDSP
@testable import DigitoneAudio

final class AudioIOTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-audio-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testRecordingFinalizesPlayableFileAndSecondStartCannotTruncateTake() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("take.wav")
            let recorder = AudioRecorder()
            try recorder.start(url: url, format: .wav24, sampleRate: 48_000, channelCount: 2)
            let samples: [[Float]] = [[0.25, -0.25, 0.5, -0.5], [-0.1, 0.1, 0.2, -0.2]]
            _ = samples.withUnsafeBufferPointers { recorder.append($0) }
            XCTAssertThrowsError(try recorder.start(url: url, format: .wav24, sampleRate: 48_000, channelCount: 2)) {
                XCTAssertEqual($0 as? AudioEngineError, .alreadyRecording)
            }
            XCTAssertEqual(recorder.recordedDuration, 4 / 48_000.0, accuracy: 0.000_000_1)
            let recording = try XCTUnwrap(recorder.stop())
            XCTAssertFalse(recorder.isRecording)
            XCTAssertEqual(recording.duration, 4 / 48_000.0, accuracy: 0.000_000_1)
            XCTAssertEqual(recording.channelCount, 2)
            XCTAssertFalse(recording.peaks.isEmpty)
            let decoded = try AudioFileIO.load(url)
            XCTAssertEqual(decoded.sampleRate, 48_000)
            XCTAssertEqual(decoded.frameCount, 4)
            for channel in samples.indices {
                for frame in samples[channel].indices {
                    XCTAssertEqual(decoded.channels[channel][frame], samples[channel][frame], accuracy: 0.000_001)
                }
            }
            XCTAssertNil(try recorder.stop())
        }
    }

    func testRecorderPreservesExistingFilesAndRejectsInvalidFormats() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("existing.caf")
            let original = Data("existing audio".utf8)
            try original.write(to: url)
            let recorder = AudioRecorder()
            XCTAssertThrowsError(try recorder.start(url: url, format: .caf32, sampleRate: 48_000, channelCount: 1)) {
                XCTAssertEqual($0 as? AudioEngineError, .fileExists("existing.caf"))
            }
            XCTAssertEqual(try Data(contentsOf: url), original)
            let invalidURL = directory.appendingPathComponent("invalid.wav")
            for rate in [0, -1, Double.nan, Double.infinity] {
                XCTAssertThrowsError(try recorder.start(url: invalidURL, format: .wav24, sampleRate: rate, channelCount: 2))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
            XCTAssertFalse(recorder.isRecording)
        }
    }

    func testFailedTakeFinalizesAndRetainsUsableAudio() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("partial.caf")
            let recorder = AudioRecorder()
            try recorder.start(url: url, format: .caf32, sampleRate: 48_000, channelCount: 1)
            let channels: [[Float]] = [[0.25, -0.25, 0.5]]
            _ = channels.withUnsafeBufferPointers { recorder.append($0) }
            recorder.fail(.inputOverflow)
            XCTAssertThrowsError(try recorder.stop()) { XCTAssertEqual($0 as? AudioEngineError, .inputOverflow) }
            let finished = try XCTUnwrap(recorder.lastFinishedRecording)
            XCTAssertEqual(finished.url, url)
            XCTAssertEqual(finished.duration, 3 / 48_000.0, accuracy: 0.000_000_1)
            XCTAssertEqual(try AudioFileIO.load(url).channels, channels)
            XCTAssertFalse(recorder.isRecording)
        }
    }

    func testTapCopiesInputBeforeBufferIsReusedAndDrainsBeforeRecordingCloses() throws {
        try withDirectory { directory in
            let pipeline = InputPipeline()
            pipeline.configure(StreamFormat(sampleRate: 48_000, channelCount: 2))
            let url = directory.appendingPathComponent("queued.caf")
            try pipeline.recorder.start(url: url, format: .caf32, sampleRate: 48_000, channelCount: 2)
            let source = SampleBuffer(sampleRate: 48_000, channels: [[Float](repeating: 0.25, count: 512), [Float](repeating: -0.5, count: 512)])
            let pcm = try XCTUnwrap(AudioFileIO.makePCMBuffer(source))
            pipeline.makeTapBlock()(pcm, AVAudioTime(sampleTime: 0, atRate: 48_000))
            pcm.floatChannelData?[0].update(repeating: 0, count: 512)
            pcm.floatChannelData?[1].update(repeating: 0, count: 512)
            pipeline.stopInput()
            let recording = try XCTUnwrap(pipeline.recorder.stop())
            XCTAssertEqual(recording.duration, 512 / 48_000.0, accuracy: 0.000_000_1)
            XCTAssertEqual(try AudioFileIO.load(url), source)
            XCTAssertEqual(pipeline.captureLast(seconds: 1), source)
            XCTAssertEqual(pipeline.meters.snapshot.framesProcessed, 512)
        }
    }

    func testRetrospectiveCaptureKeepsNewestStereoAndDuplicatesMono() {
        let ring = SampleRingBuffer(seconds: 1, sampleRate: 4)
        [[Float](arrayLiteral: 1, 2, 3)].withUnsafeBufferPointers { ring.write($0) }
        [[Float](arrayLiteral: 4, 5, 6)].withUnsafeBufferPointers { ring.write($0) }
        XCTAssertEqual(ring.captureLast(seconds: 10).channels, [[3, 4, 5, 6], [3, 4, 5, 6]])
        XCTAssertEqual(ring.captureLast(seconds: 0.5).channels, [[5, 6], [5, 6]])
        XCTAssertEqual(ring.captureLast(seconds: .nan).frameCount, 0)
        ring.reset()
        XCTAssertEqual(ring.filledFrames, 0)
        XCTAssertEqual(ring.captureLast(seconds: 1).frameCount, 0)
    }

    func testSegmentCollectsExactlyRequestedFramesAndCompletesOnce() throws {
        let pipeline = InputPipeline(sampleRate: 48_000, channelCount: 1)
        let results = SegmentResults()
        let id = UUID()
        pipeline.addSegment(id: id, frames: 3) { results.append($0) }
        [[Float](arrayLiteral: 0.1, 0.2)].withUnsafeBufferPointers { pipeline.process($0) }
        XCTAssertEqual(results.count, 0)
        [[Float](arrayLiteral: 0.3, 0.4)].withUnsafeBufferPointers { pipeline.process($0) }
        pipeline.cancelSegment(id: id)
        pipeline.failSegments(AudioEngineError.notRunning)
        XCTAssertEqual(results.count, 1)
        let buffer = try results.first().get()
        XCTAssertEqual(buffer.sampleRate, 48_000)
        XCTAssertEqual(buffer.channels, [[0.1, 0.2, 0.3], [0.1, 0.2, 0.3]])
    }

    func testCancellationBeforeSegmentRegistrationDoesNotLeavePendingCapture() throws {
        let pipeline = InputPipeline()
        let request = SegmentRequest(id: UUID(), frames: 32)
        let results = SegmentResults()
        request.finish(.failure(CancellationError()))
        request.install { results.append($0) }
        pipeline.addSegment(request)
        [[Float](repeating: 1, count: 64)].withUnsafeBufferPointers { pipeline.process($0) }
        pipeline.failSegments(AudioEngineError.notRunning)
        XCTAssertEqual(results.count, 1)
        XCTAssertThrowsError(try results.first().get()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testInputFormatChangeFailsSegmentInsteadOfCombiningRates() throws {
        let pipeline = InputPipeline(sampleRate: 48_000)
        let results = SegmentResults()
        pipeline.addSegment(id: UUID(), frames: 4) { results.append($0) }
        [[Float](arrayLiteral: 0.1, 0.2)].withUnsafeBufferPointers { pipeline.process($0) }
        pipeline.configure(StreamFormat(sampleRate: 44_100, channelCount: 2))
        defer { pipeline.stopInput() }
        [[Float](arrayLiteral: 0.3, 0.4)].withUnsafeBufferPointers { pipeline.process($0) }
        XCTAssertEqual(results.count, 1)
        XCTAssertThrowsError(try results.first().get()) {
            guard case .formatUnsupported = $0 as? AudioEngineError else { return XCTFail("Expected format change, got \($0)") }
        }
        XCTAssertEqual(pipeline.captureLast(seconds: 1).sampleRate, 44_100)
        XCTAssertEqual(pipeline.captureLast(seconds: 1).channels, [[0.3, 0.4], [0.3, 0.4]])
    }

    func testFileRoundTripAndResamplingUseRequestedRate() throws {
        try withDirectory { directory in
            let samples = (0..<4_800).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.5 }
            let original = SampleBuffer(sampleRate: 48_000, channels: [samples])
            let url = directory.appendingPathComponent("mono.caf")
            try AudioFileIO.write(original, to: url, encoding: .float32)
            XCTAssertEqual(try AudioFileIO.load(url), original)
            let converted = try AudioFileIO.load(url, resampleTo: 24_000)
            XCTAssertEqual(converted.sampleRate, 24_000)
            XCTAssertEqual(converted.channelCount, 1)
            XCTAssertEqual(converted.duration, original.duration, accuracy: 0.002)
            XCTAssertThrowsError(try AudioFileIO.resample(original, to: .nan))
            XCTAssertThrowsError(try AudioFileIO.load(directory.appendingPathComponent("missing.wav")))
        }
    }

    func testLargeSparseWAVIsRejectedBeforeDecodedMemoryAllocation() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("huge.wav")
            let dataBytes: UInt32 = 100_000_004 // stereo PCM16 → 50,000,002 Float samples
            var header = Data()
            func text(_ value: String) { header.append(contentsOf: value.utf8) }
            func word(_ value: UInt16) { header.append(contentsOf: [UInt8(value & 255), UInt8(value >> 8)]) }
            func dword(_ value: UInt32) {
                header.append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 255) })
            }
            text("RIFF"); dword(dataBytes + 36); text("WAVEfmt "); dword(16)
            word(1); word(2); dword(48_000); dword(192_000); word(4); word(16)
            text("data"); dword(dataBytes)
            try header.write(to: url)
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: UInt64(dataBytes) + 44)
            try file.close()
            XCTAssertThrowsError(try AudioFileIO.load(url)) {
                XCTAssertEqual($0 as? AudioEngineError, .formatUnsupported("слишком большой файл для загрузки в память"))
            }
        }
    }

    func testPlaybackTimelineClampsLoopAndWrapsPlayhead() {
        let timeline = PlaybackTimeline(frameCount: 100, start: 20, loop: 30..<60)
        XCTAssertEqual(timeline.intro, 20..<60)
        XCTAssertEqual(timeline.position(afterPlaying: 39), 59)
        XCTAssertEqual(timeline.position(afterPlaying: 40), 30)
        XCTAssertEqual(timeline.position(afterPlaying: 70), 30)
        XCTAssertEqual(PlaybackTimeline(frameCount: 100, start: 80, loop: 30..<60).start, 30)
        XCTAssertNil(PlaybackTimeline(frameCount: 0).position(afterPlaying: 0))
        XCTAssertNil(PlaybackTimeline(frameCount: 100).position(afterPlaying: 100))
    }

    func testRenderHostRespectsShorterOutputBuffer() {
        let raw = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size,
                                                  alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        list.pointee.mNumberBuffers = 2
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var left = [Float](repeating: 9, count: 10)
        var right = [Float](repeating: 9, count: 3)
        let source = TestRenderSource()
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count * 4), mData: l.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count * 4), mData: r.baseAddress)
                RenderSourceHost.render(source, frameCount: 10, into: list)
            }
        }
        XCTAssertEqual(source.renderedFrames, 3)
        XCTAssertEqual(left, [0.25, 0.25, 0.25, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(right, [0.5, 0.5, 0.5])
    }
}

private final class SegmentResults: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Result<SampleBuffer, Error>]())
    func append(_ result: Result<SampleBuffer, Error>) { lock.withLockUnchecked { $0.append(result) } }
    var count: Int { lock.withLockUnchecked { $0.count } }
    func first() throws -> Result<SampleBuffer, Error> { try lock.withLockUnchecked { try XCTUnwrap($0.first) } }
}

private final class TestRenderSource: AudioRenderSource, @unchecked Sendable {
    private(set) var renderedFrames = 0
    func prepare(sampleRate: Double, maximumFrames: Int) {}
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        renderedFrames += frameCount
        for frame in 0..<frameCount { left[frame] += 0.25; right[frame] += 0.5 }
    }
}
