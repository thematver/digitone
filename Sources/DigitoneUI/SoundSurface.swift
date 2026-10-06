import SwiftUI
import DigitoneCore
import DigitoneDesign

struct SoundSurface: View {
    @ObservedObject var model: StudioModel
    var compact: Bool
    @State private var section = "SYN"
    private let pages = ["SYN", "FILTER", "AMP", "FX"]
    private var controls: [ParameterDefinition] {
        switch section {
        case "SYN": Array(model.parameters.prefix(8))
        case "FILTER": model.parameters.filter { $0.section == "FILTER" || $0.section == "FILTER envelope" }
        case "AMP": model.parameters.filter { $0.section == "AMP" }
        default: model.parameters.filter { $0.section == "FX sends" || $0.section == "TRACK" }
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                HStack(spacing: 5) {
                    ForEach(pages, id: \.self) { page in
                        Button { section = page } label: {
                            Text(page).font(.system(size: 10, weight: .semibold, design: .monospaced)).padding(.horizontal, compact ? 10 : 16).padding(.vertical, 10)
                                .background(section == page ? InstrumentTheme.ink : InstrumentTheme.panel, in: Capsule())
                                .foregroundStyle(section == page ? InstrumentTheme.panel : InstrumentTheme.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            InstrumentPanel {
                VStack(spacing: 24) {
                    HStack {
                        Picker("Движок", selection: $model.machine) {
                            ForEach(SynthMachine.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.menu).disabled(model.busy).snapshotControl(model.machine.title)
                        Spacer()
                        Menu {
                            Button("Очистить известные значения") { model.clearCurrentValues() }
                            Button("Применить черновик") { Task { await model.apply() } }.disabled(!model.canApply)
                            Divider()
                            Text("— неизвестно · ○ черновик · ◌ отправлено · ● получено")
                            Text("Движок на приборе выбирается вручную.")
                            Text("Схема иллюстративна, значения — MIDI 0–127.")
                        } label: { Image(systemName: "info.circle").foregroundStyle(InstrumentTheme.secondary) }.snapshotControl("ⓘ", chevron: false)
                    }
                    SoundDrawing(model: model, section: section).frame(height: compact ? 220 : 285)
                    HStack {
                        Text(section == "SYN" ? "СХЕМА ТЕМБРА" : section == "FILTER" ? "СХЕМА ФИЛЬТРА" : section == "AMP" ? "ОГИБАЮЩАЯ" : "ПРОСТРАНСТВО")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(InstrumentTheme.secondary)
                        Spacer()
                        Text("\(model.knownCount) / \(model.parameters.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 12 : 20), count: compact ? 4 : min(8, controls.count)), spacing: 22) {
                ForEach(Array(controls.enumerated()), id: \.element.id) { index, parameter in
                    EncoderControl(model: model, parameter: parameter, index: index)
                }
            }
            if let incoming = model.lastParameterChannel, incoming != model.channel {
                Button("Ручки прибора → MIDI \(incoming + 1)") { model.channel = incoming }
                    .buttonStyle(InstrumentButtonStyle()).font(.system(size: 12))
            }
            HStack {
                Button { Task { await model.apply() } } label: { Label("Применить черновик", systemImage: "arrow.up.right") }
                    .buttonStyle(InstrumentButtonStyle(prominent: true)).disabled(!model.canApply || !model.known.values.contains { $0.origin == .draft })
                Spacer()
                Menu("A / B") {
                    ForEach(["A", "B"], id: \.self) { side in
                        Button("Запомнить \(side)") { model.checkpoint(side) }.disabled(model.known.isEmpty)
                        Button("Открыть \(side)") { model.useCheckpoint(side) }.disabled(!model.hasCheckpoint(side))
                    }
                }.disabled(model.busy).snapshotControl("A / B")
            }
            HStack(spacing: 3) {
                ForEach(0..<8) { key in
                    Button { Task { await model.audition(note: 60 + [0, 2, 4, 5, 7, 9, 11, 12][key]) } } label: {
                        RoundedRectangle(cornerRadius: 7).fill(InstrumentTheme.panel).frame(height: compact ? 50 : 66)
                            .overlay(alignment: .bottom) { Text(["C", "D", "E", "F", "G", "A", "B", "C"][key]).font(.system(size: 9, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary).padding(.bottom, 8) }
                    }.buttonStyle(.plain).disabled(!model.connected || model.busy).accessibilityLabel("Прослушать MIDI-ноту \(60 + [0, 2, 4, 5, 7, 9, 11, 12][key])")
                }
            }
        }
    }
}

private struct EncoderControl: View {
    @ObservedObject var model: StudioModel
    let parameter: ParameterDefinition
    let index: Int
    @State private var dragValue: Int?
    private var known: KnownParameter? { model.known[parameter.id] }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(InstrumentTheme.line, style: StrokeStyle(lineWidth: 3, dash: known == nil ? [3, 3] : []))
                Circle().trim(from: 0, to: Double(known?.value ?? 0) / 127 * 0.78)
                    .stroke(InstrumentTheme.encoder(index), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(130))
                VStack(spacing: 3) {
                    Text(known.map { "\($0.value)" } ?? "—").font(.system(size: 16, weight: .medium, design: .monospaced))
                    Circle().fill(known?.origin == .received ? InstrumentTheme.encoder(index) : .clear)
                        .frame(width: 4, height: 4).overlay(Circle().stroke(InstrumentTheme.secondary, lineWidth: 1))
                }
            }.frame(width: 53, height: 53)
                .contentShape(Circle()).gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    if dragValue == nil { dragValue = known?.value ?? 0 }
                    model.change(parameter, to: (dragValue ?? 0) - Int(gesture.translation.height / 1.5))
                }.onEnded { _ in dragValue = nil })
                .accessibilityElement(children: .ignore).accessibilityLabel(parameter.title)
                .accessibilityValue(known.map { "\($0.value), \($0.origin.rawValue)" } ?? "Неизвестно")
                .accessibilityAdjustableAction { direction in model.change(parameter, to: (known?.value ?? 0) + (direction == .increment ? 1 : -1)) }
            Text(parameter.title).font(.system(size: 10)).multilineTextAlignment(.center).lineLimit(2).frame(height: 27, alignment: .top)
        }.frame(maxWidth: .infinity).help(parameter.detail)
    }
}

private struct SoundDrawing: View {
    @ObservedObject var model: StudioModel
    let section: String
    private func normalized(_ id: String) -> Double { Double(model.known[id]?.value ?? 0) / 127 }
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, size in
                var grid = Path()
                for i in 0...8 { let x = CGFloat(i) * size.width / 8; grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
                for i in 0...4 { let y = CGFloat(i) * size.height / 4; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(grid, with: .color(InstrumentTheme.line.opacity(0.45)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 5]))
                var path = Path()
                if section == "FILTER" {
                    let cutoff = 0.15 + normalized("filter.frequency") * 0.7
                    for i in 0...240 {
                        let x = Double(i) / 240
                        let y = 0.76 - 0.52 / (1 + exp((x - cutoff) * 22))
                        if i == 0 { path.move(to: CGPoint(x: x * size.width, y: y * size.height)) }
                        else { path.addLine(to: CGPoint(x: x * size.width, y: y * size.height)) }
                    }
                } else if section == "AMP" {
                    let a = 0.06 + normalized("amp.attack") * 0.24
                    let d = a + 0.08 + normalized("amp.decay") * 0.2
                    let s = 0.84 - normalized("amp.sustain") * 0.7
                    let points = [CGPoint(x: 0, y: size.height * 0.84), CGPoint(x: a * size.width, y: size.height * 0.14), CGPoint(x: d * size.width, y: s * size.height), CGPoint(x: size.width * 0.7, y: s * size.height), CGPoint(x: size.width, y: size.height * 0.84)]
                    path.addLines(points)
                } else {
                    let harmonics = 1 + normalized("syn.1.e") * 4
                    let feedback = normalized("syn.1.g")
                    for i in 0...360 {
                        let x = Double(i) / 360
                        let y = 0.5 - (sin(x * .pi * 6 + sin(x * .pi * 6 * harmonics) * feedback * 2) * 0.24)
                        if i == 0 { path.move(to: CGPoint(x: x * size.width, y: y * size.height)) }
                        else { path.addLine(to: CGPoint(x: x * size.width, y: y * size.height)) }
                    }
                }
                let hasValue = model.known.keys.contains { section == "AMP" ? $0.hasPrefix("amp.") : section == "FILTER" ? $0.hasPrefix("filter.") : $0.hasPrefix("syn.") }
                context.stroke(path, with: .color(InstrumentTheme.green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: hasValue ? [] : [7, 6]))
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                if section == "FILTER", let cutoff = model.parameters.first(where: { $0.id == "filter.frequency" }) {
                    let fraction = (gesture.location.x / max(1, size.width) - 0.15) / 0.7
                    model.change(cutoff, to: Int(min(1, max(0, fraction)) * 127))
                }
            })
            if section == "FILTER" {
                Circle().fill(InstrumentTheme.orange).frame(width: 14, height: 14)
                    .position(x: size.width * (0.15 + normalized("filter.frequency") * 0.7), y: size.height / 2)
                    .allowsHitTesting(false)
            }
        }.accessibilityLabel(section == "FILTER" ? "Схема фильтра, регулируется перетаскиванием" : "Иллюстративная схема тембра")
    }
}
