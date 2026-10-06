import Foundation

/// Onset detection for slicing: log-compressed spectral flux, an adaptive
/// moving-median threshold, peak picking, then refinement in the time domain
/// to the frame where the energy rise starts. Offline; allocates freely.
public struct TransientDetector: Sendable, Equatable {
    /// 0 keeps only the strongest hits, 1 also finds subtle onsets.
    public var sensitivity: Float
    /// Minimum distance between reported onsets, in seconds.
    public var minimumGap: Double

    static let frameSize = 1024
    static let hopSize = 256
    static let medianRadius = 8
    static let refineBlock = 32

    public init(sensitivity: Float = 0.5, minimumGap: Double = 0.05) {
        self.sensitivity = sensitivity
        self.minimumGap = minimumGap
    }

    /// Onset positions in frames, ascending. Multichannel input is mixed to mono.
    public func detect(in buffer: SampleBuffer) -> [Int] {
        detect(SampleMath.toMono(buffer).channels[0], sampleRate: buffer.sampleRate)
    }

    public func detect(_ samples: [Float], sampleRate: Double) -> [Int] {
        guard samples.count > 1, sampleRate.isFinite, sampleRate > 0 else { return [] }
        let flux = spectralFlux(samples)
        guard let maximum = flux.max(), maximum > 0 else { return [] }
        let normalized = flux.map { $0 / maximum }

        let clamped = sensitivity.isFinite ? min(max(sensitivity, 0), 1) : 0.5
        let delta = 0.5 - 0.47 * clamped
        let gapSeconds = minimumGap.isFinite ? max(0, minimumGap) : 0.05
        let gap = max(1, Int(min(Double(samples.count), gapSeconds * sampleRate)))
        let radius = Self.medianRadius
        var onsets: [Int] = []
        for index in normalized.indices {
            let value = normalized[index]
            let window = normalized[max(0, index - radius)...min(normalized.count - 1, index + radius)]
            guard value >= Self.median(window) + delta else { continue }
            let neighbours = max(0, index - 2)...min(normalized.count - 1, index + 2)
            // Strict maximum towards the past so a plateau reports its first frame.
            guard neighbours.allSatisfy({ $0 == index || ($0 < index ? normalized[$0] < value : normalized[$0] <= value) }) else {
                continue
            }
            let centre = index * Self.hopSize
            let lower = max(0, centre - Self.frameSize / 2, (onsets.last ?? -1) + 1)
            let upper = min(samples.count, centre + Self.frameSize / 2)
            guard lower < upper else { continue }
            let onset = Self.refine(samples, lower..<upper)
            if let last = onsets.last, onset - last < gap { continue }
            onsets.append(onset)
        }
        return onsets
    }

    /// Start frames of `count` equal slices covering `frameCount` frames.
    public static func equalSlices(frameCount: Int, count: Int) -> [Int] {
        guard frameCount > 0, count > 0 else { return [] }
        let slices = min(count, frameCount)
        return (0..<slices).map { $0 * frameCount / slices }
    }

    /// Converts ascending start frames into contiguous slice ranges ending at `frameCount`.
    public static func ranges(from starts: [Int], frameCount: Int) -> [Range<Int>] {
        let sorted = Array(Set(starts.filter { $0 >= 0 && $0 < frameCount })).sorted()
        return sorted.enumerated().map { index, start in
            start..<(index + 1 < sorted.count ? sorted[index + 1] : frameCount)
        }
    }

    // MARK: Internals

    /// Positive log-magnitude change per hop; frame `n` is centred on `n * hopSize`.
    private func spectralFlux(_ samples: [Float]) -> [Float] {
        let size = Self.frameSize
        let hop = Self.hopSize
        let fft = RealFFT(size: size)
        let bins = fft.binCount
        let frameCount = samples.count / hop + 1
        var frame = [Float](repeating: 0, count: size)
        var power = [Float](repeating: 0, count: bins)
        var previous = [Float](repeating: 0, count: bins)
        var current = [Float](repeating: 0, count: bins)
        let compression = Float(1000) / fft.windowSum
        var flux = [Float](repeating: 0, count: frameCount)
        for index in 0..<frameCount {
            let start = index * hop - size / 2
            for offset in 0..<size {
                let source = start + offset
                frame[offset] = source >= 0 && source < samples.count ? samples[source] : 0
            }
            frame.withUnsafeBufferPointer { input in
                power.withUnsafeMutableBufferPointer { output in
                    guard let source = input.baseAddress, let destination = output.baseAddress else { return }
                    fft.powerSpectrum(of: source, into: destination)
                }
            }
            var sum: Float = 0
            for bin in 1..<bins {
                current[bin] = log1p(compression * power[bin].squareRoot())
                sum += max(0, current[bin] - previous[bin])
            }
            flux[index] = sum
            swap(&previous, &current)
        }
        return flux
    }

    /// Finds the block with the sharpest energy rise relative to the
    /// preceding blocks, then the first sample in it that clearly exceeds
    /// the preceding level.
    private static func refine(_ samples: [Float], _ range: Range<Int>) -> Int {
        let block = refineBlock
        // Include the partial final block: an onset can fall in the last
        // frames of a recording, not only in complete analysis blocks.
        let blockCount = max(1, (range.count + block - 1) / block)
        let history = 4
        var energies = [Float](repeating: 0, count: blockCount + history)
        for index in energies.indices {
            let start = range.lowerBound + (index - history) * block
            let lower = max(0, start)
            let upper = min(range.upperBound, start + block)
            guard lower < upper else { continue }
            var sum: Float = 0
            for frame in lower..<upper { sum += samples[frame] * samples[frame] }
            energies[index] = sum / Float(max(1, upper - lower))
        }
        let floor: Float = 1e-10
        var best = history
        var bestRise = -Float.infinity
        // Compare the first candidate with actual preceding audio too. Using
        // a zero baseline at every search-window boundary turns the previous
        // note's decaying tail into a false onset hundreds of frames early.
        for index in history..<energies.count {
            let before = energies[(index - history)..<index].max() ?? 0
            let rise = log10(energies[index] + floor) - log10(before + floor)
            if rise > bestRise { bestRise = rise; best = index }
        }
        let before = energies[(best - history)..<best].max() ?? 0
        let threshold = max(4 * before.squareRoot(), 1e-4)
        let lower = range.lowerBound + (best - history) * block
        let upper = min(range.upperBound, lower + block)
        return (lower..<upper).first { abs(samples[$0]) > threshold } ?? lower
    }

    private static func median(_ values: ArraySlice<Float>) -> Float {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
