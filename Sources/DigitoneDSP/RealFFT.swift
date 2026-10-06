import Accelerate

/// Hann-windowed real FFT producing a power spectrum. All memory is allocated
/// in `init`; `powerSpectrum` performs no allocation. Not thread-safe.
final class RealFFT {
    let size: Int
    let log2Size: vDSP_Length
    /// Sum of the window coefficients (coherent gain × size).
    let windowSum: Float

    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>

    var binCount: Int { size / 2 }

    init(size: Int) {
        precondition(size >= 4 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        log2Size = vDSP_Length(size.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed for size \(size)")
        }
        self.setup = setup
        window = .allocate(capacity: size)
        windowed = .allocate(capacity: size)
        real = .allocate(capacity: size / 2)
        imaginary = .allocate(capacity: size / 2)
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        var sum: Float = 0
        vDSP_sve(window, 1, &sum, vDSP_Length(size))
        windowSum = sum
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate()
        windowed.deallocate()
        real.deallocate()
        imaginary.deallocate()
    }

    /// Windows `size` samples from `input` and writes `binCount` squared
    /// magnitudes to `output`, scaled so that `sqrt(output[k]) / windowSum`
    /// is the amplitude of a sinusoid centred on bin `k`.
    func powerSpectrum(of input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>) {
        let half = vDSP_Length(size / 2)
        vDSP_vmul(input, 1, window, 1, windowed, 1, vDSP_Length(size))
        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complex in
            vDSP_ctoz(complex, 2, &split, 1, half)
        }
        vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(kFFTDirection_Forward))
        // zrip packs DC into real[0] and Nyquist into imag[0]; keep DC only,
        // halved because DC is not split between positive and negative bins.
        let dc = real[0] * 0.5
        imaginary[0] = 0
        vDSP_zvmags(&split, 1, output, 1, half)
        output[0] = dc * dc
    }
}
