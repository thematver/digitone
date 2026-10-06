import SwiftUI
import UniformTypeIdentifiers
import DigitoneCore
import DigitoneDesign

struct ShelfSurface: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    let open: (WorkspaceImport) -> Void
    let export: (Data, UTType, String) -> Void
    var onOpenSound: () -> Void = {}
    @State private var archiveTab = false
    @State private var editing: SoundSnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Button("Снимки · \(model.snapshots.count)") { archiveTab = false }.buttonStyle(InstrumentButtonStyle(prominent: !archiveTab))
                Button("SysEx · \(workspace.archives.count)") { archiveTab = true }.buttonStyle(InstrumentButtonStyle(prominent: archiveTab))
            }.font(.system(size: 12))
            if archiveTab { archives } else { snapshots }
        }.sheet(item: $editing) { SnapshotMetadataEditor(model: model, snapshot: $0) }
    }

    private var snapshots: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(InstrumentTheme.secondary)
                TextField("Имя или тег", text: $model.search).textFieldStyle(.plain).snapshotControl(model.search.isEmpty ? "Имя или тег" : model.search, chevron: false)
                Button { model.favoritesOnly.toggle() } label: { Image(systemName: model.favoritesOnly ? "star.fill" : "star") }.buttonStyle(.plain).foregroundStyle(InstrumentTheme.orange).accessibilityLabel("Фильтр избранного")
            }.padding(15).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            ViewThatFits(in: .horizontal) {
                HStack { filters }
                VStack(alignment: .leading, spacing: 10) { filters }
            }.font(.system(size: 11))
            if model.filteredSnapshots.isEmpty {
                InstrumentPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 32, weight: .light)).foregroundStyle(InstrumentTheme.green)
                        Text(model.snapshots.isEmpty ? "Здесь будут твои звуки" : "Ничего не найдено").font(.system(size: 20, weight: .medium))
                        Text(model.snapshots.isEmpty ? "Сохрани снимок из «Звука» или открой библиотеку из файла." : "Попробуй другой фильтр.").font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                        Button(model.snapshots.isEmpty ? "Импорт снимков" : "Сбросить фильтры") {
                            if model.snapshots.isEmpty { open(.snapshot) } else { model.resetLibraryFilters() }
                        }.buttonStyle(InstrumentButtonStyle())
                    }.padding(.vertical, 24)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 16) {
                ForEach(model.filteredSnapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text(snapshot.machine.title.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                            Spacer(minLength: 0)
                            Button { model.toggleFavorite(snapshot) } label: { Image(systemName: snapshot.isFavorite ? "star.fill" : "star").font(.system(size: 12)).frame(width: 24, height: 24) }.buttonStyle(.plain).foregroundStyle(InstrumentTheme.orange).disabled(!model.storageAvailable || model.busy)
                        }
                        Button { model.load(snapshot); onOpenSound() } label: {
                            ZStack {
                                Circle().stroke(InstrumentTheme.green.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: 82, height: 82)
                                Circle().trim(from: 0, to: Double(snapshot.parameters.count) / Double(max(1, ParameterCatalog.parameters(for: snapshot.machine).count)))
                                    .stroke(InstrumentTheme.green, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 82, height: 82).rotationEffect(.degrees(-90))
                                Image(systemName: "waveform.path").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(InstrumentTheme.green)
                            }.frame(maxWidth: .infinity).frame(height: 110)
                        }.buttonStyle(.plain).disabled(model.busy).accessibilityLabel("Открыть черновик \(snapshot.name)")
                        Text(snapshot.name).font(.system(size: 15, weight: .medium)).lineLimit(2).frame(height: 38, alignment: .top)
                        Text("Снимок · \(snapshot.parameters.count) значений").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                        HStack {
                            Text(snapshot.tags.prefix(2).joined(separator: " · ")).font(.system(size: 9)).lineLimit(1).foregroundStyle(InstrumentTheme.secondary)
                            Spacer(minLength: 0)
                            Menu {
                                Button("Открыть черновик") { model.load(snapshot); onOpenSound() }
                                Button("Название и теги") { model.error = nil; editing = snapshot }.disabled(!model.storageAvailable)
                                Button("Создать копию") { model.duplicate(snapshot) }.disabled(!model.storageAvailable)
                                Button("Экспорт") { if let data = model.exportSnapshots([snapshot]) { export(data, .json, "Digitone-snapshot.json") } }
                                Button("Удалить", role: .destructive) { model.delete(snapshot) }.disabled(!model.storageAvailable)
                            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }.disabled(model.busy).snapshotControl("•••", chevron: false)
                        }
                    }.padding(18).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            Text("Снимки содержат известные параметры. Открытие готовит черновик; отправка — в «Звуке».").font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
        }
    }

    @ViewBuilder private var filters: some View {
        Picker("Движок", selection: $model.libraryMachine) {
            Text("Все движки").tag(Optional<SynthMachine>.none)
            ForEach(SynthMachine.allCases) { Text($0.title).tag(Optional($0)) }
        }.pickerStyle(.menu).snapshotControl(model.libraryMachine?.title ?? "Все движки")
        Picker("Тег", selection: $model.libraryTag) {
            Text("Все теги").tag("")
            ForEach(model.libraryTags, id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.menu).snapshotControl(model.libraryTag.isEmpty ? "Все теги" : model.libraryTag)
        if model.hasLibraryFilters { Button("Сбросить") { model.resetLibraryFilters() }.buttonStyle(.plain) }
    }

    private var archives: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { open(.bank) } label: { Label("Открыть .syx", systemImage: "plus") }.buttonStyle(InstrumentButtonStyle())
            if workspace.archives.isEmpty {
                InstrumentPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "shippingbox").font(.system(size: 32, weight: .light))
                        Text("Место для банков и архивов").font(.system(size: 20, weight: .medium))
                        Text("Сохраняй исходные SysEx-файлы целиком. Приложение проверит сообщения и контрольные суммы.")
                            .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                    }.padding(.vertical, 24)
                }
            }
            ForEach(workspace.archives) { archive in
                InstrumentPanel {
                    HStack(spacing: 16) {
                        Image(systemName: "shippingbox").font(.system(size: 24, weight: .light)).foregroundStyle(InstrumentTheme.green)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(archive.name).font(.system(size: 15, weight: .medium))
                            Text("SysEx · \(archive.messageCount) сообщений · \(archive.byteCount.formatted()) байт").font(.system(size: 10)).foregroundStyle(InstrumentTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        Button { if let data = workspace.bankData(archive) { export(data, .sysEx, archive.name + ".syx") } } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.plain).accessibilityLabel("Экспорт \(archive.name)")
                    }
                }
            }
            Text("Архив хранит исходные байты. Запись банков и полных пресетов в Digitone пока требует проверки протокола.").font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
        }
    }
}
