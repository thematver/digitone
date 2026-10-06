import Foundation
import Combine
import DigitoneCore

/// Drives timestamped playback with a small look-ahead window. The scheduling
/// core and an injectable output keep this testable without MIDI hardware.
@MainActor
public final class SequencePlayer: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var playhead: Double = 0
    @Published public private(set) var lastError: String?
    public var onError: ((Error) -> Void)?

    private var scheduler: SequenceScheduler?
    private var output: (any TimedMIDIOutput)?
    private var pumpTask: Task<Void, Never>?
    private let lookAhead = 0.05

    public init() {}

    deinit {
        pumpTask?.cancel()
        if var scheduler, let output {
            output.flush()
            try? output.send(scheduler.stop(at: HostClock.now).map(\.timed))
        }
    }

    public func start(sequence: NoteSequence, session: DigitoneSession, sendsClock: Bool = false) throws {
        guard session.identity?.isDigitoneII == true, let output = session.transport.timedOutput() else {
            throw MIDIConnectionError.disconnected
        }
        try start(sequence: sequence, output: output, sendsClock: sendsClock)
    }

    public func start(sequence: NoteSequence, output: any TimedMIDIOutput, sendsClock: Bool = false) throws {
        stop()
        lastError = nil
        var scheduler = SequenceScheduler(sequence: sequence, sendsClock: sendsClock)
        let now = HostClock.now
        let events = scheduler.start(at: now, tempo: sequence.tempo)
            + scheduler.render(until: HostClock.adding(seconds: lookAhead, to: now), now: now)
        do { try output.send(events.map(\.timed)) }
        catch {
            output.flush()
            try? output.send(scheduler.stop(at: HostClock.now).map(\.timed))
            lastError = error.localizedDescription
            throw error
        }
        self.scheduler = scheduler
        self.output = output
        isPlaying = true
        playhead = 0
        pumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                guard !Task.isCancelled, self != nil else { break }
                self?.pump()
            }
        }
    }

    public func setTempo(_ bpm: Double) { scheduler?.setTempo(bpm) }

    public func update(sequence: NoteSequence) { scheduler?.sequence = sequence }

    public func stop() {
        finish(reportError: true)
    }

    private func finish(reportError: Bool) {
        pumpTask?.cancel()
        pumpTask = nil
        guard var scheduler, let output else {
            isPlaying = false
            return
        }
        output.flush()
        let now = HostClock.now
        let releases = scheduler.stop(at: now)
        do { try output.send(releases.map(\.timed)) }
        catch {
            lastError = error.localizedDescription
            if reportError { onError?(error) }
        }
        playhead = scheduler.position(at: now).loopTick
        self.scheduler = nil
        self.output = nil
        isPlaying = false
    }

    private func pump() {
        guard isPlaying, var scheduler, let output else { return }
        let now = HostClock.now
        let events = scheduler.render(until: HostClock.adding(seconds: lookAhead, to: now), now: now)
        self.scheduler = scheduler
        playhead = scheduler.position(at: now).loopTick
        do { try output.send(events.map(\.timed)) }
        catch {
            let failure = error
            finish(reportError: false)
            lastError = failure.localizedDescription
            onError?(failure)
        }
    }
}
