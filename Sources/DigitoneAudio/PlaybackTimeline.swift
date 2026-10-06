import Foundation

/// How a buffer is scheduled on the player: an intro from `start` to the end
/// of the loop (or the buffer), then the loop region repeated forever.
public struct PlaybackTimeline: Sendable, Equatable {
    public let frameCount: Int
    public let start: Int
    public let loop: Range<Int>?

    /// `loop` is clamped to the buffer; an empty loop plays once.
    public init(frameCount: Int, start: Int = 0, loop: Range<Int>? = nil) {
        self.frameCount = max(0, frameCount)
        let clampedLoop = loop?.clamped(to: 0..<max(0, frameCount))
        self.loop = clampedLoop?.isEmpty == false ? clampedLoop : nil
        let clampedStart = min(max(0, start), max(0, frameCount - 1))
        if let region = self.loop, clampedStart >= region.upperBound {
            self.start = region.lowerBound
        } else {
            self.start = clampedStart
        }
    }

    /// Frames played before the loop takes over.
    public var intro: Range<Int> { start..<(loop?.upperBound ?? frameCount) }

    /// Buffer frame under the playhead after `played` frames, or nil once a
    /// non-looping playback has finished.
    public func position(afterPlaying played: Int) -> Int? {
        let played = max(0, played)
        if played < intro.count { return start + played }
        guard let loop else { return nil }
        return loop.lowerBound + (played - intro.count) % loop.count
    }
}
