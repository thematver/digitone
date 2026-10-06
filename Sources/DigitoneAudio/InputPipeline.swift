import AVFoundation
import os
import DigitoneDSP

/// Everything that happens to input audio, off the main thread: metering,
/// scope and spectrum, the retrospective ring, recording and segment capture.
///
/// The tap only enqueues into preallocated storage. Analysis, segment capture
/// and disk writes run on a serial worker; `process` also accepts offline data.
public final class InputPipeline: @unchecked Sendable {
    public let meters = MeterStore()
    public let recorder = AudioRecorder()

    private struct Analysis {
        var format: StreamFormat
        var ring: SampleRingBuffer
        var analyzer: SpectrumAnalyzer
        /// Mono history for scope and spectrum, newest at `historyIndex - 1`.
        var history: [Float]
        var historyIndex = 0
        var historyFilled = 0
        var linear: [Float]
        var framesProcessed: Int64 = 0
        var framesSinceSnapshot = 0
        var hasSnapshot = false
        var peak: [Float] = []
        var energy: [Double] = []
        var levelFrames = 0
    }

    private struct Segment {
        let request: SegmentRequest
        let sampleRate: Double
        var channels: [[Float]]
    }

    private let analysisLock = OSAllocatedUnfairLock()
    private var analysis: Analysis
    private let segmentLock = OSAllocatedUnfairLock()
    private var segments: [Segment] = []
    private var captureQueue: InputCaptureQueue?
    private let errorLock = OSAllocatedUnfairLock()
    private var errorHandler: (@Sendable (AudioEngineError) -> Void)?

    public init(sampleRate: Double = DigitoneAudioModule.preferredSampleRate, channelCount: Int = 2) {
        analysis = Self.makeAnalysis(StreamFormat(sampleRate: sampleRate, channelCount: channelCount))
    }

    public var format: StreamFormat { analysisLock.withLockUnchecked { analysis.format } }

    /// Call while the tap is removed. Keeps the ring when the sample rate is unchanged.
    public func configure(_ format: StreamFormat) {
        configure(format, automaticallyDrain: true)
    }

    /// Internal scheduling control keeps queue-boundary tests deterministic.
    func configure(_ format: StreamFormat, automaticallyDrain: Bool) {
        stopInput()
        let previous = self.format
        if previous != format { failSegments(AudioEngineError.formatUnsupported("формат входа изменился")) }
        analysisLock.withLockUnchecked {
            if format.sampleRate == analysis.format.sampleRate {
                analysis.format = format
            } else {
                analysis = Self.makeAnalysis(format)
            }
            analysis.hasSnapshot = false
            analysis.framesSinceSnapshot = 0
            analysis.peak = []
            analysis.energy = []
            analysis.levelFrames = 0
        }
        meters.publish(.empty)
        captureQueue = InputCaptureQueue(channelCount: format.channelCount, automaticallyDrain: automaticallyDrain, consume: { [weak self] channels in
            self?.process(channels)
        }, onOverflow: { [weak self] in
            self?.handleInputOverflow()
        })
    }

    func setErrorHandler(_ handler: @escaping @Sendable (AudioEngineError) -> Void) {
        errorLock.withLockUnchecked { errorHandler = handler }
    }

    private func report(_ error: AudioEngineError) {
        let callback = errorLock.withLockUnchecked { errorHandler }
        callback?(error)
    }

    /// A gap in background analysis does not imply a failed recording. The
    /// queue calls this after delivering its intact prefix and before it
    /// accepts post-gap input, so captures never silently bridge missing audio.
    func handleInputOverflow() {
        let failedTake = recorder.fail(.inputOverflow)
        let failedSegment = failSegments(AudioEngineError.captureOverflow)
        resetCapture()
        if failedTake { report(.inputOverflow) }
        else if failedSegment { report(.captureOverflow) }
    }

    func stopInput() {
        captureQueue?.finish()
        captureQueue = nil
    }

    func startRecording(to url: URL, format: RecordingFormat, sampleRate: Double, channelCount: Int) throws {
        guard let captureQueue else { throw AudioEngineError.notRunning }
        try captureQueue.synchronize {
            try recorder.start(url: url, format: format, sampleRate: sampleRate, channelCount: channelCount)
        }
    }

    func stopRecording() throws -> Recording? {
        if let captureQueue { return try captureQueue.synchronize { try recorder.stop() } }
        return try recorder.stop()
    }

    func resetCapture() {
        analysisLock.withLockUnchecked {
            analysis.ring.reset()
            analysis.history = [Float](repeating: 0, count: analysis.history.count)
            analysis.historyIndex = 0
            analysis.historyFilled = 0
            analysis.hasSnapshot = false
            analysis.framesSinceSnapshot = 0
            analysis.peak = []
            analysis.energy = []
            analysis.levelFrames = 0
        }
        meters.publish(.empty)
    }

    /// The handoff for the current input format; nil until `configure`.
    /// Callers keep it alive while their input callback runs.
    var inputQueue: InputCaptureQueue? { captureQueue }

    func makeTapBlock(levels: LevelTap? = nil) -> AVAudioNodeTapBlock {
        let capture = captureQueue
        return { buffer, _ in
            capture?.enqueue(buffer)
            guard let levels, let data = buffer.floatChannelData, buffer.stride == 1 else { return }
            levels.accumulate(left: data[0], right: buffer.format.channelCount > 1 ? data[1] : nil, frames: Int(buffer.frameLength))
        }
    }

    public func captureLast(seconds: Double) -> SampleBuffer {
        analysisLock.withLockUnchecked { analysis.ring }.captureLast(seconds: seconds)
    }

    // MARK: Tap thread

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let frames = Int(buffer.frameLength)
        let stride = buffer.stride
        if stride == 1 {
            process((0..<Int(buffer.format.channelCount)).map { UnsafeBufferPointer(start: data[$0], count: frames) })
        } else {
            // Interleaved input: split into channels first.
            let channels = (0..<Int(buffer.format.channelCount)).map { channel in
                (0..<frames).map { data[0][$0 * stride + channel] }
            }
            channels.withUnsafeBufferPointers { process($0) }
        }
    }

    /// Non-interleaved Float32 channels of equal length.
    public func process(_ channels: [UnsafeBufferPointer<Float>]) {
        guard let frameCount = channels.first?.count, frameCount > 0,
              channels.allSatisfy({ $0.count == frameCount }) else { return }
        analyze(channels, frameCount: frameCount)
        if let failure = recorder.append(channels) { report(failure) }
        feedSegments(channels, frameCount: frameCount)
    }

    private func analyze(_ channels: [UnsafeBufferPointer<Float>], frameCount: Int) {
        let snapshot: MeterSnapshot? = analysisLock.withLockUnchecked {
            analysis.ring.write(channels)
            let size = analysis.history.count
            let scale = 1 / Float(channels.count)
            if analysis.peak.count != channels.count {
                analysis.peak = [Float](repeating: 0, count: channels.count)
                analysis.energy = [Double](repeating: 0, count: channels.count)
                analysis.levelFrames = 0
            }
            for frame in 0..<frameCount {
                var mono: Float = 0
                for channel in channels.indices {
                    let sample = channels[channel][frame]
                    mono += sample
                    analysis.peak[channel] = max(analysis.peak[channel], abs(sample))
                    analysis.energy[channel] += Double(sample) * Double(sample)
                }
                analysis.history[analysis.historyIndex] = mono * scale
                analysis.historyIndex = (analysis.historyIndex + 1) % size
            }
            analysis.historyFilled = min(size, analysis.historyFilled + frameCount)
            analysis.framesProcessed += Int64(frameCount)
            analysis.levelFrames += frameCount
            analysis.framesSinceSnapshot += frameCount
            let interval = max(1, Int(analysis.format.sampleRate / 30))
            guard !analysis.hasSnapshot || analysis.framesSinceSnapshot >= interval else { return nil }
            analysis.hasSnapshot = true
            analysis.framesSinceSnapshot %= interval
            let levels = channels.indices.map { channel in
                AudioLevel(peak: LevelMeter.decibels(analysis.peak[channel]),
                           rms: LevelMeter.decibels(Float(analysis.energy[channel] / Double(analysis.levelFrames)).squareRoot()))
            }
            for channel in channels.indices { analysis.peak[channel] = 0; analysis.energy[channel] = 0 }
            analysis.levelFrames = 0
            // FFT, scope allocations and publication run at display rate;
            // recording, levels and retrospective storage still see every frame.
            let tail = size - analysis.historyIndex
            for index in 0..<size {
                analysis.linear[index] = index < tail
                    ? analysis.history[analysis.historyIndex + index]
                    : analysis.history[index - tail]
            }
            let spectrum = analysis.linear.withUnsafeBufferPointer { analysis.analyzer.analyze($0) }
            let scopeCount = min(DigitoneAudioModule.scopeLength, analysis.historyFilled)
            return MeterSnapshot(
                levels: levels,
                scope: Array(analysis.linear.suffix(scopeCount)),
                spectrum: spectrum,
                sampleRate: analysis.format.sampleRate,
                framesProcessed: analysis.framesProcessed
            )
        }
        if let snapshot { meters.publish(snapshot) }
    }

    // MARK: Segment capture

    /// Collects the next `frames` of input as stereo; `completion` runs once on the worker.
    func addSegment(id: UUID, frames: Int, completion: @escaping @Sendable (Result<SampleBuffer, Error>) -> Void) {
        let request = SegmentRequest(id: id, frames: frames)
        request.install(completion)
        addSegment(request)
    }

    func addSegment(_ request: SegmentRequest) {
        if let captureQueue {
            // Previously accepted input belongs to the retrospective history,
            // not to a new request for the next frames. Match recording start's
            // worker boundary, including any pending gap or cancellation.
            captureQueue.synchronize { registerSegment(request) }
        } else {
            registerSegment(request)
        }
    }

    private func registerSegment(_ request: SegmentRequest) {
        let sampleRate = format.sampleRate
        guard request.frames > 0 else {
            request.finish(.success(SampleBuffer(sampleRate: sampleRate, channels: [[], []])))
            return
        }
        var channels: [[Float]] = [[], []]
        for index in channels.indices { channels[index].reserveCapacity(request.frames) }
        segmentLock.withLockUnchecked {
            guard request.isPending else { return }
            segments.append(Segment(request: request, sampleRate: sampleRate, channels: channels))
        }
    }

    func cancelSegment(id: UUID) {
        let cancelled = segmentLock.withLockUnchecked { () -> Segment? in
            guard let index = segments.firstIndex(where: { $0.request.id == id }) else { return nil }
            return segments.remove(at: index)
        }
        cancelled?.request.finish(.failure(CancellationError()))
    }

    @discardableResult
    func failSegments(_ error: Error) -> Bool {
        let pending = segmentLock.withLockUnchecked { () -> [Segment] in
            defer { segments.removeAll() }
            return segments
        }
        let affected = pending.contains { $0.request.isPending }
        pending.forEach { $0.request.finish(.failure(error)) }
        return affected
    }

    private func feedSegments(_ source: [UnsafeBufferPointer<Float>], frameCount: Int) {
        let finished = segmentLock.withLockUnchecked { () -> [Segment] in
            guard !segments.isEmpty else { return [] }
            for index in segments.indices {
                let take = min(frameCount, segments[index].request.frames - segments[index].channels[0].count)
                for channel in 0..<2 {
                    segments[index].channels[channel].append(contentsOf: source[min(channel, source.count - 1)].prefix(take))
                }
            }
            let done = segments.filter { $0.channels[0].count >= $0.request.frames }
            segments.removeAll { $0.channels[0].count >= $0.request.frames }
            return done
        }
        for segment in finished {
            segment.request.finish(.success(SampleBuffer(sampleRate: segment.sampleRate, channels: segment.channels)))
        }
    }

    private static func makeAnalysis(_ format: StreamFormat) -> Analysis {
        let analyzer = SpectrumAnalyzer(sampleRate: format.sampleRate)
        let size = max(analyzer.fftSize, DigitoneAudioModule.scopeLength)
        return Analysis(
            format: format,
            ring: SampleRingBuffer(seconds: DigitoneAudioModule.retrospectiveSeconds, sampleRate: format.sampleRate),
            analyzer: analyzer,
            history: [Float](repeating: 0, count: size),
            linear: [Float](repeating: 0, count: size)
        )
    }
}

/// One-shot completion that handles cancellation before registration as well
/// as cancellation racing the final input buffer.
final class SegmentRequest: @unchecked Sendable {
    let id: UUID
    let frames: Int
    private let lock = OSAllocatedUnfairLock()
    private var result: Result<SampleBuffer, Error>?
    private var completion: (@Sendable (Result<SampleBuffer, Error>) -> Void)?

    init(id: UUID, frames: Int) { self.id = id; self.frames = frames }

    var isPending: Bool { lock.withLockUnchecked { result == nil } }

    func install(_ callback: @escaping @Sendable (Result<SampleBuffer, Error>) -> Void) {
        let finished = lock.withLockUnchecked { () -> Result<SampleBuffer, Error>? in
            if let result { return result }
            completion = callback
            return nil
        }
        if let finished { callback(finished) }
    }

    func finish(_ outcome: Result<SampleBuffer, Error>) {
        let callback = lock.withLockUnchecked { () -> (@Sendable (Result<SampleBuffer, Error>) -> Void)? in
            guard result == nil else { return nil }
            result = outcome
            defer { completion = nil }
            return completion
        }
        callback?(outcome)
    }
}

extension Array where Element == [Float] {
    /// Exposes every inner array as a buffer pointer for the duration of `body`.
    func withUnsafeBufferPointers<R>(_ body: ([UnsafeBufferPointer<Float>]) throws -> R) rethrows -> R {
        func recurse(_ index: Int, _ collected: [UnsafeBufferPointer<Float>]) throws -> R {
            guard index < count else { return try body(collected) }
            return try self[index].withUnsafeBufferPointer { try recurse(index + 1, collected + [$0]) }
        }
        return try recurse(0, [])
    }
}
