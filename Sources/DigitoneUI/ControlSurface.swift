import SwiftUI
import DigitoneCore
import DigitoneDesign

/// The track and FX controls share one model with the transport and setup sheet.
struct ControlSurface: View {
    @ObservedObject var model: StudioModel
    @ObservedObject private var control: ControlModel
    var compact: Bool
    var showTracks: Bool
    @State private var showFigure = false

    @MainActor init(model: StudioModel, compact: Bool, showTracks: Bool = true) {
        self.model = model
        self.compact = compact
        self.showTracks = showTracks
        _control = ObservedObject(wrappedValue: ControlModel.attached(to: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showTracks { ControlTrackStrip(control: control, compact: compact) }
            InstrumentPanel {
                VStack(alignment: .leading, spacing: 16) {
                    editorHeader
                    ControlPageSelector(control: control)
                    HStack(alignment: .center, spacing: 12) {
                        Text(control.page.editorTitle).font(.system(size: 18, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(control.page.title).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(InstrumentTheme.secondary)
                    }
                    parameterGrid
                    if control.pageParameters.isEmpty {
                        Text("На этой странице нет доступных MIDI-параметров.")
                            .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                    }
                    draftActions
                    valueLegend
                    DisclosureGroup("Схема страницы · иллюстрация", isExpanded: $showFigure) {
                        ControlFigureView(control: control).frame(height: compact ? 120 : 140).padding(.top, 8)
                    }.font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                }
            }
            DeviceAuditionKeyboard(control: control, compact: compact)
        }
        .onDisappear { control.releaseKeys(); control.flushAll() }
    }

    private var parameterGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 2 : 4), spacing: 10) {
            ForEach(control.pageParameters) { parameter in
                ControlParameterCard(control: control, parameter: parameter)
            }
        }
    }

    private var editorHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) { editorContext; Spacer(minLength: 0); starterMenu }
            VStack(alignment: .leading, spacing: 10) { editorContext; starterMenu }
        }
    }

    private var editorContext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(control.page.isGlobal ? "ОБЩИЕ ЭФФЕКТЫ" : "ТРЕК \(control.selectedTrack + 1) · \(control.machine.title)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(InstrumentTheme.ink)
            Text((control.page.isGlobal ? "FX CONTROL CH " : "MIDI-канал ") + (control.channel(for: control.page).map { String($0 + 1) } ?? "OFF"))
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
        }
    }

    private var starterMenu: some View {
        Menu {
            ForEach(SoundStarter.all) { starter in
                Button("\(starter.title) · \(starter.machine.title)") {
                    control.stageSound(starter)
                    model.notice = "«\(starter.title)» открыт как частичный черновик. Выбери \(starter.machine.title) на приборе, затем примени параметры. Остальные параметры не заменены."
                }
            }
        } label: { Label("Начать со звука", systemImage: "sparkles") }
            .font(.system(size: 12, weight: .medium)).disabled(model.busy || control.isApplying)
            .snapshotControl("Начать со звука")
            .help("Добавляет основу тембра локально. Передача в Digitone — по кнопке «Применить».")
    }

    private var draftActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            if control.draftCount > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { applyButton; draftExplanation }
                    VStack(alignment: .leading, spacing: 8) { applyButton; draftExplanation }
                }
            }
            if !control.canSend {
                Label("Без прибора можно создавать и сохранять черновики. Подключи Digitone II для прослушивания и отправки.", systemImage: "pencil.and.outline")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            } else if control.channel(for: control.page) == nil {
                Label(control.page.isGlobal ? "FX CONTROL CH выключен. Укажи его в подключении для отправки эффектов." : "MIDI-канал трека выключен. Черновик доступен; для отправки укажи канал трека.", systemImage: "cable.connector")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.orange).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ручки меняют подключённый прибор сразу. Для текущих значений поверни энкодеры на Digitone.")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if control.machine == .midi && !control.page.isGlobal {
                Text("MIDI-трек управляет внешним инструментом; в библиотеку звуков сохраняются аудиотреки.")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
            }
        }
    }

    private var applyButton: some View {
        Button { Task { await control.applyDrafts() } } label: {
            Label(control.isApplying ? "Отправляем…" : "Применить \(control.draftCount) параметров", systemImage: "arrow.up.right")
        }.buttonStyle(InstrumentButtonStyle(prominent: true)).disabled(!control.canApplyDrafts)
    }

    private var draftExplanation: some View {
        Text(control.page.isGlobal ? "Черновик общих эффектов. Отправка в FX CONTROL CH." : "Черновик трека \(control.selectedTrack + 1). Изменит текущий звук.")
            .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var valueLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { originLabels }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) { ControlOriginLabel(origin: nil, text: "Неизвестно"); ControlOriginLabel(origin: .received, text: "С прибора") }
                HStack(spacing: 12) { ControlOriginLabel(origin: .sent, text: "Отправлено"); ControlOriginLabel(origin: .draft, text: "Черновик") }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originLabels: some View {
        Group {
            ControlOriginLabel(origin: nil, text: "Неизвестно")
            ControlOriginLabel(origin: .received, text: "С прибора")
            ControlOriginLabel(origin: .sent, text: "Отправлено")
            ControlOriginLabel(origin: .draft, text: "Черновик")
        }
    }
}

private struct ControlTrackStrip: View {
    @ObservedObject var control: ControlModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ВЫБЕРИ ТРЕК").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(InstrumentTheme.secondary)
                Spacer()
                Text("\(control.selectedTrack + 1) / 16").font(.system(size: 11, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: compact ? 4 : 8), spacing: 6) {
                ForEach(0..<ControlModel.trackCount, id: \.self) { track in
                    Button { control.selectTrack(track) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(String(format: "%02d", track + 1)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Spacer(minLength: 2)
                                if control.mute(track: track)?.value == true { Image(systemName: "speaker.slash.fill").font(.system(size: 9)) }
                            }
                            Text(trackName(track)).font(.system(size: 9, weight: .medium, design: .monospaced)).lineLimit(1)
                            Text(control.channelMap.channel(forTrack: track).map { "CH \($0 + 1)" } ?? "CH OFF")
                                .font(.system(size: 9, design: .monospaced)).opacity(0.7)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .foregroundStyle(control.selectedTrack == track ? InstrumentTheme.panel : InstrumentTheme.ink)
                            .background(control.selectedTrack == track ? InstrumentTheme.ink : InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(InstrumentTheme.line.opacity(control.selectedTrack == track ? 0 : 1), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(control.isApplying)
                        .accessibilityLabel("Трек \(track + 1), \(trackName(track)), MIDI-канал \(control.channelMap.channel(forTrack: track).map { String($0 + 1) } ?? "выключен")")
                        .accessibilityValue(control.mute(track: track).map { $0.value ? "Выключен" : "Играет" } ?? "Mute неизвестен")
                        .accessibilityAddTraits(control.selectedTrack == track ? .isSelected : [])
                        .contextMenu {
                            Button(control.mute(track: track)?.value == true ? "Включить трек" : "Выключить трек") { control.toggleMute(track: track) }
                                .disabled(!control.canMute(track: track))
                        }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { machinePicker; Spacer(minLength: 0); muteButton }
                VStack(alignment: .leading, spacing: 10) { machinePicker; muteButton }
            }
            Text("Машина — описание трека в приложении. Она должна совпадать с SYN machine на Digitone.")
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var machinePicker: some View {
        HStack(spacing: 8) {
            Text("Машина трека \(control.selectedTrack + 1)").font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
            Picker("Машина трека", selection: Binding(get: { control.machine }, set: { control.setMachine($0, track: control.selectedTrack) })) {
                ForEach(DNMachine.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).labelsHidden().snapshotControl(control.machine.title).disabled(control.isApplying)
        }
    }

    private var muteButton: some View {
        HStack(spacing: 8) {
            if control.mute(track: control.selectedTrack) == nil {
                Text("Mute —").font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
            }
            Button { control.toggleMute(track: control.selectedTrack) } label: {
                Label(control.mute(track: control.selectedTrack)?.value == true ? "Включить трек" : "Выключить трек", systemImage: control.mute(track: control.selectedTrack)?.value == true ? "speaker.wave.2" : "speaker.slash")
            }.buttonStyle(InstrumentButtonStyle()).disabled(!control.canMute(track: control.selectedTrack) || control.isApplying)
        }
    }

    private func trackName(_ track: Int) -> String {
        if control.trackNames.indices.contains(track), !control.trackNames[track].isEmpty { return control.trackNames[track] }
        return control.machines[track].title
    }
}

private struct ControlPageSelector: View {
    @ObservedObject var control: ControlModel
    @State private var showGlobal = false
    private var visiblePages: [DNPage] {
        if showGlobal { return control.globalPages }
        let order: [DNPage] = [.syn1, .syn2, .syn3, .syn4, .fltr1, .fltr2, .amp, .fx, .mod1, .mod2, .mod3, .trig, .track, .sequencer]
        return order.filter { control.pages.contains($0) }
    }
    private var groups: [String] { visiblePages.reduce(into: []) { if !$0.contains($1.group) { $0.append($1.group) } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                scopeButton("Звук трека", global: false)
                scopeButton("Общие FX", global: true)
                Spacer(minLength: 0)
            }
            DSScroll(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(groups, id: \.self) { group in
                        Button {
                            let members = visiblePages.filter { $0.group == group }
                            if let page = members.first { control.select(page: page) }
                        } label: {
                            let selected = control.page.group == group && control.page.isGlobal == showGlobal
                            Text(visiblePages.first { $0.group == group }?.editorGroupTitle ?? group)
                                .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(selected ? InstrumentTheme.panel : InstrumentTheme.ink)
                                .background(selected ? InstrumentTheme.ink : InstrumentTheme.paper, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(control.page.group == group ? .isSelected : [])
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }.frame(height: 34)
            let members = visiblePages.filter { $0.group == control.page.group }
            if members.count > 1 {
                HStack(spacing: 7) {
                    ForEach(members) { page in
                        Button { control.select(page: page) } label: {
                            Text(page.title).font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(control.page == page ? InstrumentTheme.green : InstrumentTheme.secondary)
                                .overlay(Capsule().stroke(control.page == page ? InstrumentTheme.green : InstrumentTheme.line, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityAddTraits(control.page == page ? .isSelected : [])
                    }
                }
            }
        }.disabled(control.isApplying)
            .onAppear { showGlobal = control.page.isGlobal }
            .onChange(of: control.page) { _, page in showGlobal = page.isGlobal }
    }

    private func scopeButton(_ title: String, global: Bool) -> some View {
        Button {
            showGlobal = global
            if control.page.isGlobal != global, let page = (global ? control.globalPages : visiblePages).first { control.select(page: page) }
        } label: {
            Text(title).font(.system(size: 12, weight: showGlobal == global ? .semibold : .regular))
                .foregroundStyle(showGlobal == global ? InstrumentTheme.ink : InstrumentTheme.secondary)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) { if showGlobal == global { Rectangle().fill(InstrumentTheme.green).frame(height: 2) } }
        }.buttonStyle(.plain).accessibilityAddTraits(showGlobal == global ? .isSelected : [])
    }
}

struct ControlOriginLabel: View {
    var origin: ControlOrigin?
    var text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(origin == .received ? InstrumentTheme.green : origin == .sent ? InstrumentTheme.orange : origin == .draft ? InstrumentTheme.blue : InstrumentTheme.line).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
        }
    }
}

private struct ControlParameterCard: View {
    @ObservedObject var control: ControlModel
    let parameter: DNParameter
    @State private var numericEditor = false
    @Environment(\.isSnapshotRendering) private var snapshot
    private var observed: ControlValue? { control.value(parameter) }
    private var value: Int { observed?.value ?? parameter.defaultValue14 }
    private var color: Color { InstrumentTheme.encoder(parameter.slot) }
    private var step: Int { parameter.isHighResolution ? 1 : 128 }
    private var originTitle: String { observed?.origin == .received ? "С прибора" : observed?.origin == .sent ? "Отправлено" : observed?.origin == .draft ? "Черновик" : "Неизвестно" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parameter.knobLetter).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                Text(parameter.label).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer(minLength: 0)
                Button { control.reset(parameter) } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(InstrumentTheme.secondary)
                    .accessibilityLabel("Начальное значение: \(parameter.editorTitle)").help("Начальное значение каталога; не чтение с Digitone")
            }
            Text(parameter.editorTitle).font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                .lineLimit(2).frame(height: 30, alignment: .top)
            HStack(spacing: 5) {
                Button { adjust(-step) } label: { Image(systemName: "minus").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Уменьшить \(parameter.editorTitle)")
                Button { numericEditor = true } label: {
                    Text(observed.map { parameter.display($0.value) } ?? "—")
                        .font(.system(size: 18, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }.buttonStyle(.plain).accessibilityLabel("Ввести значение: \(parameter.editorTitle)")
                    .popover(isPresented: $numericEditor) { ControlValueEntry(control: control, parameter: parameter).padding(18) }
                Button { adjust(step) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Увеличить \(parameter.editorTitle)")
            }
            parameterInput.frame(height: 20)
            ControlOriginLabel(origin: observed?.origin, text: originTitle)
        }.padding(12).frame(maxWidth: .infinity)
            .background(InstrumentTheme.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(InstrumentTheme.line, lineWidth: 1))
            .disabled(!control.canEdit(parameter.page))
            .help("\(parameter.name) · \(parameter.page.title) · \(parameter.nrpn.map { "NRPN \($0)" } ?? parameter.cc.map { "CC \($0)" } ?? "MIDI")")
    }

    @ViewBuilder private var parameterInput: some View {
        if parameter.format.isToggle {
            HStack(spacing: 6) {
                toggleOption("OFF", value: 0)
                toggleOption("ON", value: 127 << 7)
            }
        } else if case .options(let options) = parameter.format, options.count <= 16 {
            Picker(parameter.editorTitle, selection: Binding(get: { observed.map { DNParameter.coarse($0.value) } ?? -1 }, set: { amount in
                guard amount >= 0 else { return }
                control.set(parameter, to: amount << 7); control.endEdit(parameter)
            })) {
                if observed == nil { Text("Выбери значение").tag(-1) }
                ForEach(Array(options.enumerated()), id: \.offset) { index, title in Text(title).tag(index) }
            }.pickerStyle(.menu).labelsHidden().snapshotControl(observed.map { parameter.display($0.value) } ?? "Выбери значение")
        } else {
            if snapshot {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(InstrumentTheme.line).frame(height: 3)
                        if let observed {
                            Capsule().fill(color).frame(width: geometry.size.width * parameter.fraction(of: observed.value), height: 3)
                            Circle().fill(color).frame(width: 10, height: 10).offset(x: (geometry.size.width - 10) * parameter.fraction(of: observed.value))
                        }
                    }.frame(height: 20)
                }
            } else {
                Slider(value: Binding(get: { parameter.fraction(of: value) }, set: { control.set(parameter, to: parameter.value14(atFraction: $0)) }),
                       in: 0...1, onEditingChanged: { editing in if !editing { control.endEdit(parameter) } })
                    .tint(observed == nil ? InstrumentTheme.secondary : color).opacity(observed == nil ? 0.5 : 1)
                    .accessibilityLabel(parameter.editorTitle).accessibilityValue(observed.map { parameter.display($0.value) } ?? "Неизвестно")
            }
        }
    }

    private func toggleOption(_ title: String, value: Int) -> some View {
        Button { control.set(parameter, to: value); control.endEdit(parameter) } label: {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .foregroundStyle(observed.map { ($0.value > 0) == (value > 0) } == true ? InstrumentTheme.panel : InstrumentTheme.secondary)
                .background(observed.map { ($0.value > 0) == (value > 0) } == true ? InstrumentTheme.ink : InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    private func adjust(_ amount: Int) { control.set(parameter, to: value + amount); control.endEdit(parameter) }
}

/// Precise entry uses the published MIDI value, avoiding invented time/frequency conversions.
private struct ControlValueEntry: View {
    @ObservedObject var control: ControlModel
    let parameter: DNParameter
    @Environment(\.dismiss) private var dismiss
    @State private var entered = ""

    private var parsed: Int? {
        guard let value = Double(entered.replacingOccurrences(of: ",", with: ".")), value.isFinite,
              value >= Double(parameter.rawRange.lowerBound), value <= Double(parameter.rawRange.upperBound) + (parameter.isHighResolution ? 127.0 / 128 : 0) else { return nil }
        return parameter.isHighResolution ? Int((value * 128).rounded()) : Int(value.rounded()) << 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(parameter.editorTitle).font(.system(size: 16, weight: .semibold))
            Text("Значение MIDI: \(parameter.rawRange.lowerBound)…\(parameter.rawRange.upperBound)\(parameter.isHighResolution ? " · шаг 1/128" : "")")
                .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
            TextField("Значение MIDI", text: $entered).textFieldStyle(.roundedBorder).onSubmit { commit() }
                .accessibilityLabel("Числовое значение MIDI")
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(InstrumentButtonStyle())
                Button("Задать") { commit() }.buttonStyle(InstrumentButtonStyle(prominent: true)).disabled(parsed == nil)
            }
        }.frame(width: 260).onAppear {
            if let value = control.value(parameter)?.value { entered = parameter.isHighResolution ? String(format: "%.5f", Double(value) / 128) : String(DNParameter.coarse(value)) }
        }
    }

    private func commit() {
        guard let value = parsed else { return }
        control.set(parameter, to: value)
        control.endEdit(parameter)
        dismiss()
    }
}

/// The device sequencer's transport, separate from playback of the app's note sketch.
struct DeviceTransportBar: View {
    @ObservedObject private var control: ControlModel
    var compact: Bool
    @State private var patterns = false

    @MainActor init(model: StudioModel, compact: Bool) {
        self.compact = compact
        _control = ObservedObject(wrappedValue: ControlModel.attached(to: model))
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            if !compact { Text("DN").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary) }
            Button { patterns = true } label: {
                HStack(spacing: 4) {
                    Circle().fill(control.program?.origin == .received ? InstrumentTheme.green : control.program?.origin == .sent ? InstrumentTheme.orange : InstrumentTheme.line).frame(width: 4, height: 4)
                    Text(control.program.map { PatternSnapshot.slotName($0.value) } ?? "— —").font(.system(size: 12, weight: .medium, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }.buttonStyle(.plain).accessibilityLabel("Выбрать паттерн на Digitone")
                .popover(isPresented: $patterns) { DevicePatternSelector(control: control).padding(20) }
            if !compact {
                Text(control.tempo.map { String(format: "%.1f", $0) } ?? "— BPM")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary).frame(minWidth: 44)
            }
            Button { control.togglePlay() } label: {
                Image(systemName: control.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10)).frame(width: 28, height: 28)
                    .background(control.isPlaying ? InstrumentTheme.green : InstrumentTheme.paper, in: Circle())
                    .foregroundStyle(control.isPlaying ? InstrumentTheme.panel : InstrumentTheme.ink)
            }.buttonStyle(.plain).disabled(!control.canSend).accessibilityLabel(control.isPlaying ? "Остановить Digitone" : "Запустить Digitone")
            Button { control.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 9)).frame(width: 22, height: 28) }
                .buttonStyle(.plain).disabled(!control.canSend).accessibilityLabel("Стоп Digitone")
        }.foregroundStyle(InstrumentTheme.ink)
    }
}

struct DevicePatternSelector: View {
    @ObservedObject var control: ControlModel
    @State private var bank: Int

    init(control: ControlModel) {
        self.control = control
        _bank = State(initialValue: (control.program?.value ?? 0) / 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Паттерн Digitone").font(.system(size: 20, weight: .medium, design: .rounded))
            HStack(spacing: 5) {
                ForEach(0..<8, id: \.self) { index in
                    Button { bank = index } label: {
                        Text(String(UnicodeScalar(65 + index)!)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 29, height: 29).background(bank == index ? InstrumentTheme.ink : InstrumentTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(bank == index ? InstrumentTheme.panel : InstrumentTheme.ink)
                    }.buttonStyle(.plain).accessibilityAddTraits(bank == index ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                ForEach(0..<16, id: \.self) { index in
                    let program = ControlEncoding.program(bank: bank, pattern: index)
                    Button { control.selectPattern(program) } label: {
                        Text(PatternSnapshot.slotName(program)).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(control.program?.value == program ? InstrumentTheme.green : InstrumentTheme.paper, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(control.program?.value == program ? InstrumentTheme.panel : InstrumentTheme.ink)
                    }.buttonStyle(.plain).disabled(!control.canSend)
                }
            }
            if let program = control.program {
                ControlOriginLabel(origin: program.origin, text: program.origin == .received ? "Паттерн получен с прибора" : "Запрошен \(PatternSnapshot.slotName(program.value))")
            }
            Text("PROGRAM CHG IN CH: \(control.channelMap.effectiveProgramChangeChannel + 1) · PRG CH RECEIVE → ON\nПри воспроизведении прибор может сменить паттерн на границе цикла.")
                .font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(width: 275).foregroundStyle(InstrumentTheme.ink).background(InstrumentTheme.panel)
            .onAppear { bank = (control.program?.value ?? 0) / 16 }
    }
}

private struct DeviceAuditionKeyboard: View {
    @ObservedObject var control: ControlModel
    var compact: Bool
    @State private var velocity = 100.0
    @Environment(\.isSnapshotRendering) private var snapshot
    private let offsets = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
    private let black = [1, 3, 6, 8, 10, 13, 15, 18, 20, 22]

    var body: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("ПРОСЛУШАТЬ ТРЕК \(control.selectedTrack + 1)").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1)
                    Spacer()
                    Button { control.releaseKeys(); control.keyboardBase -= 12 } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).disabled(control.keyboardBase == 0).accessibilityLabel("Октава ниже")
                    Text(FigureMath.noteName(control.keyboardBase)).font(.system(size: 11, design: .monospaced))
                    Button { control.releaseKeys(); control.keyboardBase += 12 } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).disabled(control.keyboardBase == 96).accessibilityLabel("Октава выше")
                }
                GeometryReader { geometry in
                    let width = geometry.size.width / 14
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 2) {
                            ForEach(offsets, id: \.self) { offset in
                                DeviceAuditionKey(control: control, note: control.keyboardBase + offset, velocity: Int(velocity), black: false)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        ForEach(black, id: \.self) { offset in
                            let whiteBefore = offsets.filter { $0 < offset }.count
                            DeviceAuditionKey(control: control, note: control.keyboardBase + offset, velocity: Int(velocity), black: true)
                                .frame(width: width * 0.58, height: 65).offset(x: width * CGFloat(whiteBefore) - width * 0.29)
                        }
                    }
                }.frame(height: 100).opacity(control.canSend && control.keyboardChannel != nil ? 1 : 0.45)
                HStack(spacing: 10) {
                    Text("VEL").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                    Group {
                        if snapshot {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(InstrumentTheme.line).frame(height: 3)
                                    Capsule().fill(InstrumentTheme.green).frame(width: geometry.size.width * (velocity - 1) / 126, height: 3)
                                    Circle().fill(InstrumentTheme.green).frame(width: 10, height: 10).offset(x: geometry.size.width * (velocity - 1) / 126 - 5)
                                }.frame(height: 20)
                            }.frame(height: 20)
                        } else { Slider(value: $velocity, in: 1...127, step: 1) }
                    }.frame(maxWidth: compact ? 120 : 180)
                    Text("\(Int(velocity))").font(.system(size: 10, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                    Spacer()
                    Button("Отпустить ноты") { control.releaseKeys() }.font(.system(size: 10)).buttonStyle(.plain)
                }
            }
        }.onDisappear { control.releaseKeys() }
    }
}

private struct DeviceAuditionKey: View {
    @ObservedObject var control: ControlModel
    var note: Int
    var velocity: Int
    var black: Bool
    @State private var pressed = false
    private var sounding: Bool { control.heldNotes.contains(note) || control.incomingNotes.contains(note) }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5).fill(sounding ? InstrumentTheme.green : black ? Color(red: 0.12, green: 0.14, blue: 0.13) : Color(red: 0.96, green: 0.96, blue: 0.93))
            if note % 12 == 0 { Text(FigureMath.noteName(note)).font(.system(size: 8, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary).padding(.bottom, 9) }
        }.overlay(RoundedRectangle(cornerRadius: 5).stroke(InstrumentTheme.line, lineWidth: black ? 0 : 1))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                guard !pressed else { return }
                pressed = true; control.noteOn(note, velocity: velocity)
            }.onEnded { _ in pressed = false; control.noteOff(note) })
            .accessibilityLabel(FigureMath.noteName(note))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                control.noteOn(note, velocity: velocity)
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(180)); control.noteOff(note) }
            }
            .onChange(of: note) { old, _ in if pressed { control.noteOff(old); pressed = false } }
            .onDisappear { if pressed { control.noteOff(note); pressed = false } }
    }
}

/// Additional connected, unknown and FX states rendered without hardware output.
enum ControlSurfaceSnapshots {
    @MainActor static func scenes() -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        for device in [SnapshotScene.Device.mac, .phone] {
            for scheme in [ColorScheme.light, .dark] {
                for page in [DNPage.syn1, .fltr1, .mod1, .delay] {
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-control-preview-\(UUID())")
                    let studio = StudioModel(directory: directory, startMIDI: false)
                    let control = ControlModel(output: SilentControlOutput(), defaults: nil)
                    control.setFXChannel(15)
                    control.select(page: page)
                    if page != .syn1 {
                        for parameter in control.pageParameters {
                            control.set(parameter, to: parameter.value14(atFraction: parameter.slot.isMultiple(of: 2) ? 0.68 : 0.34))
                            control.endEdit(parameter)
                        }
                    }
                    ControlModel.attach(control, to: studio)
                    scenes.append(SnapshotScene("control-\(page.rawValue)", device: device, colorScheme: scheme) {
                        DSScroll { VStack(alignment: .leading, spacing: 20) {
                            HStack { Text("Digitone II").font(.system(size: 24, weight: .medium, design: .rounded)); Spacer(); DeviceTransportBar(model: studio, compact: device == .phone) }
                            ControlSurface(model: studio, compact: device == .phone, showTracks: device != .phone)
                        }.padding(device == .phone ? 20 : 36) }.background(InstrumentTheme.paper).foregroundStyle(InstrumentTheme.ink)
                    })
                }
            }
        }
        for device in [SnapshotScene.Device.mac, .phone] {
            for scheme in [ColorScheme.light, .dark] {
                let control = ControlModel(output: SilentControlOutput(), defaults: nil)
                control.selectPattern(127)
                control.noteOn(48, velocity: 100)
                control.noteOn(52, velocity: 100)
                control.noteOn(55, velocity: 100)
                scenes.append(SnapshotScene("control-keyboard", device: device, colorScheme: scheme) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Прослушать трек").font(.system(size: 28, weight: .medium, design: .rounded))
                        DeviceAuditionKeyboard(control: control, compact: device == .phone)
                        Spacer(minLength: 0)
                    }.padding(device == .phone ? 20 : 36).background(InstrumentTheme.paper).foregroundStyle(InstrumentTheme.ink)
                })
                scenes.append(SnapshotScene("control-patterns", device: device, colorScheme: scheme) {
                    VStack {
                        DevicePatternSelector(control: control).padding(24)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity).padding(.top, 20).background(InstrumentTheme.paper)
                })
            }
        }
        return scenes
    }
}
