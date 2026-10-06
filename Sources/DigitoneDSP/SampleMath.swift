import Accelerate
import Foundation

/// Offline, non-destructive editing operations on `SampleBuffer`. Every
/// function returns a new buffer; none of them are meant for the render thread.
public enum SampleMath {
    public enum FadeCurve: String, Sendable, CaseIterable {
        case linear
        /// Quarter sine: constant-power, softer start.
        case equalPower
    }

    public enum ResampleQuality: String, Sendable, CaseIterable {
        /// 4-point, 3rd-order Hermite. Fast; no anti-alias filtering.
        case hermite
        /// Blackman-windowed sinc, 32 taps, low-passed when downsampling.
        case sinc
    }

    // MARK: Level

    /// Largest absolute sample value over all channels.
    public static func peak(_ buffer: SampleBuffer) -> Float {
        buffer.channels.reduce(0) { result, channel in
            guard !channel.isEmpty else { return result }
            var value: Float = 0
            vDSP_maxmgv(channel, 1, &value, vDSP_Length(channel.count))
            return max(result, value)
        }
    }

    public static func gain(_ buffer: SampleBuffer, decibels: Float) -> SampleBuffer {
        scaled(buffer, by: amplitude(decibels: decibels))
    }

    /// Scales so the loudest sample reaches `peakDecibels` dBFS. Silence is returned unchanged.
    public static func normalize(_ buffer: SampleBuffer, peakDecibels: Float = 0) -> SampleBuffer {
        let current = peak(buffer)
        guard current > 0 else { return buffer }
        return scaled(buffer, by: amplitude(decibels: peakDecibels) / current)
    }

    // MARK: Editing

    /// Removes leading and trailing frames whose level on every channel stays
    /// below `thresholdDecibels`. A fully silent buffer becomes empty.
    public static func trimSilence(_ buffer: SampleBuffer, thresholdDecibels: Float = -60) -> SampleBuffer {
        let threshold = amplitude(decibels: thresholdDecibels)
        let frames = buffer.frameCount
        func isLoud(_ frame: Int) -> Bool {
            buffer.channels.contains { abs($0[frame]) > 0 && abs($0[frame]) >= threshold }
        }
        guard let first = (0..<frames).first(where: isLoud),
              let last = (0..<frames).reversed().first(where: isLoud) else {
            return slice(buffer, 0..<0)
        }
        return slice(buffer, first..<(last + 1))
    }

    /// Frames in `range`, clamped to the buffer.
    public static func slice(_ buffer: SampleBuffer, _ range: Range<Int>) -> SampleBuffer {
        let lower = min(max(0, range.lowerBound), buffer.frameCount)
        let upper = min(max(lower, range.upperBound), buffer.frameCount)
        return SampleBuffer(sampleRate: buffer.sampleRate, channels: buffer.channels.map { Array($0[lower..<upper]) })
    }

    public static func reverse(_ buffer: SampleBuffer) -> SampleBuffer {
        SampleBuffer(sampleRate: buffer.sampleRate, channels: buffer.channels.map { Array($0.reversed()) })
    }

    /// Ramps the first `frames` frames up from silence.
    public static func fadeIn(_ buffer: SampleBuffer, frames: Int, curve: FadeCurve = .linear) -> SampleBuffer {
        let length = min(max(0, frames), buffer.frameCount)
        guard length > 0 else { return buffer }
        return SampleBuffer(sampleRate: buffer.sampleRate, channels: buffer.channels.map { channel in
            var result = channel
            for index in 0..<length { result[index] *= fadeGain(Float(index) / Float(length), curve) }
            return result
        })
    }

    /// Ramps the last `frames` frames down to silence (the final frame is zero).
    public static func fadeOut(_ buffer: SampleBuffer, frames: Int, curve: FadeCurve = .linear) -> SampleBuffer {
        let length = min(max(0, frames), buffer.frameCount)
        guard length > 0 else { return buffer }
        let start = buffer.frameCount - length
        return SampleBuffer(sampleRate: buffer.sampleRate, channels: buffer.channels.map { channel in
            var result = channel
            for index in 0..<length {
                let position = length > 1 ? Float(length - 1 - index) / Float(length - 1) : 0
                result[start + index] *= fadeGain(position, curve)
            }
            return result
        })
    }

    // MARK: Channels

    /// Averages all channels into one.
    public static func toMono(_ buffer: SampleBuffer) -> SampleBuffer {
        guard buffer.channelCount > 1 else { return buffer }
        var mono = [Float](repeating: 0, count: buffer.frameCount)
        for channel in buffer.channels { vDSP.add(mono, channel, result: &mono) }
        vDSP.multiply(1 / Float(buffer.channelCount), mono, result: &mono)
        return SampleBuffer(sampleRate: buffer.sampleRate, channels: [mono])
    }

    /// Mono is duplicated to both sides; more than two channels keep the first two.
    public static func toStereo(_ buffer: SampleBuffer) -> SampleBuffer {
        switch buffer.channelCount {
        case 1: SampleBuffer(sampleRate: buffer.sampleRate, channels: [buffer.channels[0], buffer.channels[0]])
        case 2: buffer
        default: SampleBuffer(sampleRate: buffer.sampleRate, channels: Array(buffer.channels.prefix(2)))
        }
    }

    // MARK: Time

    /// Converts to `sampleRate`, keeping the duration.
    public static func resample(_ buffer: SampleBuffer, to sampleRate: Double, quality: ResampleQuality = .sinc) -> SampleBuffer {
        guard sampleRate.isFinite, sampleRate > 0, buffer.sampleRate.isFinite,
              buffer.sampleRate > 0, sampleRate != buffer.sampleRate else { return buffer }
        let step = buffer.sampleRate / sampleRate
        let count = (Double(buffer.frameCount) / step).rounded()
        guard count.isFinite, count >= 0, count < Double(Int.max) else { return buffer }
        let outputCount = Int(count)
        let channels = buffer.channels.map { channel in
            channel.withUnsafeBufferPointer { source in
                [Float](unsafeUninitializedCapacity: outputCount) { output, initialized in
                    switch quality {
                    case .hermite:
                        for index in 0..<outputCount { output[index] = Interpolation.hermite(source, at: Double(index) * step) }
                    case .sinc:
                        let kernel = SincKernel(step: step)
                        for index in 0..<outputCount { output[index] = kernel.value(source, at: Double(index) * step) }
                    }
                    initialized = outputCount
                }
            }
        }
        return SampleBuffer(sampleRate: sampleRate, channels: channels)
    }

    /// Joins buffers end to end. The result uses the first buffer's sample
    /// rate and the largest channel count; others are converted to match.
    public static func concatenate(_ buffers: [SampleBuffer], quality: ResampleQuality = .sinc) -> SampleBuffer? {
        guard let first = buffers.first else { return nil }
        let stereo = buffers.contains { $0.channelCount > 1 }
        var channels = [[Float]](repeating: [], count: stereo ? 2 : 1)
        for buffer in buffers {
            var part = resample(buffer, to: first.sampleRate, quality: quality)
            part = stereo ? toStereo(part) : part
            for index in channels.indices { channels[index] += part.channels[index] }
        }
        return SampleBuffer(sampleRate: first.sampleRate, channels: channels)
    }

    // MARK: Helpers

    public static func amplitude(decibels: Float) -> Float {
        decibels.isFinite ? pow(10, decibels / 20) : (decibels > 0 ? .greatestFiniteMagnitude : 0)
    }

    private static func scaled(_ buffer: SampleBuffer, by factor: Float) -> SampleBuffer {
        guard factor != 1 else { return buffer }
        return SampleBuffer(sampleRate: buffer.sampleRate, channels: buffer.channels.map { vDSP.multiply(factor, $0) })
    }

    private static func fadeGain(_ position: Float, _ curve: FadeCurve) -> Float {
        switch curve {
        case .linear: position
        case .equalPower: sin(position * .pi / 2)
        }
    }
}

/// Windowed-sinc interpolator for offline resampling.
private struct SincKernel {
    static let halfWidth = 16
    /// Normalized cutoff (1 = source Nyquist); below 1 when downsampling.
    let cutoff: Double

    init(step: Double) {
        cutoff = min(1, 1 / step) * 0.95
    }

    func value(_ source: UnsafeBufferPointer<Float>, at position: Double) -> Float {
        let centre = Int(position.rounded(.down))
        let width = Double(Self.halfWidth) / cutoff
        let lower = max(0, centre - Int(width.rounded(.up)) + 1)
        let upper = min(source.count - 1, centre + Int(width.rounded(.up)))
        guard lower <= upper else { return 0 }
        var sum: Double = 0
        for index in lower...upper {
            let distance = position - Double(index)
            let normalized = distance / width
            guard abs(normalized) < 1 else { continue }
            let window = 0.42 + 0.5 * cos(.pi * normalized) + 0.08 * cos(2 * .pi * normalized)
            sum += Double(source[index]) * cutoff * sinc(distance * cutoff) * window
        }
        return Float(sum)
    }

    private func sinc(_ x: Double) -> Double {
        x == 0 ? 1 : sin(.pi * x) / (.pi * x)
    }
}
