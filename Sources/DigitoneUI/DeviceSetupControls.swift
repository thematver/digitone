import SwiftUI
import DigitoneCore
import DigitoneDesign

/// These settings describe the unit's MIDI configuration; changing them updates routing in the app.
struct DeviceSetupControls: View {
    @ObservedObject var control: ControlModel
    @State private var showTracks = false
    private let checks: [(String, String, String)] = [
        ("ports.usb", "USB MIDI", "USB CONFIG → USB MIDI или USB AUDIO/MIDI · INPUT/OUTPUT FROM → USB"),
        ("receive.notes", "Ноты и параметры", "RECEIVE NOTES и RECEIVE CC/NRPN → ON"),
        ("feedback.parameters", "Ручки на приборе", "ENCODER DEST → INT+EXT · PARAM OUTPUT → CC или NRPN"),
        ("sync.transport", "Транспорт", "TRANSPORT RECEIVE → ON · TRANSPORT SEND → ON для обратной связи"),
        ("sync.program", "Паттерны", "PRG CH RECEIVE → ON · PRG CH SEND → ON для обратной связи"),
        ("sync.clock", "Темп", "CLOCK SEND → ON, чтобы видеть темп и позицию прибора")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("НАСТРОЙКИ НА ПРИБОРЕ").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
            ForEach(checks, id: \.0) { id, title, detail in
                Button { control.toggleCheck(id) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: control.setupChecks.contains(id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(control.setupChecks.contains(id) ? InstrumentTheme.green : InstrumentTheme.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.system(size: 12, weight: .medium))
                            Text(detail).font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain).accessibilityAddTraits(control.setupChecks.contains(id) ? .isSelected : [])
            }
            if control.feedbackSeen {
                Label("Параметры с прибора получены", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(InstrumentTheme.green)
            }
            Picker("OUTPUT CH на приборе", selection: $control.inputRouting) {
                ForEach(ControlInputRouting.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("AUTO CH: входящие ручки относятся к выбранному здесь треку. TRK CH: к треку с этим MIDI-каналом. FX CONTROL CH имеет приоритет для общих эффектов.")
                .font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("MIDI CONFIG → CHANNELS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
            Text("Укажи те же каналы, что на Digitone. Эти поля меняют маршрутизацию приложения.")
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            channelPicker("Трек \(control.selectedTrack + 1)", value: control.channelMap.channel(forTrack: control.selectedTrack), automatic: "OFF") {
                control.setTrackChannel($0, track: control.selectedTrack)
            }
            channelPicker("FX CONTROL CH", value: control.channelMap.fxControlChannel, automatic: "OFF", setter: control.setFXChannel)
            Picker("AUTO CHANNEL", selection: Binding(get: { control.channelMap.autoChannel }, set: control.setAutoChannel)) {
                ForEach(0..<16, id: \.self) { Text(String($0 + 1)).tag($0) }
            }
            channelPicker("PROGRAM CHG IN CH", value: control.channelMap.programChangeChannel, automatic: "AUTO", setter: control.setProgramChannel)
            DisclosureGroup("Все 16 треков", isExpanded: $showTracks) {
                VStack(spacing: 9) {
                    ForEach(0..<16, id: \.self) { track in
                        channelPicker("Трек \(track + 1)", value: control.channelMap.channel(forTrack: track), automatic: "OFF") {
                            control.setTrackChannel($0, track: track)
                        }
                    }
                }.padding(.top, 10)
            }.font(.system(size: 12))
            Button("Сбросить каналы приложения") { control.resetChannels() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(InstrumentTheme.secondary)
            Text("Машины и каналы выбираются вручную: MIDI не сообщает их назначение. Подписи списков и схемы основаны на руководстве OS 1.12; значение MIDI показано отдельно. Отметки выше — твой чеклист, подтверждение передачи видно у каждого параметра.")
                .font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func channelPicker(_ label: String, value: Int?, automatic: String, setter: @escaping (Int?) -> Void) -> some View {
        Picker(label, selection: Binding<Int>(get: { value ?? -1 }, set: { setter($0 < 0 ? nil : $0) })) {
            Text(automatic).tag(-1)
            ForEach(0..<16, id: \.self) { Text(String($0 + 1)).tag($0) }
        }
    }
}
