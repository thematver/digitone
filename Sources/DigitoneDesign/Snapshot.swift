import SwiftUI

/// One screen state rendered to PNG by the `DigitoneSnapshots` tool, so a
/// design can be reviewed as an image without launching the app.
public struct SnapshotScene: Identifiable {
    public enum Device: String, Sendable {
        case phone, pad, mac
        public var size: CGSize {
            switch self {
            case .phone: CGSize(width: 393, height: 852)
            case .pad: CGSize(width: 1194, height: 834)
            case .mac: CGSize(width: 1280, height: 820)
            }
        }
    }

    public let name: String
    public let device: Device
    public let colorScheme: ColorScheme
    public let view: AnyView
    public var id: String { "\(name)-\(device.rawValue)-\(colorScheme == .dark ? "dark" : "light")" }

    public init<V: View>(_ name: String, device: Device, colorScheme: ColorScheme = .light, @ViewBuilder view: () -> V) {
        self.name = name
        self.device = device
        self.colorScheme = colorScheme
        self.view = AnyView(view())
    }
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering with `ImageRenderer`. Platform-backed controls and
    /// scroll views do not render there; components use this to substitute
    /// static equivalents.
    public var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

/// A scroll view that renders its content statically (top-aligned, clipped)
/// during snapshot rendering, where ScrollView would draw nothing.
public struct DSScroll<Content: View>: View {
    @Environment(\.isSnapshotRendering) private var snapshot
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: Content

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = false, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        if snapshot {
            GeometryReader { geometry in
                content
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: axes.contains(.vertical))
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
            }
        } else {
            ScrollView(axes, showsIndicators: showsIndicators) { content }
        }
    }
}
