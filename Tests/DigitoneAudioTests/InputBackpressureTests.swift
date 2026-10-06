import AVFoundation
import os
import XCTest
import DigitoneDSP
@testable import DigitoneAudio

final class InputBackpressureTests: XCTestCase {
    func testIdleOverflowDoesNotReportRecordingFailureAndCaptureResumesAfterGap() throws {
        let pipeline = InputPipeline()
        let errors = ErrorResults()
        pipeline.setErrorHandler { errors.append($0) }
        let queue = makeQueue(pipeline, capacity: 64)
        queue.enqueue(try pcm(0.25, frames: 64))
        queue.enqueue(try pcm(0.75, frames: 64)) // actual capacity overflow
        queue.synchronize {}
        XCTAssertEqual(queue.droppedBlocks, 1)
        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertNil(pipeline.recorder.failure)
        XCTAssertEqual(pipeline.captureLast(seconds: 1).frameCount, 0)
        queue.enqueue(try pcm(-0.5, frames: 32))
        queue.finish()
        XCTAssertEqual(pipeline.captureLast(seconds: 1).channels, [[Float](repeating: -0.5, count: 32), [Float](repeating: -0.5, count: 32)])
    }

    func testRecordingOverflowPreservesIntactPrefixAndFailsBeforePostGapAudio() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("prefix.caf")
            let pipeline = InputPipeline()
            let errors = ErrorResults()
            pipeline.setErrorHandler { errors.append($0) }
            let queue = makeQueue(pipeline, capacity: 64)
            try queue.synchronize { try pipeline.recorder.start(url: url, format: .caf32, sampleRate: 48_000, channelCount: 1) }
            queue.enqueue(try pcm(0.25, frames: 64))
            queue.enqueue(try pcm(0.5, frames: 64))
            queue.synchronize {}
            XCTAssertEqual(errors.values, [.inputOverflow])
            XCTAssertEqual(pipeline.recorder.failure, .inputOverflow)
            queue.enqueue(try pcm(-0.75, frames: 64))
            queue.finish()
            XCTAssertThrowsError(try pipeline.recorder.stop()) { XCTAssertEqual($0 as? AudioEngineError, .inputOverflow) }
            let recording = try XCTUnwrap(pipeline.recorder.lastFinishedRecording)
            XCTAssertEqual(recording.duration, 64 / 48_000.0, accuracy: 1e-9)
            XCTAssertEqual(try AudioFileIO.load(url).channels, [[Float](repeating: 0.25, count: 64)])
        }
    }

    func testSegmentFailsOnceOnGapAndNeverCombinesAudioAcrossIt() throws {
        let pipeline = InputPipeline()
        let errors = ErrorResults()
        let captures = CaptureResults()
        pipeline.setErrorHandler { errors.append($0) }
        pipeline.addSegment(id: UUID(), frames: 96) { captures.append($0) }
        let queue = makeQueue(pipeline, capacity: 64)
        queue.enqueue(try pcm(0.25, frames: 64))
        queue.enqueue(try pcm(0.5, frames: 64))
        queue.synchronize {}
        queue.enqueue(try pcm(-0.25, frames: 64))
        queue.finish()
        XCTAssertEqual(errors.values, [.captureOverflow])
        XCTAssertEqual(captures.values.count, 1)
        XCTAssertThrowsError(try XCTUnwrap(captures.values.first).get()) {
            XCTAssertEqual($0 as? AudioEngineError, .captureOverflow)
        }
    }

    func testSynchronizeOrdersRecordingStartAndStopAroundAlreadyAcceptedFrames() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("phase.caf")
            let pipeline = InputPipeline()
            let queue = makeQueue(pipeline, capacity: 128)
            queue.enqueue(try pcm(0.1, frames: 64))
            try queue.synchronize { try pipeline.recorder.start(url: url, format: .caf32, sampleRate: 48_000, channelCount: 1) }
            queue.enqueue(try pcm(0.3, frames: 100)) // wraps the ring
            let finished = try queue.synchronize { try pipeline.recorder.stop() }
            XCTAssertEqual(finished?.duration ?? 0, 100 / 48_000.0, accuracy: 1e-9)
            queue.enqueue(try pcm(0.9, frames: 64))
            queue.finish()
            XCTAssertEqual(queue.droppedBlocks, 0)
            XCTAssertEqual(try AudioFileIO.load(url).channels, [[Float](repeating: 0.3, count: 100)])
            XCTAssertEqual(pipeline.captureLast(seconds: 1).frameCount, 228)
        }
    }

    func testLiveSegmentStartsAfterQueuedPreRequestInputAndCancellationStillWins() throws {
        let pipeline = InputPipeline()
        pipeline.configure(StreamFormat(sampleRate: 48_000, channelCount: 1), automaticallyDrain: false)
        defer { pipeline.stopInput() }
        let queue = try XCTUnwrap(pipeline.inputQueue)
        let captures = CaptureResults()
        queue.enqueue(try pcm(0.25, frames: 64))
        pipeline.addSegment(id: UUID(), frames: 64) { captures.append($0) }
        XCTAssertTrue(captures.values.isEmpty)
        XCTAssertEqual(pipeline.captureLast(seconds: 1).frameCount, 64)
        queue.enqueue(try pcm(-0.5, frames: 64))
        queue.synchronize {}
        XCTAssertEqual(captures.values.count, 1)
        XCTAssertEqual(try XCTUnwrap(captures.values.first).get().channels,
                       [[Float](repeating: -0.5, count: 64), [Float](repeating: -0.5, count: 64)])

        let cancelled = CaptureResults()
        let request = SegmentRequest(id: UUID(), frames: 64)
        request.finish(.failure(CancellationError()))
        request.install { cancelled.append($0) }
        queue.enqueue(try pcm(0.75, frames: 64))
        pipeline.addSegment(request)
        queue.enqueue(try pcm(0.9, frames: 64))
        queue.synchronize {}
        XCTAssertEqual(cancelled.values.count, 1)
        XCTAssertThrowsError(try XCTUnwrap(cancelled.values.first).get()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testConcurrentWorkerCannotDropInputWhenTotalFitsInCapacity() throws {
        let totals = OSAllocatedUnfairLock(initialState: (frames: 0, sum: Double(0)))
        let errors = ErrorResults()
        let queue = InputCaptureQueue(channelCount: 1, consume: { channels in
            totals.withLockUnchecked {
                $0.frames += channels[0].count
                $0.sum += channels[0].reduce(0) { $0 + Double($1) }
            }
        }, onOverflow: { errors.append(.inputOverflow) })
        let buffer = try pcm(0.25, frames: 128)
        // Less than the five-second capacity even if the worker is completely
        // stalled; scheduling or copying on the worker must not lose blocks.
        for _ in 0..<1_000 { queue.enqueue(buffer) }
        queue.finish()
        XCTAssertEqual(queue.droppedBlocks, 0)
        XCTAssertTrue(errors.values.isEmpty)
        XCTAssertEqual(totals.withLockUnchecked { $0.frames }, 128_000)
        XCTAssertEqual(totals.withLockUnchecked { $0.sum }, 32_000)
    }

    func testAnalysisRunsAtDisplayRateWithoutLosingFramesOrTransientPeaks() {
        let pipeline = InputPipeline()
        let block = [[Float](repeating: 0.25, count: 128)]
        var publishedFrames = Set<Int64>()
        block.withUnsafeBufferPointers { channels in
            for _ in 0..<375 {
                pipeline.process(channels)
                publishedFrames.insert(pipeline.meters.snapshot.framesProcessed)
            }
        }
        XCTAssertLessThanOrEqual(publishedFrames.count, 31)
        XCTAssertEqual(pipeline.meters.snapshot.framesProcessed, 48_000)
        XCTAssertEqual(pipeline.captureLast(seconds: 1).channels, [[Float](repeating: 0.25, count: 48_000), [Float](repeating: 0.25, count: 48_000)])

        let transient = InputPipeline()
        let silent = [[Float](repeating: 0, count: 128)]
        silent.withUnsafeBufferPointers { transient.process($0) }
        var pulse = silent
        pulse[0][0] = 0.9
        pulse.withUnsafeBufferPointers { transient.process($0) }
        silent.withUnsafeBufferPointers { channels in
            for _ in 0..<11 { transient.process(channels) }
        }
        XCTAssertEqual(transient.meters.snapshot.framesProcessed, 1_664)
        XCTAssertEqual(transient.meters.snapshot.levels[0].peak, LevelMeter.decibels(0.9), accuracy: 1e-5)
        XCTAssertGreaterThan(transient.meters.snapshot.levels[0].rms, -.infinity)
    }

    private func makeQueue(_ pipeline: InputPipeline, capacity: Int) -> InputCaptureQueue {
        InputCaptureQueue(channelCount: 1, capacityFrames: capacity, automaticallyDrain: false,
                          consume: { pipeline.process($0) }, onOverflow: { pipeline.handleInputOverflow() })
    }

    private func pcm(_ value: Float, frames: Int) throws -> AVAudioPCMBuffer {
        try XCTUnwrap(AudioFileIO.makePCMBuffer(SampleBuffer(sampleRate: 48_000, channels: [[Float](repeating: value, count: frames)])))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-backpressure-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private final class ErrorResults: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [AudioEngineError]())
    func append(_ error: AudioEngineError) { lock.withLockUnchecked { $0.append(error) } }
    var values: [AudioEngineError] { lock.withLockUnchecked { $0 } }
}

private final class CaptureResults: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Result<SampleBuffer, Error>]())
    func append(_ result: Result<SampleBuffer, Error>) { lock.withLockUnchecked { $0.append(result) } }
    var values: [Result<SampleBuffer, Error>] { lock.withLockUnchecked { $0 } }
}
