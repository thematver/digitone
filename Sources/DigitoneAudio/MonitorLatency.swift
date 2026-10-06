import Foundation

/// One side of an audio device as the HAL reports it, in frames at `sampleRate`.
public struct DeviceLatency: Sendable, Equatable {
    public var sampleRate: Double
    /// Converter/driver latency (kAudioDevicePropertyLatency).
    public var deviceFrames: Int
    /// How far ahead of/behind the hardware the IO cycle runs.
    public var safetyFrames: Int
    /// IO buffer size.
    public var bufferFrames: Int
    /// Per-stream latency (e.g. built-in speaker processing).
    public var streamFrames: Int

    public init(sampleRate: Double, deviceFrames: Int = 0, safetyFrames: Int = 0, bufferFrames: Int = 0, streamFrames: Int = 0) {
        self.sampleRate = sampleRate
        self.deviceFrames = deviceFrames
        self.safetyFrames = safetyFrames
        self.bufferFrames = bufferFrames
        self.streamFrames = streamFrames
    }

    public var totalFrames: Int { deviceFrames + safetyFrames + bufferFrames + streamFrames }
    public var milliseconds: Double { sampleRate > 0 ? Double(totalFrames) / sampleRate * 1_000 : 0 }
}

/// Estimated delay from the Digitone's converters to the computer's speakers.
public struct MonitorLatency: Sendable, Equatable {
    public var input: DeviceLatency
    /// Frames waiting in the input → output handoff, at the input rate.
    public var handoffFrames: Int
    public var output: DeviceLatency

    public init(input: DeviceLatency, handoffFrames: Int, output: DeviceLatency) {
        self.input = input
        self.handoffFrames = handoffFrames
        self.output = output
    }

    public var handoffMilliseconds: Double {
        input.sampleRate > 0 ? Double(handoffFrames) / input.sampleRate * 1_000 : 0
    }

    public var milliseconds: Double { input.milliseconds + handoffMilliseconds + output.milliseconds }

    /// "≈ 9 мс"
    public var label: String { "≈ \(Int(milliseconds.rounded())) мс" }
}
