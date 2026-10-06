import Foundation
import DigitoneCore

public struct MIDINoteEvent: Hashable, Sendable {
    public var channel: Int
    public var note: Int
    /// Note-on velocity 1...127; release velocity for note-off.
    public var velocity: Int
    /// False for note-off and for note-on with velocity 0.
    public var isOn: Bool
    public var hostTime: UInt64

    public init(channel: Int, note: Int, velocity: Int, isOn: Bool, hostTime: UInt64) {
        self.channel = channel
        self.note = note
        self.velocity = velocity
        self.isOn = isOn
        self.hostTime = hostTime
    }
}

public enum MIDITransportEvent: Hashable, Sendable {
    case start
    case stop
    case `continue`
    /// Song Position Pointer in MIDI beats (sixteenth notes from the song start).
    case songPosition(Int)
}

/// The performance-relevant subset of incoming MIDI.
public enum MIDIInputEvent: Hashable, Sendable {
    case note(MIDINoteEvent)
    case programChange(channel: Int, program: Int)
    case transport(MIDITransportEvent)
    /// One 24-PPQ timing clock pulse.
    case clock(hostTime: UInt64)

    public init?(_ message: MIDIMessage, hostTime: UInt64) {
        switch message {
        case .channel(let status, let data):
            let channel = Int(status & 0x0f)
            switch status & 0xf0 {
            case 0x80 where data.count == 2:
                self = .note(MIDINoteEvent(channel: channel, note: Int(data[0]), velocity: Int(data[1]), isOn: false, hostTime: hostTime))
            case 0x90 where data.count == 2:
                self = .note(MIDINoteEvent(channel: channel, note: Int(data[0]), velocity: Int(data[1]),
                                           isOn: data[1] > 0, hostTime: hostTime))
            case 0xc0 where data.count == 1:
                self = .programChange(channel: channel, program: Int(data[0]))
            default: return nil
            }
        case .realtime(0xf8): self = .clock(hostTime: hostTime)
        case .realtime(0xfa): self = .transport(.start)
        case .realtime(0xfb): self = .transport(.continue)
        case .realtime(0xfc): self = .transport(.stop)
        case .system(0xf2, let data) where data.count == 2:
            self = .transport(.songPosition(Int(data[0]) | Int(data[1]) << 7))
        default: return nil
        }
    }
}

/// Follows an incoming 24-PPQ MIDI clock: tempo estimate plus song position.
///
/// The tempo is the mean pulse interval over a sliding window, so per-pulse
/// jitter is divided by the window length. Three consecutive pulses that
/// disagree with the mean by more than `jumpTolerance` restart the window,
/// so a real tempo change is followed within a few pulses; a gap longer than
/// a pulse at the slowest tempo restarts it too.
public struct IncomingClock: Equatable, Sendable {
    public static let pulsesPerQuarter = 24
    /// Pulses averaged; 48 is two beats.
    public var windowSize: Int
    public var jumpTolerance = 0.3
    public private(set) var bpm: Double?
    /// Transport state from Start/Stop/Continue.
    public private(set) var isRunning = false
    /// Position of the next expected pulse, in pulses from the song start.
    public private(set) var position = 0
    public private(set) var lastPulseHostTime: UInt64?
    private var pulses: [UInt64] = []
    private var disagreements = 0

    public init(windowSize: Int = 48) { self.windowSize = max(2, windowSize) }

    /// Position in quarter notes.
    public var beat: Double { Double(position) / Double(Self.pulsesPerQuarter) }

    public func isReceiving(at hostTime: UInt64, timeout: Double = 0.5) -> Bool {
        guard let lastPulseHostTime else { return false }
        let age = HostClock.seconds(from: lastPulseHostTime, to: hostTime)
        return age >= 0 && age < timeout
    }

    public mutating func pulse(at hostTime: UInt64) {
        defer {
            lastPulseHostTime = hostTime
            if isRunning { position += 1 }
        }
        if let last = pulses.last {
            let interval = HostClock.seconds(from: last, to: hostTime)
            let mean = meanInterval
            let gapLimit = max(0.2, 3 * (mean ?? 0))
            if interval < 0 || interval > gapLimit {
                pulses = [hostTime]
                bpm = nil
                disagreements = 0
                return
            }
            if let mean, pulses.count >= 4, abs(interval - mean) > mean * jumpTolerance {
                disagreements += 1
                if disagreements >= 3 { pulses.removeFirst(max(0, pulses.count - disagreements)) }
            } else {
                disagreements = 0
            }
        }
        pulses.append(hostTime)
        if pulses.count > windowSize + 1 { pulses.removeFirst(pulses.count - windowSize - 1) }
        if pulses.count >= 3, let mean = meanInterval, mean > 0 {
            bpm = 60 / (mean * Double(Self.pulsesPerQuarter))
        }
    }

    public mutating func receive(_ event: MIDITransportEvent) {
        switch event {
        case .start: isRunning = true; position = 0
        case .stop: isRunning = false
        case .continue: isRunning = true
        case .songPosition(let sixteenths): position = max(0, sixteenths) * Self.pulsesPerQuarter / 4
        }
    }

    public mutating func reset() {
        let tolerance = jumpTolerance
        self = IncomingClock(windowSize: windowSize)
        jumpTolerance = tolerance
    }

    private var meanInterval: Double? {
        guard let first = pulses.first, let last = pulses.last, pulses.count >= 2 else { return nil }
        return HostClock.seconds(from: first, to: last) / Double(pulses.count - 1)
    }
}
