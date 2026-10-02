import Foundation

/// A partial collection of observed or edited MIDI values. It is not an
/// Elektron preset dump and does not imply the entire sound was captured.
public struct SoundSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var machine: SynthMachine
    /// MIDI channel index, 0...15. Add one only for user-facing channel names.
    public var channel: Int
    public var parameters: [String: Int]
    public let createdAt: Date
    public var tags: [String]

    public init(id: UUID = UUID(), name: String, machine: SynthMachine, channel: Int,
                parameters: [String: Int], createdAt: Date = Date(), tags: [String] = []) {
        self.id = id
        self.name = name
        self.machine = machine
        self.channel = channel
        self.parameters = parameters
        self.createdAt = createdAt
        self.tags = tags
    }
}

public enum SnapshotStoreError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidSnapshot(String)
    case unreadableLibrary(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Версия библиотеки \(version) не поддерживается. Исходный файл сохранён."
        case .invalidSnapshot(let reason): return "Некорректный снимок: \(reason)."
        case .unreadableLibrary(let reason): return "Библиотеку не удалось прочитать: \(reason). Исходный файл сохранён."
        }
    }
}

/// Versioned, atomic local storage. An unreadable existing library is never
/// overwritten by save: the caller must deliberately move it aside first.
public struct SnapshotStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("snapshots.json") }

    public init(directory: URL) { self.directory = directory }

    private struct Library: Codable {
        let schemaVersion: Int
        let snapshots: [SoundSnapshot]
    }

    public func load() throws -> [SoundSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let library: Library
        do {
            let data = try Data(contentsOf: fileURL)
            library = try JSONDecoder().decode(Library.self, from: data)
        } catch {
            throw SnapshotStoreError.unreadableLibrary(error.localizedDescription)
        }
        guard library.schemaVersion == 1 else { throw SnapshotStoreError.unsupportedSchema(library.schemaVersion) }
        try Self.validate(library.snapshots)
        return library.snapshots
    }

    public func save(_ snapshots: [SoundSnapshot]) throws {
        try Self.validate(snapshots)
        // Also validates an existing file before allowing replacement, so a UI
        // that handled a load error cannot inadvertently erase corrupt data.
        if FileManager.default.fileExists(atPath: fileURL.path) { _ = try load() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Library(schemaVersion: 1, snapshots: snapshots))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func validate(_ snapshots: [SoundSnapshot]) throws {
        var ids = Set<UUID>()
        for snapshot in snapshots {
            guard ids.insert(snapshot.id).inserted else { throw SnapshotStoreError.invalidSnapshot("повторяющийся идентификатор") }
            guard !snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SnapshotStoreError.invalidSnapshot("пустое имя")
            }
            guard (0..<16).contains(snapshot.channel) else { throw SnapshotStoreError.invalidSnapshot("канал MIDI должен быть 1–16") }
            guard snapshot.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw SnapshotStoreError.invalidSnapshot("дата") }
            let knownIDs = Set(ParameterCatalog.parameters(for: snapshot.machine).map(\.id))
            for (id, value) in snapshot.parameters {
                guard knownIDs.contains(id) else { throw SnapshotStoreError.invalidSnapshot("неизвестный параметр \(id)") }
                guard (0..<128).contains(value) else { throw SnapshotStoreError.invalidSnapshot("\(id): значение должно быть 0–127") }
            }
        }
    }
}
