import XCTest
import DigitoneCore
@testable import DigitoneMIDI

final class SequenceSchedulerTests: XCTestCase {
    private let origin: UInt64 = HostClock.hostTicks(fromNanoseconds: 10_000_000_000)

    private func sequence(notes: [SequenceNote], length: Int = 96) -> NoteSequence {
        NoteSequence(name: "Test", tempo: 120, length: length,
                     lanes: [SequenceLane(name: "Bass", channel: 2, notes: notes)])
    }

    func testConsecutiveWindowsDoNotRepeatBoundaryEventsAndLoop() {
        let clip = sequence(notes: [SequenceNote(pitch: 60, start: 0, duration: 24),
                                    SequenceNote(pitch: 62, start: 24, duration: 24)])
        var scheduler = SequenceScheduler(sequence: clip)
        XCTAssertEqual(scheduler.start(at: origin), [])
        let first = scheduler.render(until: scheduler.timeline.hostTime(atTick: 24), now: origin)
        XCTAssertEqual(first.map(\.tick), [0])
        let second = scheduler.render(until: scheduler.timeline.hostTime(atTick: 96), now: origin)
        XCTAssertEqual(second.map(\.tick), [24, 24, 48])
        XCTAssertEqual(second.map(\.message), [.noteOff(channel: 2, note: 60),
                                              .noteOn(channel: 2, note: 62, velocity: 100),
                                              .noteOff(channel: 2, note: 62)])
        XCTAssertEqual(scheduler.render(until: scheduler.timeline.hostTime(atTick: 96), now: origin), [])
        let third = scheduler.render(until: scheduler.timeline.hostTime(atTick: 97), now: origin)
        XCTAssertEqual(third.map(\.tick), [96])
        XCTAssertEqual(third.first?.message, .noteOn(channel: 2, note: 60, velocity: 100))
    }

    func testClockHasTwentyFourPulsesPerQuarterAndTransportStartsBeforeClock() {
        var scheduler = SequenceScheduler(sequence: sequence(notes: []), sendsClock: true)
        XCTAssertEqual(scheduler.start(at: origin).map(\.message), [.start])
        let clocks = scheduler.render(until: scheduler.timeline.hostTime(atTick: 96), now: origin)
        XCTAssertEqual(clocks.map(\.tick), Array(stride(from: 0, to: 96, by: 4)))
        XCTAssertTrue(clocks.allSatisfy { $0.message == .clock })
        XCTAssertEqual(scheduler.stop(at: scheduler.timeline.hostTime(atTick: 96)).map(\.message), [.stop])
        let resumed = scheduler.start(at: origin, fromTick: 50)
        XCTAssertEqual(resumed.map(\.message), [.songPosition(2), .continue])
        XCTAssertEqual(scheduler.startTick, 48)
    }

    func testCrossLoopTailKeepsOriginalPitchAfterMuteAndTransposeChanges() {
        let clip = sequence(notes: [SequenceNote(pitch: 60, start: 80, duration: 40)])
        var scheduler = SequenceScheduler(sequence: clip)
        _ = scheduler.start(at: origin)
        let opening = scheduler.render(until: scheduler.timeline.hostTime(atTick: 96), now: origin)
        XCTAssertEqual(opening.map(\.message), [.noteOn(channel: 2, note: 60, velocity: 100)])
        scheduler.transpose = 12
        scheduler.mutedLanes = [clip.lanes[0].id]
        let tail = scheduler.render(until: scheduler.timeline.hostTime(atTick: 200), now: origin)
        XCTAssertEqual(tail.map(\.tick), [120])
        XCTAssertEqual(tail.map(\.message), [.noteOff(channel: 2, note: 60)])
        XCTAssertEqual(scheduler.soundingNoteCount, 0)
    }

    func testRetriggerReleasesOldVoiceAndSameTickDuplicatesUseLongestDuration() {
        let clip = sequence(notes: [SequenceNote(pitch: 60, start: 0, duration: 20),
                                    SequenceNote(pitch: 60, start: 0, duration: 40),
                                    SequenceNote(pitch: 60, velocity: 90, start: 24, duration: 24)])
        var scheduler = SequenceScheduler(sequence: clip)
        _ = scheduler.start(at: origin)
        let events = scheduler.render(until: scheduler.timeline.hostTime(atTick: 96), now: origin)
        XCTAssertEqual(events.map(\.tick), [0, 24, 24, 48])
        XCTAssertEqual(events.map(\.message), [.noteOn(channel: 2, note: 60, velocity: 100),
                                              .noteOff(channel: 2, note: 60),
                                              .noteOn(channel: 2, note: 60, velocity: 90),
                                              .noteOff(channel: 2, note: 60)])
    }

    func testStopAndRestartReleaseNotesWhoseQueuedOffMayBeFlushed() {
        var scheduler = SequenceScheduler(sequence: sequence(notes: [SequenceNote(pitch: 60, start: 0, duration: 24)]))
        _ = scheduler.start(at: origin)
        _ = scheduler.render(until: scheduler.timeline.hostTime(atTick: 48), now: origin)
        XCTAssertEqual(scheduler.soundingNoteCount, 0)
        XCTAssertEqual(scheduler.stop(at: origin).map(\.message), [.noteOff(channel: 2, note: 60)])
        XCTAssertEqual(scheduler.stop(at: origin), [])
        _ = scheduler.start(at: origin)
        _ = scheduler.render(until: scheduler.timeline.hostTime(atTick: 1), now: origin)
        XCTAssertEqual(scheduler.start(at: origin).map(\.message), [.noteOff(channel: 2, note: 60)])
    }

    func testTempoChangeKeepsAlreadyScheduledEventsAndAnchorsNextTick() {
        var scheduler = SequenceScheduler(sequence: sequence(notes: []))
        _ = scheduler.start(at: origin)
        _ = scheduler.render(until: scheduler.timeline.hostTime(atTick: 48), now: origin)
        let anchor = scheduler.timeline.hostTime(atTick: 48)
        scheduler.setTempo(60)
        XCTAssertEqual(scheduler.timeline.hostTime(atTick: 0), origin)
        XCTAssertEqual(scheduler.timeline.tick(atHostTime: origin), 0, accuracy: 0.000001)
        XCTAssertEqual(scheduler.timeline.hostTime(atTick: 48), anchor)
        XCTAssertEqual(HostClock.seconds(from: anchor, to: scheduler.timeline.hostTime(atTick: 144)), 1, accuracy: 0.000001)
    }

    func testLateRenderSkipsExpiredNoteOnsAndReleasesHeldNotes() {
        var scheduler = SequenceScheduler(sequence: sequence(notes: [SequenceNote(pitch: 60, start: 0, duration: 24)]))
        _ = scheduler.start(at: origin)
        _ = scheduler.render(until: scheduler.timeline.hostTime(atTick: 1), now: origin)
        let now = scheduler.timeline.hostTime(atTick: 80)
        let events = scheduler.render(until: scheduler.timeline.hostTime(atTick: 90), now: now)
        XCTAssertEqual(events.map(\.message), [.noteOff(channel: 2, note: 60)])
        XCTAssertEqual(events.first?.hostTime, now)
    }

    func testIncomingClockTempoPositionAndGapReset() {
        var clock = IncomingClock()
        clock.receive(.start)
        for pulse in 0..<49 { clock.pulse(at: HostClock.adding(seconds: Double(pulse) / 48, to: origin)) }
        XCTAssertEqual(clock.bpm ?? 0, 120, accuracy: 0.00001)
        XCTAssertEqual(clock.position, 49)
        clock.receive(.stop)
        clock.pulse(at: HostClock.adding(seconds: 49.0 / 48, to: origin))
        XCTAssertEqual(clock.position, 49)
        clock.receive(.songPosition(16))
        XCTAssertEqual(clock.beat, 4)
        let gap = HostClock.adding(seconds: 5, to: origin)
        clock.pulse(at: gap)
        XCTAssertNil(clock.bpm)
        XCTAssertFalse(clock.isReceiving(at: origin))
        XCTAssertTrue(clock.isReceiving(at: gap))
    }

    func testPacketBuilderKeepsSysExSeparateAndPreservesTimestampOrder() throws {
        let events = [TimedMIDIEvent(hostTime: 2, bytes: [0xf8]),
                      TimedMIDIEvent(hostTime: 1, bytes: [0x90, 60, 100]),
                      TimedMIDIEvent(hostTime: 1, bytes: [0x80, 60, 0]),
                      TimedMIDIEvent(hostTime: 1, bytes: [0xf0, 1, 0xf7])]
        let packets = try MIDIPacketListBuilder.packetLists(for: events)
        XCTAssertEqual(packets.flatMap { $0 }.map(\.hostTime), [1, 1, 2])
        XCTAssertEqual(packets.first?.first?.bytes, [0x90, 60, 100, 0x80, 60, 0])
        XCTAssertThrowsError(try MIDIPacketListBuilder.packetLists(for: [TimedMIDIEvent(hostTime: 0, bytes: [])]))
        XCTAssertThrowsError(try MIDIPacketListBuilder.packetLists(for: [TimedMIDIEvent(hostTime: 0, bytes: Array(repeating: 0, count: 1025))]))
        var copied: [[UInt8]] = []
        try MIDIPacketListBuilder.withPacketLists(for: events) { copied += MIDITransport.copyPackets(from: $0) }
        XCTAssertEqual(copied, packets.flatMap { $0 }.map(\.bytes))
    }
}

private final class RecordingMIDIOutput: TimedMIDIOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [TimedMIDIEvent] = []
    private var flushes = 0
    var fails = false
    var events: [TimedMIDIEvent] { lock.withLock { stored } }
    var flushCount: Int { lock.withLock { flushes } }
    func send(_ events: [TimedMIDIEvent]) throws {
        try lock.withLock {
            if fails { throw MIDIConnectionError.disconnected }
            stored += events
        }
    }
    func flush() { lock.withLock { flushes += 1 } }
}

final class SequencePlayerTests: XCTestCase {
    @MainActor
    func testPlayerStartsAndStopsWithoutHardwareAndFlushesFutureNotes() throws {
        let output = RecordingMIDIOutput()
        let player = SequencePlayer()
        let sequence = NoteSequence(name: "Test", lanes: [SequenceLane(name: "Lane", channel: 0,
                                                                       notes: [SequenceNote(pitch: 60, start: 0, duration: 96)])])
        try player.start(sequence: sequence, output: output)
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(output.events.contains { $0.bytes == [0x90, 60, 100] })
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(output.flushCount, 1)
        XCTAssertTrue(output.events.contains { $0.bytes == [0x80, 60, 0] })
        let eventCount = output.events.count
        player.stop()
        XCTAssertEqual(output.events.count, eventCount)
    }

    @MainActor
    func testInitialSendFailureLeavesPlayerStoppedAndProvidesError() {
        let output = RecordingMIDIOutput()
        output.fails = true
        let player = SequencePlayer()
        XCTAssertThrowsError(try player.start(sequence: NoteSequence(name: "Empty"), output: output))
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.lastError)
        XCTAssertEqual(output.flushCount, 1)
    }
}
