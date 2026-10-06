import SwiftUI
import Combine
import DigitoneAudio
import DigitoneDesign

/// Listen to the USB input through the computer's output, without changing
/// the Digitone's project or MIDI parameters.
struct MonitorControl: View {
    @ObservedObject var workspace: WorkspaceModel
    var compact: Bool
    @State private var expanded = false
    @State private var levels = StereoLevels.silent
    @Environment(\.isSnapshotRendering) private var snapshot
    private let timer = Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()

    private var presentation: MonitorPresentation {
        MonitorPresentation(audio: workspace.audio, levels: levels)
    }

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: presentation.active ? "headphones" : "headphones.circle")
                    .font(.system(size: compact ? 19 : 15))
                if !compact {
                    Text("Слушать").font(.system(size: 12, weight: .medium))
                    MonitorMeter(levels: levels, active: presentation.active).frame(width: 38, height: 13)
                }
            }
            .foregroundStyle(presentation.active ? InstrumentTheme.green : InstrumentTheme.secondary)
            .frame(minWidth: compact ? 30 : nil, minHeight: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Слушать Digitone: \(presentation.status)")
        .help("USB-аудио Digitone через динамики или наушники компьютера")
        .popover(isPresented: $expanded) {
            MonitorSettingsPanel(presentation: presentation,
                                 gain: Binding(get: { Double(workspace.audio?.monitorGain ?? MonitorSettings.defaultGain) },
                                               set: { workspace.audio?.monitorGain = Float($0) }),
                                 toggle: { Task { await workspace.toggleMonitor() } }) {
                routingControls
            }
            .frame(width: 310).padding(20)
            .background(InstrumentTheme.panel)
            .presentationCompactAdaptation(.popover)
        }
        .onReceive(timer) { _ in
            guard !snapshot, let audio = workspace.audio else { return }
            levels = audio.monitorPathLevels()
            if expanded { audio.refreshLatency() }
        }
    }

    @ViewBuilder private var routingControls: some View {
        if let audio = workspace.audio {
            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    Button("Автоматически · Digitone") { Task { await workspace.selectAudioInput(nil) } }
                    ForEach(audio.devices.inputs) { device in
                        Button(device.name) { Task { await workspace.selectAudioInput(device) } }
                    }
                } label: { routeLabel("Вход", audio.inputDevice?.name ?? "Не подключён") }
                .snapshotControl("Вход · \(audio.inputDevice?.name ?? "Не подключён")")
                #if os(macOS)
                Menu {
                    Button("Автоматически · компьютер") { workspace.selectAudioOutput(nil) }
                    ForEach(audio.devices.outputs) { device in
                        Button(device.name) { workspace.selectAudioOutput(device) }
                    }
                } label: { routeLabel("Выход", audio.outputDevice?.name ?? "Не подключён") }
                .snapshotControl("Выход · \(audio.outputDevice?.name ?? "Не подключён")")
                #else
                routeLabel("Выход", audio.outputDevice?.name ?? "Системный маршрут")
                #endif
            }
        }
    }

    private func routeLabel(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(InstrumentTheme.secondary)
            Spacer(minLength: 0)
            Text(value).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }.font(.system(size: 11))
    }
}

private struct MonitorPresentation {
    var enabled = true
    var active = false
    var starting = false
    var block: MonitorBlock? = .noDigitone
    var input = "Digitone II"
    var output = "Динамики MacBook Pro"
    var latency: String?
    var levels = StereoLevels.silent

    init() {}
    @MainActor init(audio: StudioAudioEngine?, levels: StereoLevels) {
        enabled = audio?.isMonitoringInput ?? true
        active = audio?.isMonitorActive ?? false
        starting = audio?.isStarting ?? false
        if let audio { block = audio.monitorBlock } else { block = .noDigitone }
        input = audio?.inputDevice?.name ?? "Не подключён"
        output = audio?.outputDevice?.name ?? "Не подключён"
        latency = audio?.monitorLatency?.label
        self.levels = levels
    }

    var status: String {
        if !enabled { return "Выключено" }
        if starting { return "Подключаем аудио…" }
        switch block {
        case .noDigitone: return "Ждём Digitone"
        case .sameDevice: return "Выберите другой выход"
        case .permissionDenied: return "Нужно разрешение на аудиовход"
        case .noOutput: return "Нет аудиовыхода"
        case nil: return active ? "USB-аудио включено" : "Аудио готово"
        }
    }

    var detail: String {
        if !enabled { return "Включите, чтобы слышать Digitone через компьютер." }
        switch block {
        case .noDigitone: return "Подключите Digitone по USB и выберите USB AUDIO/MIDI в настройках устройства."
        case .sameDevice: return "Вход и выход ведут в Digitone. Выберите динамики или наушники компьютера, чтобы избежать петли звука."
        case .permissionDenied: return "Разрешите Digitone Studio доступ к микрофону в настройках системы: он нужен для USB-аудиовхода."
        case .noOutput: return "Подключите наушники или выберите доступный аудиовыход."
        case nil: return "\(input) → \(output)"
        }
    }
}

private struct MonitorSettingsPanel<Routing: View>: View {
    let presentation: MonitorPresentation
    @Binding var gain: Double
    var toggle: () -> Void
    @ViewBuilder var routing: () -> Routing
    @Environment(\.isSnapshotRendering) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "headphones").font(.system(size: 22))
                    .foregroundStyle(presentation.active ? InstrumentTheme.green : InstrumentTheme.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Слушать Digitone").font(.system(size: 15, weight: .semibold))
                    Text(presentation.status).font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                }
                Spacer(minLength: 0)
                Button(action: toggle) {
                    Text(presentation.enabled ? "Вкл" : "Выкл")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 42, height: 29)
                        .background(presentation.enabled ? InstrumentTheme.green : InstrumentTheme.line, in: Capsule())
                        .foregroundStyle(presentation.enabled ? InstrumentTheme.panel : InstrumentTheme.secondary)
                }.buttonStyle(.plain).disabled(presentation.starting)
                    .accessibilityLabel(presentation.enabled ? "Выключить мониторинг" : "Включить мониторинг")
            }
            Text(presentation.detail).font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            routing()
            Rectangle().fill(InstrumentTheme.line).frame(height: 1)
            HStack {
                Text("Громкость").font(.system(size: 11))
                Spacer()
                Text("\(Int((gain * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
            }
            if snapshot {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(InstrumentTheme.line).frame(height: 3)
                        Capsule().fill(InstrumentTheme.green).frame(width: geometry.size.width * gain, height: 3)
                        Circle().fill(InstrumentTheme.green).frame(width: 12, height: 12).offset(x: max(0, geometry.size.width * gain - 6))
                    }.frame(height: 18)
                }.frame(height: 18)
            } else {
                Slider(value: $gain, in: 0...1).tint(InstrumentTheme.green)
                    .accessibilityLabel("Громкость мониторинга").accessibilityValue("\(Int(gain * 100)) процентов")
            }
            HStack(spacing: 12) {
                Text("L / R").font(.system(size: 9, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                MonitorMeter(levels: presentation.levels, active: presentation.active).frame(height: 17)
                if let latency = presentation.latency {
                    Text(latency).font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                        .fixedSize().help("Оценка задержки входа, буфера и выхода")
                }
            }
        }.foregroundStyle(InstrumentTheme.ink)
    }
}

private struct MonitorMeter: View {
    var levels: StereoLevels
    var active: Bool
    var body: some View {
        Canvas { context, size in
            for (index, channel) in [levels.left, levels.right].enumerated() {
                let y = CGFloat(index) * (size.height / 2 + 1)
                let height = max(2, size.height / 2 - 2)
                let background = CGRect(x: 0, y: y, width: size.width, height: height)
                context.fill(Path(roundedRect: background, cornerRadius: 2), with: .color(InstrumentTheme.line))
                let amplitude = active ? channel.peak : 0
                let width = size.width * CGFloat(ChannelLevel.position(amplitude))
                if width > 0 {
                    let color = amplitude >= 0.98 ? InstrumentTheme.record : InstrumentTheme.green
                    context.fill(Path(roundedRect: CGRect(x: 0, y: y, width: width, height: height), cornerRadius: 2), with: .color(color))
                    let rms = size.width * CGFloat(ChannelLevel.position(channel.rms))
                    context.fill(Path(CGRect(x: 0, y: y, width: rms, height: height)), with: .color(color.opacity(0.65)))
                }
            }
        }
        .accessibilityLabel("Уровень USB-аудио")
        .accessibilityValue(active ? "Левый и правый канал" : "Мониторинг выключен")
    }
}

/// Visual states use values only: no audio units, file writes or permission prompts.
enum MonitorControlSnapshots {
    @MainActor static func scenes() -> [SnapshotScene] {
        var result: [SnapshotScene] = []
        for device in [SnapshotScene.Device.mac, .phone] {
            for scheme in [ColorScheme.light, .dark] {
                for state in ["on", "off", "no-device", "feedback", "permission"] {
                    var presentation = MonitorPresentation()
                    presentation.enabled = state != "off"
                    presentation.active = state == "on"
                    presentation.block = state == "feedback" ? .sameDevice : state == "permission" ? .permissionDenied : state == "no-device" ? .noDigitone : nil
                    if state == "on" {
                        presentation.latency = "≈ 9 мс"
                        presentation.levels = StereoLevels(left: ChannelLevel(peak: 0.56, rms: 0.23), right: ChannelLevel(peak: 0.48, rms: 0.19))
                    }
                    let current = presentation
                    result.append(SnapshotScene("monitor-\(state)", device: device, colorScheme: scheme) {
                        VStack(alignment: .leading, spacing: 28) {
                            Text("USB AUDIO").font(.system(size: 10, design: .monospaced)).tracking(3)
                                .foregroundStyle(InstrumentTheme.secondary)
                            Text("Слушать Digitone").font(.system(size: device == .phone ? 30 : 42, weight: .medium, design: .rounded))
                            MonitorSettingsPanel(presentation: current, gain: .constant(0.8), toggle: {}) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Вход · Digitone II")
                                    Text("Выход · \(state == "feedback" ? "Digitone II" : "Динамики MacBook Pro")")
                                }.font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                            }
                            .padding(22).frame(maxWidth: 354)
                            .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 24))
                            Spacer()
                        }.padding(device == .phone ? 20 : 48)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(InstrumentTheme.paper)
                    })
                }
            }
        }
        return result
    }
}
