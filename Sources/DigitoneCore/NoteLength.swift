import Foundation

/// The Elektron trig LEN byte (0...127) of a Digitone II note record.
///
/// Source: digi-roll `dt2-pattern-format.md`, which `dn2-pattern-format.md`
/// declares identical for the Digitone II (read 3 October 2026):
/// "piecewise-linear, doubling every 16 values: 0 = 0.125 steps, 14 = 1 step,
/// 30 = 2, 46 = 4, 62 = 8, 78 = 16, 94 = 32, 110 = 64, 126 = 128,
/// 127 = infinite. Between landmarks each increment adds 1/16 of the current
/// base"; codes 0...14 advance by 1/16 step.
///
/// Confidence: the default 14 = 1 step was seen in hardware dumps and
/// LEN 1/4 = 46 in a controlled DN2 experiment; the rest of the curve is
/// inferred from the Analog Rytm / Digitakt II scale, not measured on this
/// instrument. The manual (TRIG PAGE 1, LEN) documents only the musical
/// values, not their encoding.
///
/// Durations shorter than one tick (1/24 step) cannot be represented, so
/// fractional ticks round to nearest; codes 0...29 lose up to half a tick.
public enum NoteLength {
    public static let defaultCode = 14
    public static let infiniteCode = 127

    /// Exact duration in sequencer steps, or nil for INF and out-of-range codes.
    public static func steps(code: Int) -> Double? {
        guard (0..<infiniteCode).contains(code) else { return nil }
        if code < defaultCode { return Double(code + 2) / 16 }
        let segment = (code - defaultCode) / 16
        let base = Double(1 << segment)
        return base * Double(16 + (code - defaultCode) % 16) / 16
    }

    /// Duration in ticks. INF yields nil; any other unknown code falls back to one step.
    public static func ticks(code: Int) -> Int? {
        if code == infiniteCode { return nil }
        return table.indices.contains(code) ? table[code] : MusicalTime.ticksPerStep
    }

    /// The finite code whose duration is nearest to `ticks`; ties pick the shorter code.
    public static func code(nearestTicks ticks: Int) -> Int {
        let ticks = min(table.last ?? MusicalTime.ticksPerStep, max(0, ticks))
        var best = 0
        for code in table.indices where abs(table[code] - ticks) < abs(table[best] - ticks) { best = code }
        return best
    }

    private static let table: [Int] = (0..<infiniteCode).map { code in
        let steps = NoteLength.steps(code: code) ?? 1
        return max(1, Int((steps * Double(MusicalTime.ticksPerStep)).rounded()))
    }
}
