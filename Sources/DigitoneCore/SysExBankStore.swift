import Foundation

/// A byte-preserving local archive. It does not assert that the payload is a
/// decoded sound, or that it can be restored to a particular hardware slot.
public struct SysExBankArchive: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let fileName: String
    public let messageCount: Int
    public let byteCount: Int
    public let createdAt: Date
}

public enum SysExArchiveError: Error, LocalizedError {
    case malformed, tooLarge
    public var errorDescription: String? {
        switch self {
        case .malformed: "Ожидается архив Elektron SysEx с корректными дампами и контрольными суммами."
        case .tooLarge: "Архив SysEx превышает 20 МБ."
        }
    }
}

public struct SysExBankStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public static func messageCount(in data: Data) throws -> Int {
        guard data.count <= 20_000_000 else { throw SysExArchiveError.tooLarge }
        let bytes = Array(data)
        var start = 0, count = 0
        while start < bytes.count {
            guard bytes[start] == 0xf0, let end = bytes[(start + 1)...].firstIndex(of: 0xf7) else { throw SysExArchiveError.malformed }
            guard case .dump = try ElektronProtocol.parse(Array(bytes[start...end])) else { throw SysExArchiveError.malformed }
            count += 1; start = end + 1
        }
        guard count > 0 else { throw SysExArchiveError.malformed }
        return count
    }

    public func load() throws -> [SysExBankArchive] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension.lowercased() == "syx" }
            .map { url in
                let stem = url.deletingPathExtension().lastPathComponent
                guard stem.count > 38, let id = UUID(uuidString: String(stem.prefix(36))), stem.dropFirst(36).hasPrefix("--") else {
                    throw SysExArchiveError.malformed
                }
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                return SysExBankArchive(id: id, name: String(stem.dropFirst(38)), fileName: url.lastPathComponent,
                                        messageCount: try Self.messageCount(in: bytes), byteCount: bytes.count,
                                        createdAt: try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast)
            }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func importFile(_ url: URL) throws -> SysExBankArchive {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let count = try Self.messageCount(in: data)
        // Reimporting the same file does not create another stored copy.
        for archive in try load() where archive.byteCount == data.count {
            if try self.data(for: archive) == data { return archive }
        }
        let rawName = url.deletingPathExtension().lastPathComponent
        let name = String(rawName.map { "/\\:\n\r".contains($0) ? "-" : $0 }.prefix(100))
        let id = UUID()
        let fileName = "\(id.uuidString)--\(name.isEmpty ? "Архив" : name).syx"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return SysExBankArchive(id: id, name: name.isEmpty ? "Архив" : name, fileName: fileName,
                                messageCount: count, byteCount: data.count, createdAt: Date())
    }

    public func data(for archive: SysExBankArchive) throws -> Data {
        guard archive.fileName == URL(fileURLWithPath: archive.fileName).lastPathComponent,
              archive.fileName.hasPrefix("\(archive.id.uuidString)--") else { throw SysExArchiveError.malformed }
        let data = try Data(contentsOf: directory.appendingPathComponent(archive.fileName), options: .mappedIfSafe)
        _ = try Self.messageCount(in: data)
        return data
    }
}
