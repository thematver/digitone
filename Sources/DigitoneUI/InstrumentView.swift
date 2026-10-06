import SwiftUI
import UniformTypeIdentifiers
import DigitoneCore
import DigitoneMIDI
import DigitoneDesign
#if os(macOS)
import AppKit
#endif

enum InstrumentMode: String, CaseIterable, Identifiable {
    case notes = "Паттерн", sound = "Звук", shelf = "Библиотека"
    var id: Self { self }
    var symbol: String {
        switch self { case .sound: "slider.horizontal.3"; case .notes: "square.grid.3x3"; case .shelf: "square.stack.3d.up" }
    }
    var subtitle: String {
        switch self { case .sound: "Параметры выбранного трека и общие эффекты"; case .notes: "Собери бит по шагам или открой редактор нот"; case .shelf: "Сохранённые звуки и исходные архивы Digitone" }
    }
}

enum WorkspaceImport: CaseIterable { case midi, snapshot, bank, pattern, audio, project
    var types: [UTType] {
        switch self { case .midi: [.midi, .data]; case .snapshot, .project: [.json]; case .bank, .pattern: [.sysEx, .data]; case .audio: [.audio] }
    }
}

public struct StudioView: View {
    @StateObject private var model: StudioModel
    @StateObject private var workspace: WorkspaceModel
    @State private var mode: InstrumentMode
    @State private var notesEditor: NotesSurface.Editor
    @State private var connection = false
    @State private var savingSound = false
    @State private var recording = false
    @State private var agents = false
    @State private var autosave: Task<Void, Never>?
    @State private var importing = false
    @State private var importKind: WorkspaceImport = .midi
    @State private var exporting = false
    @State private var document = StudioFileDocument(data: Data())
    @State private var exportType: UTType = .json
    @State private var exportName = "Digitone-library.json"
    @Environment(\.isSnapshotRendering) private var snapshot
    @Environment(\.scenePhase) private var scenePhase

    public init() {
        _model = StateObject(wrappedValue: StudioModel())
        _workspace = StateObject(wrappedValue: WorkspaceModel())
        _mode = State(initialValue: .notes)
        _notesEditor = State(initialValue: .steps)
    }

    init(model: StudioModel, workspace: WorkspaceModel, mode: InstrumentMode, notesEditor: NotesSurface.Editor = .steps) {
        _model = StateObject(wrappedValue: model); _workspace = StateObject(wrappedValue: workspace)
        _mode = State(initialValue: mode)
        _notesEditor = State(initialValue: notesEditor)
    }

    public var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 900
            VStack(spacing: 0) {
                topBar(compact: compact)
                HStack(spacing: 0) {
                    if !compact { modeRail }
                    DSScroll {
                        VStack(alignment: .leading, spacing: compact ? 16 : 20) {
                            heading(compact: compact)
                            if let error = model.error ?? workspace.error {
                                feedback(error, isError: true)
                            } else if let notice = workspace.notice ?? model.notice {
                                feedback(notice, isError: false)
                            }
                            content(compact: compact)
                        }.padding(compact ? 14 : 24).frame(maxWidth: 1280, alignment: .leading).frame(maxWidth: .infinity)
                    }
                }.frame(maxHeight: .infinity)
                if compact { bottomModes }
            }.background(InstrumentTheme.paper).foregroundStyle(InstrumentTheme.ink)
                .tint(InstrumentTheme.green)
                .buttonStyle(.plain)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importKind.types) { result in
            do {
                let url = try result.get()
                switch importKind {
                case .midi: model.stopSequence(); workspace.importMIDI(url)
                case .snapshot: model.importSnapshots(url)
                case .bank: workspace.importBank(url)
                case .pattern: model.importPattern(url)
                case .audio: Task { await workspace.loadAudio(url) }
                case .project: model.stopSequence(); workspace.importAgentProject(url, studio: model)
                }
            } catch { workspace.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let error) = result { workspace.error = error.localizedDescription }
        }
        .sheet(isPresented: $connection) { ConnectionPanel(model: model, workspace: workspace) }
        .sheet(isPresented: $savingSound) { SaveSoundPanel(model: model) }
        .sheet(isPresented: $recording) { RecordingPanel(workspace: workspace) }
        .sheet(isPresented: $agents) { AgentConnectionPanel() }
        .onChange(of: workspace.sequence) { _, _ in
            guard !snapshot else { return }
            autosave?.cancel()
            autosave = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                workspace.saveSequence(announce: false)
            }
        }
        .task {
            guard !snapshot else { return }
            await workspace.startMonitoringIfNeeded()
        }
        #if os(macOS)
        .onDisappear {
            guard !snapshot else { return }
            autosave?.cancel(); workspace.saveSequence(announce: false)
            model.disconnect(); workspace.suspend()
        }
        #endif
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            guard !snapshot, phase == .background else { return }
            autosave?.cancel(); workspace.saveSequence(announce: false)
            model.disconnect(); workspace.suspend()
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            guard !snapshot else { return }
            autosave?.cancel(); workspace.saveSequence(announce: false)
            model.disconnect(); workspace.suspend()
        }
        #endif
    }

    private func topBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 18) {
            Text(compact ? "DN II" : "Digitone Studio")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
            Spacer(minLength: 4)
            Button { connection = true } label: {
                HStack(spacing: 7) {
                    Circle().fill(model.connected ? InstrumentTheme.green : InstrumentTheme.orange).frame(width: 7, height: 7)
                    Text(compact ? (model.connected ? "USB" : "Подключить") : (model.connected ? "Digitone подключён" : "Подключить Digitone"))
                        .font(.system(size: 11, weight: .medium))
                }.padding(.horizontal, compact ? 8 : 12).frame(height: 34)
                    .background(InstrumentTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            }.accessibilityLabel("Подключение Digitone").keyboardShortcut("k", modifiers: [.command, .shift])
            MonitorControl(workspace: workspace, compact: compact)
            Button { recording = true } label: {
                if compact { Image(systemName: "record.circle").frame(width: 32, height: 34) }
                else { Label("Запись", systemImage: "record.circle").font(.system(size: 12)).frame(height: 34) }
            }.foregroundStyle(InstrumentTheme.record).accessibilityLabel("Записать аудио Digitone")
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button { agents = true } label: {
                if compact { Image(systemName: "terminal").frame(width: 32, height: 34) }
                else { Label("Агенты", systemImage: "terminal").font(.system(size: 12)).frame(height: 34) }
            }.accessibilityLabel("Подключить агента через MCP")
            if model.isSequencePlaying && mode != .notes {
                Button { model.stopSequence() } label: { Image(systemName: "stop.fill").frame(width: 32, height: 34) }
                    .foregroundStyle(InstrumentTheme.green).accessibilityLabel("Остановить паттерн")
            }
        }.padding(.horizontal, compact ? 14 : 24).padding(.vertical, 10)
            .background(InstrumentTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(InstrumentTheme.line).frame(height: 1) }
    }

    private var modeRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("СТУДИЯ").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(InstrumentTheme.secondary).padding(.horizontal, 12).padding(.bottom, 10)
            ForEach(InstrumentMode.allCases) { item in modeButton(item, compact: false) }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("DIGITONE II").font(.system(size: 9, weight: .semibold, design: .monospaced))
                Text("Звуки · биты · идеи").font(.system(size: 10))
            }.foregroundStyle(InstrumentTheme.secondary).padding(12)
        }.padding(.horizontal, 10).padding(.top, 24).frame(width: 166)
            .overlay(alignment: .trailing) { Rectangle().fill(InstrumentTheme.line).frame(width: 1) }
    }

    private var bottomModes: some View {
        HStack(spacing: 0) { ForEach(InstrumentMode.allCases) { item in modeButton(item, compact: true).frame(maxWidth: .infinity) } }
            .padding(.vertical, 8).background(InstrumentTheme.panel)
            .overlay(alignment: .top) { Rectangle().fill(InstrumentTheme.line).frame(height: 1) }
    }

    private func modeButton(_ item: InstrumentMode, compact: Bool) -> some View {
        Button {
            if item == .sound, let track = workspace.lane?.track {
                ControlModel.attached(to: model).selectTrack(track)
            }
            mode = item
        } label: {
            Group {
                if compact {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 18))
                        Text(item.rawValue).font(.system(size: 10, weight: mode == item ? .semibold : .regular))
                    }.frame(width: 96, height: 44)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).font(.system(size: 16)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 13, weight: mode == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).frame(width: 146, height: 44)
                }
            }.foregroundStyle(mode == item ? InstrumentTheme.ink : InstrumentTheme.secondary)
                .background(mode == item ? InstrumentTheme.panel : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.keyboardShortcut(item == .notes ? "1" : item == .sound ? "2" : "3", modifiers: .command)
            .accessibilityAddTraits(mode == item ? .isSelected : [])
    }

    private func heading(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.rawValue).font(.system(size: compact ? 22 : 25, weight: .semibold))
                if !compact { Text(mode.subtitle).font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary) }
            }
            Spacer(minLength: 0)
            if mode == .sound {
                Button { savingSound = true } label: {
                    Label(compact ? "Сохранить" : "Сохранить звук", systemImage: "square.and.arrow.down")
                }.buttonStyle(InstrumentButtonStyle())
                    .disabled(model.known.isEmpty || !model.storageAvailable || ControlModel.existing(for: model)?.machine == .midi || ControlModel.existing(for: model)?.keyboardChannel == nil)
            }
            Menu {
                Button("Открыть проект агента…") { open(.project) }
                Button("Экспорт проекта…") {
                    if let data = workspace.exportAgentProject(studio: model) { export(data, type: .json, name: "Digitone-project.digitone.json") }
                }
                Divider()
                switch mode {
                case .notes:
                    Button("Открыть MIDI…") { open(.midi) }
                    Button("Экспорт MIDI…") { if let data = workspace.exportMIDI() { export(data, type: .midi, name: "Digitone-sequence.mid") } }
                    Button("Сохранить паттерн") { workspace.saveSequence() }
                    Divider()
                    Button("Открыть аппаратный паттерн .syx…") { open(.pattern) }
                case .shelf:
                    Button("Импорт звуков…") { open(.snapshot) }
                    Button("Экспорт звуков…") { if let data = model.exportSnapshots() { export(data, type: .json, name: "Digitone-library.json") } }
                    Button("Импорт архива .syx…") { open(.bank) }
                case .sound:
                    Button("Импорт звуков…") { open(.snapshot) }
                    Button("Подключение и MIDI-каналы…") { connection = true }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                .snapshotControl("•••", chevron: false)
                .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Открыть, сохранить и экспортировать")
        }
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        switch mode {
        case .sound: ControlSurface(model: model, compact: compact)
        case .notes: NotesSurface(model: model, workspace: workspace, compact: compact, editor: $notesEditor)
        case .shelf: ShelfSurface(model: model, workspace: workspace, open: open, export: export, onOpenSound: { mode = .sound })
        }
    }

    private func feedback(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(isError ? InstrumentTheme.record : InstrumentTheme.green)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.error = nil; workspace.error = nil; model.notice = nil; workspace.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 24, height: 24) }.buttonStyle(.plain)
        }.padding(14).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func open(_ kind: WorkspaceImport) { importKind = kind; importing = true }
    private func export(_ data: Data, type: UTType, name: String) {
        document = StudioFileDocument(data: data); exportType = type; exportName = name; exporting = true
    }
}
