import Foundation

/// Produces stereo audio on the real-time render thread.
///
/// `render` is called from the audio thread: it must not allocate, block on
/// locks, call into Swift concurrency, or touch the main actor. Exchange state
/// through lock-free or try-lock structures prepared outside the render call.
public protocol AudioRenderSource: AnyObject, Sendable {
    /// Called outside the render thread before rendering starts or when the
    /// hardware format changes.
    func prepare(sampleRate: Double, maximumFrames: Int)
    /// Adds (mixes) `frameCount` frames into the provided non-interleaved buffers.
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>)
}

/// Note input for playable sources: the sampler today, other app-side
/// "virtual machines" (granular, spectral, additive, subtractive) later.
/// Methods may be called from any thread.
public protocol NoteReceiver: AnyObject, Sendable {
    func noteOn(note: Int, velocity: Int)
    func noteOff(note: Int)
    func allNotesOff()
}

/// Immutable decoded audio held in memory, non-interleaved Float32.
public struct SampleBuffer: Sendable, Equatable {
    public let sampleRate: Double
    /// One array per channel (1 = mono, 2 = stereo). All channels have equal length.
    public let channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        precondition(!channels.isEmpty, "SampleBuffer needs at least one channel")
        precondition(Set(channels.map(\.count)).count == 1, "SampleBuffer channels must have equal length")
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var frameCount: Int { channels[0].count }
    public var channelCount: Int { channels.count }
    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
}

/// One column of a waveform overview.
public struct PeakBin: Sendable, Equatable {
    public var min: Float
    public var max: Float
    public var rms: Float
    public init(min: Float, max: Float, rms: Float) { self.min = min; self.max = max; self.rms = rms }
}

/// Instantaneous level in dBFS (`-.infinity` for silence).
public struct AudioLevel: Sendable, Equatable {
    public var peak: Float
    public var rms: Float
    public init(peak: Float, rms: Float) { self.peak = peak; self.rms = rms }
    public static let silent = AudioLevel(peak: -.infinity, rms: -.infinity)
}

/// Magnitudes in dBFS for log-spaced bands, lowest frequency first.
public struct Spectrum: Sendable, Equatable {
    public var bandFrequencies: [Float]
    public var magnitudes: [Float]
    public init(bandFrequencies: [Float], magnitudes: [Float]) {
        self.bandFrequencies = bandFrequencies
        self.magnitudes = magnitudes
    }
    public static let empty = Spectrum(bandFrequencies: [], magnitudes: [])
}
