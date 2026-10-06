import Foundation
import os

/// Linear peak and RMS amplitude of one channel (0 = silence, 1 = full scale).
public struct ChannelLevel: Sendable, Equatable {
    public var peak: Float
    public var rms: Float
    public init(peak: Float = 0, rms: Float = 0) { self.peak = peak; self.rms = rms }

    /// 0...1 bar position on a dB scale from `floor` dBFS to 0 dBFS.
    public static func position(_ amplitude: Float, floor: Float = -60) -> Float {
        guard amplitude > 0 else { return 0 }
        return min(max((20 * log10(amplitude) - floor) / -floor, 0), 1)
    }
}

/// Left/right levels with ballistics applied, for drawing meters.
public struct StereoLevels: Sendable, Equatable {
    public var left: ChannelLevel
    public var right: ChannelLevel
    public init(left: ChannelLevel = .init(), right: ChannelLevel = .init()) { self.left = left; self.right = right }
    public static let silent = StereoLevels()
}

/// Real-time side of a stereo meter: the audio thread accumulates block peak
/// and energy into atomic cells; nothing is dispatched per buffer.
final class LevelTap: @unchecked Sendable {
    // Per channel c: peak bits at 3c, energy (Double bits) at 3c+1, frames at 3c+2.
    let cells = AtomicCells(count: 6)

    init() {}

    /// Mono input (`right == nil`) feeds both channels.
    @inline(__always)
    func accumulate(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, frames: Int) {
        guard frames > 0 else { return }
        accumulate(channel: 0, left, frames)
        accumulate(channel: 1, right ?? left, frames)
    }

    @inline(__always)
    private func accumulate(channel: Int, _ samples: UnsafePointer<Float>, _ frames: Int) {
        var peak: Float = 0
        var energy: Float = 0
        for index in 0..<frames {
            let sample = samples[index]
            peak = Swift.max(peak, abs(sample))
            energy += sample * sample
        }
        // Non-negative floats order like their bit patterns.
        if peak.isFinite { cells.max(channel * 3, Int64(peak.bitPattern)) }
        if energy.isFinite { cells.addDouble(channel * 3 + 1, Double(energy)) }
        cells.add(channel * 3 + 2, Int64(frames))
    }

    /// Peak and mean square per channel since the previous call, plus frames seen.
    func drain() -> [(peak: Float, meanSquare: Float, frames: Int)] {
        (0..<2).map { channel in
            let peak = Float(bitPattern: UInt32(truncatingIfNeeded: cells.exchange(channel * 3, 0)))
            let energy = cells.exchangeDouble(channel * 3 + 1, 0)
            let frames = Int(cells.exchange(channel * 3 + 2, 0))
            return (peak, frames > 0 ? Float(energy / Double(frames)) : 0, frames)
        }
    }
}

/// Peak falls at a fixed dB rate; RMS follows a fast-attack, slow-release envelope.
public struct MeterBallistics: Sendable, Equatable {
    public static let peakReleaseDecibelsPerSecond: Float = 26
    public static let rmsAttackSeconds = 0.03
    public static let rmsReleaseSeconds = 0.3

    public private(set) var level = ChannelLevel()
    private var meanSquare: Float = 0

    public init() {}

    /// Advances by `elapsed` seconds. `peak`/`meanSquare` describe the audio
    /// that arrived meanwhile; `meanSquare == nil` holds the RMS envelope
    /// (no new audio yet), while 0 lets it fall.
    public mutating func update(peak: Float, meanSquare newMeanSquare: Float?, elapsed: Double) {
        let elapsed = max(0, elapsed.isFinite ? elapsed : 0)
        let fall = powf(10, -Self.peakReleaseDecibelsPerSecond * Float(elapsed) / 20)
        level.peak = max(peak.isFinite ? peak : 0, level.peak * fall)
        if level.peak < 0.000_01 { level.peak = 0 }
        if let input = newMeanSquare, input.isFinite {
            let tau = input > meanSquare ? Self.rmsAttackSeconds : Self.rmsReleaseSeconds
            meanSquare += (input - meanSquare) * Float(1 - exp(-elapsed / tau))
            if meanSquare < 1e-10 { meanSquare = 0 }
        }
        // The bar never pokes out above the peak tick.
        level.rms = min(meanSquare.squareRoot(), level.peak)
    }
}

/// Reader side: poll at display rate from any thread.
final class StereoMeter: @unchecked Sendable {
    let tap = LevelTap()
    private let lock = OSAllocatedUnfairLock()
    private var ballistics = [MeterBallistics(), MeterBallistics()]
    private var lastRead: Double?
    private var lastAudio: Double = 0

    func read(now: Double = ProcessInfo.processInfo.systemUptime) -> StereoLevels {
        lock.withLockUnchecked {
            let elapsed = lastRead.map { now - $0 } ?? 0
            lastRead = now
            let blocks = tap.drain()
            let hasAudio = blocks.contains { $0.frames > 0 }
            if hasAudio { lastAudio = now }
            // Between audio blocks hold the RMS envelope; after a gap let it fall.
            let stale = now - lastAudio > 0.1
            for channel in 0..<2 {
                let block = blocks[channel]
                let meanSquare: Float? = block.frames > 0 ? block.meanSquare : (stale ? 0 : nil)
                ballistics[channel].update(peak: block.peak, meanSquare: meanSquare, elapsed: elapsed)
            }
            return StereoLevels(left: ballistics[0].level, right: ballistics[1].level)
        }
    }
}
