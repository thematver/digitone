import Foundation
import os
import DigitoneDSP

/// Preallocated multichannel ring holding the most recent input.
///
/// Written from the input tap thread, read from any thread. A mono source is
/// duplicated to every channel; extra source channels are ignored.
public final class SampleRingBuffer: @unchecked Sendable {
    public let channelCount: Int
    public let capacity: Int
    public let sampleRate: Double

    private let storage: [UnsafeMutablePointer<Float>]
    private var writeIndex = 0
    private var filled = 0
    private let lock = OSAllocatedUnfairLock()

    public init(seconds: Double, sampleRate: Double, channelCount: Int = 2) {
        precondition(seconds > 0 && sampleRate > 0 && channelCount > 0, "Ring buffer needs a positive size")
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        let frames = Int((seconds * sampleRate).rounded(.up))
        capacity = frames
        storage = (0..<channelCount).map { _ in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            pointer.initialize(repeating: 0, count: frames)
            return pointer
        }
    }

    deinit { storage.forEach { $0.deallocate() } }

    public var filledFrames: Int { lock.withLockUnchecked { filled } }
    public var filledDuration: Double { Double(filledFrames) / sampleRate }

    public func write(_ source: [UnsafeBufferPointer<Float>]) {
        guard let frameCount = source.first?.count, frameCount > 0,
              source.allSatisfy({ $0.count == frameCount }) else { return }
        lock.withLockUnchecked {
            // Only the newest `capacity` frames can survive.
            let skip = max(0, frameCount - capacity)
            var remaining = frameCount - skip
            var sourceOffset = skip
            while remaining > 0 {
                let run = min(remaining, capacity - writeIndex)
                for channel in 0..<channelCount {
                    let input = source[min(channel, source.count - 1)]
                    guard let base = input.baseAddress else { continue }
                    (storage[channel] + writeIndex).update(from: base + sourceOffset, count: run)
                }
                writeIndex = (writeIndex + run) % capacity
                sourceOffset += run
                remaining -= run
            }
            filled = min(capacity, filled + frameCount)
        }
    }

    /// The newest `seconds` of audio, or everything captured so far when less is available.
    public func captureLast(seconds: Double) -> SampleBuffer {
        let clampedSeconds = seconds.isFinite ? min(max(0, seconds), Double(capacity) / sampleRate) : 0
        let wanted = min(capacity, Int((clampedSeconds * sampleRate).rounded()))
        return lock.withLockUnchecked {
            let count = min(wanted, filled)
            let start = (writeIndex - count + capacity) % capacity
            let channels = storage.map { pointer -> [Float] in
                [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
                    guard let base = buffer.baseAddress else { initialized = 0; return }
                    let firstRun = min(count, capacity - start)
                    base.update(from: pointer + start, count: firstRun)
                    (base + firstRun).update(from: pointer, count: count - firstRun)
                    initialized = count
                }
            }
            return SampleBuffer(sampleRate: sampleRate, channels: channels)
        }
    }

    public func reset() {
        lock.withLockUnchecked {
            writeIndex = 0
            filled = 0
        }
    }
}
