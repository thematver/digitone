import AVFoundation
import os
import DigitoneDSP

/// A finished take on disk.
public struct Recording: Sendable, Equatable {
    public var url: URL
    public var duration: Double
    public var sampleRate: Double
    public var channelCount: Int
    public var peaks: [PeakBin]
}

/// On-disk encoding of a live recording.
public enum RecordingFormat: Sendable, Equatable {
    /// 24-bit integer WAV, the Digitone's native resolution.
    case wav24
    /// 32-bit float CAF: no clipping, no size limit.
    case caf32

    public var fileExtension: String { self == .wav24 ? "wav" : "caf" }
    var encoding: AudioFileIO.Encoding { self == .wav24 ? .int24 : .float32 }
}

/// Streams input to a file from the input worker. Writes happen under a lock
/// that `stop()` also takes, so the file is never closed mid-write.
public final class AudioRecorder: @unchecked Sendable {
    private struct Take {
        let file: AVAudioFile
        let scratch: AVAudioPCMBuffer
        let url: URL
        let sampleRate: Double
        let channelCount: Int
        var frames = 0
        var peaks = PeakAccumulator()
        var failure: AudioEngineError?
    }

    private let lock = OSAllocatedUnfairLock()
    private var take: Take?
    private var completed: Recording?

    public init() {}

    public var isRecording: Bool { lock.withLockUnchecked { take != nil } }
    /// Most recently finalized file, including the usable portion of a failed take.
    public var lastFinishedRecording: Recording? { lock.withLockUnchecked { completed } }

    /// Sample rate of the take in progress.
    public var activeSampleRate: Double? { lock.withLockUnchecked { take?.sampleRate } }
    public var activeChannelCount: Int? { lock.withLockUnchecked { take?.channelCount } }

    /// Seconds written so far, 0 when idle.
    public var recordedDuration: Double {
        lock.withLockUnchecked { take.map { Double($0.frames) / $0.sampleRate } ?? 0 }
    }

    /// `channelCount` above 2 is reduced to stereo.
    public func start(url: URL, format: RecordingFormat, sampleRate: Double, channelCount: Int) throws {
        let channels = min(max(channelCount, 1), 2)
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0 else {
            throw AudioEngineError.formatUnsupported("частота или число каналов")
        }
        guard let processing = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)),
              let scratch = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 4_096) else {
            throw AudioEngineError.formatUnsupported("\(channels) кан., \(Int(sampleRate)) Гц")
        }
        try lock.withLockUnchecked {
            guard take == nil else { throw AudioEngineError.alreadyRecording }
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw AudioEngineError.fileExists(url.lastPathComponent)
            }
            let file: AVAudioFile
            do {
                file = try AVAudioFile(
                    forWriting: url,
                    settings: AudioFileIO.fileSettings(sampleRate: sampleRate, channelCount: channels, encoding: format.encoding),
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
            } catch { throw AudioEngineError.fileWrite(url.lastPathComponent) }
            take = Take(file: file, scratch: scratch, url: url, sampleRate: sampleRate, channelCount: channels)
        }
    }

    @discardableResult
    func append(_ source: [UnsafeBufferPointer<Float>]) -> AudioEngineError? {
        guard let frameCount = source.first?.count, frameCount > 0,
              source.allSatisfy({ $0.count == frameCount }) else { return nil }
        return lock.withLockUnchecked {
            guard var current = take, current.failure == nil, let data = current.scratch.floatChannelData else { return nil }
            let capacity = Int(current.scratch.frameCapacity)
            var offset = 0
            while offset < frameCount {
                let run = min(capacity, frameCount - offset)
                for channel in 0..<current.channelCount {
                    guard let base = source[min(channel, source.count - 1)].baseAddress else { continue }
                    data[channel].update(from: base + offset, count: run)
                }
                current.scratch.frameLength = AVAudioFrameCount(run)
                do {
                    try current.file.write(from: current.scratch)
                    current.frames += run
                    for frame in 0..<run {
                        var mono: Float = 0
                        for channel in 0..<current.channelCount { mono += data[channel][frame] }
                        current.peaks.append(mono / Float(current.channelCount))
                    }
                } catch {
                    current.failure = .fileWrite(current.url.lastPathComponent)
                    break
                }
                offset += run
            }
            take = current
            return current.failure
        }
    }

    /// Returns true only when this call newly failed an active take. Keep the
    /// original failure when later errors arrive before finalization.
    @discardableResult
    func fail(_ error: AudioEngineError) -> Bool {
        lock.withLockUnchecked {
            guard take != nil, take?.failure == nil else { return false }
            take?.failure = error
            return true
        }
    }

    var failure: AudioEngineError? { lock.withLockUnchecked { take?.failure } }

    /// Closes the file. Returns nil when not recording.
    public func stop() throws -> Recording? {
        var finished: Take? = lock.withLockUnchecked {
            defer { take = nil }
            return take
        }
        let failure = finished?.failure
        let recording = finished.map { take in
            Recording(url: take.url, duration: Double(take.frames) / take.sampleRate,
                      sampleRate: take.sampleRate, channelCount: take.channelCount,
                      peaks: take.peaks.peaks(bins: DigitoneAudioModule.recordingPeakBins))
        }
        // Release AVAudioFile and finalize its header before publishing the URL.
        finished = nil
        guard let recording else { return nil }
        lock.withLockUnchecked { completed = recording }
        if let failure { throw failure }
        return recording
    }
}
