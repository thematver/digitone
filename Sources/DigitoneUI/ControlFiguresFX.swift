import SwiftUI
import DigitoneCore
import DigitoneDesign

// Drawings for TRIG, FX, MOD and the global FX/mixer pages.
extension FigureBuilder {
    // MARK: FX (track)

    /// Bit reduction + sample-rate reduction on a sine, the overdrive transfer curve and the three sends.
    static func effects(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        let bits = context.p("BR"), rate = context.p("SRR"), drive = context.p("OVER", "OD")
        let sends = [context.p("DEL"), context.p("REV"), context.p("CHR", "CHO")].compactMap { $0 }
        guard bits != nil || rate != nil || drive != nil || !sends.isEmpty else { return nil }
        var figure = Figure()
        let wave = CGRect(x: rect.minX, y: rect.minY + 10, width: rect.width * 0.44, height: rect.height - 20)
        let curveSide = min(rect.height - 20, rect.width * 0.22)
        let curve = CGRect(x: rect.minX + rect.width * 0.5, y: rect.midY - curveSide / 2, width: curveSide, height: curveSide)
        let sendRect = CGRect(x: rect.minX + rect.width * 0.78, y: rect.minY + 10, width: rect.width * 0.22, height: rect.height - 10)

        let reduction = context.unit(bits, 0), downsample = context.unit(rate, 0)
        let levels = reduction < 0.01 ? 0.0 : max(1, pow(2, 1 + (1 - reduction) * 5).rounded())
        let samples = downsample < 0.01 ? 0.0 : max(3, (60 * pow(1 - downsample, 1.6)).rounded() + 3)
        figure.guide(FigureMath.horizontal(wave.midY, wave))
        figure.stroke(FigureMath.curve(in: wave, samples: 200) { 0.5 + 0.42 * sin(2 * .pi * 2 * $0) }, InstrumentTheme.line, width: 1.2)
        let crushed = FigureMath.curve(in: wave, samples: 480) { x in
            let held = samples > 0 ? (x * samples).rounded(.down) / samples : x
            var value = sin(2 * .pi * 2 * held)
            if levels > 0 { value = (value * levels).rounded() / levels }
            return 0.5 + 0.42 * value
        }
        figure.stroke(crushed, context.color(bits ?? rate), width: 2.2, known: context.known(bits, rate))
        if let bits {
            let y = wave.maxY - wave.height * (0.08 + 0.84 * (1 - context.unit(bits, 0)))
            figure.handle(CGPoint(x: wave.minX - 2, y: y), y: bits, ySpan: -wave.height * 0.84, context: context)
        }
        if let rate {
            figure.handle(CGPoint(x: wave.minX + wave.width * (0.1 + 0.8 * downsample), y: wave.maxY + 4), x: rate,
                          xSpan: wave.width * 0.8, context: context)
        }

        if let drive {
            let amount = 0.3 + context.unit(drive, 0) * 7
            figure.guide(Path(roundedRect: curve, cornerRadius: 2), dash: nil)
            figure.guide(FigureMath.line(CGPoint(x: curve.minX, y: curve.maxY), CGPoint(x: curve.maxX, y: curve.minY)))
            let transfer = FigureMath.curve(in: curve) { x in 0.5 + 0.5 * tanh(amount * (x * 2 - 1)) / tanh(amount) }
            figure.stroke(transfer, context.color(drive), width: 2.4, known: context.known(drive))
            let knee = 0.72
            let y = 0.5 + 0.5 * tanh(amount * (knee * 2 - 1)) / tanh(amount)
            figure.handle(CGPoint(x: curve.minX + curve.width * knee, y: curve.maxY - curve.height * y), y: drive,
                          ySpan: curve.height * 0.5, context: context)
        }

        sendBars(&figure, context, sends, in: sendRect)
        return figure
    }

    /// Small vertical send levels with their labels under them.
    static func sendBars(_ figure: inout Figure, _ context: FigureContext, _ sends: [DNParameter], in rect: CGRect) {
        guard !sends.isEmpty else { return }
        let plot = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 22)
        let column = rect.width / CGFloat(sends.count)
        for (index, parameter) in sends.enumerated() {
            let x = rect.minX + column * (CGFloat(index) + 0.5)
            figure.guide(FigureMath.vertical(x, plot), dash: nil)
            let top = plot.maxY - plot.height * context.unit(parameter, 0)
            figure.stroke(FigureMath.line(CGPoint(x: x, y: plot.maxY), CGPoint(x: x, y: top)), context.color(parameter),
                          width: min(12, column * 0.3), known: context.known(parameter))
            figure.mark(parameter.label, CGPoint(x: x, y: rect.maxY - 6), size: 8.5)
            figure.handle(CGPoint(x: x, y: top), y: parameter, ySpan: plot.height, context: context)
        }
    }

    // MARK: MOD (LFO)

    static func lfo(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        let speed = context.p("SPD"), depth = context.p("DEP", "DEPTH")
        guard speed != nil || depth != nil else { return nil }
        var figure = Figure()
        let plot = rect.insetBy(dx: 0, dy: 14)
        for step in 0...16 {
            let x = plot.minX + plot.width * CGFloat(step) / 16
            figure.guide(FigureMath.vertical(x, plot), opacity: step % 4 == 0 ? 1 : 0.45, dash: step % 4 == 0 ? nil : [1, 4])
        }
        figure.guide(FigureMath.horizontal(plot.midY, plot), dash: nil)

        let shape = context.text(context.p("WAVE", "WAV")) ?? "SIN"
        let mode = context.text(context.p("MODE")) ?? "FREE"
        let rawSpeed = context.number(speed) ?? context.bipolar(speed) * 64
        let multiplier = max(0.0001, context.number(context.p("MULT")) ?? 1)
        let cycles = min(16, abs(rawSpeed) * multiplier / 128)
        let reverse = rawSpeed < 0
        let phase = context.unit(context.p("SPH"), 0)
        let amount = context.bipolar(depth)
        let fade = context.bipolar(context.p("FADE"))
        let fadeLength = 0.05 + (1 - abs(fade)) * 2
        let stopAt = mode.contains("ONE") ? 1.0 : mode.contains("HALF") ? 0.5 : .infinity
        func wave(_ p: Double, cycle: Int) -> Double {
            if shape.contains("TRI") { return p < 0.25 ? 4 * p : p < 0.75 ? 2 - 4 * p : 4 * p - 4 }
            if shape.contains("SQ") { return p < 0.5 ? 1 : -1 }
            if shape.contains("SAW") { return 1 - 2 * p }
            if shape.contains("EXP") { return exp(-5 * p) }
            if shape.contains("RMP") || shape.contains("RAMP") { return p }
            if shape.contains("RND") || shape.contains("RAND") { return FigureMath.noise(cycle * 7 + Int(p * 4)) * 2 - 1 }
            return sin(2 * .pi * p)
        }
        func value(_ x: Double) -> Double {
            var position = min(x * cycles, stopAt) + phase
            if reverse { position = -position }
            let cycle = Int(position.rounded(.down))
            let p = position - position.rounded(.down)
            let envelope = fade > 0.01 ? max(0, 1 - x / fadeLength) : fade < -0.01 ? min(1, x / fadeLength) : 1
            return wave(p, cycle: cycle) * amount * envelope
        }
        if abs(fade) > 0.01 {
            let fadeParameter = context.p("FADE")
            let envelope = FigureMath.curve(in: plot) { x in
                0.5 + 0.46 * abs(amount) * (fade > 0 ? max(0, 1 - x / fadeLength) : min(1, x / fadeLength))
            }
            figure.stroke(envelope, context.color(fadeParameter), width: 1.2, known: context.known(fadeParameter), opacity: 0.8, dash: [3, 4])
        }
        let path = FigureMath.curve(in: plot, samples: 600) { 0.5 + 0.46 * value($0) }
        figure.stroke(path, context.color(context.p("WAVE", "WAV") ?? speed), width: 2.4,
                      known: context.known(speed, depth, context.p("WAVE", "WAV")))
        if let destination = context.text(context.p("DEST")) {
            figure.mark("→ \(destination)", CGPoint(x: plot.minX, y: rect.minY + 2), anchor: .topLeading, color: InstrumentTheme.ink, size: 10, weight: .semibold)
        }
        if let depth {
            let probe = (0...200).map { Double($0) / 200 * min(1, 1 / max(cycles, 0.0001)) }
            let peakX = probe.max { abs(value($0)) < abs(value($1)) } ?? 0.25
            let height = plot.height * 0.46
            figure.handle(CGPoint(x: plot.minX + plot.width * peakX, y: plot.midY - height * value(peakX)),
                          y: depth, ySpan: height * 2 * (value(peakX) >= 0 ? 1 : -1) * (amount >= 0 ? 1 : -1), context: context)
        }
        return figure
    }

    // MARK: TRIG

    static func trig(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        let noteParameter = context.p("NOTE"), velocity = context.p("VEL", "VELO"), length = context.p("LEN")
        guard noteParameter != nil || velocity != nil || length != nil else { return nil }
        var figure = Figure()
        let keys = CGRect(x: rect.minX, y: rect.minY + 6, width: 34, height: rect.height * 0.56)
        let lane = CGRect(x: rect.minX + 52, y: rect.minY + 6, width: rect.width - 52, height: rect.height * 0.56)
        let velocityLane = CGRect(x: lane.minX, y: lane.maxY + 16, width: lane.width, height: rect.maxY - lane.maxY - 22)

        let note = context.text(noteParameter).flatMap(FigureMath.note(in:)) ?? 60
        let rows = 12
        let row = keys.height / CGFloat(rows)
        for index in 0..<rows {
            let pitch = rows - 1 - index
            let black = [1, 3, 6, 8, 10].contains(pitch)
            let key = CGRect(x: keys.minX, y: keys.minY + CGFloat(index) * row, width: black ? keys.width * 0.6 : keys.width, height: row - 1)
            figure.fills.append(Figure.Fill(path: Path(roundedRect: key, cornerRadius: 2), color: black ? InstrumentTheme.ink : InstrumentTheme.line,
                                            opacity: black ? 0.55 : 0.6))
            if pitch == note % 12 {
                figure.fills.append(Figure.Fill(path: Path(roundedRect: key, cornerRadius: 2), color: context.color(noteParameter), opacity: 1))
            }
        }
        figure.mark(FigureMath.noteName(note), CGPoint(x: keys.midX, y: keys.maxY + 10), color: InstrumentTheme.ink, size: 10, weight: .semibold)

        let step = lane.width / 16
        for index in 0...16 {
            figure.guide(FigureMath.vertical(lane.minX + step * CGFloat(index), lane), opacity: index % 4 == 0 ? 1 : 0.5,
                         dash: index % 4 == 0 ? nil : [1, 4])
        }
        let lengthText = context.text(length) ?? ""
        let infinite = lengthText.contains("INF")
        let steps: Double
        if infinite { steps = 16 }
        else if lengthText.contains("/"), let value = FigureMath.number(in: lengthText) { steps = min(16, max(0.125, value * 16)) }
        else { steps = 0.25 + context.unit(length, 0.06) * 15.75 }
        let probability = context.number(context.p("PROB")).map { min(100, max(0, $0)) / 100 } ?? 1
        let block = CGRect(x: lane.minX + 1, y: lane.midY - 9, width: max(4, step * CGFloat(steps) - 2), height: 18)
        figure.fills.append(Figure.Fill(path: Path(roundedRect: block, cornerRadius: 4), color: context.color(length),
                                        opacity: 0.2 + 0.7 * context.unit(velocity, 0.8) * probability))
        figure.stroke(Path(roundedRect: block, cornerRadius: 4), context.color(length), width: 1.4, known: context.known(length))
        if infinite { figure.mark("→", CGPoint(x: block.maxX - 8, y: block.midY), color: InstrumentTheme.panel, size: 11, weight: .bold) }
        if probability < 1 {
            figure.mark("\(Int((probability * 100).rounded()))%", CGPoint(x: block.minX + 4, y: block.minY - 9), anchor: .leading, size: 9)
        }
        figure.handle(CGPoint(x: block.maxX, y: block.midY), x: length, xSpan: lane.width, context: context)

        if let velocity {
            let level = context.unit(velocity, 0.8)
            figure.guide(FigureMath.horizontal(velocityLane.maxY, velocityLane), dash: nil)
            let x = velocityLane.minX + 6
            let top = velocityLane.maxY - velocityLane.height * level
            figure.stroke(FigureMath.line(CGPoint(x: x, y: velocityLane.maxY), CGPoint(x: x, y: top)), context.color(velocity),
                          width: 3, known: context.known(velocity))
            figure.handle(CGPoint(x: x, y: top), y: velocity, ySpan: velocityLane.height, context: context)
        }
        return figure
    }

    // MARK: DELAY

    static func delay(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard let time = context.p("TIME") else { return nil }
        var figure = Figure()
        let feedback = context.p("FDBK", "FB")
        let pingPong = context.text(context.p("X")).map { $0.contains("ON") } ?? false
        let width = context.bipolar(context.p("WID", "WIDTH"))
        let hpf = context.p("HPF"), lpf = context.p("LPF")
        let hasFilter = hpf != nil || lpf != nil
        let plot = CGRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: rect.height - (hasFilter ? 40 : 12))
        let center = pingPong ? plot.midY : plot.maxY
        let reach = pingPong ? plot.height * 0.46 : plot.height * 0.92
        figure.guide(FigureMath.horizontal(center, plot), dash: nil)
        for beat in 1..<8 { figure.guide(FigureMath.vertical(plot.minX + plot.width * CGFloat(beat) / 8, plot), opacity: beat % 4 == 0 ? 1 : 0.5) }

        let interval = plot.width * CGFloat(Double(DNParameter.coarse(context.value14(time)) + 1) / 256)
        let gain = min(1.05, context.unit(feedback, 0.4) * 1.1)
        figure.stroke(FigureMath.line(CGPoint(x: plot.minX, y: center), CGPoint(x: plot.minX, y: center - reach)), InstrumentTheme.ink, width: 3)
        var amplitude = 1.0
        var firstTap: CGPoint?
        for tap in 1...32 {
            let x = plot.minX + interval * CGFloat(tap)
            guard x <= plot.maxX, amplitude > 0.02 else { break }
            if tap > 1 { amplitude *= gain }
            let side: CGFloat = pingPong && tap % 2 == 0 ? -1 : 1
            let spread = pingPong ? 0.45 + 0.55 * abs(width) : 1
            let top = CGPoint(x: x, y: center - side * reach * CGFloat(min(1, amplitude) * spread))
            let parameter = tap == 1 ? time : feedback
            figure.stroke(FigureMath.line(CGPoint(x: x, y: center), top), context.color(parameter), width: 2.6,
                          known: context.known(parameter), opacity: tap == 1 ? 1 : max(0.25, min(1, amplitude)))
            if tap == 1 { firstTap = top }
        }
        if let firstTap {
            figure.handle(firstTap, x: time, xSpan: plot.width * 127 / 256, y: feedback, ySpan: reach * 0.9, context: context, role: ".tap")
        }
        if hasFilter { filterStrip(&figure, context, high: hpf, low: lpf, shelf: nil, gain: nil, in: CGRect(x: rect.minX, y: rect.maxY - 22, width: rect.width, height: 18)) }
        return figure
    }

    /// A small spectrum: HPF rising edge, LPF falling edge and an optional high shelf.
    static func filterStrip(_ figure: inout Figure, _ context: FigureContext, high: DNParameter?, low: DNParameter?,
                            shelf: DNParameter?, gain: DNParameter?, in rect: CGRect) {
        let hp = context.unit(high, 0), lp = context.unit(low, 1)
        let shelfAt = context.unit(shelf, 0.7), shelfGain = context.unit(gain, 1)
        func level(_ x: Double) -> Double {
            var value = high == nil ? 1 : 1 / (1 + exp(-(x - hp) * 40))
            if low != nil { value *= 1 / (1 + exp((x - lp) * 40)) }
            if shelf != nil { value *= 1 - (1 - shelfGain) * 0.6 / (1 + exp(-(x - shelfAt) * 30)) }
            return value
        }
        figure.guide(FigureMath.horizontal(rect.maxY, rect), dash: nil)
        figure.stroke(FigureMath.curve(in: rect, samples: 160, level), InstrumentTheme.ink, width: 1.6,
                      known: context.known(high) || context.known(low), opacity: 0.85)
        if let high { figure.handle(CGPoint(x: rect.minX + rect.width * hp, y: rect.midY), x: high, xSpan: rect.width, context: context) }
        if let low { figure.handle(CGPoint(x: rect.minX + rect.width * lp, y: rect.midY), x: low, xSpan: rect.width, context: context) }
        if let shelf {
            figure.handle(CGPoint(x: rect.minX + rect.width * shelfAt, y: rect.maxY - rect.height * level(min(1, shelfAt + 0.08))),
                          x: shelf, xSpan: rect.width, y: gain, ySpan: rect.height * 0.6, context: context)
        }
    }

    // MARK: REVERB

    static func reverb(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard let decay = context.p("DEC") else { return nil }
        var figure = Figure()
        let predelay = context.p("PRE")
        let hpf = context.p("HPF"), lpf = context.p("LPF"), shelf = context.p("FREQ"), gain = context.p("GAIN")
        let hasStrip = hpf != nil || lpf != nil || shelf != nil
        let plot = CGRect(x: rect.minX + 6, y: rect.minY + 6, width: rect.width - 12, height: rect.height - (hasStrip ? 46 : 12))
        figure.guide(FigureMath.horizontal(plot.maxY, plot), dash: nil)
        let gapEnd = plot.minX + 4 + plot.width * 0.22 * CGFloat(context.unit(predelay, 0.1))
        let tau = 0.03 + context.unit(decay) * 0.5
        let damping = 0.55 + 0.45 * context.unit(gain, 1)
        figure.stroke(FigureMath.line(CGPoint(x: plot.minX, y: plot.maxY), CGPoint(x: plot.minX, y: plot.minY)), InstrumentTheme.ink, width: 3)
        figure.stroke(FigureMath.line(CGPoint(x: plot.minX, y: plot.maxY + 4), CGPoint(x: gapEnd, y: plot.maxY + 4)), context.color(predelay),
                      width: 2, known: context.known(predelay))
        var hairs = Path()
        let count = 150
        for index in 0..<count {
            let t = Double(index) / Double(count)
            let x = gapEnd + (plot.maxX - gapEnd) * CGFloat(t)
            let envelope = exp(-t / tau) * 0.82 * damping
            let height = plot.height * CGFloat(envelope * (0.35 + 0.65 * FigureMath.noise(index)))
            guard height > 0.5 else { continue }
            hairs.move(to: CGPoint(x: x, y: plot.maxY)); hairs.addLine(to: CGPoint(x: x, y: plot.maxY - height))
        }
        figure.stroke(hairs, InstrumentTheme.ink, width: 1, opacity: 0.35)
        let tailRect = CGRect(x: gapEnd, y: plot.minY, width: plot.maxX - gapEnd, height: plot.height)
        figure.stroke(FigureMath.curve(in: tailRect) { exp(-$0 / tau) * 0.82 * damping }, context.color(decay), width: 2.4,
                      known: context.known(decay))
        let endT = min(1, tau * 3)
        figure.handle(CGPoint(x: tailRect.minX + tailRect.width * CGFloat(endT), y: tailRect.maxY - tailRect.height * CGFloat(exp(-endT / tau) * 0.82 * damping)),
                      x: decay, xSpan: tailRect.width * 1.41, context: context)
        if let predelay { figure.handle(CGPoint(x: gapEnd, y: plot.maxY + 4), x: predelay, xSpan: plot.width * 0.22, context: context) }
        if hasStrip {
            filterStrip(&figure, context, high: hpf, low: lpf, shelf: shelf, gain: gain,
                        in: CGRect(x: rect.minX, y: rect.maxY - 26, width: rect.width, height: 22))
        }
        return figure
    }

    // MARK: CHORUS

    static func chorus(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        let depth = context.p("DPTH", "DEPTH"), speed = context.p("SPD")
        guard depth != nil || speed != nil else { return nil }
        var figure = Figure()
        let sends = [context.p("DEL"), context.p("REV")].compactMap { $0 }
        let plot = CGRect(x: rect.minX, y: rect.minY + 8, width: rect.width * (sends.isEmpty ? 1 : 0.8), height: rect.height - 50)
        let lfoRect = CGRect(x: plot.minX, y: plot.maxY + 14, width: plot.width, height: 28)
        let amount = context.unit(depth, 0.4), rate = context.unit(speed, 0.3)
        let spread = context.unit(context.p("WDTH", "WID", "WIDTH"), 0.5)
        figure.guide(FigureMath.horizontal(plot.midY, plot))
        for voice in 0..<3 {
            let offset = Double(voice - 1) * spread * 0.16
            let path = FigureMath.curve(in: plot, samples: 360) { x in
                let modulation = amount * 1.8 * sin(2 * .pi * (0.6 + rate * 3) * x + Double(voice) * 2.1)
                return 0.5 + offset + 0.3 * sin(2 * .pi * 3 * x + modulation)
            }
            figure.stroke(path, voice == 1 ? InstrumentTheme.ink : context.color(depth), width: voice == 1 ? 2.4 : 1.6,
                          known: context.known(depth, speed), opacity: voice == 1 ? 1 : 0.65)
        }
        figure.guide(FigureMath.horizontal(lfoRect.midY, lfoRect), dash: nil)
        figure.stroke(FigureMath.curve(in: lfoRect, samples: 200) { 0.5 + 0.5 * amount * sin(2 * .pi * (0.6 + rate * 3) * $0) },
                      context.color(speed), width: 1.6, known: context.known(speed))
        let peak = 0.25 / (0.6 + rate * 3)
        figure.handle(CGPoint(x: lfoRect.minX + lfoRect.width * peak, y: lfoRect.midY - lfoRect.height * 0.5 * amount),
                      y: depth, ySpan: lfoRect.height * 0.5, context: context)
        if !sends.isEmpty {
            sendBars(&figure, context, sends, in: CGRect(x: rect.minX + rect.width * 0.84, y: rect.minY + 8, width: rect.width * 0.16, height: rect.height - 8))
        }
        return figure
    }

    // MARK: COMP

    static func compressor(_ context: FigureContext, _ rect: CGRect) -> Figure? {
        guard let threshold = context.p("THR") else { return nil }
        var figure = Figure()
        let side = min(rect.height - 12, rect.width * 0.46)
        let graph = CGRect(x: rect.minX + 4, y: rect.minY + 6, width: side, height: side)
        let time = CGRect(x: graph.maxX + 36, y: graph.minY + side * 0.15, width: rect.maxX - graph.maxX - 40, height: side * 0.7)
        let ratioParameter = context.p("RAT", "RATIO"), makeup = context.p("MUP"), mix = context.p("MIX", "DRY/WET")
        let knee = context.unit(threshold, 0.7)
        let ratio = max(1, context.number(ratioParameter) ?? (1.5 + context.unit(ratioParameter, 0.3) * 18.5))
        let gain = context.unit(makeup, 0) * 0.4
        let wet = context.unit(mix, 1)
        figure.guide(Path(roundedRect: graph, cornerRadius: 2), dash: nil)
        figure.guide(FigureMath.line(CGPoint(x: graph.minX, y: graph.maxY), CGPoint(x: graph.maxX, y: graph.minY)))
        func output(_ x: Double) -> Double {
            let compressed = (x < knee ? x : knee + (x - knee) / ratio) + gain
            return min(1.02, wet * compressed + (1 - wet) * x)
        }
        figure.stroke(FigureMath.curve(in: graph, output), context.color(threshold), width: 2.6,
                      known: context.known(threshold, ratioParameter))
        figure.handle(CGPoint(x: graph.minX + graph.width * knee, y: graph.maxY - graph.height * output(knee)),
                      x: threshold, xSpan: graph.width, context: context)
        if let makeup {
            figure.handle(CGPoint(x: graph.minX + graph.width * 0.12, y: graph.maxY - graph.height * output(0.12)), y: makeup,
                          ySpan: graph.height * 0.4 * wet, context: context)
        }
        if let ratioParameter {
            figure.handle(CGPoint(x: graph.maxX, y: graph.maxY - graph.height * output(1)), y: ratioParameter,
                          ySpan: -graph.height * max(0.05, 1 - knee), context: context)
        }

        let attack = context.p("ATK"), release = context.p("REL")
        let depth = (1 - knee) * (1 - 1 / ratio) * 1.6
        let attackTime = 0.01 + context.unit(attack, 0.2) * 0.15
        let releaseTime = 0.02 + context.unit(release, 0.3) * 0.4
        let burst = (start: 0.12, end: 0.55)
        var input = Path()
        input.move(to: CGPoint(x: time.minX, y: time.maxY))
        input.addLine(to: CGPoint(x: time.minX + time.width * burst.start, y: time.maxY))
        input.addLine(to: CGPoint(x: time.minX + time.width * burst.start, y: time.minY))
        input.addLine(to: CGPoint(x: time.minX + time.width * burst.end, y: time.minY))
        input.addLine(to: CGPoint(x: time.minX + time.width * burst.end, y: time.maxY))
        input.addLine(to: CGPoint(x: time.maxX, y: time.maxY))
        figure.stroke(input, InstrumentTheme.line, width: 1.4, dash: [3, 3])
        let reductionAtEnd = min(1, depth) * (1 - exp(-(burst.end - burst.start) / attackTime))
        func reduction(_ t: Double) -> Double {
            if t < burst.start { return 0 }
            if t < burst.end { return min(1, depth) * (1 - exp(-(t - burst.start) / attackTime)) }
            return reductionAtEnd * exp(-(t - burst.end) / releaseTime)
        }
        let attackRect = CGRect(x: time.minX, y: time.minY, width: time.width * burst.end, height: time.height)
        let releaseRect = CGRect(x: time.minX + time.width * burst.end, y: time.minY, width: time.width * (1 - burst.end), height: time.height)
        figure.stroke(FigureMath.curve(in: attackRect) { 1 - reduction($0 * burst.end) }, context.color(attack), width: 2.2, known: context.known(attack))
        figure.stroke(FigureMath.curve(in: releaseRect) { 1 - reduction(burst.end + $0 * (1 - burst.end)) }, context.color(release), width: 2.2,
                      known: context.known(release))
        figure.mark("GR", CGPoint(x: time.minX - 16, y: time.minY), size: 8)
        return figure
    }
}
