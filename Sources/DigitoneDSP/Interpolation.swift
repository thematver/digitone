/// Fractional-position sample readers shared by the sampler voices and the
/// offline resampler. Neighbours outside `lower...upper` are clamped to the
/// edge. Real-time safe.
public enum SampleInterpolation: String, Sendable, Codable, CaseIterable {
    case linear
    /// 4-point, 3rd-order Hermite (Catmull-Rom): smoother highs when repitching.
    case hermite
}

enum Interpolation {
    @inline(__always)
    static func read(
        _ samples: UnsafeBufferPointer<Float>, at position: Double,
        lower: Int, upper: Int, mode: SampleInterpolation, looping: Bool = false
    ) -> Float {
        let index = Int(position.rounded(.down))
        let fraction = Float(position - Double(index))
        @inline(__always) func at(_ offset: Int) -> Float {
            let neighbour = index + offset
            if looping {
                let length = upper - lower + 1
                let relative = (neighbour - lower) % length
                return samples[lower + (relative < 0 ? relative + length : relative)]
            }
            return samples[min(max(neighbour, lower), upper)]
        }
        switch mode {
        case .linear:
            let x0 = at(0)
            return fraction == 0 ? x0 : x0 + fraction * (at(1) - x0)
        case .hermite:
            let x0 = at(0)
            guard fraction != 0 else { return x0 }
            return hermite(at(-1), x0, at(1), at(2), fraction)
        }
    }

    @inline(__always)
    static func hermite(_ xm1: Float, _ x0: Float, _ x1: Float, _ x2: Float, _ t: Float) -> Float {
        let c1 = 0.5 * (x1 - xm1)
        let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
        let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
        return ((c3 * t + c2) * t + c1) * t + x0
    }

    /// Hermite read over the whole buffer; positions outside it read silence.
    static func hermite(_ samples: UnsafeBufferPointer<Float>, at position: Double) -> Float {
        guard !samples.isEmpty, position >= 0, position < Double(samples.count) else { return 0 }
        return read(samples, at: position, lower: 0, upper: samples.count - 1, mode: .hermite)
    }
}
