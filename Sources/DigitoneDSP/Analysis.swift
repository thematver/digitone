import Accelerate
import Foundation

public enum LevelMeter {
    /// Peak and RMS of a block of samples in dBFS.
    public static func measure(_ samples: UnsafeBufferPointer<Float>) -> AudioLevel {
        guard !samples.isEmpty else { return .silent }
        var peak: Float = 0
        var sum: Float = 0
        for sample in samples {
            peak = max(peak, abs(sample))
            sum += sample * sample
        }
        return AudioLevel(peak: decibels(peak), rms: decibels((sum / Float(samples.count)).squareRoot()))
    }

    public static func decibels(_ amplitude: Float) -> Float {
        amplitude > 0 ? 20 * log10(amplitude) : -.infinity
    }
}

public enum WaveformPeaks {
    /// Splits `samples` into `bins` equal columns. Returns fewer bins only when
    /// there are fewer samples than bins.
    public static func compute(_ samples: UnsafeBufferPointer<Float>, bins: Int) -> [PeakBin] {
        guard bins > 0, !samples.isEmpty else { return [] }
        let count = min(bins, samples.count)
        var result: [PeakBin] = []
        result.reserveCapacity(count)
        for bin in 0..<count {
            let lower = bin * samples.count / count
            let upper = max(lower + 1, (bin + 1) * samples.count / count)
            var low = Float.greatestFiniteMagnitude
            var high = -Float.greatestFiniteMagnitude
            var sum: Float = 0
            for index in lower..<upper {
                let sample = samples[index]
                low = min(low, sample)
                high = max(high, sample)
                sum += sample * sample
            }
            result.append(PeakBin(min: low, max: high, rms: (sum / Float(upper - lower)).squareRoot()))
        }
        return result
    }

    public static func compute(_ samples: [Float], bins: Int) -> [PeakBin] {
        samples.withUnsafeBufferPointer { compute($0, bins: bins) }
    }
}

/// Log-band magnitude spectrum for live visualization.
///
/// Hann-windowed real FFT; band magnitudes are the loudest bin in each of
/// `bandCount` log-spaced bands from 20 Hz to min(20 kHz, Nyquist), in dBFS
/// where a full-scale sine reads about 0 dB. Bands too narrow to contain a bin
/// are interpolated from the neighbouring bins. Values are clamped to
/// `floorDecibels`. FFT working memory is allocated in init; analyze returns
/// an allocated snapshot and should run off the real-time audio thread.
public final class SpectrumAnalyzer: @unchecked Sendable {
    public static let floorDecibels: Float = -120
    public static let lowestFrequency: Float = 20
    public static let highestFrequency: Float = 20_000

    public let fftSize: Int
    public let bandCount: Int
    public let sampleRate: Double
    /// Geometric centre frequency of every band, lowest first.
    public let bandFrequencies: [Float]

    private struct Band {
        /// Bins `lowerBin..<upperBin` belong to the band; empty when the band
        /// falls between two bins, then `position` is the fractional bin of
        /// the band centre used for interpolation.
        var lowerBin: Int
        var upperBin: Int
        var position: Float
    }

    private let fft: RealFFT
    private let bands: [Band]
    private let input: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>

    public init(fftSize: Int = 2048, bandCount: Int = 64, sampleRate: Double = 48_000) {
        precondition(fftSize >= 64 && fftSize & (fftSize - 1) == 0, "fftSize must be a power of two")
        precondition(sampleRate.isFinite && sampleRate > 0, "sampleRate must be finite and positive")
        self.fftSize = fftSize
        self.bandCount = max(0, bandCount)
        self.sampleRate = sampleRate
        fft = RealFFT(size: fftSize)
        input = .allocate(capacity: fftSize)
        input.initialize(repeating: 0, count: fftSize)
        power = .allocate(capacity: fftSize / 2)
        power.initialize(repeating: 0, count: fftSize / 2)

        let binCount = fftSize / 2
        let binWidth = sampleRate > 0 ? Float(sampleRate) / Float(fftSize) : 1
        let high = min(Self.highestFrequency, Float(sampleRate / 2))
        let low = min(Self.lowestFrequency, high / 2)
        let count = self.bandCount
        var frequencies: [Float] = []
        var bands: [Band] = []
        frequencies.reserveCapacity(count)
        bands.reserveCapacity(count)
        for index in 0..<count {
            let lowerEdge = low * pow(high / low, Float(index) / Float(count))
            let upperEdge = low * pow(high / low, Float(index + 1) / Float(count))
            let centre = (lowerEdge * upperEdge).squareRoot()
            let lowerBin = min(binCount, max(1, Int((lowerEdge / binWidth).rounded(.up))))
            var upperBin = min(binCount, Int((upperEdge / binWidth).rounded(.up)))
            if index == count - 1 { upperBin = min(binCount, Int(upperEdge / binWidth) + 1) }
            let position = min(Float(binCount - 1), centre / binWidth)
            frequencies.append(centre)
            bands.append(Band(lowerBin: lowerBin, upperBin: max(lowerBin, upperBin), position: position))
        }
        bandFrequencies = frequencies
        self.bands = bands
    }

    deinit {
        input.deallocate()
        power.deallocate()
    }

    /// Analyzes the most recent `fftSize` samples (zero-padded if fewer).
    /// Not thread-safe; use one analyzer per thread.
    public func analyze(_ samples: UnsafeBufferPointer<Float>) -> Spectrum {
        guard bandCount > 0 else { return .empty }
        let available = min(samples.count, fftSize)
        let padding = fftSize - available
        if padding > 0 { input.update(repeating: 0, count: padding) }
        if available > 0, let base = samples.baseAddress {
            (input + padding).update(from: base + (samples.count - available), count: available)
        }
        fft.powerSpectrum(of: input, into: power)

        let scale = 1 / (fft.windowSum * fft.windowSum)
        let floorPower = pow(10, Self.floorDecibels / 10)
        let magnitudes = [Float](unsafeUninitializedCapacity: bandCount) { buffer, initialized in
            for (index, band) in bands.enumerated() {
                var value: Float
                if band.upperBin > band.lowerBin {
                    value = 0
                    vDSP_maxv(power + band.lowerBin, 1, &value, vDSP_Length(band.upperBin - band.lowerBin))
                } else {
                    let lower = Int(band.position)
                    let upper = min(lower + 1, fftSize / 2 - 1)
                    let fraction = band.position - Float(lower)
                    let amplitude = power[lower].squareRoot() * (1 - fraction) + power[upper].squareRoot() * fraction
                    value = amplitude * amplitude
                }
                buffer[index] = 10 * log10(max(value * scale, floorPower))
            }
            initialized = bandCount
        }
        return Spectrum(bandFrequencies: bandFrequencies, magnitudes: magnitudes)
    }
}
