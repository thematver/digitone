import XCTest
import DigitoneCore
@testable import DigitoneUI

final class PianoRollGeometryTests: XCTestCase {
    private func geometry() -> PianoRollGeometry {
        // 2 px per tick, 10 px rows, pitch 72's row at the top.
        PianoRollGeometry(width: 768, height: 240, pixelsPerTick: 2, originTick: 0, rowHeight: 10, topPitch: 72)
    }

    func testSnapGridMath() {
        XCTAssertEqual(PianoRollSnap.allCases.map(\.grid), [96, 48, 24, 12, 1])
        XCTAssertEqual(PianoRollSnap.sixteenth.step, 24)
        XCTAssertEqual(PianoRollSnap.off.step, 24, "with snap off new notes and steps stay 1/16")
        XCTAssertEqual(PianoRollSnap.sixteenth.floor(47.9), 24)
        XCTAssertEqual(PianoRollSnap.sixteenth.round(36.0), 48)
        XCTAssertEqual(PianoRollSnap.sixteenth.round(35.9), 24)
        XCTAssertEqual(PianoRollSnap.quarter.round(150), 192)
        XCTAssertEqual(PianoRollSnap.thirtySecond.floor(-1), -12)
        XCTAssertEqual(PianoRollSnap.off.round(37.4), 37)
        XCTAssertEqual(PianoRollSnap.off.floor(37.9), 37)
        XCTAssertEqual(PianoRollSnap.sixteenth.label, "1/16")
    }

    func testTicksAndPitchesMapToPointsAndBack() {
        var g = geometry()
        XCTAssertEqual(g.x(96), 192)
        XCTAssertEqual(g.tick(atX: 192), 96)
        XCTAssertEqual(g.rowTop(72), 0)
        XCTAssertEqual(g.rowTop(60), 120)
        XCTAssertEqual(g.pitch(atY: 0), 72)
        XCTAssertEqual(g.pitch(atY: 9.9), 72)
        XCTAssertEqual(g.pitch(atY: 10), 71)
        XCTAssertEqual(g.pitch(atY: 125), 60)
        XCTAssertEqual(g.visiblePitches, 48...72)
        // Scrolled by half a row and a bar.
        g.topPitch = 72.5
        g.originTick = 384
        XCTAssertEqual(g.pitch(atY: 2), 73)
        XCTAssertEqual(g.pitch(atY: 6), 72)
        XCTAssertEqual(g.x(384), 0)
        XCTAssertEqual(g.rect(for: SequenceNote(pitch: 72, start: 408, duration: 24)), CGRect(x: 48, y: 5, width: 48, height: 10))
        // Out of range rows clamp to MIDI.
        XCTAssertEqual(g.pitch(atY: -10_000), 127)
        XCTAssertEqual(g.pitch(atY: 10_000), 0)
    }

    func testZoomFitsTheLoopAndScrollClamps() {
        XCTAssertEqual(PianoRollGeometry.extent(length: 384, notes: []), 480)
        XCTAssertEqual(PianoRollGeometry.extent(length: 384, notes: [SequenceNote(pitch: 60, start: 360, duration: 96)]), 552)
        XCTAssertEqual(PianoRollGeometry.pixelsPerTick(width: 960, extent: 480, zoom: 1), 2)
        XCTAssertEqual(PianoRollGeometry.pixelsPerTick(width: 960, extent: 480, zoom: 2), 4)
        XCTAssertEqual(PianoRollGeometry.pixelsPerTick(width: 960, extent: 480, zoom: 100), PianoRollGeometry.maximumPixelsPerTick)
        XCTAssertEqual(PianoRollGeometry.pixelsPerTick(width: 960, extent: 480, zoom: 0.1), 2, "never narrower than the fit")
        let g = geometry()
        XCTAssertEqual(g.clampedOriginTick(-50, extent: 1000), 0)
        XCTAssertEqual(g.clampedOriginTick(900, extent: 1000), 616)
        XCTAssertEqual(g.clampedTopPitch(200), 127)
        XCTAssertEqual(g.clampedTopPitch(3), 23, "the bottom row of pitch 0 stays on screen")
    }

    func testHitTestingSeparatesBodyRightEdgeAndEmptyCells() {
        let g = geometry()
        let long = SequenceNote(pitch: 70, start: 0, duration: 48)    // x 0...96, y 20...30
        let short = SequenceNote(pitch: 68, start: 96, duration: 3)   // x 192...198
        let notes = [long, short]
        XCTAssertEqual(g.hit(CGPoint(x: 40, y: 25), notes: notes), .note(long.id, edge: false))
        XCTAssertEqual(g.hit(CGPoint(x: 90, y: 25), notes: notes), .note(long.id, edge: true))
        XCTAssertEqual(g.hit(CGPoint(x: 87, y: 25), notes: notes), .note(long.id, edge: false))
        // A tiny note keeps a touchable body of 8 px and a small edge zone.
        XCTAssertEqual(g.hit(CGPoint(x: 191.5, y: 45), notes: notes), .note(short.id, edge: false))
        XCTAssertEqual(g.hit(CGPoint(x: 197.5, y: 45), notes: notes), .note(short.id, edge: true))
        XCTAssertEqual(g.hit(CGPoint(x: 120, y: 25), notes: notes), .empty(tick: 60, pitch: 70))
    }

    func testHitTestingPrefersSelectedThenLaterNotes() {
        let g = geometry()
        let first = SequenceNote(pitch: 70, start: 0, duration: 96)
        let second = SequenceNote(pitch: 70, start: 24, duration: 96)
        XCTAssertEqual(g.hit(CGPoint(x: 60, y: 25), notes: [first, second]), .note(second.id, edge: false))
        XCTAssertEqual(g.hit(CGPoint(x: 60, y: 25), notes: [first, second], selected: [first.id]), .note(first.id, edge: false))
    }

    func testMarqueeSelectsIntersectingNotesInAnyDirection() {
        let g = geometry()
        let a = SequenceNote(pitch: 70, start: 0, duration: 24)     // x 0...48, y 20...30
        let b = SequenceNote(pitch: 66, start: 48, duration: 24)    // x 96...144, y 60...70
        let c = SequenceNote(pitch: 60, start: 192, duration: 24)   // x 384...432, y 120...130
        let notes = [a, b, c]
        XCTAssertEqual(g.notes(in: CGRect(x: 40, y: 25, width: 70, height: 40), from: notes), [a.id, b.id])
        XCTAssertEqual(g.notes(in: CGRect(x: 110, y: 65, width: -70, height: -40), from: notes), [a.id, b.id])
        XCTAssertEqual(g.notes(in: CGRect(x: 200, y: 0, width: 100, height: 100), from: notes), [])
    }

    func testKeyboardKeysLineUpWithRowsAndBlackKeysAreShorter() {
        let g = geometry()
        let layout = PianoKeyboardLayout(width: 80)
        XCTAssertEqual(layout.blackWidth, 48)
        // Pitch 70 (A♯4) row: y 20...30.
        XCTAssertEqual(layout.pitch(at: CGPoint(x: 20, y: 24), geometry: g), 70)
        XCTAssertEqual(layout.pitch(at: CGPoint(x: 60, y: 22), geometry: g), 71, "front of a black row, upper half: B")
        XCTAssertEqual(layout.pitch(at: CGPoint(x: 60, y: 28), geometry: g), 69, "lower half: A")
        XCTAssertEqual(layout.pitch(at: CGPoint(x: 60, y: 15), geometry: g), 71)
        // White keys meet in the middle of black rows, or at row edges for E/F and B/C.
        let a = layout.whiteSpan(69, geometry: g)
        XCTAssertEqual(a.top, 25); XCTAssertEqual(a.bottom, 45)
        let e = layout.whiteSpan(64, geometry: g)
        XCTAssertEqual(e.top, 80); XCTAssertEqual(e.bottom, 95)
        XCTAssertEqual(PianoRollNames.name(60), "C4")
        XCTAssertEqual(PianoRollNames.name(0), "C-1")
        XCTAssertEqual(PianoRollNames.name(127), "G9")
        XCTAssertEqual(PianoRollNames.name(61), "C♯4")
    }

    func testVelocityLaneMapsValuesBothWays() {
        let height: CGFloat = 74
        for velocity in [1, 64, 100, 127] {
            XCTAssertEqual(PianoRollScene.velocity(atY: PianoRollScene.velocityY(velocity, height: height), height: height), velocity)
        }
        XCTAssertLessThan(PianoRollScene.velocityY(127, height: height), PianoRollScene.velocityY(1, height: height))
        XCTAssertEqual(PianoRollScene.velocity(atY: -100, height: height), 127)
        XCTAssertEqual(PianoRollScene.velocity(atY: 500, height: height), 1)
    }
}
