import AVFoundation

/// Counters from both sides of the monitor path, read at any time.
public struct MonitorDiagnostics: Sendable, Equatable {
    public var inputCallbacks: Int64 = 0
    public var inputFrames: Int64 = 0
    public var inputRenderErrors: Int64 = 0
    /// Measured input clock (frames per host second), 0 until known.
    public var inputRate: Double = 0
    public var outputCallbacks: Int64 = 0
    public var outputFrames: Int64 = 0
    public var outputRate: Double = 0
    /// Output blocks that found too little input (silence was played).
    public var underruns: Int64 = 0
    /// Times the reader jumped forward because input piled up (output stalled).
    public var resyncs: Int64 = 0
    /// Input blocks dropped because the ring was full.
    public var droppedInputBlocks: Int64 = 0
    /// Frames waiting between input and output, last block and target.
    public var fill: Int = 0
    public var targetFill: Int = 0
    /// Rate correction applied by the drift loop.
    public var correctionPPM: Double = 0
    public var overloads: Int = 0

    public init() {}

    /// Clock difference measured against the host clock, in ppm.
    public var measuredDriftPPM: Double {
        inputRate > 0 && outputRate > 0 ? (inputRate / outputRate - 1) * 1_000_000 : 0
    }
}

/// Host-clock rate measurement for one IO callback stream (frames vs host time).
/// Cells: 0 calls, 1 frames, 2 first host, 3 first sample, 4 last host, 5 last sample.
final class ClockProbe: @unchecked Sendable {
    let cells = AtomicCells(count: 6)

    @inline(__always) func record(_ timeStamp: UnsafePointer<AudioTimeStamp>, frames: Int) {
        cells.add(0, 1)
        cells.add(1, Int64(frames))
        let stamp = timeStamp.pointee
        guard stamp.mFlags.contains(.hostTimeValid), stamp.mFlags.contains(.sampleTimeValid) else { return }
        if cells.load(2) == 0 {
            cells.store(3, Int64(stamp.mSampleTime))
            cells.store(2, Int64(bitPattern: stamp.mHostTime))
        }
        cells.store(5, Int64(stamp.mSampleTime))
        cells.store(4, Int64(bitPattern: stamp.mHostTime))
    }

    var calls: Int64 { cells.load(0) }
    var frames: Int64 { cells.load(1) }

    /// Frames per second of host time between the first and last callback.
    var rate: Double {
        let first = UInt64(bitPattern: cells.load(2)), last = UInt64(bitPattern: cells.load(4))
        guard first > 0, last > first else { return 0 }
        let seconds = AVAudioTime.seconds(forHostTime: last) - AVAudioTime.seconds(forHostTime: first)
        return seconds > 0.5 ? Double(cells.load(5) - cells.load(3)) / seconds : 0
    }

    func reset() { (0..<6).forEach { cells.store($0, 0) } }
}

/// Plays the monitor ring into the output graph at the input sample rate.
/// Reads at a fractional position (4-point Hermite) steered by `DriftCorrector`,
/// applies the monitor gain with a ramp, and meters what it plays.
final class MonitorSource: @unchecked Sendable {
    static let maximumTarget = 4_096
    static let fadeFrames = 256

    let ring: MonitorRing
    /// Monitor-path level after the monitor gain, before the master level.
    let meter = StereoMeter()
    let clock = ClockProbe()
    /// 0 gain bits, 1 target fill, 2 last fill, 3 correction ppm·1000, 4 underruns, 5 resyncs, 6 minimum target, 7 reprime request.
    private let shared = AtomicCells(count: 8)

    // Render-thread state.
    private var readIndex: Int64 = 0
    private var fraction: Double = 0
    private var corrector: DriftCorrector
    private var priming = true
    private var fade = 0
    private var gain: Float = 0
    /// The node's rate: the input device rate; the mixer converts to the output rate.
    let sampleRate: Double

    init(ring: MonitorRing, sampleRate: Double, targetFill: Int = 256) {
        self.ring = ring
        self.sampleRate = sampleRate > 0 && sampleRate.isFinite ? sampleRate : DigitoneAudioModule.preferredSampleRate
        readIndex = ring.written
        ring.release(upTo: readIndex)
        corrector = DriftCorrector(target: Double(targetFill))
        shared.store(1, Int64(targetFill))
        shared.store(6, Int64(targetFill))
    }

    /// Smoothly applied on the render thread; 0 silences the path.
    var targetGain: Float {
        get { Float(bitPattern: UInt32(truncatingIfNeeded: shared.load(0))) }
        set { shared.store(0, Int64(min(max(newValue.isFinite ? newValue : 0, 0), 1).bitPattern)) }
    }

    /// Handoff size the reader aims for; raised automatically after an underrun.
    var targetFill: Int { Int(shared.load(1)) }

    /// Sets the floor (e.g. after buffer sizes change); resets the adaptive target.
    func setMinimumTarget(_ frames: Int) {
        let frames = min(max(frames, 32), Self.maximumTarget)
        shared.store(6, Int64(frames))
        shared.store(1, Int64(frames))
    }

    /// Discard queued audio after a route restart, before accepting fresh input.
    func reprime() { shared.store(7, 1) }

    var underruns: Int64 { shared.load(4) }
    var resyncs: Int64 { shared.load(5) }
    var lastFill: Int { Int(shared.load(2)) }
    var correctionPPM: Double { Double(shared.load(3)) / 1_000 }

    /// Builds the node outside any actor so the render block carries no isolation.
    nonisolated static func makeNode(for source: MonitorSource) -> AVAudioSourceNode {
        // Rates come from validated device formats or the 48 kHz default.
        let format = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate, channels: 2)!
        return AVAudioSourceNode(format: format) { _, timeStamp, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
                return noErr
            }
            let capacity = Int(min(buffers[0].mDataByteSize, buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
            let frames = min(Int(frameCount), capacity)
            source.clock.record(timeStamp, frames: frames)
            source.render(frames: frames, left: left, right: right)
            return noErr
        }
    }

    /// Writes (not mixes) `frames` into `left`/`right`. Real-time safe.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frames > 0 else { return }
        let written = ring.written
        let target = Int64(shared.load(1))
        if shared.exchange(7, 0) != 0 {
            readIndex = written
            fraction = 0
            priming = true
            fade = 0
            gain = 0
            ring.release(upTo: readIndex)
        }
        if corrector.target != Double(target) {
            corrector.reset(target: Double(target), fill: corrector.smoothedFill)
        }
        var available = written - readIndex
        if priming {
            guard available >= target + 2 else {
                silence(frames, left, right)
                shared.store(2, available)
                return
            }
            // Start from the newest audio, `target` frames behind the writer.
            readIndex = written - target
            fraction = 0
            corrector.reset(target: Double(target), fill: Double(target))
            priming = false
            fade = 0
            available = target
        } else if available > target + Int64(max(4_096, ring.capacity / 2)) || available < 0 {
            // Output stalled while input kept coming: skip ahead.
            readIndex = written - target
            fraction = 0
            corrector.reset(target: Double(target), fill: Double(target))
            shared.add(5, 1)
            fade = 0
            available = target
        }
        let fill = Double(available) - fraction
        let ratio = corrector.update(fill: fill, frames: frames, sampleRate: sampleRate)
        shared.store(2, available)
        shared.store(3, Int64((ratio - 1) * 1_000_000_000))
        // Hermite needs one frame behind and two ahead of each read position.
        let needed = Int64((fraction + ratio * Double(frames)).rounded(.up)) + 2
        guard available >= needed else {
            silence(frames, left, right)
            priming = true
            shared.add(4, 1)
            // Larger handoff after a dropout: trade a little latency for stability.
            shared.store(1, min(target + 64, Int64(Self.maximumTarget)))
            return
        }
        let goal = targetGain
        let step = (goal - gain) / Float(frames)
        let lowerLimit = written - Int64(ring.capacity) + 1
        for frame in 0..<frames {
            let base = readIndex
            let t = Float(fraction)
            let previous = max(base - 1, lowerLimit)
            var l = Self.hermite(ring.sample(ring.left, at: previous), ring.sample(ring.left, at: base),
                                 ring.sample(ring.left, at: base + 1), ring.sample(ring.left, at: base + 2), t)
            var r = Self.hermite(ring.sample(ring.right, at: previous), ring.sample(ring.right, at: base),
                                 ring.sample(ring.right, at: base + 1), ring.sample(ring.right, at: base + 2), t)
            gain += step
            var scale = gain
            if fade < Self.fadeFrames {
                scale *= Float(fade) / Float(Self.fadeFrames)
                fade += 1
            }
            l *= scale
            r *= scale
            left[frame] = l
            right[frame] = r
            fraction += ratio
            let whole = fraction.rounded(.down)
            readIndex += Int64(whole)
            fraction -= whole
        }
        gain = goal
        ring.release(upTo: readIndex - 1)
        meter.tap.accumulate(left: left, right: right, frames: frames)
    }

    @inline(__always)
    private func silence(_ frames: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        // Keep the producer free to write while we wait.
        if ring.written - readIndex > Int64(ring.capacity / 2) { readIndex = ring.written - Int64(ring.capacity / 4) }
        ring.release(upTo: max(readIndex - 1, 0))
    }

    @inline(__always)
    static func hermite(_ xm1: Float, _ x0: Float, _ x1: Float, _ x2: Float, _ t: Float) -> Float {
        guard t != 0 else { return x0 }
        let c1 = 0.5 * (x1 - xm1)
        let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
        let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
        return ((c3 * t + c2) * t + c1) * t + x0
    }
}
