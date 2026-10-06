import Darwin
import Foundation

public enum SamplerPlaybackMode: String, Codable, Sendable, CaseIterable {
    /// Plays to the end even after note-off. allNotesOff always stops playback.
    case oneShot
    /// Plays to the end, or stops on note-off.
    case gate
    /// Repeats the selected region until note-off.
    case loop
}

/// A polyphonic, in-memory sample player. Configure it before attaching it to
/// an audio host; replace the source when a sample or its slices change.
///
/// Samples, voices, pitch ratios and a per-note command mailbox are allocated
/// in init. Rendering adds stereo audio without allocations, locks or actors.
/// Commands may arrive from any thread and take effect at the next render
/// block. Multiple commands for the same note between blocks coalesce to the
/// latest one. Only the audio host may call prepare/render; prepare must not
/// overlap render. One voice is held per note, up to maximumVoices, with the
/// oldest voice stolen when the limit is reached.
public final class SamplerRenderSource: AudioRenderSource, NoteReceiver, @unchecked Sendable {
    public let rootNote: Int
    public let sliceRootNote: Int
    public let slices: [Range<Int>]
    public let mode: SamplerPlaybackMode
    public let maximumVoices: Int

    private struct Voice {
        var active = false
        var note = 0
        var lower = 0
        var upper = 0
        var position: Double = 0
        var increment: Double = 1
        var amplitude: Float = 1
        var generation: UInt64 = 0
    }

    private let sourceRate: Double
    private let frameCount: Int
    private let gain: Float
    private let interpolation: SampleInterpolation
    private let leftSamples: UnsafeMutablePointer<Float>
    private let rightSamples: UnsafeMutablePointer<Float>
    private let voices: UnsafeMutablePointer<Voice>
    private let commands: UnsafeMutablePointer<Int32>
    private let pitchRatios: UnsafeMutablePointer<Double>
    private var rateRatio: Double = 1
    private var generation: UInt64 = 0

    public init(
        sample: SampleBuffer,
        rootNote: Int = 60,
        slices: [Range<Int>] = [],
        sliceRootNote: Int = 36,
        mode: SamplerPlaybackMode = .oneShot,
        pitchSemitones: Double = 0,
        gain: Float = 1,
        interpolation: SampleInterpolation = .hermite,
        maximumVoices: Int = 16
    ) {
        self.rootNote = min(127, max(0, rootNote))
        self.sliceRootNote = min(127, max(0, sliceRootNote))
        self.slices = slices.prefix(128 - self.sliceRootNote).map {
            let lower = min(sample.frameCount, max(0, $0.lowerBound))
            let upper = min(sample.frameCount, max(lower, $0.upperBound))
            return lower..<upper
        }
        self.mode = mode
        self.maximumVoices = min(128, max(1, maximumVoices))
        self.gain = gain.isFinite ? gain : 0
        self.interpolation = interpolation
        sourceRate = sample.sampleRate.isFinite && sample.sampleRate > 0 ? sample.sampleRate : 48_000
        frameCount = sample.frameCount
        rateRatio = sourceRate / 48_000

        let capacity = max(1, sample.frameCount)
        leftSamples = .allocate(capacity: capacity)
        rightSamples = .allocate(capacity: capacity)
        leftSamples.initialize(repeating: 0, count: capacity)
        rightSamples.initialize(repeating: 0, count: capacity)
        let rightChannel = min(1, sample.channelCount - 1)
        for index in 0..<sample.frameCount {
            let left = sample.channels[0][index]
            let right = sample.channels[rightChannel][index]
            leftSamples[index] = left.isFinite ? left : 0
            rightSamples[index] = right.isFinite ? right : 0
        }
        voices = .allocate(capacity: self.maximumVoices)
        voices.initialize(repeating: Voice(), count: self.maximumVoices)
        commands = .allocate(capacity: 128)
        commands.initialize(repeating: 0, count: 128)
        pitchRatios = .allocate(capacity: 128)
        pitchRatios.initialize(repeating: 1, count: 128)
        let transpose = pitchSemitones.isFinite ? min(96, max(-96, pitchSemitones)) : 0
        for note in 0..<128 {
            let chromatic = self.slices.isEmpty ? Double(note - self.rootNote) : 0
            pitchRatios[note] = pow(2, (chromatic + transpose) / 12)
        }
    }

    deinit {
        leftSamples.deallocate()
        rightSamples.deallocate()
        voices.deinitialize(count: maximumVoices)
        voices.deallocate()
        commands.deallocate()
        pitchRatios.deallocate()
    }

    public func prepare(sampleRate: Double, maximumFrames: Int) {
        guard sampleRate.isFinite, sampleRate > 0 else { return }
        let ratio = sourceRate / sampleRate
        guard ratio.isFinite, ratio > 0 else { return }
        rateRatio = ratio
        for index in 0..<maximumVoices where voices[index].active {
            let increment = rateRatio * pitchRatios[voices[index].note]
            if increment.isFinite, increment > 0 {
                voices[index].increment = increment
            } else {
                voices[index].active = false
            }
        }
    }

    public func triggerSlice(_ index: Int, velocity: Int = 100) {
        guard slices.indices.contains(index) else { return }
        noteOn(note: sliceRootNote + index, velocity: velocity)
    }

    public func noteOn(note: Int, velocity: Int) {
        guard (0..<128).contains(note) else { return }
        if velocity <= 0 { noteOff(note: note); return }
        if !slices.isEmpty, !slices.indices.contains(note - sliceRootNote) { return }
        setCommand(Int32(min(127, velocity)), note: note)
    }

    public func noteOff(note: Int) {
        guard (0..<128).contains(note) else { return }
        // A one-shot already queued should still sound when the key is released
        // before the next block. allNotesOff uses the unconditional stop command.
        guard mode != .oneShot else { return }
        setCommand(-1, note: note)
    }

    public func allNotesOff() {
        for note in 0..<128 { setCommand(-2, note: note) }
    }

    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frameCount > 0 else { return }
        consumeCommands()
        let leftBuffer = UnsafeBufferPointer(start: leftSamples, count: self.frameCount)
        let rightBuffer = UnsafeBufferPointer(start: rightSamples, count: self.frameCount)
        for index in 0..<maximumVoices {
            var voice = voices[index]
            guard voice.active else { continue }
            let looping = mode == .loop
            let length = Double(voice.upper - voice.lower + 1)
            for frame in 0..<frameCount {
                if voice.position >= Double(voice.upper + 1) {
                    if looping {
                        guard voice.position.isFinite else { voice.active = false; break }
                        voice.position = Double(voice.lower) + (voice.position - Double(voice.lower)).truncatingRemainder(dividingBy: length)
                    } else {
                        voice.active = false
                        break
                    }
                }
                left[frame] += voice.amplitude * Interpolation.read(leftBuffer, at: voice.position,
                    lower: voice.lower, upper: voice.upper, mode: interpolation, looping: looping)
                right[frame] += voice.amplitude * Interpolation.read(rightBuffer, at: voice.position,
                    lower: voice.lower, upper: voice.upper, mode: interpolation, looping: looping)
                voice.position += voice.increment
            }
            if !looping, voice.position >= Double(voice.upper + 1) { voice.active = false }
            voices[index] = voice
        }
    }

    // Darwin's compare-and-swap wrappers are backed by compiler atomics on our
    // macOS 14/iOS 17 deployment targets. Swift Synchronization.Atomic requires
    // newer deployment targets. This fixed mailbox has no objects to retain or
    // release on the render thread; producers retry, the consumer never retries.
    private func setCommand(_ command: Int32, note: Int) {
        let location = commands + note
        var previous = OSAtomicAdd32Barrier(0, location)
        while !OSAtomicCompareAndSwap32Barrier(previous, command, location) {
            previous = OSAtomicAdd32Barrier(0, location)
        }
    }

    private func consumeCommands() {
        for note in 0..<128 {
            let location = commands + note
            let command = OSAtomicAdd32Barrier(0, location)
            guard command != 0, OSAtomicCompareAndSwap32Barrier(command, 0, location) else { continue }
            if command < 0 {
                for index in 0..<maximumVoices where voices[index].active && voices[index].note == note {
                    voices[index].active = false
                }
                continue
            }
            guard frameCount > 0 else { continue }
            let range: Range<Int>
            if slices.isEmpty {
                range = 0..<frameCount
            } else {
                let sliceIndex = note - sliceRootNote
                guard slices.indices.contains(sliceIndex) else { continue }
                range = slices[sliceIndex]
            }
            guard !range.isEmpty else { continue }
            let increment = rateRatio * pitchRatios[note]
            guard increment.isFinite, increment > 0 else { continue }
            var selected = 0
            var oldest = UInt64.max
            for index in 0..<maximumVoices {
                if voices[index].active && voices[index].note == note {
                    selected = index
                    break
                }
                if !voices[index].active {
                    selected = index
                    oldest = 0
                } else if oldest > 0 && voices[index].generation < oldest {
                    selected = index
                    oldest = voices[index].generation
                }
            }
            generation &+= 1
            voices[selected] = Voice(active: true, note: note, lower: range.lowerBound, upper: range.upperBound - 1,
                position: Double(range.lowerBound), increment: increment, amplitude: gain * Float(command) / 127,
                generation: generation)
        }
    }
}
