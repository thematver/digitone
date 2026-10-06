import SwiftUI
import DigitoneCore
import DigitoneDesign

/// Diagram handles use the same 14-bit values and final-send rule as the dials.
struct ControlFigureView: View {
    @ObservedObject var control: ControlModel

    var body: some View {
        GeometryReader { geometry in
            let context = FigureContext(page: control.page, machine: control.machine, parameters: control.pageParameters, lookup: control.value)
            let rect = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 18, dy: 18)
            let figure = FigureBuilder.build(context, in: rect)
            ZStack(alignment: .topLeading) {
                Canvas { drawing, _ in
                    for fill in figure.fills { drawing.fill(fill.path, with: .color(fill.color.opacity(fill.opacity))) }
                    for stroke in figure.guides + figure.strokes {
                        drawing.stroke(stroke.path, with: .color(stroke.color.opacity(stroke.opacity)),
                                       style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round,
                                                          dash: stroke.dash ?? (stroke.known ? [] : [4, 5])))
                    }
                    for mark in figure.marks {
                        drawing.draw(Text(mark.text).font(.system(size: mark.size, weight: mark.weight, design: .monospaced)).foregroundStyle(mark.color),
                                     at: mark.point, anchor: mark.anchor)
                    }
                }
                ForEach(figure.handles) { handle in
                    ControlFigureHandle(control: control, handle: handle).position(handle.point)
                }
            }.background(InstrumentTheme.paper.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityLabel("Схема параметров \(control.page.title)")
    }
}

private struct ControlFigureHandle: View {
    @ObservedObject var control: ControlModel
    let handle: Figure.Handle
    @State private var startX: Double?
    @State private var startY: Double?

    var body: some View {
        Circle().fill(InstrumentTheme.panel)
            .overlay(Circle().stroke(InstrumentTheme.encoder(handle.slot).opacity(handle.origin == nil ? 0.45 : 1), style: StrokeStyle(lineWidth: 2, dash: handle.origin == nil ? [2, 2] : [])))
            .frame(width: 13, height: 13).padding(8).contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
                if let axis = handle.x {
                    if startX == nil { startX = fraction(axis.parameter) }
                    control.set(axis.parameter, to: axis.parameter.value14(atFraction: (startX ?? 0) + Double(gesture.translation.width / axis.span)))
                }
                if let axis = handle.y {
                    if startY == nil { startY = fraction(axis.parameter) }
                    control.set(axis.parameter, to: axis.parameter.value14(atFraction: (startY ?? 0) - Double(gesture.translation.height / axis.span)))
                }
            }.onEnded { _ in
                if let axis = handle.x { control.endEdit(axis.parameter) }
                if let axis = handle.y { control.endEdit(axis.parameter) }
                startX = nil; startY = nil
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([handle.x?.parameter.name, handle.y?.parameter.name].compactMap { $0 }.joined(separator: ", "))
            .accessibilityValue([handle.x?.parameter, handle.y?.parameter].compactMap { $0 }.map { parameter in
                control.value(parameter).map { parameter.display($0.value) } ?? "Неизвестно"
            }.joined(separator: ", "))
            .accessibilityAdjustableAction { direction in
                guard let parameter = handle.x?.parameter ?? handle.y?.parameter else { return }
                let value = control.value(parameter)?.value ?? parameter.defaultValue14
                control.set(parameter, to: value + (direction == .increment ? 128 : -128)); control.endEdit(parameter)
            }
    }

    private func fraction(_ parameter: DNParameter) -> Double {
        parameter.fraction(of: control.value(parameter)?.value ?? parameter.defaultValue14)
    }
}
