import AVFoundation
import DigitoneDSP

/// Thin wrapper around one AVAudioPlayerNode. Owned and driven by
/// `StudioAudioEngine` on the main actor.
@MainActor
final class AudioPlayback {
    let node = AVAudioPlayerNode()
    private(set) var timeline: PlaybackTimeline?
    private(set) var sampleRate: Double = DigitoneAudioModule.preferredSampleRate
    /// Format the node is connected with; the engine reconnects when a buffer differs.
    var format: AVAudioFormat?
    private var generation = 0
    private var onFinished: (@MainActor () -> Void)?

    var isPlaying: Bool { timeline != nil }

    /// Schedules `buffer`; the caller connects `node` with `format` first.
    func schedule(_ buffer: SampleBuffer, timeline: PlaybackTimeline, onFinish: @escaping @MainActor () -> Void) throws {
        stop()
        guard let intro = AudioFileIO.makePCMBuffer(buffer, frames: timeline.intro) else {
            throw AudioEngineError.formatUnsupported("пустой буфер")
        }
        generation += 1
        let token = generation
        if let loop = timeline.loop {
            guard let region = AudioFileIO.makePCMBuffer(buffer, frames: loop) else {
                throw AudioEngineError.formatUnsupported("пустая петля")
            }
            node.scheduleBuffer(intro, at: nil)
            node.scheduleBuffer(region, at: nil, options: .loops)
        } else {
            onFinished = onFinish
            node.scheduleBuffer(intro, at: nil, completionCallbackType: .dataPlayedBack,
                                completionHandler: Self.completion(owner: self, token: token))
        }
        self.timeline = timeline
        sampleRate = buffer.sampleRate
        node.play()
    }

    func stop() {
        generation += 1
        onFinished = nil
        node.stop()
        timeline = nil
    }

    private func finish(token: Int) {
        guard generation == token else { return }
        timeline = nil
        let callback = onFinished
        onFinished = nil
        callback?()
    }

    /// Built outside the main actor: AVFAudio calls it on its own queue.
    nonisolated private static func completion(owner: AudioPlayback, token: Int) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak owner] _ in
            Task { @MainActor in owner?.finish(token: token) }
        }
    }

    /// Seconds into the buffer, nil when idle.
    var playhead: Double? {
        guard let timeline else { return nil }
        guard let renderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: renderTime) else {
            return Double(timeline.start) / sampleRate
        }
        // Player time runs at the connection rate, which equals the buffer rate.
        let played = Int(Double(playerTime.sampleTime) * sampleRate / playerTime.sampleRate)
        return timeline.position(afterPlaying: played).map { Double($0) / sampleRate }
    }
}
