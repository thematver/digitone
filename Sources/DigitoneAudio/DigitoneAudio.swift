import Foundation
import DigitoneDSP

/// Namespace marker for the audio I/O module.
public enum DigitoneAudioModule {
    /// Digitone II streams 48 kHz / 24-bit stereo in USB AUDIO/MIDI mode.
    public static let preferredSampleRate: Double = 48_000
    /// Retrospective capture window ("catch what was just played").
    public static let retrospectiveSeconds: Double = 30
    /// Samples kept for the live oscilloscope.
    public static let scopeLength = 1024
    /// Columns in a finished recording's waveform overview.
    public static let recordingPeakBins = 400
}

/// Sample rate and channel count of one side of the audio graph.
public struct StreamFormat: Sendable, Equatable {
    public var sampleRate: Double
    public var channelCount: Int
    public init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}
