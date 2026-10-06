import SwiftUI
import DigitoneDesign
import DigitoneCore
import DigitoneDSP

/// Registry of screen states rendered by the DigitoneSnapshots tool.
public enum StudioSnapshots {
    @MainActor public static func scenes() -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        for device in [SnapshotScene.Device.mac, .phone] {
            for scheme in [ColorScheme.light, .dark] {
                for mode in InstrumentMode.allCases {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-preview-unwritten-\(UUID())")
                    let model = StudioModel(directory: directory, startMIDI: false)
                    let workspace = WorkspaceModel(directory: directory, startAudio: false)
                    model.values[model.route] = ["syn.1.e": KnownParameter(value: 56, origin: .draft), "syn.1.g": KnownParameter(value: 48, origin: .draft),
                                               "filter.frequency": KnownParameter(value: 74, origin: .draft)]
                    for (index, name) in ["Soft glass", "Sunday bass", "Paper bells", "Little swarm", "Warm current", "After hours"].enumerated() {
                        model.snapshots.append(SoundSnapshot(name: name, machine: SynthMachine.allCases[index % 4], channel: 0,
                                                            parameters: ["syn.1.e": 56, "syn.1.g": 48, "filter.frequency": 74], tags: [index % 2 == 0 ? "soft" : "bass"], isFavorite: index == 0))
                    }
                    workspace.sequence.name = "Sunday sketch"
                    workspace.sequence.lanes[0].notes = [SequenceNote(pitch: 60, start: 0, duration: 48), SequenceNote(pitch: 64, start: 48, duration: 24), SequenceNote(pitch: 67, start: 96, duration: 48), SequenceNote(pitch: 64, start: 168, duration: 24), SequenceNote(pitch: 62, start: 216, duration: 48), SequenceNote(pitch: 57, start: 288, duration: 72)]
                    workspace.sample = demoBuffer()
                    workspace.sampleName = "Демо · перкуссия"
                    workspace.samplePeaks = WaveformPeaks.compute(workspace.sample!.channels[0], bins: 240).map { .init(low: $0.min, high: $0.max) }
                    workspace.chop(16)
                    scenes.append(SnapshotScene(mode.id.rawValue, device: device, colorScheme: scheme) { StudioView(model: model, workspace: workspace, mode: mode) })
                }
            }
        }
        // Extra states owned by individual surfaces (focused states, overlays).
        scenes += NotesSurfaceSnapshots.scenes() + ControlSurfaceSnapshots.scenes() + MonitorControlSnapshots.scenes()
        return scenes
    }

    static func demoBuffer() -> SampleBuffer {
        let rate = 48_000.0
        let frames = 96_000
        let audio: [Float] = (0..<frames).map { index in
            let phase = Double(index % 12_000) / rate
            let pitch = 85 + 260 * exp(-phase * 60)
            return Float((sin(2 * .pi * pitch * phase) + sin(2 * .pi * 1_470 * phase) * 0.12) * exp(-phase * 20) * 0.7)
        }
        return SampleBuffer(sampleRate: rate, channels: [audio])
    }
}
