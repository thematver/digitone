import Foundation
import DigitoneCore

public struct ScheduledMIDIEvent: Hashable, Sendable {
    public enum Message: Hashable, Sendable {
        /// Song Position Pointer in sixteenth notes.
        case songPosition(Int)
        case start
        case `continue`
        case stop
        case clock
        case noteOff(channel: Int, note: Int)
        case noteOn(channel: Int, note: Int, velocity: Int)

        public var bytes: [UInt8] {
            switch self {
            case .songPosition(let position):
                let value = min(max(position, 0), 16383)
                return [0xf2, UInt8(value & 0x7f), UInt8(value >> 7)]
            case .start: return [0xfa]
            case .continue: return [0xfb]
            case .stop: return [0xfc]
            case .clock: return [0xf8]
            case .noteOff(let channel, let note): return [0x80 | UInt8(channel & 15), UInt8(note & 127), 0]
            case .noteOn(let channel, let note, let velocity):
                return [0x90 | UInt8(channel & 15), UInt8(note & 127), UInt8(min(max(velocity, 1), 127))]
            }
        }

        /// Order among events with the same timestamp: position before
        /// transport before clock, note-offs before note-ons so a retrigger works.
        var rank: Int {
            switch self {
            case .songPosition: 0
            case .start, .continue, .stop: 1
            case .clock: 2
            case .noteOff: 3
            case .noteOn: 4
            }
        }
    }

    public var hostTime: UInt64
    /// Absolute sequence tick (not wrapped to the loop).
    public var tick: Int
    public var message: Message

    public init(hostTime: UInt64, tick: Int, message: Message) {
        self.hostTime = hostTime
        self.tick = tick
        self.message = message
    }

    public var timed: TimedMIDIEvent { TimedMIDIEvent(hostTime: hostTime, bytes: message.bytes) }
}

public struct MIDIPlaybackPosition: Equatable, Sendable {
    public var isPlaying: Bool
    /// Absolute ticks from the sequence start; keeps growing across loops.
    public var tick: Double
    /// `tick` wrapped into the loop, 0..<length.
    public var loopTick: Double
    public var bpm: Double
    public var hostTime: UInt64

    public static let stopped = MIDIPlaybackPosition(isPlaying: false, tick: 0, loopTick: 0, bpm: 120, hostTime: 0)
}

/// The pure scheduling core of sequence playback and clock output.
///
/// Playback is rendered in consecutive windows of host time. Bookkeeping is in
/// whole ticks (`scheduledThrough` is the first tick not yet rendered), so
/// windows never duplicate or skip an event, and a tempo change re-anchors the
/// tempo map exactly at that tick. The sequence loops on `sequence.length`;
/// note-offs come from a voice table, so a note crossing the loop end, a muted
/// lane or a transpose change still ends with the pitch it started with.
public struct SequenceScheduler: Sendable {
    struct VoiceKey: Hashable, Comparable, Sendable {
        let channel: Int
        let note: Int
        static func < (a: VoiceKey, b: VoiceKey) -> Bool { (a.channel, a.note) < (b.channel, b.note) }
    }
    struct Voice: Sendable {
        let start: Int
        var end: Int
    }
    struct Release: Sendable {
        let key: VoiceKey
        let hostTime: UInt64
    }
    private struct NoteStart {
        let tick: Int
        let key: VoiceKey
        let velocity: Int
        let duration: Int
    }

    public var sequence: NoteSequence
    public var mutedLanes: Set<UUID> = []
    /// When any lane of the sequence is soloed, only soloed lanes play. Mute wins over solo.
    public var soloedLanes: Set<UUID> = []
    /// Semitones added to every note-on; results are clamped to 0...127.
    public var transpose = 0 { didSet { transpose = min(max(transpose, -127), 127) } }
    /// Emit 24-PPQ clock and Start/Continue/Stop/Song Position on the same timeline as the notes.
    public var sendsClock: Bool
    /// Rendering further behind `now` than this skips ahead instead of bursting late events.
    public var lateTolerance = 0.05

    public private(set) var timeline: TempoTimeline
    public private(set) var isPlaying = false
    public private(set) var startTick = 0
    public private(set) var scheduledThrough = 0
    private var stoppedTick = 0.0
    private var voices: [VoiceKey: Voice] = [:]
    private var releases: [Release] = []

    public init(sequence: NoteSequence, sendsClock: Bool = false) {
        self.sequence = sequence
        self.sendsClock = sendsClock
        timeline = TempoTimeline(bpm: sequence.tempo, startHostTime: 0)
    }

    public var tempo: Double { timeline.bpm }
    /// Number of notes currently held (started and not yet released).
    public var soundingNoteCount: Int { voices.count }

    /// Starts at `hostTime`. With clock output, a start from 0 sends Start;
    /// otherwise Song Position + Continue, and the start is moved back to a sixteenth.
    public mutating func start(at hostTime: UInt64, fromTick tick: Int = 0, tempo: Double? = nil) -> [ScheduledMIDIEvent] {
        let ending = stop(at: hostTime)
        var from = min(Int.max - 4 * NoteSequence.maximumLength, max(0, tick))
        if sendsClock { from -= from % MusicalTime.ticksPerStep }
        timeline = TempoTimeline(bpm: tempo ?? timeline.bpm, startHostTime: hostTime, startTick: Double(from))
        startTick = from
        scheduledThrough = from
        voices = [:]
        releases = []
        isPlaying = true
        guard sendsClock else { return ending }
        if from == 0 { return ending + [ScheduledMIDIEvent(hostTime: hostTime, tick: 0, message: .start)] }
        return ending + [ScheduledMIDIEvent(hostTime: hostTime, tick: from, message: .songPosition(from / MusicalTime.ticksPerStep)),
                ScheduledMIDIEvent(hostTime: hostTime, tick: from, message: .continue)]
    }

    /// Everything due before `end`, sorted by time. `now` is the current host time,
    /// used to drop events that could only arrive late.
    public mutating func render(until end: UInt64, now: UInt64) -> [ScheduledMIDIEvent] {
        guard isPlaying else { return [] }
        var events: [ScheduledMIDIEvent] = []
        let margin = HostClock.adding(seconds: -lateTolerance, to: now)
        releases.removeAll { $0.hostTime < margin }
        if timeline.hostTime(atTick: scheduledThrough) < margin {
            let resume = max(scheduledThrough, Self.boundedTick(timeline.tick(atHostTime: now).rounded(.up)))
            for (key, voice) in voices.sorted(by: { $0.key < $1.key }) where voice.end < resume {
                events.append(ScheduledMIDIEvent(hostTime: now, tick: voice.end, message: .noteOff(channel: key.channel, note: key.note)))
                releases.append(Release(key: key, hostTime: now))
                voices[key] = nil
            }
            scheduledThrough = resume
        }
        let limit = timeline.tick(atHostTime: end).rounded(.up)
        guard limit.isFinite, limit > Double(scheduledThrough) else { return events }
        guard scheduledThrough <= Int.max - 4 * NoteSequence.maximumLength else { return events }
        var upper = min(Self.boundedTick(limit), scheduledThrough + 1_000_000)
        // Host timestamps are rounded to integer ticks. Inverting that value
        // can be a tiny fraction above a musical tick; the end stays exclusive.
        while upper > scheduledThrough, timeline.hostTime(atTick: upper - 1) >= end { upper -= 1 }
        guard upper > scheduledThrough else { return events }
        events += renderTicks(scheduledThrough..<upper)
        scheduledThrough = upper
        return Self.sorted(events)
    }

    /// Changes tempo from the first unrendered tick on; rendered events keep their times.
    public mutating func setTempo(_ bpm: Double) {
        timeline.setTempo(bpm, atTick: Double(scheduledThrough))
    }

    /// Note-offs for every note that may sound (held, or released by an
    /// event a flush could have dropped), plus Stop with clock output.
    public mutating func stop(at hostTime: UInt64) -> [ScheduledMIDIEvent] {
        guard isPlaying else { return [] }
        let tick = Self.boundedTick(timeline.tick(atHostTime: hostTime).rounded(.down))
        stoppedTick = max(Double(startTick), timeline.tick(atHostTime: hostTime))
        var keys = Set(voices.keys)
        keys.formUnion(releases.map(\.key))
        var events = keys.sorted().map {
            ScheduledMIDIEvent(hostTime: hostTime, tick: tick, message: .noteOff(channel: $0.channel, note: $0.note))
        }
        if sendsClock { events.insert(ScheduledMIDIEvent(hostTime: hostTime, tick: tick, message: .stop), at: 0) }
        voices = [:]
        releases = []
        isPlaying = false
        return events
    }

    public func position(at hostTime: UInt64) -> MIDIPlaybackPosition {
        let tick = isPlaying ? max(Double(startTick), timeline.tick(atHostTime: hostTime)) : stoppedTick
        let length = Double(sequence.length)
        let loopTick = length > 0 ? tick.truncatingRemainder(dividingBy: length) : 0
        return MIDIPlaybackPosition(isPlaying: isPlaying, tick: tick, loopTick: loopTick, bpm: timeline.bpm, hostTime: hostTime)
    }

    /// The events of one window [t0, t1) of playback started at `startHostTime`,
    /// including note-offs of notes started before the window.
    public static func events(for sequence: NoteSequence, tempo: Double? = nil, startHostTime: UInt64,
                              window: Range<UInt64>, configure: (inout SequenceScheduler) -> Void = { _ in }) -> [ScheduledMIDIEvent] {
        var scheduler = SequenceScheduler(sequence: sequence)
        configure(&scheduler)
        let opening = scheduler.start(at: startHostTime, tempo: tempo ?? sequence.tempo)
        _ = scheduler.render(until: window.lowerBound, now: startHostTime)
        return sorted(opening.filter { window.contains($0.hostTime) } + scheduler.render(until: window.upperBound, now: startHostTime))
    }

    private mutating func renderTicks(_ range: Range<Int>) -> [ScheduledMIDIEvent] {
        var events: [ScheduledMIDIEvent] = []
        if sendsClock {
            let pulse = MusicalTime.ticksPerQuarter / IncomingClock.pulsesPerQuarter
            let first = range.lowerBound + (pulse - range.lowerBound % pulse) % pulse
            for tick in stride(from: first, to: range.upperBound, by: pulse) {
                events.append(event(at: tick, .clock))
            }
        }
        for start in noteStarts(in: range) {
            release(through: start.tick, into: &events)
            if let voice = voices[start.key] {
                if voice.start == start.tick {
                    // The same pitch twice on one tick: one note, the longer length.
                    voices[start.key]?.end = max(voice.end, start.tick + start.duration)
                    continue
                }
                events.append(noteOff(start.key, at: start.tick))
            }
            events.append(event(at: start.tick, .noteOn(channel: start.key.channel, note: start.key.note, velocity: start.velocity)))
            voices[start.key] = Voice(start: start.tick, end: start.tick + start.duration)
        }
        release(through: range.upperBound - 1, into: &events)
        return events
    }

    private mutating func release(through tick: Int, into events: inout [ScheduledMIDIEvent]) {
        let due = voices.filter { $0.value.end <= tick }.sorted { ($0.value.end, $0.key) < ($1.value.end, $1.key) }
        for (key, voice) in due {
            events.append(noteOff(key, at: voice.end))
            voices[key] = nil
        }
    }

    private mutating func noteOff(_ key: VoiceKey, at tick: Int) -> ScheduledMIDIEvent {
        let event = event(at: tick, .noteOff(channel: key.channel, note: key.note))
        releases.append(Release(key: key, hostTime: event.hostTime))
        return event
    }

    private func event(at tick: Int, _ message: ScheduledMIDIEvent.Message) -> ScheduledMIDIEvent {
        ScheduledMIDIEvent(hostTime: timeline.hostTime(atTick: tick), tick: tick, message: message)
    }

    private var activeLanes: [SequenceLane] {
        let soloing = sequence.lanes.contains { soloedLanes.contains($0.id) }
        return sequence.lanes.filter { lane in
            (0..<16).contains(lane.channel) && !lane.isMuted && !mutedLanes.contains(lane.id)
                && (!soloing || soloedLanes.contains(lane.id))
        }
    }

    private func noteStarts(in range: Range<Int>) -> [NoteStart] {
        let length = min(sequence.length, NoteSequence.maximumLength)
        guard length > 0, !range.isEmpty else { return [] }
        let lanes = activeLanes
        guard !lanes.isEmpty else { return [] }
        var starts: [NoteStart] = []
        var iteration = range.lowerBound >= 0 ? range.lowerBound / length : -((-range.lowerBound + length - 1) / length)
        while iteration * length < range.upperBound {
            let base = iteration * length
            let window = max(range.lowerBound - base, 0)..<min(range.upperBound - base, length)
            for lane in lanes {
                for note in lane.notes where window.contains(note.start) {
                    starts.append(NoteStart(tick: base + note.start,
                                            key: VoiceKey(channel: lane.channel, note: min(max(min(max(note.pitch, -127), 254) + transpose, 0), 127)),
                                            velocity: min(max(note.velocity, 1), 127),
                                            duration: min(NoteSequence.maximumLength, max(1, note.duration))))
                }
            }
            iteration += 1
        }
        return starts.sorted { ($0.tick, $0.key) < ($1.tick, $1.key) }
    }

    private static func sorted(_ events: [ScheduledMIDIEvent]) -> [ScheduledMIDIEvent] {
        events.enumerated().sorted {
            ($0.element.hostTime, $0.element.message.rank, $0.offset) < ($1.element.hostTime, $1.element.message.rank, $1.offset)
        }.map(\.element)
    }

    private static func boundedTick(_ tick: Double) -> Int {
        guard tick.isFinite else { return 0 }
        let bound = Int.max - 4 * NoteSequence.maximumLength
        if tick >= Double(bound) { return bound }
        if tick <= -Double(bound) { return -bound }
        return Int(tick)
    }
}
