import SwiftUI
import DigitoneCore
import DigitoneDesign

/// Velocity colours (Logic-style): soft notes cool blue, medium green, loud
/// warm orange, interpolated in OKLCH between the instrument's own colours.
enum PianoRollPalette {
    static func velocity(_ velocity: Int, dark: Bool) -> Color {
        (dark ? darkTable : lightTable)[min(127, max(0, velocity))].color
    }

    /// Text drawn on a note: dark on light fills, paper on dark fills.
    static func label(_ velocity: Int, dark: Bool) -> Color {
        let lightness = (dark ? darkTable : lightTable)[min(127, max(0, velocity))].lightness
        return lightness > 0.7 ? Color(hex: 0x1A1D1B, opacity: 0.82) : Color(hex: 0xFBFAF6)
    }

    static func lane(_ index: Int) -> Color { InstrumentTheme.encoder(index) }

    /// OKLCH stops (velocity, L, C, hue°): pale blue → blue → green → amber → orange.
    private static let lightTable = table([(1, 0.72, 0.045, 250), (40, 0.58, 0.085, 255), (78, 0.55, 0.10, 158),
                                           (104, 0.74, 0.135, 78), (127, 0.66, 0.165, 46)])
    private static let darkTable = table([(1, 0.58, 0.04, 250), (40, 0.70, 0.085, 255), (78, 0.76, 0.10, 158),
                                          (104, 0.84, 0.125, 85), (127, 0.77, 0.15, 52)])

    private static func table(_ stops: [(Int, Double, Double, Double)]) -> [(color: Color, lightness: Double)] {
        (0...127).map { velocity in
            let v = max(1, velocity)
            let upper = stops.firstIndex { $0.0 >= v } ?? stops.count - 1
            let lower = max(0, upper - 1)
            let (a, b) = (stops[lower], stops[upper])
            let t = b.0 == a.0 ? 0 : Double(v - a.0) / Double(b.0 - a.0)
            var hue = b.3 - a.3
            if hue > 180 { hue -= 360 } else if hue < -180 { hue += 360 }
            let l = a.1 + (b.1 - a.1) * t, c = a.2 + (b.2 - a.2) * t, h = (a.3 + hue * t) * .pi / 180
            return (color(l: l, a: c * cos(h), b: c * sin(h)), l)
        }
    }

    private static func color(l: Double, a: Double, b: Double) -> Color {
        let l1 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m1 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s1 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        func gamma(_ c: Double) -> Double {
            let v = min(1, max(0, c))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return Color(.sRGB,
                     red: gamma(4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1),
                     green: gamma(-1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1),
                     blue: gamma(-0.0041960863 * l1 - 0.7034186147 * m1 + 1.7076147010 * s1))
    }
}

/// Everything the three roll canvases draw, captured once per frame.
struct PianoRollScene {
    var geometry: PianoRollGeometry
    var sequence: NoteSequence
    var laneIndex: Int
    var selection: Set<UUID>
    var snap: PianoRollSnap
    var lit: [Int: PianoKeyLight]
    var playhead: Double?
    var cursor: Int?
    var recording: Bool
    var pending: [PianoRollRecorder.Pending]
    var marquee: CGRect?
    var dark: Bool
    var compact: Bool

    var notes: [SequenceNote] { sequence.lanes.indices.contains(laneIndex) ? sequence.lanes[laneIndex].notes : [] }
    var accent: Color { recording ? InstrumentTheme.record : InstrumentTheme.ink }

    // MARK: Grid

    func drawGrid(_ context: GraphicsContext, size: CGSize) {
        let g = geometry
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(InstrumentTheme.panel))
        let pitches = g.visiblePitches
        var octaves = Path(), seams = Path()
        for pitch in pitches {
            let top = g.rowTop(pitch)
            let row = CGRect(x: 0, y: top, width: size.width, height: g.rowHeight)
            if PianoRollNames.isBlack(pitch) {
                context.fill(Path(row), with: .color(InstrumentTheme.paper.opacity(dark ? 0.55 : 0.62)))
            }
            if let light = lit[pitch] { context.fill(Path(row), with: .color(light.color.opacity(0.14))) }
            if pitch % 12 == 0 {
                octaves.move(to: CGPoint(x: 0, y: row.maxY)); octaves.addLine(to: CGPoint(x: size.width, y: row.maxY))
            } else if pitch % 12 == 5 {
                seams.move(to: CGPoint(x: 0, y: row.maxY)); seams.addLine(to: CGPoint(x: size.width, y: row.maxY))
            }
        }
        context.stroke(seams, with: .color(InstrumentTheme.line.opacity(0.6)), lineWidth: 0.5)
        context.stroke(octaves, with: .color(InstrumentTheme.line), lineWidth: 1)
        drawTimeLines(context, size: size, bar: InstrumentTheme.secondary.opacity(dark ? 0.32 : 0.28))
        drawOutsideLoop(context, size: size)

        // Other lanes as quiet ghosts.
        for (index, lane) in sequence.lanes.enumerated() where index != laneIndex {
            let color = PianoRollPalette.lane(index)
            for note in lane.notes where visible(note) {
                let shape = Path(roundedRect: g.rect(for: note).insetBy(dx: 0.5, dy: 1.5), cornerRadius: 3)
                context.fill(shape, with: .color(color.opacity(0.06)))
                context.stroke(shape, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }

        let ordered = notes.filter { !selection.contains($0.id) && visible($0) } + notes.filter { selection.contains($0.id) && visible($0) }
        for note in ordered { drawNote(note, context: context) }

        for note in pending {
            let end = playhead.map { $0 >= note.tick ? $0 : Double(sequence.length) } ?? note.tick + Double(snap.step)
            let rect = CGRect(x: g.x(note.tick), y: g.rowTop(note.pitch), width: max(3, g.x(end) - g.x(note.tick)), height: g.rowHeight)
            let shape = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 1), cornerRadius: 3)
            context.fill(shape, with: .color(InstrumentTheme.record.opacity(0.28)))
            context.stroke(shape, with: .color(InstrumentTheme.record), lineWidth: 1.2)
        }

        if let cursor, playhead == nil {
            var line = Path(); let x = g.x(cursor)
            line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(recording ? InstrumentTheme.record : InstrumentTheme.secondary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: [4, 3]))
        }
        drawPlayhead(context, size: size)
        if let marquee {
            let shape = Path(marquee.standardized)
            context.fill(shape, with: .color(InstrumentTheme.blue.opacity(0.08)))
            context.stroke(shape, with: .color(InstrumentTheme.blue.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    private func visible(_ note: SequenceNote) -> Bool {
        geometry.visiblePitches.contains(note.pitch)
            && Double(note.end) >= geometry.visibleTicks.lowerBound && Double(note.start) <= geometry.visibleTicks.upperBound
    }

    private func drawNote(_ note: SequenceNote, context: GraphicsContext) {
        let g = geometry
        let selected = selection.contains(note.id)
        let rect = g.rect(for: note).insetBy(dx: 0.5, dy: g.rowHeight >= 12 ? 1 : 0.5)
        let radius = min(4, rect.height / 2.5)
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        let fill = PianoRollPalette.velocity(note.velocity, dark: dark)
        if selected {
            context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2), with: .color(InstrumentTheme.ink.opacity(dark ? 0.9 : 0.85)))
        }
        context.fill(shape, with: .color(fill))
        context.stroke(shape, with: .color(.black.opacity(dark ? 0.35 : 0.16)), lineWidth: 0.75)
        if rect.width >= 30, g.rowHeight >= 11 {
            let label = Text(PianoRollNames.name(note.pitch))
                .font(.system(size: compact ? 9 : 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(PianoRollPalette.label(note.velocity, dark: dark))
            var clipped = context
            clipped.clip(to: shape)
            clipped.draw(label, at: CGPoint(x: rect.minX + 5, y: rect.midY - 0.5), anchor: .leading)
        }
    }

    private func drawTimeLines(_ context: GraphicsContext, size: CGSize, bar: Color) {
        let g = geometry
        let range = g.visibleTicks
        let barTicks = sequence.barTicks, beat = sequence.beatTicks
        var fine = snap == .off ? MusicalTime.ticksPerStep : snap.grid
        while CGFloat(fine) * g.pixelsPerTick < 7 && fine < barTicks { fine *= 2 }
        var minor = Path(), beats = Path(), bars = Path()
        var tick = Int(range.lowerBound) / fine * fine
        while Double(tick) <= range.upperBound {
            let x = g.x(tick).rounded() + 0.5
            if tick % barTicks == 0 {
                bars.move(to: CGPoint(x: x, y: 0)); bars.addLine(to: CGPoint(x: x, y: size.height))
            } else if tick % beat == 0 {
                beats.move(to: CGPoint(x: x, y: 0)); beats.addLine(to: CGPoint(x: x, y: size.height))
            } else {
                minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height))
            }
            tick += fine
        }
        // Bar/beat boundaries must survive a coarse snap grid (e.g. 1/4 in 3/8).
        // The fine-grid loop alone visits only every second bar in that case.
        tick = Int(range.lowerBound) / barTicks * barTicks
        while Double(tick) <= range.upperBound {
            if tick % fine != 0 {
                let x = g.x(tick).rounded() + 0.5
                bars.move(to: CGPoint(x: x, y: 0)); bars.addLine(to: CGPoint(x: x, y: size.height))
            }
            tick += barTicks
        }
        if CGFloat(beat) * g.pixelsPerTick >= 7 {
            tick = Int(range.lowerBound) / beat * beat
            while Double(tick) <= range.upperBound {
                if tick % fine != 0, tick % barTicks != 0 {
                    let x = g.x(tick).rounded() + 0.5
                    beats.move(to: CGPoint(x: x, y: 0)); beats.addLine(to: CGPoint(x: x, y: size.height))
                }
                tick += beat
            }
        }
        context.stroke(minor, with: .color(InstrumentTheme.line.opacity(0.55)), lineWidth: 0.5)
        context.stroke(beats, with: .color(InstrumentTheme.line), lineWidth: 1)
        context.stroke(bars, with: .color(bar), lineWidth: 1)
    }

    private func drawOutsideLoop(_ context: GraphicsContext, size: CGSize) {
        let end = geometry.x(sequence.length)
        guard end < size.width else { return }
        context.fill(Path(CGRect(x: end, y: 0, width: size.width - end, height: size.height)),
                     with: .color(InstrumentTheme.paper.opacity(dark ? 0.7 : 0.78)))
        var line = Path(); line.move(to: CGPoint(x: end, y: 0)); line.addLine(to: CGPoint(x: end, y: size.height))
        context.stroke(line, with: .color(InstrumentTheme.secondary.opacity(0.5)), lineWidth: 1)
    }

    private func drawPlayhead(_ context: GraphicsContext, size: CGSize) {
        guard let playhead else { return }
        var line = Path(); let x = geometry.x(playhead)
        line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(accent), lineWidth: 1.5)
    }

    // MARK: Ruler

    func drawRuler(_ context: GraphicsContext, size: CGSize) {
        let g = geometry
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(InstrumentTheme.panel))
        let barTicks = sequence.barTicks, beat = sequence.beatTicks
        let loopEnd = g.x(sequence.length)
        // Loop (cycle) strip with its end handle.
        let strip = CGRect(x: g.x(0), y: 4, width: max(0, loopEnd - g.x(0)), height: 5)
        context.fill(Path(roundedRect: strip, cornerRadius: 2.5), with: .color((recording ? InstrumentTheme.record : InstrumentTheme.secondary).opacity(recording ? 0.45 : 0.28)))
        let handle = CGRect(x: loopEnd - 5, y: 1, width: 10, height: 13)
        context.fill(Path(roundedRect: handle, cornerRadius: 3), with: .color(recording ? InstrumentTheme.record : InstrumentTheme.ink))
        var grip = Path()
        grip.move(to: CGPoint(x: loopEnd - 1.5, y: 4.5)); grip.addLine(to: CGPoint(x: loopEnd - 1.5, y: 10.5))
        grip.move(to: CGPoint(x: loopEnd + 1.5, y: 4.5)); grip.addLine(to: CGPoint(x: loopEnd + 1.5, y: 10.5))
        context.stroke(grip, with: .color(InstrumentTheme.panel), lineWidth: 1)

        var ticks = Path()
        let range = g.visibleTicks
        let barWidth = CGFloat(barTicks) * g.pixelsPerTick
        let labelEvery = barWidth < 26 ? (barWidth < 13 ? 4 : 2) : 1
        var tick = Int(range.lowerBound) / beat * beat
        while Double(tick) <= range.upperBound {
            let x = g.x(tick).rounded() + 0.5
            if tick % barTicks == 0 {
                ticks.move(to: CGPoint(x: x, y: size.height - 11)); ticks.addLine(to: CGPoint(x: x, y: size.height))
                let bar = tick / barTicks
                if bar % labelEvery == 0 {
                    let label = Text("\(bar + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(tick < sequence.length ? InstrumentTheme.ink : InstrumentTheme.secondary)
                    context.draw(label, at: CGPoint(x: x + 6, y: size.height - 8), anchor: .leading)
                }
            } else if CGFloat(beat) * g.pixelsPerTick >= 8 {
                ticks.move(to: CGPoint(x: x, y: size.height - 4)); ticks.addLine(to: CGPoint(x: x, y: size.height))
            }
            tick += beat
        }
        context.stroke(ticks, with: .color(InstrumentTheme.secondary.opacity(0.6)), lineWidth: 1)

        if let cursor, playhead == nil {
            let x = g.x(cursor)
            var marker = Path()
            marker.move(to: CGPoint(x: x - 4.5, y: size.height - 7)); marker.addLine(to: CGPoint(x: x + 4.5, y: size.height - 7))
            marker.addLine(to: CGPoint(x: x, y: size.height)); marker.closeSubpath()
            context.fill(marker, with: .color(recording ? InstrumentTheme.record : InstrumentTheme.secondary))
        }
        if let playhead {
            let x = g.x(playhead)
            var head = Path()
            head.move(to: CGPoint(x: x - 5, y: size.height - 9)); head.addLine(to: CGPoint(x: x + 5, y: size.height - 9))
            head.addLine(to: CGPoint(x: x, y: size.height)); head.closeSubpath()
            context.fill(head, with: .color(accent))
        }
        var base = Path(); base.move(to: CGPoint(x: 0, y: size.height - 0.5)); base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        context.stroke(base, with: .color(InstrumentTheme.line), lineWidth: 1)
    }

    // MARK: Velocity

    /// Top of a velocity stem in a lane of `height`.
    static func velocityY(_ velocity: Int, height: CGFloat) -> CGFloat {
        let top: CGFloat = 9, bottom = height - 4
        return bottom - (bottom - top) * CGFloat(min(127, max(0, velocity))) / 127
    }

    static func velocity(atY y: CGFloat, height: CGFloat) -> Int {
        let top: CGFloat = 9, bottom = height - 4
        return min(127, max(1, Int(((bottom - y) / max(1, bottom - top) * 127).rounded())))
    }

    func drawVelocity(_ context: GraphicsContext, size: CGSize) {
        let g = geometry
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(InstrumentTheme.panel))
        var guides = Path()
        for value in [64, 127] {
            let y = Self.velocityY(value, height: size.height).rounded() + 0.5
            guides.move(to: CGPoint(x: 0, y: y)); guides.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(guides, with: .color(InstrumentTheme.line), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        drawOutsideLoop(context, size: size)
        let ordered = notes.filter { !selection.contains($0.id) } + notes.filter { selection.contains($0.id) }
        for note in ordered where Double(note.start) >= g.visibleTicks.lowerBound - 1 && Double(note.start) <= g.visibleTicks.upperBound {
            let selected = selection.contains(note.id)
            let x = g.x(note.start) + 1.5
            let y = Self.velocityY(note.velocity, height: size.height)
            let color = selected ? InstrumentTheme.ink : PianoRollPalette.velocity(note.velocity, dark: dark)
            var stem = Path(); stem.move(to: CGPoint(x: x, y: size.height - 3)); stem.addLine(to: CGPoint(x: x, y: y))
            context.stroke(stem, with: .color(color.opacity(selected ? 1 : 0.85)), lineWidth: selected ? 2 : 1.5)
            let radius: CGFloat = selected ? 3.5 : 3
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }
        drawPlayhead(context, size: size)
        var top = Path(); top.move(to: CGPoint(x: 0, y: 0.5)); top.addLine(to: CGPoint(x: size.width, y: 0.5))
        context.stroke(top, with: .color(InstrumentTheme.line), lineWidth: 1)
    }
}
