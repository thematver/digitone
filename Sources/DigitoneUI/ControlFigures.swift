import SwiftUI
import DigitoneCore
import DigitoneDesign

/// A page drawing computed from the page's values: lines, fills, small marks and
/// draggable handles. Every element knows which parameter drives it, so unknown
/// values draw dashed and each part takes its knob's colour.
struct Figure {
    struct Stroke {
        var path: Path
        var color: Color
        var width: CGFloat = 2
        var known = true
        var opacity = 1.0
        var dash: [CGFloat]? = nil
    }
    struct Fill {
        var path: Path
        var color: Color
        var opacity = 0.08
    }
    struct Mark {
        var text: String
        var point: CGPoint
        var anchor: UnitPoint = .center
        var color: Color = InstrumentTheme.secondary
        var size: CGFloat = 9
        var weight: Font.Weight = .medium
    }
    /// A drag axis: moving `span` points changes the parameter across its whole range.
    struct Axis {
        let parameter: DNParameter
        let span: CGFloat
    }
    struct Handle: Identifiable {
        var id: String
        var point: CGPoint
        var x: Axis?
        var y: Axis?
        var slot: Int
        var origin: ControlOrigin?
    }

    var guides: [Stroke] = []
    var fills: [Fill] = []
    var strokes: [Stroke] = []
    var marks: [Mark] = []
    var handles: [Handle] = []

    mutating func stroke(_ path: Path, _ color: Color, width: CGFloat = 2, known: Bool = true, opacity: Double = 1, dash: [CGFloat]? = nil) {
        strokes.append(Stroke(path: path, color: color, width: width, known: known, opacity: opacity, dash: dash))
    }

    mutating func guide(_ path: Path, opacity: Double = 1, dash: [CGFloat]? = [2, 4]) {
        guides.append(Stroke(path: path, color: InstrumentTheme.line, width: 1, known: true, opacity: opacity, dash: dash))
    }

    mutating func mark(_ text: String, _ point: CGPoint, anchor: UnitPoint = .center, color: Color = InstrumentTheme.secondary,
                       size: CGFloat = 9, weight: Font.Weight = .medium) {
        marks.append(Mark(text: text, point: point, anchor: anchor, color: color, size: size, weight: weight))
    }

    /// A handle on one or two parameters (absent parameters are skipped).
    mutating func handle(_ point: CGPoint, x: DNParameter? = nil, xSpan: CGFloat = 0, y: DNParameter? = nil, ySpan: CGFloat = 0,
                         context: FigureContext, role: String = "") {
        guard let driver = x ?? y else { return }
        handles.append(Handle(id: driver.id + role, point: point,
                              x: x.map { Axis(parameter: $0, span: abs(xSpan) < 1 ? 1 : xSpan) },
                              y: y.map { Axis(parameter: $0, span: abs(ySpan) < 1 ? 1 : ySpan) },
                              slot: driver.slot, origin: context.origin(driver)))
    }
}

/// The values a figure is computed from.
struct FigureContext {
    let page: DNPage
    let machine: DNMachine
    let parameters: [DNParameter]
    let lookup: (DNParameter) -> ControlValue?

    /// The `occurrence`-th parameter whose device label is one of `labels`.
    func find(_ labels: [String], occurrence: Int = 0) -> DNParameter? {
        let wanted = Set(labels.map { $0.uppercased() })
        let found = parameters.filter { wanted.contains($0.label.uppercased()) }
        return found.indices.contains(occurrence) ? found[occurrence] : nil
    }

    func p(_ labels: String...) -> DNParameter? { find(labels) }

    func value14(_ parameter: DNParameter) -> Int { lookup(parameter)?.value ?? parameter.defaultValue14 }

    /// 0...1 position of the value (or the default when unknown).
    func unit(_ parameter: DNParameter?, _ fallback: Double = 0.5) -> Double {
        guard let parameter else { return fallback }
        return parameter.fraction(of: value14(parameter))
    }

    /// -1...1 for bipolar knobs.
    func bipolar(_ parameter: DNParameter?) -> Double { parameter == nil ? 0 : unit(parameter) * 2 - 1 }

    func origin(_ parameter: DNParameter?) -> ControlOrigin? { parameter.flatMap { lookup($0)?.origin } }

    /// True when every given parameter exists and its value is known.
    func known(_ parameters: DNParameter?...) -> Bool { parameters.allSatisfy { $0.map { lookup($0) != nil } ?? false } }

    func text(_ parameter: DNParameter?) -> String? { parameter.map { $0.display(value14($0)).uppercased() } }

    /// The first number in the device text: "BPM 2" → 2, "1/16" → 0.0625, "1K" → 1000.
    func number(_ parameter: DNParameter?) -> Double? { text(parameter).flatMap(FigureMath.number(in:)) }

    func color(_ parameter: DNParameter?) -> Color { parameter.map { InstrumentTheme.encoder($0.slot) } ?? InstrumentTheme.ink }
}

enum FigureMath {
    static func number(in text: String) -> Double? {
        let characters = Array(text)
        guard let start = characters.indices.first(where: { index in
            characters[index].isNumber || ((characters[index] == "-" || characters[index] == "+")
                && characters.indices.contains(index + 1) && characters[index + 1].isNumber)
        }) else { return nil }
        var end = start + 1
        while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
        guard var value = Double(String(characters[start..<end])) else { return nil }
        if end < characters.count, characters[end] == "/" {
            var denominatorEnd = end + 1
            while denominatorEnd < characters.count, characters[denominatorEnd].isNumber { denominatorEnd += 1 }
            if let denominator = Double(String(characters[(end + 1)..<denominatorEnd])), denominator > 0 { value /= denominator }
        } else if end < characters.count, characters[end] == "K" {
            value *= 1000
        }
        return value
    }

    /// Every number in the text, in order.
    static func numbers(in text: String) -> [Double] {
        var result: [Double] = []
        var rest = Substring(text)
        while let value = number(in: String(rest)) {
            result.append(value)
            guard let index = rest.firstIndex(where: { $0.isNumber }) else { break }
            rest = rest[index...].drop { $0.isNumber || $0 == "." || $0 == "/" }
        }
        return result
    }

    /// MIDI note from "C4", "F#3", "A♯2" or a plain number.
    static func note(in text: String) -> Int? {
        let names: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        let upper = Array(text.uppercased())
        if let first = upper.first, let base = names[first] {
            var index = 1, pitch = base
            if index < upper.count, upper[index] == "#" || upper[index] == "♯" { pitch += 1; index += 1 }
            else if index < upper.count, upper[index] == "B" || upper[index] == "♭" { pitch -= 1; index += 1 }
            if let octave = Int(String(upper[index...])) { return min(127, max(0, (octave + 1) * 12 + pitch)) }
        }
        return number(in: text).map { min(127, max(0, Int($0))) }
    }

    static func noteName(_ note: Int) -> String {
        ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"][((note % 12) + 12) % 12] + "\(note / 12 - 1)"
    }

    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// Samples `y(x)` for x in 0...1 into `rect` (y in 0...1, up).
    static func curve(in rect: CGRect, samples: Int = 160, _ y: (Double) -> Double) -> Path {
        polyline((0...samples).map { index in
            let x = Double(index) / Double(samples)
            return CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * y(x))
        })
    }

    static func line(_ a: CGPoint, _ b: CGPoint) -> Path { polyline([a, b]) }

    static func horizontal(_ y: CGFloat, _ rect: CGRect) -> Path { line(CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)) }

    static func vertical(_ x: CGFloat, _ rect: CGRect) -> Path { line(CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)) }

    /// Deterministic pseudo-random 0...1 for drawing texture (reverb tails, random LFO).
    static func noise(_ index: Int) -> Double {
        var value = UInt64(truncatingIfNeeded: index &* 2_654_435_761 &+ 0x9E37_79B9)
        value ^= value >> 13; value &*= 0x5bd1_e995; value ^= value >> 15
        return Double(value % 10_000) / 10_000
    }
}

// MARK: - Builders

enum FigureBuilder {
    static func build(_ context: FigureContext, in rect: CGRect) -> Figure {
        guard !context.parameters.isEmpty, rect.width > 20, rect.height > 20 else { return Figure() }
        let specific: Figure?
        switch context.page {
        case .fltr1: specific = filter(context, rect)
        case .fltr2: specific = band(context, rect)
        case .amp: specific = amp(context, rect)
        case .fx: specific = effects(context, rect)
        case .mod1, .mod2, .mod3: specific = lfo(context, rect)
        case .trig: specific = trig(context, rect)
        case .delay: specific = delay(context, rect)
        case .reverb: specific = reverb(context, rect)
        case .chorus: specific = chorus(context, rect)
        case .compressor: specific = compressor(context, rect)
        case .syn1, .syn2, .syn3, .syn4: specific = synth(context, rect)
        case .track, .sequencer, .mixer, .mixerRight: specific = nil
        }
        return specific ?? rows(context, rect)
    }

    // MARK: Envelopes

    struct EnvelopeParts {
        var attack: DNParameter?
        var hold: DNParameter?
        var decay: DNParameter?
        var sustain: DNParameter?
        var release: DNParameter?
        /// Level the decay ends at when there is no sustain/release (FM operator END).
        var end: DNParameter?
        var peak: DNParameter?
    }

    /// Draws an envelope into `rect`; each stage in its knob's colour, dashed while unknown.
    static func envelope(_ figure: inout Figure, _ context: FigureContext, _ parts: EnvelopeParts, in rect: CGRect,
                         gated: Bool = true, peakFloor: Double = 0.25) {
        let hasSustain = gated && parts.sustain != nil
        let stages: [(DNParameter?, Double)] = [(parts.attack, 0.24), (parts.hold, parts.hold == nil ? 0 : 0.14),
                                                 (parts.decay, 0.22), (nil, hasSustain ? 0.14 : 0),
                                                 (parts.release, hasSustain && parts.release != nil ? 0.22 : 0)]
        let budget = stages.reduce(0) { $0 + ($1.1 > 0 ? $1.1 + 0.015 : 0) }
        let scale = rect.width / max(1, budget)
        func width(_ stage: (DNParameter?, Double)) -> CGFloat {
            guard stage.1 > 0 else { return 0 }
            let amount = stage.0 == nil ? 1 : context.unit(stage.0, 0.3)
            if stage.0 == parts.hold, let text = context.text(parts.hold), text.contains("NOTE") { return CGFloat(0.015 + stage.1) * scale }
            return CGFloat(0.015 + stage.1 * amount) * scale
        }
        let base = rect.maxY
        let peakLevel = parts.peak == nil ? 1 : peakFloor + (1 - peakFloor) * context.unit(parts.peak)
        let top = base - rect.height * peakLevel
        let level = hasSustain ? context.unit(parts.sustain, 0.6) : (parts.end.map { context.unit($0) } ?? 0)
        let rest = base - (base - top) * level

        let x0 = rect.minX
        let x1 = x0 + width(stages[0])
        let x2 = x1 + width(stages[1])
        let x3 = x2 + width(stages[2])
        let x4 = x3 + width(stages[3])
        let x5 = x4 + width(stages[4])
        let p0 = CGPoint(x: x0, y: base), p1 = CGPoint(x: x1, y: top), p2 = CGPoint(x: x2, y: top)
        let p3 = CGPoint(x: x3, y: rest), p4 = CGPoint(x: x4, y: rest)
        let p5 = CGPoint(x: hasSustain ? x5 : x3, y: hasSustain ? base : rest)
        var outline = [p0, p1, p2, p3]
        if hasSustain { outline += [p4, p5] } else if parts.end != nil { outline.append(CGPoint(x: rect.maxX, y: rest)) }

        var area = FigureMath.polyline(outline)
        area.addLine(to: CGPoint(x: outline.last!.x, y: base))
        area.closeSubpath()
        figure.fills.append(Figure.Fill(path: area, color: InstrumentTheme.ink, opacity: 0.045))
        figure.guide(FigureMath.horizontal(base, rect), dash: nil)

        func segment(_ a: CGPoint, _ b: CGPoint, _ parameter: DNParameter?) {
            figure.stroke(FigureMath.line(a, b), context.color(parameter), width: 2.4, known: context.known(parameter))
        }
        segment(p0, p1, parts.attack)
        if parts.hold != nil { segment(p1, p2, parts.hold) }
        segment(p2, p3, parts.decay)
        if hasSustain {
            segment(p3, p4, parts.sustain)
            segment(p4, p5, parts.release)
        } else if parts.end != nil {
            segment(p3, CGPoint(x: rect.maxX, y: rest), parts.end)
        }

        let reach = rect.height * peakLevel
        figure.handle(p1, x: parts.attack, xSpan: CGFloat(0.24) * scale, y: parts.peak, ySpan: rect.height * (1 - peakFloor),
                      context: context, role: ".peak")
        if parts.hold != nil { figure.handle(p2, x: parts.hold, xSpan: CGFloat(0.14) * scale, context: context) }
        figure.handle(p3, x: parts.decay, xSpan: CGFloat(0.22) * scale, context: context)
        if hasSustain {
            figure.handle(CGPoint(x: (x3 + x4) / 2, y: rest), y: parts.sustain, ySpan: reach, context: context)
            figure.handle(p5, x: parts.release, xSpan: CGFloat(0.22) * scale, context: context)
        } else if parts.end != nil {
            figure.handle(CGPoint(x: (x3 + rect.maxX) / 2, y: rest), y: parts.end, ySpan: reach, context: context)
        }
    }

    // MARK: FLTR

    static func filter(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard let frequency = context.p("FREQ") else { return nil }
        var figure = Figure()
        let left = CGRect(x: rect.minX, y: rect.minY + 8, width: rect.width * 0.38, height: rect.height - 8)
        let right = CGRect(x: rect.minX + rect.width * 0.46, y: rect.minY, width: rect.width * 0.54, height: rect.height)
        envelope(&figure, context, EnvelopeParts(attack: context.p("ATK"), decay: context.p("DEC"),
                                                 sustain: context.p("SUS"), release: context.p("REL")), in: left)
        figure.guide(FigureMath.vertical(rect.minX + rect.width * 0.42, rect.insetBy(dx: 0, dy: rect.height * 0.1)))

        let resonance = context.p("RESO", "RES", "Q")
        let type = context.text(context.p("TYPE")) ?? "LP"
        let cutoff = context.unit(frequency)
        let reso = context.unit(resonance, 0.15)
        let envelopeDepth = context.p("ENV")
        let sweep = context.bipolar(envelopeDepth) * 0.35
        func response(_ x: Double, cutoff: Double) -> Double {
            let u = (x - cutoff) * 9
            let shape: Double
            if type.contains("HP") { shape = 1 / (1 + exp(-6 * u)) }
            else if type.contains("BP") { shape = exp(-u * u * 2.5) }
            else if type.contains("BR") || type.contains("NOTCH") { shape = 1 - exp(-u * u * 4) }
            else { shape = 1 / (1 + exp(6 * u)) }
            return 0.08 + 0.5 * shape + reso * 0.42 * exp(-u * u * 14)
        }
        let plot = right.insetBy(dx: 0, dy: 10)
        for decade in 1..<4 { figure.guide(FigureMath.vertical(plot.minX + plot.width * CGFloat(decade) / 4, plot)) }
        figure.guide(FigureMath.horizontal(plot.maxY - plot.height * 0.58, plot))
        let envelopeKnown = context.known(envelopeDepth)
        if abs(sweep) > 0.005 {
            let target = min(1, max(0, cutoff + sweep))
            figure.stroke(FigureMath.curve(in: plot) { response($0, cutoff: target) }, context.color(envelopeDepth),
                          width: 1.3, opacity: 0.75, dash: [3, 4])
            let y = plot.minY - 2
            let from = CGPoint(x: plot.minX + plot.width * cutoff, y: y), to = CGPoint(x: plot.minX + plot.width * target, y: y)
            figure.stroke(FigureMath.line(from, to), context.color(envelopeDepth), width: 1.5, known: envelopeKnown)
            let direction: CGFloat = to.x > from.x ? -1 : 1
            figure.stroke(FigureMath.polyline([CGPoint(x: to.x + direction * 6, y: y - 4), to, CGPoint(x: to.x + direction * 6, y: y + 4)]),
                          context.color(envelopeDepth), width: 1.5, known: envelopeKnown)
        }
        var area = FigureMath.curve(in: plot) { response($0, cutoff: cutoff) }
        area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY)); area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY)); area.closeSubpath()
        figure.fills.append(Figure.Fill(path: area, color: context.color(frequency), opacity: 0.08))
        figure.stroke(FigureMath.curve(in: plot) { response($0, cutoff: cutoff) }, context.color(frequency), width: 2.6,
                      known: context.known(frequency))
        let point = CGPoint(x: plot.minX + plot.width * cutoff, y: plot.maxY - plot.height * response(cutoff, cutoff: cutoff))
        figure.handle(point, x: frequency, xSpan: plot.width, y: resonance, ySpan: plot.height * 0.42 * 0.8, context: context)
        if let envelopeDepth {
            let target = min(1, max(0, cutoff + sweep))
            figure.handle(CGPoint(x: plot.minX + plot.width * target, y: plot.minY - 2), x: envelopeDepth, xSpan: plot.width * 0.7,
                          context: context)
        }
        return figure
    }

    /// FLTR2: the base-width band (high-pass at BASE, low-pass WDTH above it).
    static func band(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard let baseParameter = context.p("BASE"), let widthParameter = context.p("WDTH", "WIDTH") else { return nil }
        var figure = Figure()
        let plot = rect.insetBy(dx: 0, dy: 12)
        let base = context.unit(baseParameter, 0), width = context.unit(widthParameter, 1)
        let low = base, high = base + width * (1 - base)
        for decade in 1..<4 { figure.guide(FigureMath.vertical(plot.minX + plot.width * CGFloat(decade) / 4, plot)) }
        figure.guide(FigureMath.horizontal(plot.maxY, plot), dash: nil)
        func gain(_ x: Double) -> Double {
            let rise = low <= 0.001 ? 1 : 1 / (1 + exp(-(x - low) * 40))
            let fall = high >= 0.999 ? 1 : 1 / (1 + exp((x - high) * 40))
            return 0.06 + 0.76 * rise * fall
        }
        var area = FigureMath.curve(in: plot, samples: 220, gain)
        area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY)); area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY)); area.closeSubpath()
        figure.fills.append(Figure.Fill(path: area, color: InstrumentTheme.green, opacity: 0.09))
        figure.stroke(FigureMath.curve(in: plot, samples: 220, gain), InstrumentTheme.ink, width: 2.4,
                      known: context.known(baseParameter, widthParameter))
        let lowX = plot.minX + plot.width * low, highX = plot.minX + plot.width * high
        figure.stroke(FigureMath.line(CGPoint(x: lowX, y: plot.maxY + 6), CGPoint(x: highX, y: plot.maxY + 6)),
                      context.color(widthParameter), width: 3, known: context.known(widthParameter))
        figure.handle(CGPoint(x: lowX, y: plot.maxY - plot.height * 0.82 / 2), x: baseParameter, xSpan: plot.width, context: context)
        figure.handle(CGPoint(x: highX, y: plot.maxY + 6), x: widthParameter, xSpan: max(8, plot.width * (1 - base)), context: context)
        if let keyTrack = context.p("KEY.T", "KEYT") {
            let slope = context.unit(keyTrack, 0)
            let origin = CGPoint(x: plot.maxX - 46, y: plot.minY + 22)
            figure.guide(FigureMath.line(origin, CGPoint(x: origin.x + 36, y: origin.y)))
            figure.stroke(FigureMath.line(origin, CGPoint(x: origin.x + 36, y: origin.y - 18 * slope)), context.color(keyTrack),
                          width: 1.6, known: context.known(keyTrack))
        }
        return figure
    }

    // MARK: AMP

    static func amp(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard context.p("ATK") != nil || context.p("DEC") != nil else { return nil }
        var figure = Figure()
        let pan = context.p("PAN")
        let envelopeRect = CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: rect.height - (pan == nil ? 4 : 34))
        let mode = context.text(context.p("MODE")) ?? "ADSR"
        envelope(&figure, context, EnvelopeParts(attack: context.p("ATK"), hold: context.p("HOLD"), decay: context.p("DEC"),
                                                 sustain: context.p("SUS"), release: context.p("REL"), peak: context.p("VOL")),
                 in: envelopeRect, gated: !mode.contains("AHD"))
        if let pan {
            let y = rect.maxY - 8
            let line = CGRect(x: rect.midX - 90, y: y, width: 180, height: 0)
            figure.guide(FigureMath.horizontal(y, line), dash: nil)
            figure.guide(FigureMath.line(CGPoint(x: line.midX, y: y - 4), CGPoint(x: line.midX, y: y + 4)), dash: nil)
            figure.mark("L", CGPoint(x: line.minX - 10, y: y))
            figure.mark("R", CGPoint(x: line.maxX + 10, y: y))
            let x = line.midX + CGFloat(context.bipolar(pan)) * 90
            figure.stroke(FigureMath.line(CGPoint(x: line.midX, y: y), CGPoint(x: x, y: y)), context.color(pan), width: 3, known: context.known(pan))
            figure.handle(CGPoint(x: x, y: y), x: pan, xSpan: 180, context: context)
        }
        return figure
    }

    // MARK: SYN

    /// SYN pages retain their device slot order. Envelope pages get stage handles;
    /// the remaining controls use a level/option plot rather than claiming to
    /// reconstruct the audio waveform from MIDI alone.
    static func synth(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        rows(context, rect)
    }

    // MARK: Generic

    /// Top row A–D and bottom row E–H, each an envelope when its labels describe one, else level bars.
    static func rows(_ context: FigureContext, _ rect: CGRect) -> Figure {
        let halves = [context.parameters.filter { $0.slot < 4 }, context.parameters.filter { (4..<8).contains($0.slot) }]
        let envelopes = halves.map { half in half.contains { $0.label.uppercased() == "ATK" } && half.contains { $0.label.uppercased() == "DEC" } }
        guard envelopes.contains(true) else { return bars(context, rect) }
        var figure = Figure()
        let gap: CGFloat = 18
        let height = (rect.height - gap) / 2
        for (index, half) in halves.enumerated() {
            let area = CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * (height + gap), width: rect.width, height: height)
            let local = FigureContext(page: context.page, machine: context.machine, parameters: half, lookup: context.lookup)
            if envelopes[index] {
                let inner = area.insetBy(dx: 0, dy: 4)
                envelope(&figure, local, EnvelopeParts(attack: local.p("ATK"), hold: local.p("HOLD"), decay: local.p("DEC"),
                                                       sustain: local.p("SUS"), release: local.p("REL"), end: local.p("END"),
                                                       peak: local.p("LEV")), in: inner, peakFloor: 0.05)
            } else {
                append(&figure, bars(local, area, slots: index * 4..<(index * 4 + 4)))
            }
        }
        return figure
    }

    /// One vertical level per knob A–H, aligned like a mixer.
    static func bars(_ context: FigureContext, _ rect: CGRect, slots: Range<Int> = 0..<8) -> Figure {
        var figure = Figure()
        let columns = CGFloat(slots.count)
        let column = rect.width / columns
        let plot = CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: rect.height - 22)
        for slot in slots {
            let x = rect.minX + column * (CGFloat(slot - slots.lowerBound) + 0.5)
            guard let parameter = context.parameters.first(where: { $0.slot == slot }) else {
                figure.guide(FigureMath.line(CGPoint(x: x, y: plot.maxY - 2), CGPoint(x: x, y: plot.maxY + 2)), dash: nil)
                continue
            }
            figure.guide(FigureMath.vertical(x, plot), opacity: 0.9, dash: nil)
            let fraction = context.unit(parameter)
            let bipolar = parameter.format.isBipolar
            let from = bipolar ? plot.midY : plot.maxY
            let to = plot.maxY - plot.height * fraction
            let width = min(14, column * 0.28)
            if case .options(let labels) = parameter.format, labels.count > 1, labels.count <= 16 {
                for index in 0..<labels.count {
                    let y = plot.maxY - plot.height * CGFloat(index) / CGFloat(labels.count - 1)
                    figure.guide(FigureMath.line(CGPoint(x: x - 5, y: y), CGPoint(x: x + 5, y: y)), dash: nil)
                }
            }
            figure.stroke(FigureMath.line(CGPoint(x: x, y: from), CGPoint(x: x, y: to)), context.color(parameter),
                          width: width, known: context.known(parameter), opacity: 0.9)
            figure.mark(parameter.label, CGPoint(x: x, y: rect.maxY - 6), size: 8.5)
            figure.handle(CGPoint(x: x, y: to), y: parameter, ySpan: plot.height, context: context)
        }
        return figure
    }

    static func append(_ figure: inout Figure, _ other: Figure) {
        figure.guides += other.guides
        figure.fills += other.fills
        figure.strokes += other.strokes
        figure.marks += other.marks
        figure.handles += other.handles
    }
}
