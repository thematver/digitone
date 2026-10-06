import AVFoundation

/// Single-producer, single-consumer handoff from an audio callback to its
/// serial worker. The callback only copies into preallocated storage and
/// publishes counters; it never locks, allocates, analyzes or writes files.
final class InputCaptureQueue: @unchecked Sendable {
    private let channelCount: Int
    let capacityFrames: Int
    private let mask: Int
    private let blockFrames = 4_096
    private let storage: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    /// Written, released, first gap position + 1, stopped, dropped blocks.
    private let counters = AtomicCells(count: 5)
    /// Only the serial worker touches this position.
    private var readIndex: Int64 = 0
    private let worker = DispatchQueue(label: "Digitone.audio.input", qos: .userInitiated)
    private let timer: DispatchSourceTimer
    private let consume: @Sendable ([UnsafeBufferPointer<Float>]) -> Void
    private let onOverflow: @Sendable () -> Void

    init(channelCount: Int, capacityFrames requested: Int = 262_144, automaticallyDrain: Bool = true,
         consume: @escaping @Sendable ([UnsafeBufferPointer<Float>]) -> Void,
         onOverflow: @escaping @Sendable () -> Void) {
        self.channelCount = min(max(channelCount, 1), 2)
        self.consume = consume
        self.onOverflow = onOverflow
        var capacity = 64
        while capacity < requested { capacity <<= 1 }
        capacityFrames = capacity
        mask = capacity - 1
        storage = .allocate(capacity: capacity * self.channelCount)
        scratch = .allocate(capacity: blockFrames * self.channelCount)
        timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: automaticallyDrain ? .now() : .distantFuture,
                       repeating: .milliseconds(5), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.drain() }
        timer.resume()
    }

    deinit {
        timer.cancel()
        storage.deallocate()
        scratch.deallocate()
    }

    var droppedBlocks: Int64 { counters.load(4) }

    /// AVAudioEngine owns the supplied buffer; copy before the tap returns.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        enqueue(data, channelCount: Int(buffer.format.channelCount), frames: Int(buffer.frameLength), stride: buffer.stride)
    }

    /// One audio callback is the producer. An entire block is rejected only
    /// when it cannot fit; worker activity cannot cause a spurious lock miss.
    func enqueue(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount sourceChannels: Int, frames: Int, stride: Int = 1) {
        guard frames > 0, sourceChannels > 0, stride > 0, counters.load(3) == 0 else { return }
        // Keep the gap contiguous until the worker has consumed the intact
        // prefix and failed affected captures. No post-gap audio can enter a
        // take or segment before its loss has been reported.
        guard counters.load(2) == 0 else { counters.add(4, 1); return }
        let written = counters.load(0)
        guard frames <= capacityFrames, written - counters.load(1) <= Int64(capacityFrames - frames) else {
            counters.store(2, written + 1)
            counters.add(4, 1)
            return
        }
        let offset = Int(written) & mask
        let first = min(frames, capacityFrames - offset)
        for channel in 0..<channelCount {
            let sourceChannel = min(channel, sourceChannels - 1)
            let destination = storage + channel * capacityFrames
            if stride == 1 {
                (destination + offset).update(from: data[sourceChannel], count: first)
                if first < frames { destination.update(from: data[sourceChannel] + first, count: frames - first) }
            } else {
                for frame in 0..<frames { destination[(offset + frame) & mask] = data[0][frame * stride + sourceChannel] }
            }
        }
        // Publish samples only after all channel copies are complete.
        counters.store(0, written + Int64(frames))
    }

    /// Called after stopping the producer. All accepted frames and any final
    /// gap are delivered before the recorder can close its file.
    func finish() {
        counters.store(3, 1)
        timer.cancel()
        worker.sync { drain() }
    }

    /// Orders file lifecycle changes after input already accepted when this
    /// worker job begins. Later callbacks belong to the next recording phase.
    func synchronize<T>(_ body: () throws -> T) rethrows -> T {
        try worker.sync {
            drain()
            return try body()
        }
    }

    private func drain() {
        // A finite boundary prevents continuous input from starving start/stop
        // jobs queued behind this timer handler.
        let boundary = counters.load(0)
        while readIndex < boundary {
            let frames = min(blockFrames, Int(boundary - readIndex))
            let offset = Int(readIndex) & mask
            let first = min(frames, capacityFrames - offset)
            for channel in 0..<channelCount {
                let source = storage + channel * capacityFrames
                let destination = scratch + channel * blockFrames
                destination.update(from: source + offset, count: first)
                if first < frames { (destination + first).update(from: source, count: frames - first) }
            }
            readIndex += Int64(frames)
            // The producer may reuse storage once its samples are in scratch.
            counters.store(1, readIndex)
            consume((0..<channelCount).map { UnsafeBufferPointer(start: scratch + $0 * blockFrames, count: frames) })
        }
        let gap = counters.load(2)
        if gap > 0, readIndex >= gap - 1 {
            onOverflow()
            // Resume accepting input only after affected captures have failed.
            counters.store(2, 0)
        }
    }
}
