import Foundation
import os
import DigitoneDSP

/// Latest input analysis, read by the UI at display rate.
public struct MeterSnapshot: Sendable, Equatable {
    /// Level per input channel.
    public var levels: [AudioLevel]
    /// Most recent samples, mono mix, oldest first.
    public var scope: [Float]
    /// May be empty while the analyzer is unavailable.
    public var spectrum: Spectrum
    public var sampleRate: Double
    /// Total frames analyzed since the pipeline was configured; changes on every update.
    public var framesProcessed: Int64

    public init(levels: [AudioLevel], scope: [Float], spectrum: Spectrum, sampleRate: Double, framesProcessed: Int64) {
        self.levels = levels
        self.scope = scope
        self.spectrum = spectrum
        self.sampleRate = sampleRate
        self.framesProcessed = framesProcessed
    }

    public static let empty = MeterSnapshot(levels: [], scope: [], spectrum: .empty, sampleRate: 0, framesProcessed: 0)
}

/// Lock-protected latest snapshot: the tap thread publishes, the UI polls.
public final class MeterStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var value = MeterSnapshot.empty

    public init() {}

    public var snapshot: MeterSnapshot { lock.withLockUnchecked { value } }

    func publish(_ snapshot: MeterSnapshot) {
        lock.withLockUnchecked { value = snapshot }
    }
}
