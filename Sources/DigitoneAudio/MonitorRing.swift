import Darwin

/// Fixed 64-bit cells shared with a real-time thread without locks or
/// allocation. Darwin's barrier atomics are used because Swift's
/// `Synchronization.Atomic` needs newer deployment targets than macOS 14/iOS 17.
final class AtomicCells: @unchecked Sendable {
    private let cells: UnsafeMutablePointer<Int64>
    let count: Int

    init(count: Int) {
        self.count = count
        cells = .allocate(capacity: count)
        cells.initialize(repeating: 0, count: count)
    }

    deinit { cells.deallocate() }

    @inline(__always) func load(_ index: Int) -> Int64 { OSAtomicAdd64Barrier(0, cells + index) }

    @inline(__always) @discardableResult
    func add(_ index: Int, _ amount: Int64) -> Int64 { OSAtomicAdd64Barrier(amount, cells + index) }

    @inline(__always) func store(_ index: Int, _ value: Int64) { _ = exchange(index, value) }

    @inline(__always) @discardableResult
    func exchange(_ index: Int, _ value: Int64) -> Int64 {
        var old = load(index)
        while !OSAtomicCompareAndSwap64Barrier(old, value, cells + index) { old = load(index) }
        return old
    }

    /// Raises the cell to `value` if larger.
    @inline(__always) func max(_ index: Int, _ value: Int64) {
        var old = load(index)
        while value > old, !OSAtomicCompareAndSwap64Barrier(old, value, cells + index) { old = load(index) }
    }

    @inline(__always) func loadDouble(_ index: Int) -> Double { Double(bitPattern: UInt64(bitPattern: load(index))) }
    @inline(__always) func storeDouble(_ index: Int, _ value: Double) { store(index, Int64(bitPattern: value.bitPattern)) }

    /// Adds to a Double kept as bits; safe against a concurrent `exchange`.
    @inline(__always) func addDouble(_ index: Int, _ amount: Double) {
        var old = load(index)
        while true {
            let new = Int64(bitPattern: (Double(bitPattern: UInt64(bitPattern: old)) + amount).bitPattern)
            if OSAtomicCompareAndSwap64Barrier(old, new, cells + index) { return }
            old = load(index)
        }
    }

    @inline(__always) func exchangeDouble(_ index: Int, _ value: Double) -> Double {
        Double(bitPattern: UInt64(bitPattern: exchange(index, Int64(bitPattern: value.bitPattern))))
    }
}

/// Single-producer, single-consumer stereo ring between the input callback and
/// the monitor render callback. Positions are absolute frame counters, so the
/// consumer can read at fractional positions and keep history behind it.
/// Neither side locks or allocates.
final class MonitorRing: @unchecked Sendable {
    let capacity: Int
    private let mask: Int
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    /// 0: frames ever written, 1: frames released by the consumer, 2: dropped writes.
    private let counters = AtomicCells(count: 3)

    /// `capacity` is rounded up to a power of two.
    init(capacity requested: Int = 16_384) {
        var size = 1
        while size < Swift.max(requested, 64) { size <<= 1 }
        capacity = size
        mask = size - 1
        left = .allocate(capacity: size)
        right = .allocate(capacity: size)
        left.initialize(repeating: 0, count: size)
        right.initialize(repeating: 0, count: size)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    var written: Int64 { counters.load(0) }
    var released: Int64 { counters.load(1) }
    var droppedWrites: Int64 { counters.load(2) }

    // MARK: Producer

    /// Appends a block; a mono source (`right == nil`) is duplicated. When the
    /// consumer has stalled and the block does not fit it is dropped whole,
    /// and the consumer later resynchronises to the newest audio.
    @discardableResult
    func write(left source: UnsafePointer<Float>, right sourceRight: UnsafePointer<Float>?, frames: Int) -> Bool {
        guard frames > 0 else { return true }
        let start = counters.load(0)
        guard Int(start - counters.load(1)) + frames <= capacity else {
            counters.add(2, 1)
            return false
        }
        let offset = Int(start) & mask
        let first = Swift.min(frames, capacity - offset)
        let other = sourceRight ?? source
        (left + offset).update(from: source, count: first)
        (right + offset).update(from: other, count: first)
        if first < frames {
            left.update(from: source + first, count: frames - first)
            right.update(from: other + first, count: frames - first)
        }
        // The barrier in `add` publishes the samples before the new count.
        counters.add(0, Int64(frames))
        return true
    }

    // MARK: Consumer

    @inline(__always) func sample(_ channel: UnsafeMutablePointer<Float>, at position: Int64) -> Float {
        channel[Int(position) & mask]
    }

    /// Frames before `position` may be overwritten by the producer.
    @inline(__always) func release(upTo position: Int64) { counters.store(1, position) }
}
