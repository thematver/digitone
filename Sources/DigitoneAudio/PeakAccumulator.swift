import Foundation
import DigitoneDSP

/// Streams samples into fixed-size blocks so a waveform overview of an
/// arbitrarily long recording can be produced without re-reading the file.
struct PeakAccumulator {
    let blockSize: Int
    private var blocks: [PeakBin] = []
    private var blockSums: [Float] = []
    private var low = Float.greatestFiniteMagnitude
    private var high = -Float.greatestFiniteMagnitude
    private var sum: Float = 0
    private var count = 0

    init(blockSize: Int = 256) {
        precondition(blockSize > 0)
        self.blockSize = blockSize
    }

    mutating func append(_ sample: Float) {
        low = min(low, sample)
        high = max(high, sample)
        sum += sample * sample
        count += 1
        if count == blockSize { closeBlock() }
    }

    /// Reduces the accumulated blocks to at most `bins` columns.
    func peaks(bins: Int) -> [PeakBin] {
        var all = blocks
        var sums = blockSums.map { Double($0) }
        var counts = [Int](repeating: blockSize, count: blocks.count)
        if count > 0 {
            all.append(PeakBin(min: low, max: high, rms: 0))
            sums.append(Double(sum))
            counts.append(count)
        }
        guard bins > 0, !all.isEmpty else { return [] }
        let columns = min(bins, all.count)
        return (0..<columns).map { column in
            let lower = column * all.count / columns
            let upper = max(lower + 1, (column + 1) * all.count / columns)
            var bin = PeakBin(min: .greatestFiniteMagnitude, max: -.greatestFiniteMagnitude, rms: 0)
            var energy = 0.0
            var frames = 0
            for index in lower..<upper {
                bin.min = min(bin.min, all[index].min)
                bin.max = max(bin.max, all[index].max)
                energy += sums[index]
                frames += counts[index]
            }
            bin.rms = Float((energy / Double(max(frames, 1))).squareRoot())
            return bin
        }
    }

    private mutating func closeBlock() {
        blocks.append(PeakBin(min: low, max: high, rms: 0))
        blockSums.append(sum)
        low = .greatestFiniteMagnitude
        high = -.greatestFiniteMagnitude
        sum = 0
        count = 0
    }
}
