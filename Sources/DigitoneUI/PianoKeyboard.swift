import SwiftUI
import DigitoneDesign

/// Who is sounding a key; drawn in different colors.
enum PianoKeyLight: Int, Comparable {
    case playback, incoming, pressed
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var color: Color {
        switch self {
        case .pressed: InstrumentTheme.blue
        case .incoming: InstrumentTheme.green
        case .playback: InstrumentTheme.orange
        }
    }
}

/// A vertical piano whose keys line up with the grid rows: black keys fill
/// their row on the back part of the keyboard, white keys reach the grid and
/// meet their neighbours in the middle of the black rows, as on a real piano.
struct PianoKeyboardLayout: Equatable {
    var width: CGFloat
    var blackRatio: CGFloat = 0.6
    var blackWidth: CGFloat { (width * blackRatio).rounded() }

    func pitch(at point: CGPoint, geometry: PianoRollGeometry) -> Int {
        let pitch = geometry.pitch(atY: point.y)
        guard PianoRollNames.isBlack(pitch), point.x > blackWidth else { return pitch }
        let middle = geometry.rowTop(pitch) + geometry.rowHeight / 2
        return min(127, max(0, point.y < middle ? pitch + 1 : pitch - 1))
    }

    /// Top and bottom of a white key.
    func whiteSpan(_ pitch: Int, geometry: PianoRollGeometry) -> (top: CGFloat, bottom: CGFloat) {
        let rowTop = geometry.rowTop(pitch), height = geometry.rowHeight
        let top = pitch < 127 && PianoRollNames.isBlack(pitch + 1) ? rowTop - height / 2 : rowTop
        let bottom = pitch > 0 && PianoRollNames.isBlack(pitch - 1) ? rowTop + height * 1.5 : rowTop + height
        return (top, bottom)
    }
}

struct PianoKeyboardView: View {
    var geometry: PianoRollGeometry
    var width: CGFloat
    var lit: [Int: PianoKeyLight]
    var compact: Bool
    /// Pitch of the A key when the computer keyboard plays; letters are drawn on the keys it reaches.
    var typingBase: Int? = nil
    var interactionDisabled = false
    /// Current pitch under the pointer while pressed; nil on release.
    var onPlay: (Int?) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var current: Int?

    private static let letters: [String] = ["A", "W", "S", "E", "D", "F", "T", "G", "Y", "H", "U", "J", "K", "O", "L", "P", ";", "'"]

    /// Musical-typing letters on the keys they play, plus a thin bracket for the range.
    private func drawTypingLetters(_ context: GraphicsContext, base: Int, layout: PianoKeyboardLayout) {
        let top = geometry.rowTop(min(127, base + Self.letters.count - 1))
        let bottom = geometry.rowTop(base) + geometry.rowHeight
        context.fill(Path(roundedRect: CGRect(x: 0, y: top + 1, width: 2.5, height: max(0, bottom - top - 2)), cornerRadius: 1.25),
                     with: .color(InstrumentTheme.blue.opacity(0.75)))
        guard geometry.rowHeight >= 11 else { return }
        for (offset, letter) in Self.letters.enumerated() where base + offset <= 127 {
            let pitch = base + offset
            let y = geometry.rowTop(pitch) + geometry.rowHeight / 2
            let black = PianoRollNames.isBlack(pitch)
            let color: Color = lit[pitch] != nil ? (black ? .black.opacity(0.7) : InstrumentTheme.panel)
                : (black ? Color.white.opacity(0.62) : InstrumentTheme.blue)
            let text = Text(letter).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(color)
            context.draw(text, at: CGPoint(x: black ? layout.blackWidth - 8 : layout.blackWidth + 8, y: y), anchor: .center)
        }
    }

    var body: some View {
        Canvas { context, size in
            let layout = PianoKeyboardLayout(width: size.width)
            let dark = scheme == .dark
            let white = Color(hex: dark ? 0x3A403D : 0xFDFCF9)
            let whiteEdge = Color(hex: dark ? 0x1B1F1E : 0xCFD1C8)
            let black = Color(hex: dark ? 0x0B0D0D : 0x2B302C)
            let pitches = geometry.visiblePitches
            let low = max(0, pitches.lowerBound - 1), high = min(127, pitches.upperBound + 1)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(white))
            for pitch in low...high where !PianoRollNames.isBlack(pitch) {
                let span = layout.whiteSpan(pitch, geometry: geometry)
                let rect = CGRect(x: 0, y: span.top, width: size.width, height: span.bottom - span.top)
                if let light = lit[pitch] {
                    context.fill(Path(rect.insetBy(dx: 0, dy: 0.5)), with: .color(light.color.opacity(0.85)))
                }
                var edge = Path()
                edge.move(to: CGPoint(x: 0, y: span.bottom)); edge.addLine(to: CGPoint(x: size.width, y: span.bottom))
                context.stroke(edge, with: .color(whiteEdge), lineWidth: 1)
                if pitch % 12 == 0 || (lit[pitch] != nil && geometry.rowHeight >= 12) {
                    let label = Text(PianoRollNames.name(pitch))
                        .font(.system(size: compact ? 8 : 9, weight: pitch % 12 == 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(lit[pitch] != nil ? InstrumentTheme.panel : InstrumentTheme.secondary)
                    context.draw(label, at: CGPoint(x: size.width - 4, y: geometry.rowTop(pitch) + geometry.rowHeight / 2), anchor: .trailing)
                }
            }
            for pitch in low...high where PianoRollNames.isBlack(pitch) {
                let rect = CGRect(x: 0, y: geometry.rowTop(pitch) + 0.5, width: layout.blackWidth, height: geometry.rowHeight - 1)
                let shape = Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(bottomTrailing: 2.5, topTrailing: 2.5))
                context.fill(shape, with: .color(black))
                if let light = lit[pitch] {
                    context.fill(Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadii: RectangleCornerRadii(bottomTrailing: 2, topTrailing: 2)),
                                 with: .color(light.color))
                }
            }
            if let typingBase { drawTypingLetters(context, base: typingBase, layout: layout) }
            var divider = Path()
            divider.move(to: CGPoint(x: size.width - 0.5, y: 0)); divider.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
            context.stroke(divider, with: .color(InstrumentTheme.line), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            guard !interactionDisabled else { return }
            let pitch = PianoKeyboardLayout(width: width).pitch(at: value.location, geometry: geometry)
            guard pitch != current else { return }
            current = pitch
            onPlay(pitch)
        }.onEnded { _ in
            current = nil
            onPlay(nil)
        })
        .onChange(of: interactionDisabled) { _, disabled in
            if disabled, current != nil { current = nil; onPlay(nil) }
        }
        .accessibilityElement()
        .accessibilityLabel("Клавиатура")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

}

/// Fixed sizes of the roll per idiom.
struct PianoRollMetrics {
    var keyboard: CGFloat
    var ruler: CGFloat
    var velocity: CGFloat
    var grid: CGFloat
    var rowHeight: CGFloat

    static let regular = PianoRollMetrics(keyboard: 76, ruler: 28, velocity: 74, grid: 378, rowHeight: 14)
    static let compact = PianoRollMetrics(keyboard: 46, ruler: 26, velocity: 58, grid: 352, rowHeight: 20)
}
