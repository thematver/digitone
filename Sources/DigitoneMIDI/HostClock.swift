import Foundation
import DigitoneCore

/// Host time (`mach_absolute_time` units, the same clock as `MIDITimeStamp`)
/// converted with the machine's timebase. On Apple silicon one host tick is
/// 125/3 ns, on Intel 1 ns.
public enum HostClock {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else { return (1, 1) }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    public static var now: UInt64 { mach_absolute_time() }

    public static func nanoseconds(fromHostTicks ticks: UInt64) -> UInt64 {
        let (high, low) = ticks.multipliedFullWidth(by: timebase.numer)
        guard high < timebase.denom else { return .max }
        return timebase.denom.dividingFullWidth((high, low)).quotient
    }

    public static func hostTicks(fromNanoseconds nanoseconds: UInt64) -> UInt64 {
        let (high, low) = nanoseconds.multipliedFullWidth(by: timebase.denom)
        guard high < timebase.numer else { return .max }
        return timebase.numer.dividingFullWidth((high, low)).quotient
    }

    /// Signed conversion for offsets; sub-tick precision is kept until the caller rounds.
    public static func hostTicks(fromSeconds seconds: Double) -> Double {
        seconds * 1e9 * Double(timebase.denom) / Double(timebase.numer)
    }

    public static func seconds(fromHostTicks ticks: Double) -> Double {
        ticks * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    /// `a - b` in seconds, negative when `a` is earlier.
    public static func seconds(from b: UInt64, to a: UInt64) -> Double {
        a >= b ? seconds(fromHostTicks: Double(a - b)) : -seconds(fromHostTicks: Double(b - a))
    }

    public static func adding(seconds: Double, to time: UInt64) -> UInt64 {
        offset(time, by: hostTicks(fromSeconds: seconds))
    }

    static func offset(_ time: UInt64, by ticks: Double) -> UInt64 {
        guard ticks.isFinite else { return time }
        let rounded = ticks.rounded()
        if rounded >= 0 {
            let delta = rounded >= Double(UInt64.max) ? UInt64.max : UInt64(rounded)
            return time.addingReportingOverflow(delta).overflow ? .max : time + delta
        }
        let delta = -rounded >= Double(UInt64.max) ? UInt64.max : UInt64(-rounded)
        return delta >= time ? 0 : time - delta
    }
}

/// Maps musical ticks (96 per quarter note) to host time and back. A tempo
/// change re-anchors the map at a tick, so times before that tick never move:
/// already scheduled events stay valid and the tempo changes without a gap.
public struct TempoTimeline: Equatable, Sendable {
    private struct Segment: Equatable, Sendable {
        let tick: Double
        let hostTime: UInt64
        let bpm: Double
    }
    public static let tempoRange: ClosedRange<Double> = 20...999
    public let ticksPerQuarter: Int
    public private(set) var bpm: Double
    public private(set) var anchorTick: Double
    public private(set) var anchorHostTime: UInt64
    private var segments: [Segment]

    public init(bpm: Double, startHostTime: UInt64, startTick: Double = 0,
                ticksPerQuarter: Int = MusicalTime.ticksPerQuarter) {
        self.ticksPerQuarter = max(1, ticksPerQuarter)
        self.bpm = Self.clampTempo(bpm)
        anchorTick = startTick.isFinite ? startTick : 0
        anchorHostTime = startHostTime
        segments = [Segment(tick: anchorTick, hostTime: startHostTime, bpm: self.bpm)]
    }

    public static func clampTempo(_ bpm: Double) -> Double {
        bpm.isFinite ? min(max(bpm, tempoRange.lowerBound), tempoRange.upperBound) : 120
    }

    public var secondsPerTick: Double { 60 / (bpm * Double(ticksPerQuarter)) }

    public func hostTime(atTick tick: Double) -> UInt64 {
        let segment = segments.last { $0.tick <= tick } ?? segments[0]
        let secondsPerTick = 60 / (segment.bpm * Double(ticksPerQuarter))
        return HostClock.offset(segment.hostTime, by: HostClock.hostTicks(fromSeconds: (tick - segment.tick) * secondsPerTick))
    }

    public func hostTime(atTick tick: Int) -> UInt64 { hostTime(atTick: Double(tick)) }

    public func tick(atHostTime time: UInt64) -> Double {
        let segment = segments.last { $0.hostTime <= time } ?? segments[0]
        let secondsPerTick = 60 / (segment.bpm * Double(ticksPerQuarter))
        return segment.tick + HostClock.seconds(from: segment.hostTime, to: time) / secondsPerTick
    }

    /// Changes tempo from `tick` on; the time of `tick` itself is unchanged.
    public mutating func setTempo(_ newBPM: Double, atTick tick: Double) {
        guard tick.isFinite else { return }
        let time = hostTime(atTick: tick)
        anchorTick = tick
        anchorHostTime = time
        bpm = Self.clampTempo(newBPM)
        segments.removeAll { $0.tick >= tick }
        segments.append(Segment(tick: tick, hostTime: time, bpm: bpm))
    }
}
