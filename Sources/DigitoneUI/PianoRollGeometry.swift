import CoreGraphics
import Foundation
import DigitoneCore

/// Grid resolution of the piano roll.
enum PianoRollSnap: Int, CaseIterable, Identifiable, Sendable {
    case quarter = 96, eighth = 48, sixteenth = 24, thirtySecond = 12, off = 1

    var id: Int { rawValue }
    /// Snapping grid in ticks; 1 when snapping is off.
    var grid: Int { rawValue }
    /// One editing step: nudge distance, new-note length and step-input advance.
    var step: Int { self == .off ? MusicalTime.ticksPerStep : rawValue }
    var label: String {
        switch self {
        case .quarter: "1/4"
        case .eighth: "1/8"
        case .sixteenth: "1/16"
        case .thirtySecond: "1/32"
        case .off: "OFF"
        }
    }

    func floor(_ tick: Double) -> Int { Int((tick / Double(grid)).rounded(.down)) * grid }
    func round(_ tick: Double) -> Int { Int((tick / Double(grid)).rounded()) * grid }
    func round(_ tick: Int) -> Int { round(Double(tick)) }
}

enum PianoRollHit: Equatable {
    case note(UUID, edge: Bool)
    case empty(tick: Double, pitch: Int)
}

/// Coordinate math of the note grid: ticks run left to right, pitches bottom
/// to top, one row per semitone. Pure value type so layout, hit-testing and
/// marquee selection are testable without a view.
struct PianoRollGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var pixelsPerTick: CGFloat
    /// Tick at x = 0 (horizontal scroll).
    var originTick: Double
    var rowHeight: CGFloat
    /// Fractional pitch whose row top sits at y = 0 (vertical scroll).
    var topPitch: Double

    static let maximumPixelsPerTick: CGFloat = 6
    static let rowHeights: ClosedRange<CGFloat> = 8...34

    func x(_ tick: Double) -> CGFloat { CGFloat(tick - originTick) * pixelsPerTick }
    func x(_ tick: Int) -> CGFloat { x(Double(tick)) }
    func tick(atX x: CGFloat) -> Double { originTick + Double(x / max(0.0001, pixelsPerTick)) }

    func rowTop(_ pitch: Int) -> CGFloat { CGFloat(topPitch - Double(pitch)) * rowHeight }
    func pitch(atY y: CGFloat) -> Int {
        min(127, max(0, Int((topPitch - Double(y / rowHeight)).rounded(.up))))
    }

    /// Pitches with at least part of a row on screen.
    var visiblePitches: ClosedRange<Int> {
        let low = pitch(atY: height), high = pitch(atY: 0)
        return min(low, high)...max(low, high)
    }
    var visibleTicks: ClosedRange<Double> { originTick...tick(atX: width) }

    func rect(for note: SequenceNote) -> CGRect {
        CGRect(x: x(note.start), y: rowTop(note.pitch), width: max(3, CGFloat(note.duration) * pixelsPerTick), height: rowHeight)
    }

    /// The topmost note under `point` (later notes draw on top), with the right
    /// edge zone used for resizing; otherwise the empty cell.
    func hit(_ point: CGPoint, notes: [SequenceNote], selected: Set<UUID> = []) -> PianoRollHit {
        let ordered = notes.filter { !selected.contains($0.id) } + notes.filter { selected.contains($0.id) }
        for note in ordered.reversed() {
            let frame = rect(for: note)
            let target = frame.width < 8 ? frame.insetBy(dx: -(8 - frame.width) / 2, dy: 0) : frame
            guard target.contains(point) else { continue }
            let edgeZone = min(8, max(3, frame.width * 0.3))
            return .note(note.id, edge: point.x >= frame.maxX - edgeZone)
        }
        return .empty(tick: tick(atX: point.x), pitch: pitch(atY: point.y))
    }

    /// Notes whose rectangle intersects a marquee.
    func notes(in marquee: CGRect, from notes: [SequenceNote]) -> Set<UUID> {
        let area = marquee.standardized
        return Set(notes.filter { rect(for: $0).intersects(area) }.map(\.id))
    }

    /// Pixels per tick that fit `extent` ticks into `width`, multiplied by `zoom`.
    static func pixelsPerTick(width: CGFloat, extent: Int, zoom: Double) -> CGFloat {
        let fit = width / CGFloat(max(1, extent))
        return min(maximumPixelsPerTick, max(fit, fit * CGFloat(max(1, zoom))))
    }

    /// Ticks shown when the roll is fully zoomed out: the loop plus a beat of tail
    /// so the loop-end handle stays reachable.
    static func extent(length: Int, notes: [SequenceNote]) -> Int {
        let end = max(length, notes.map(\.end).max() ?? 0)
        return end + MusicalTime.ticksPerQuarter
    }

    func clampedOriginTick(_ tick: Double, extent: Int) -> Double {
        min(max(0, Double(extent) - Double(width / max(0.0001, pixelsPerTick))), max(0, tick))
    }

    func clampedTopPitch(_ pitch: Double) -> Double {
        let rows = Double(height / rowHeight)
        return min(127, max(rows - 1, pitch))
    }
}

enum PianoRollNames {
    static let pitchClasses = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    /// Scientific names with 60 = C4 (C-1 … G9), as on the Digitone.
    static func name(_ pitch: Int) -> String {
        let safe = min(127, max(0, pitch))
        return pitchClasses[safe % 12] + "\(safe / 12 - 1)"
    }
    static func isBlack(_ pitch: Int) -> Bool { [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12) }
}

extension NoteSequence {
    var barTicks: Int { max(1, timeSignature.ticksPerBar) }
    var beatTicks: Int { max(1, MusicalTime.ticksPerQuarter * 4 / min(64, max(1, timeSignature.unit))) }
    var bars: Int { max(1, (length + barTicks - 1) / barTicks) }
}
