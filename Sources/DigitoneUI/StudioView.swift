import SwiftUI
import UniformTypeIdentifiers
import DigitoneCore

private enum StudioPage: String, CaseIterable, Identifiable {
    case sound = "Звук"
    case library = "Библиотека"
    case patterns = "Паттерны"
    case connection = "Подключение"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .sound: "waveform.path"
        case .library: "square.stack.3d.up"
        case .patterns: "square.grid.4x3.fill"
        case .connection: "cable.connector"
        }
    }
    var subtitle: String {
        switch self {
        case .sound: "Создавай тембр. Сохраняй находки."
        case .library: "Твои звуки и локальные варианты."
        case .patterns: "Сначала прочитать. Затем понять."
        case .connection: "Прямая связь с твоим Digitone II."
        }
    }
}

private enum StudioPalette {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.07)
    static let surface = Color(red: 0.09, green: 0.105, blue: 0.115)
    static let raised = Color(red: 0.12, green: 0.14, blue: 0.15)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(red: 0.36, green: 0.88, blue: 0.72)
}

public struct StudioView: View {
    @StateObject private var model = StudioModel()
    @State private var page: StudioPage = .sound
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var importing = false
    @State private var exporting = false
    @State private var document = SysExDocument(data: Data())

    public init() {}

    public var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DIGITONE").font(.system(size: 22, weight: .black, design: .monospaced)).tracking(1.5)
                    HStack {
                        Text("STUDIO").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3)
                        Text("EARLY ACCESS").font(.system(size: 8, weight: .bold, design: .monospaced)).padding(5)
                            .background(StudioPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(StudioPalette.accent)
                    }.foregroundStyle(.secondary)
                }.padding(.top, 22)
                VStack(spacing: 7) {
                    ForEach(StudioPage.allCases) { item in
                        Button { page = item; compactColumn = .detail } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).frame(width: 22)
                                Text(item.rawValue).font(.system(size: 14, weight: .medium))
                                Spacer()
                            }.padding(.horizontal, 13).padding(.vertical, 13)
                                .foregroundStyle(page == item ? StudioPalette.accent : Color.secondary)
                                .background(page == item ? StudioPalette.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(model.connected ? StudioPalette.accent : Color.secondary).frame(width: 6, height: 6)
                        Text(model.connected ? "ПРИБОР ПОДКЛЮЧЁН" : "ЛОКАЛЬНАЯ СЕССИЯ")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.6)
                    }.foregroundStyle(model.connected ? StudioPalette.accent : .secondary)
                    if let identity = model.identity {
                        Text("\(identity.name)\nOS \(identity.version) · \(identity.build)")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    } else {
                        Text("Можно собрать черновик звука\nи подключить прибор позднее.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Button(model.connected ? "Настройки связи" : "Подключить Digitone") { page = .connection; compactColumn = .detail }
                        .font(.system(size: 12)).buttonStyle(.bordered)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudioPalette.surface, in: RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 18).padding(.bottom, 20)
                .background(StudioPalette.background)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider().overlay(StudioPalette.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        banners
                        switch page {
                        case .sound: soundPage
                        case .library: libraryPage
                        case .patterns: patternsPage
                        case .connection: connectionPage
                        }
                    }.padding(28).frame(maxWidth: 1250, alignment: .leading).frame(maxWidth: .infinity)
                }
            }.background(StudioPalette.background)
        }
        .tint(StudioPalette.accent)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .sysEx], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { model.importPattern(url) } }
            catch { model.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .sysEx,
                      defaultFilename: model.rawPatternIndex.map { "Digitone-\(PatternSnapshot.slotName($0)).syx" } ?? "Digitone-pattern.syx") { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page.rawValue).font(.system(size: 26, weight: .semibold))
                Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy {
                HStack(spacing: 9) { ProgressView().controlSize(.small); Text(model.busyText).font(.system(size: 11)) }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: model.connected ? "checkmark.circle.fill" : "circle.dashed")
                    Text(model.identity.map { "Digitone II · \($0.version)" } ?? "Без подключения")
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(model.connected ? StudioPalette.accent : .secondary)
            }
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }

    @ViewBuilder private var banners: some View {
        if let error = model.error {
            message(error, icon: "exclamationmark.triangle", color: .orange) { model.error = nil }
        }
        if let notice = model.notice {
            message(notice, icon: "info.circle", color: StudioPalette.accent) { model.notice = nil }
        }
    }

    private func message(_ text: String, icon: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(14).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var soundPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        sectionTitle("МАРШРУТ ЗВУКА", subtitle: "Выбери движок, который уже установлен на приборе")
                        Spacer()
                        Text("\(model.knownCount) / \(model.parameters.count) значений")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 22) { machinePicker; channelPicker }
                        VStack(alignment: .leading, spacing: 12) { machinePicker; channelPicker }
                    }
                    Text("Движок выбирается на Digitone. Этот список задаёт только подписи редактора. MIDI-канал нужно сопоставить с каналом нужного трека в настройках прибора.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let incomingChannel = model.lastParameterChannel, let incoming = model.lastParameterText {
                        Divider()
                        Text(incoming).font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioPalette.accent)
                        if incomingChannel != model.channel {
                            Text("Последний параметр пришёл на другом MIDI-канале. Проверь OUTPUT CH на приборе или выбери этот канал в редакторе.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Выбрать канал \(incomingChannel + 1)") { model.channel = incomingChannel }
                                .buttonStyle(.bordered).disabled(model.busy)
                        }
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { soundActions }
                VStack(alignment: .leading, spacing: 12) { soundActions }
            }
            Text("Значения 0–127 — позиции MIDI, а не частота или время. «—» означает, что значение ещё неизвестно. Отправка не подтверждает состояние прибора.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            Text("После смены звука или паттерна на Digitone очисти значения: события CC/NRPN не дают полного состояния нового звука.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            ForEach(model.sections, id: \.self) { section in
                card {
                    VStack(alignment: .leading, spacing: 19) {
                        sectionTitle(section.uppercased(), subtitle: "")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 24)], alignment: .leading, spacing: 22) {
                            ForEach(model.parameters.filter { $0.section == section }, id: \.id) { parameter in
                                parameterControl(parameter)
                            }
                        }
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle("ВАРИАНТЫ A / B", subtitle: "Локальные точки сравнения для выбранного движка и канала")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { checkpointActions }
                        VStack(alignment: .leading, spacing: 12) { checkpointActions }
                    }.buttonStyle(.bordered)
                    Text("Переключение открывает черновик. Для сравнения на приборе примени параметры и прослушай звук.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            saveCard
        }
    }

    @ViewBuilder private var soundActions: some View {
        Button { Task { await model.audition() } } label: { Label("Прослушать C4", systemImage: "play.fill") }
            .buttonStyle(.borderedProminent).disabled(!model.connected || model.busy)
        Button { Task { await model.apply() } } label: { Label("Применить параметры", systemImage: "arrow.up.right") }
            .buttonStyle(.bordered).disabled(!model.canApply)
        Button("Очистить значения") { model.clearCurrentValues() }
            .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary).disabled(model.busy)
    }

    @ViewBuilder private var checkpointActions: some View {
        ForEach(["A", "B"], id: \.self) { side in
            HStack {
                Button("Запомнить \(side)") { model.checkpoint(side) }.disabled(model.busy || model.known.isEmpty)
                Button("Открыть \(side)") { model.useCheckpoint(side) }.disabled(model.busy || !model.hasCheckpoint(side))
            }
        }
    }

    private var machinePicker: some View {
        Picker("Движок", selection: $model.machine) {
            ForEach(SynthMachine.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.menu).frame(maxWidth: 320, alignment: .leading).disabled(model.busy)
    }

    private var channelPicker: some View {
        Picker("MIDI-канал", selection: $model.channel) {
            ForEach(0..<16, id: \.self) { Text("\($0 + 1)").tag($0) }
        }.pickerStyle(.menu).frame(maxWidth: 210, alignment: .leading).disabled(model.busy)
    }

    private func parameterControl(_ parameter: ParameterDefinition) -> some View {
        let known = model.known[parameter.id]
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(parameter.title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(known.map { "\($0.value)" } ?? "—")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(known == nil ? Color.secondary : StudioPalette.accent)
                    .contentTransition(.numericText())
            }
            Slider(value: Binding(get: { Double(model.known[parameter.id]?.value ?? 0) }, set: { model.change(parameter, to: Int($0)) }), in: 0...127, step: 1)
                .disabled(model.busy).opacity(known == nil ? 0.45 : 1)
                .accessibilityLabel(parameter.title)
                .accessibilityValue(known.map { "\($0.value) из 127, \($0.origin.rawValue)" } ?? "Значение неизвестно")
            HStack {
                Text(known.map { $0.origin.rawValue } ?? "Нет данных")
                Spacer()
                Text(parameter.cc.map { "CC \($0)" } ?? "NRPN \(parameter.nrpn)")
                    .font(.system(size: 9, design: .monospaced))
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.help(parameter.detail)
    }

    private var saveCard: some View {
        card {
            VStack(alignment: .leading, spacing: 15) {
                sectionTitle("СОХРАНИТЬ НАХОДКУ", subtitle: "Снимок содержит только известные параметры редактора")
                TextField("Имя снимка", text: $model.snapshotName).textFieldStyle(.roundedBorder)
                TextField("Теги через запятую: bass, soft, live", text: $model.snapshotTags).textFieldStyle(.roundedBorder)
                Button { model.saveSnapshot() } label: { Label("Сохранить в библиотеку", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent).disabled(model.busy || model.known.isEmpty || !model.storageAvailable)
                Text("\(model.knownCount) параметров · канал \(model.channel + 1)").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Локальный снимок не является полным аппаратным пресетом: неизвестные параметры и настройки прибора в него не входят.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var libraryPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск по имени, движку или тегу", text: $model.search).textFieldStyle(.plain)
                Text("\(model.filteredSnapshots.count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(15).background(StudioPalette.surface, in: RoundedRectangle(cornerRadius: 10))
            if model.filteredSnapshots.isEmpty {
                emptyState(symbol: "square.stack.3d.up", title: model.search.isEmpty ? "Библиотека начинается с первого звука" : "Пока ничего не найдено",
                           detail: model.search.isEmpty ? "Настрой параметры в разделе «Звук» и сохрани локальный снимок. Его можно открыть и применить к Digitone позднее." : "Попробуй другое имя или тег.")
            } else {
                ForEach(model.filteredSnapshots) { snapshot in
                    card {
                        VStack(alignment: .leading, spacing: 13) {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(snapshot.name).font(.system(size: 17, weight: .semibold))
                                    Text("\(snapshot.machine.title) · \(snapshot.parameters.count) параметров · MIDI \(snapshot.channel + 1)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("Открыть черновик") { model.load(snapshot); page = .sound; compactColumn = .detail }
                                        .buttonStyle(.bordered).disabled(model.busy)
                                    Spacer()
                                    Menu {
                                        Button("Удалить снимок", role: .destructive) { model.delete(snapshot) }
                                    } label: { Image(systemName: "ellipsis").frame(width: 20) }.disabled(model.busy || !model.storageAvailable)
                                }
                            }
                            HStack(spacing: 7) {
                                Text(snapshot.tags.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(StudioPalette.accent)
                                Spacer()
                                Text(snapshot.createdAt, style: .date).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Text("Открытие снимка меняет только черновик приложения. Отправка параметров выполняется отдельной кнопкой в редакторе.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var patternsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                VStack(alignment: .leading, spacing: 17) {
                    sectionTitle("ПАТТЕРН С ПРИБОРА", subtitle: "Чтение и архивирование. Редактирование появится на следующем этапе.")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { patternReadActions }
                        VStack(alignment: .leading, spacing: 12) { patternReadActions }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { patternFileActions }
                        VStack(alignment: .leading, spacing: 12) { patternFileActions }
                    }.buttonStyle(.bordered).disabled(model.busy)
                }
            }
            if let pattern = model.pattern {
                card {
                    VStack(alignment: .leading, spacing: 19) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pattern.name.isEmpty ? PatternSnapshot.slotName(pattern.index) : pattern.name).font(.system(size: 24, weight: .semibold))
                                Text("\(PatternSnapshot.slotName(pattern.index)) · \(pattern.tempo, specifier: "%.1f") BPM · swing \(pattern.swing)% · \(pattern.notes.count) нот")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Text("ТОЛЬКО ПРОСМОТР").font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(StudioPalette.accent).padding(8).background(StudioPalette.accent.opacity(0.08), in: Capsule())
                        }
                        Picker("Трек", selection: $model.patternTrack) {
                            ForEach(0..<16, id: \.self) { index in
                                Text("\(index + 1) · \(pattern.trackNames[index].isEmpty ? "Track" : pattern.trackNames[index])").tag(index)
                            }
                        }.frame(maxWidth: 360)
                        HStack {
                            Text("\(pattern.trackLengths[model.patternTrack]) шагов").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Picker("Страница", selection: $model.patternPage) {
                                ForEach(0..<8, id: \.self) { index in Text("\(index * 16 + 1)–\(index * 16 + 16)").tag(index) }
                            }.frame(width: 165)
                        }
                        ScrollView(.horizontal) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 16), spacing: 6) {
                            ForEach(0..<16, id: \.self) { position in
                                let step = model.patternPage * 16 + position
                                let notes = pattern.notes.filter { $0.track == model.patternTrack && $0.step == step }
                                VStack(spacing: 9) {
                                    Text("\(step + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    RoundedRectangle(cornerRadius: 4).fill(notes.isEmpty ? StudioPalette.raised : StudioPalette.accent).frame(height: 31)
                                    Text(notes.first.map { noteName($0.note) } ?? "·").font(.system(size: 8, design: .monospaced)).lineLimit(1)
                                }.opacity(step < pattern.trackLengths[model.patternTrack] ? 1 : 0.3)
                            }
                        }.frame(minWidth: 620)
                        }
                        Divider()
                        ScrollView(.horizontal) {
                        VStack(spacing: 9) {
                            HStack {
                                Text("ШАГ").frame(width: 45, alignment: .leading)
                                Text("НОТА").frame(width: 65, alignment: .leading)
                                Text("VEL").frame(width: 45, alignment: .leading)
                                Text("ДЛИНА · КОД").frame(width: 100, alignment: .leading)
                                Text("МИКРОТАЙМИНГ")
                                Spacer()
                            }.font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                            ForEach(pattern.notes.filter { $0.track == model.patternTrack && $0.step / 16 == model.patternPage }.sorted { $0.step < $1.step }) { note in
                                HStack {
                                    Text("\(note.step + 1)").frame(width: 45, alignment: .leading)
                                    Text(noteName(note.note)).frame(width: 65, alignment: .leading)
                                    Text("\(note.velocity)").frame(width: 45, alignment: .leading)
                                    Text("\(note.lengthCode)").frame(width: 100, alignment: .leading)
                                    Text("\(note.microTiming)")
                                    Spacer()
                                }.font(.system(size: 11, design: .monospaced))
                            }
                        }.frame(minWidth: 460, alignment: .leading)
                        }
                    }
                }
                Text("Архив сохраняет исходный SysEx целиком. Таблица показывает только изученные ноты и грубые коды длительности; parameter locks и условия здесь не редактируются.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            } else if let raw = model.rawPatternData {
                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("АРХИВ ПАТТЕРНА", subtitle: "Исходная передача сохранена в памяти")
                        Text("\(model.rawPatternIndex.map(PatternSnapshot.slotName) ?? "SysEx") · \(raw.count.formatted()) байт")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                        Text("Контрольная сумма верна, но структуру этой версии пока не удалось прочитать. Сохрани .syx для исследования и резервного архива.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }
            } else {
                emptyState(symbol: "square.grid.4x3", title: "Посмотреть, что играет Digitone", detail: "Подключи прибор и прочитай выбранный слот. Или открой сохранённый архив .syx без подключения.")
            }
        }
    }

    @ViewBuilder private var patternReadActions: some View {
        Picker("Слот", selection: $model.patternIndex) {
            ForEach(0..<128, id: \.self) { Text(PatternSnapshot.slotName($0)).tag($0) }
        }.frame(maxWidth: 180).disabled(model.busy)
        Button { Task { await model.readPattern() } } label: { Label("Прочитать", systemImage: "arrow.down") }
            .buttonStyle(.borderedProminent).disabled(!model.connected || model.busy)
    }

    @ViewBuilder private var patternFileActions: some View {
        Button { importing = true } label: { Label("Открыть .syx", systemImage: "folder") }
        Button {
            guard let raw = model.rawPatternData else { return }
            document = SysExDocument(data: raw); exporting = true
        } label: { Label("Сохранить .syx", systemImage: "square.and.arrow.up") }
            .disabled(model.rawPatternData == nil)
    }

    private var connectionPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        sectionTitle("USB MIDI", subtitle: "Подключение начинается только по твоей команде")
                        Spacer()
                        Button { model.refreshEndpoints() } label: { Label("Обновить", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    }
                    Picker("Вход в приложение", selection: $model.sourceID) {
                        Text("Выбери MIDI-вход").tag(UInt32(0))
                        ForEach(model.sources) { Text($0.name).tag($0.id) }
                    }.disabled(model.busy || model.connected)
                    Picker("Выход на прибор", selection: $model.destinationID) {
                        Text("Выбери MIDI-выход").tag(UInt32(0))
                        ForEach(model.destinations) { Text($0.name).tag($0.id) }
                    }.disabled(model.busy || model.connected)
                    HStack {
                        if model.connected {
                            Button("Отключить") { model.disconnect() }.buttonStyle(.bordered).disabled(model.busy)
                        } else {
                            Button { Task { await model.connect() } } label: { Label("Подключить и проверить", systemImage: "cable.connector") }
                                .buttonStyle(.borderedProminent).disabled(model.busy || model.sourceID == 0 || model.destinationID == 0)
                        }
                        Spacer()
                    }
                    if let identity = model.identity {
                        Divider()
                        Text("\(identity.name) · OS \(identity.version) · сборка \(identity.build)").font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(StudioPalette.accent)
                        Text(identity.hasKnownPatternFormat ? "Формат паттернов соответствует исследованной сборке 1.10D / 0049." : "Для этой сборки формат паттернов ещё не подтверждён; при чтении проверяются структура и контрольная сумма.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(model.lastParameterText ?? "Входящие параметры ещё не получены. Поверни ручку на Digitone для проверки.")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(model.lastParameterText == nil ? Color.secondary : StudioPalette.accent)
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 19) {
                    sectionTitle("НАСТРОЙКИ НА DIGITONE II", subtitle: "Для управления и получения поворотов аппаратных ручек")
                    helpRow("01", "USB CONFIG", "SETTINGS → SYSTEM → USB CONFIG → USB MIDI или USB AUDIO/MIDI")
                    helpRow("02", "MIDI PORT CONFIG", "INPUT FROM и OUTPUT TO: USB или MIDI+USB. Включи RECEIVE CC/NRPN.")
                    helpRow("03", "ВЫХОД ПАРАМЕТРОВ", "PARAM OUTPUT: CC или NRPN. ENCODER DEST: INT+EXT, чтобы ручки меняли звук и сообщали значения приложению. OUTPUT CH: TRACK CH передаёт параметры на канале трека, AUTO CH — на Auto Channel. Выбери соответствующий канал в редакторе.")
                    helpRow("04", "КАНАЛЫ ТРЕКОВ", "Назначь разные MIDI-каналы трекам. Выбранный в редакторе канал должен совпадать с нужным треком; номер трека и MIDI-канал не обязаны совпадать.")
                    Text("Редактор не может запросить все текущие значения через CC. Неизвестные параметры остаются пустыми до получения MIDI или ручного ввода. Переподключение не отправляет локальные черновики.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }
            }
            if !model.log.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("ЖУРНАЛ СЕССИИ", subtitle: "")
                        ForEach(Array(model.log.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func helpRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(StudioPalette.accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioPalette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(StudioPalette.line, lineWidth: 1))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(StudioPalette.accent)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 17) {
            Image(systemName: symbol).font(.system(size: 42, weight: .ultraLight)).foregroundStyle(StudioPalette.accent.opacity(0.7))
            Text(title).font(.system(size: 20, weight: .medium)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 450)
        }.padding(.vertical, 65).frame(maxWidth: .infinity)
    }

    private func noteName(_ number: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[number % 12])\(number / 12 - 1)"
    }
}

extension UTType {
    static let sysEx = UTType(exportedAs: "studio.digitone.sysex", conformingTo: .data)
}

struct SysExDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sysEx, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
