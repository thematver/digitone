import SwiftUI
import DigitoneDesign
#if os(macOS)
import AppKit
#endif

struct AgentConnectionPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Агенты · MCP", systemImage: "terminal").font(.system(size: 23, weight: .semibold))
                    Spacer()
                    Button("Готово") { dismiss() }.buttonStyle(InstrumentButtonStyle())
                }
                Text("Поручи агенту собрать звук, написать бит и сыграть его на Digitone.")
                    .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    capability("slider.horizontal.3", "Звуки", "Каталог параметров по машине, создание и изменение черновиков, отправка в выбранный MIDI-канал.")
                    capability("square.grid.3x3", "Биты и мелодии", "Шаги, ноты, velocity, длина и темп; воспроизведение партии по MIDI и остановка.")
                    capability("doc", "Общий проект", "Агент сохраняет .digitone.json. Открой его через меню «•••»: партия попадёт в редактор, звуки — в библиотеку.")
                }.padding(18).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                #if os(macOS)
                Text("ПОДКЛЮЧЕНИЕ STDIO").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(InstrumentTheme.secondary)
                Text("Укажи этот исполняемый файл в настройках MCP своего агента. Клиент запускает сервер самостоятельно.")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                Text(Self.serverURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading).background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                if !FileManager.default.isExecutableFile(atPath: Self.serverURL.path) {
                    Text("Собери приложение через scripts/build-app.sh — MCP-сервер будет включён в .app.")
                        .font(.system(size: 11)).foregroundStyle(InstrumentTheme.orange)
                }
                Text(Self.configuration).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(InstrumentTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                Button(copied ? "Скопировано" : "Скопировать конфигурацию") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.configuration, forType: .string)
                    copied = true
                }.buttonStyle(InstrumentButtonStyle(prominent: true))
                Text("JSON подходит клиентам с настройкой mcpServers. Для других клиентов используй тот же command, транспорт stdio, без аргументов.")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary)
                #else
                Text("MCP-сервер запускается на Mac с подключённым Digitone. На iPhone и iPad можно открыть сохранённый агентом проект .digitone.json.")
                    .font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary)
                #endif
                VStack(alignment: .leading, spacing: 8) {
                    Text("Попробуй такое поручение").font(.system(size: 12, weight: .semibold))
                    Text("«Создай минимал-техно на 32 шага, 124 BPM: кик на T1, снейр на T2, хэт на T3 и бас на T4. Сначала покажи черновик и сохрани проект. Затем подключись к Digitone и сыграй партию». ")
                        .font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Text("Треки и MIDI-каналы задаются отдельно. Машину синтеза нужно выбрать на приборе. Применение параметров изменяет текущий звук; партия звучит из компьютера по MIDI.")
                    .font(.system(size: 11)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }.frame(minWidth: 320, idealWidth: 640, idealHeight: 690)
            .background(InstrumentTheme.paper).foregroundStyle(InstrumentTheme.ink).tint(InstrumentTheme.green)
    }

    private func capability(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(InstrumentTheme.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(InstrumentTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    #if os(macOS)
    private static var serverURL: URL {
        let sibling = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            .deletingLastPathComponent().appendingPathComponent("digitone-mcp")
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [sibling, sourceRoot.appendingPathComponent("build/bin/digitone-mcp"),
                          sourceRoot.appendingPathComponent(".build/debug/digitone-mcp")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? sibling
    }

    private static var configuration: String {
        let data = try! JSONSerialization.data(withJSONObject: ["mcpServers": ["digitone": ["command": serverURL.path, "args": [String]()]]], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    #endif
}
