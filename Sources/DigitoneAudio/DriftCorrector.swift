import Foundation

/// Keeps the input → output handoff at `target` frames when the two devices
/// run on different clocks.
///
/// The fill level is smoothed (0.5 s) and a gentle PI loop turns the error into
/// a read-rate ratio limited to ±500 ppm (under one cent of pitch). With the
/// gains below the loop settles in ~20 s and is well damped (ζ ≈ 0.85), so
/// per-callback jitter never reaches the pitch.
struct DriftCorrector: Sendable, Equatable {
    static let maximumDeviation = 0.000_5
    /// Ratio change per frame of smoothed error (1 ppm/frame).
    static let proportional = 0.000_001
    /// Integral gain per frame·second; removes the steady offset in about a minute.
    static let integral = 0.000_001 / 60
    static let smoothingSeconds = 0.5

    private(set) var target: Double
    private(set) var smoothedFill: Double
    private(set) var integralTerm: Double = 0
    private(set) var ratio: Double = 1

    init(target: Double) {
        self.target = target
        smoothedFill = target
    }

    /// Restarts around the current fill, keeping the learnt clock offset.
    mutating func reset(target: Double, fill: Double) {
        self.target = target
        smoothedFill = fill
    }

    /// `fill`: frames available ahead of the read position before this block.
    /// Returns input frames to consume per output frame.
    mutating func update(fill: Double, frames: Int, sampleRate: Double) -> Double {
        guard frames > 0, sampleRate > 0, fill.isFinite else { return ratio }
        let seconds = Double(frames) / sampleRate
        smoothedFill += (fill - smoothedFill) * (1 - exp(-seconds / Self.smoothingSeconds))
        let error = smoothedFill - target
        integralTerm = min(max(integralTerm + error * seconds * Self.integral, -Self.maximumDeviation), Self.maximumDeviation)
        let deviation = min(max(error * Self.proportional + integralTerm, -Self.maximumDeviation), Self.maximumDeviation)
        ratio = 1 + deviation
        return ratio
    }

    var ppm: Double { (ratio - 1) * 1_000_000 }
}
