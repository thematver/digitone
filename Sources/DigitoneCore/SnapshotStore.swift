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
    public var isFavorite: Bool

    public init(id: UUID = UUID(), name: String, machine: SynthMachine, channel: Int,
                parameters: [String: Int], createdAt: Date = Date(), tags: [String] = [],
                isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.machine = machine
        self.channel = channel
        self.parameters = parameters
        self.createdAt = createdAt
        self.tags = tags
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, machine, channel, parameters, createdAt, tags, isFavorite
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        machine = try values.decode(SynthMachine.self, forKey: .machine)
        channel = try values.decode(Int.self, forKey: .channel)
        parameters = try values.decode([String: Int].self, forKey: .parameters)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        // These additive schema-1 fields may be absent in older libraries.
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    /// Trims comma-separated tags, discards empty entries and keeps the first
    /// spelling of each tag when entries differ only in case.
    public static func normalizedTags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap { entry in
            let tag = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
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

public struct SnapshotImportResult: Equatable, Sendable {
    public let snapshots: [SoundSnapshot]
    /// Number of snapshots appended, including copies made for ID conflicts.
    public let addedCount: Int
    public let skippedCount: Int
    public let copiedCount: Int
}

/// Portable JSON archives use the same versioned envelope and validation as
/// the local library. Exporting preserves IDs so an unchanged reimport is safe.
public enum SnapshotArchive {
    private struct Library: Codable {
        let schemaVersion: Int
        let snapshots: [SoundSnapshot]

        init(snapshots: [SoundSnapshot]) {
            schemaVersion = 1
            self.snapshots = snapshots
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, snapshots }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            // Check the envelope before attempting to interpret future data.
            guard schemaVersion == 1 else { throw SnapshotStoreError.unsupportedSchema(schemaVersion) }
            snapshots = try values.decode([SoundSnapshot].self, forKey: .snapshots)
        }
    }

    public static func encode(_ snapshots: [SoundSnapshot]) throws -> Data {
        try SnapshotStore.validate(snapshots)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Library(snapshots: snapshots))
    }

    public static func decode(_ data: Data) throws -> [SoundSnapshot] {
        let library: Library
        do {
            library = try JSONDecoder().decode(Library.self, from: data)
        } catch let error as SnapshotStoreError {
            throw error
        } catch {
            throw SnapshotStoreError.unreadableLibrary(error.localizedDescription)
        }
        try SnapshotStore.validate(library.snapshots)
        return library.snapshots
    }

    /// Never overwrites existing data. Identical IDs and contents are skipped;
    /// conflicting IDs are copied to new IDs with all other fields preserved.
    public static func merge(_ imported: [SoundSnapshot], into existing: [SoundSnapshot]) throws -> SnapshotImportResult {
        try SnapshotStore.validate(existing)
        try SnapshotStore.validate(imported)
        var snapshots = existing
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var reservedIDs = Set(existing.map(\.id) + imported.map(\.id))
        var skippedCount = 0
        var copiedCount = 0
        for snapshot in imported {
            if byID[snapshot.id] == snapshot {
                skippedCount += 1
                continue
            }
            let added: SoundSnapshot
            if byID[snapshot.id] != nil {
                var newID = UUID()
                while reservedIDs.contains(newID) { newID = UUID() }
                reservedIDs.insert(newID)
                added = SoundSnapshot(id: newID, name: snapshot.name, machine: snapshot.machine,
                                      channel: snapshot.channel, parameters: snapshot.parameters,
                                      createdAt: snapshot.createdAt, tags: snapshot.tags,
                                      isFavorite: snapshot.isFavorite)
                copiedCount += 1
            } else {
                added = snapshot
            }
            snapshots.append(added)
            byID[added.id] = added
        }
        return SnapshotImportResult(snapshots: snapshots, addedCount: snapshots.count - existing.count,
                                    skippedCount: skippedCount, copiedCount: copiedCount)
    }
}

/// Versioned, atomic local storage. An unreadable existing library is never
/// overwritten by save: the caller must deliberately move it aside first.
public struct SnapshotStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("snapshots.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [SoundSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SnapshotStoreError.unreadableLibrary(error.localizedDescription)
        }
        return try SnapshotArchive.decode(data)
    }

    public func save(_ snapshots: [SoundSnapshot]) throws {
        try Self.validate(snapshots)
        // Also validates an existing file before allowing replacement, so a UI
        // that handled a load error cannot inadvertently erase corrupt data.
        if FileManager.default.fileExists(atPath: fileURL.path) { _ = try load() }
        let data = try SnapshotArchive.encode(snapshots)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    fileprivate static func validate(_ snapshots: [SoundSnapshot]) throws {
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
