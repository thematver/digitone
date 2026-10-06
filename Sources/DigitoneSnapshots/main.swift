import SwiftUI
import DigitoneDesign
import DigitoneUI
#if os(macOS)
import AppKit

/// Renders every registered screen state to PNG.
/// Usage: DigitoneSnapshots OUTPUT_DIR [NAME_FILTER]
@MainActor
func renderSnapshots() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let output = URL(fileURLWithPath: arguments.first ?? "build/snapshots", isDirectory: true)
    let filter = arguments.dropFirst().first?.lowercased()
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let scenes = StudioSnapshots.scenes().filter { filter == nil || $0.id.lowercased().contains(filter!) }
    for scene in scenes {
        let content = scene.view
            .frame(width: scene.device.size.width, height: scene.device.size.height)
            .environment(\.isSnapshotRendering, true)
            .environment(\.colorScheme, scene.colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scene.device == .phone ? 2 : 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("FAILED \(scene.id)")
            continue
        }
        let url = output.appendingPathComponent("\(scene.id).png")
        try png.write(to: url)
        print(url.path)
    }
    print("\(scenes.count) scenes")
}

do { try MainActor.assumeIsolated { try renderSnapshots() } }
catch { print("Error: \(error)"); exit(1) }
#else
print("Snapshots render on macOS only.")
#endif
