import SwiftUI

public enum InstrumentTheme {
    public static let paper = Color(light: 0xECEBE6, dark: 0x111313)
    public static let panel = Color(light: 0xF8F7F3, dark: 0x1D2020)
    public static let ink = Color(light: 0x242925, dark: 0xF2F1EB)
    public static let secondary = Color(light: 0x74796F, dark: 0x929A92)
    public static let line = Color(light: 0xD6D8CF, dark: 0x353B36)
    public static let green = Color(light: 0x347A54, dark: 0x83C59A)
    public static let orange = Color(light: 0xD9773C, dark: 0xF1A66F)
    public static let blue = Color(light: 0x496FA3, dark: 0x8CAFE5)
    public static let record = Color(light: 0xC14F45, dark: 0xF07E72)
    public static func encoder(_ index: Int) -> Color {
        switch index % 4 { case 0: blue; case 1: green; case 2: ink; default: orange }
    }
}

public struct InstrumentPanel<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(InstrumentTheme.line.opacity(0.7), lineWidth: 1))
    }
}

public struct InstrumentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    public var prominent: Bool
    public init(prominent: Bool = false) { self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(prominent ? InstrumentTheme.green : InstrumentTheme.panel, in: Capsule())
            .foregroundStyle(prominent ? InstrumentTheme.panel : InstrumentTheme.ink)
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

private struct RenderSafeControl: ViewModifier {
    @Environment(\.isSnapshotRendering) private var snapshot
    let title: String
    let chevron: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if snapshot {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12))
                if chevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
            }.foregroundStyle(InstrumentTheme.ink).fixedSize()
        } else { content }
    }
}

extension View {
    /// Native menu/picker controls are not drawn by ImageRenderer. A static
    /// label substitutes only in exported visual-review images.
    public func snapshotControl(_ title: String, chevron: Bool = true) -> some View {
        modifier(RenderSafeControl(title: title, chevron: chevron))
    }
}

public struct WaveformDrawing: View {
    public var peaks: [PeakPoint]
    public var color: Color
    public var cuts: [Double]
    public init(peaks: [PeakPoint], color: Color = InstrumentTheme.green, cuts: [Double] = []) {
        self.peaks = peaks; self.color = color; self.cuts = cuts
    }
    public struct PeakPoint: Sendable { public let low: Float; public let high: Float
        public init(low: Float, high: Float) { self.low = low; self.high = high }
    }
    public var body: some View {
        Canvas { context, size in
            var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: size.height / 2)); baseline.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(baseline, with: .color(InstrumentTheme.line), lineWidth: 1)
            var bars = Path()
            for (index, peak) in peaks.enumerated() {
                let x = (Double(index) + 0.5) / Double(max(1, peaks.count)) * size.width
                bars.move(to: CGPoint(x: x, y: size.height / 2 - CGFloat(peak.high) * size.height * 0.44))
                bars.addLine(to: CGPoint(x: x, y: size.height / 2 - CGFloat(peak.low) * size.height * 0.44))
            }
            context.stroke(bars, with: .color(color), style: StrokeStyle(lineWidth: max(1, size.width / CGFloat(max(1, peaks.count)) * 0.6), lineCap: .round))
            for cut in cuts {
                var line = Path(); line.move(to: CGPoint(x: cut * size.width, y: 0)); line.addLine(to: CGPoint(x: cut * size.width, y: size.height))
                context.stroke(line, with: .color(InstrumentTheme.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }.accessibilityLabel(peaks.isEmpty ? "Аудио ещё не загружено" : "Волна аудио")
    }
}
