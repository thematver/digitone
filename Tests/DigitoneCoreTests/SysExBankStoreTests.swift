import Foundation
import XCTest
@testable import DigitoneCore

final class SysExBankStoreTests: XCTestCase {
    // Independent wire fixtures with opaque payloads, not hardware sounds.
    // Encoded payload 40 7F 00 has checksum BF and count 8.
    private let soundDump: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x53, 1, 1, 7,
                                      0x40, 0x7f, 0, 1, 0x3f, 0, 8, 0xf7]
    // Encoded payload 00 12 34 has checksum 46 and count 8.
    private let kitDump: [UInt8] = [0xf0, 0, 0x20, 0x3c, 0x15, 0, 0x52, 1, 1, 3,
                                    0, 0x12, 0x34, 0, 0x46, 0, 8, 0xf7]

    private func withStore(_ body: (SysExBankStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("digitone-sysex-bank-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(SysExBankStore(directory: root.appendingPathComponent("archives", isDirectory: true)), root)
    }

    private func file(_ bytes: Data, named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    func testMultipleDumpsAreArchivedAndReopenedByteForByte() throws {
        try withStore { store, root in
            let bytes = Data(soundDump + kitDump)
            XCTAssertEqual(try SysExBankStore.messageCount(in: bytes), 2)
            let input = try file(bytes, named: "Sound collection.syx", in: root)
            let imported = try store.importFile(input)
            XCTAssertEqual(imported.name, "Sound collection")
            XCTAssertEqual(imported.messageCount, 2)
            XCTAssertEqual(imported.byteCount, bytes.count)
            XCTAssertEqual(try store.data(for: imported), bytes)

            let reopened = try SysExBankStore(directory: store.directory).load()
            XCTAssertEqual(reopened.count, 1)
            XCTAssertEqual(reopened.first?.id, imported.id)
            XCTAssertEqual(reopened.first?.messageCount, 2)
            XCTAssertEqual(try store.data(for: XCTUnwrap(reopened.first)), bytes)
        }
    }

    func testReimportingRenamedIdenticalFileKeepsTheOriginalArchive() throws {
        try withStore { store, root in
            let bytes = Data(soundDump + kitDump)
            let original = try store.importFile(file(bytes, named: "Original.syx", in: root))
            let duplicate = try store.importFile(file(bytes, named: "Renamed copy.syx", in: root))
            XCTAssertEqual(duplicate.id, original.id)
            XCTAssertEqual(duplicate.fileName, original.fileName)
            XCTAssertEqual(duplicate.name, "Original")
            XCTAssertEqual(try store.load().count, 1)
            XCTAssertEqual(try store.data(for: duplicate), bytes)
        }
    }

    func testDifferentBanksWithTheSameByteCountAreBothRetained() throws {
        try withStore { store, root in
            let first = Data(soundDump + kitDump)
            var changed = soundDump
            changed[9] = 8 // Slot is outside the payload checksum.
            let second = Data(changed + kitDump)
            XCTAssertEqual(first.count, second.count)
            let a = try store.importFile(file(first, named: "First.syx", in: root))
            let b = try store.importFile(file(second, named: "Second.syx", in: root))
            XCTAssertNotEqual(a.id, b.id)
            XCTAssertEqual(try store.load().count, 2)
            XCTAssertEqual(try store.data(for: a), first)
            XCTAssertEqual(try store.data(for: b), second)
        }
    }

    func testRejectsEmptyTruncatedMixedAndCorruptArchives() {
        var checksumFailure = soundDump
        checksumFailure[11] = 0x7e
        var foreign = soundDump
        foreign[3] = 0x3d
        let identityRequest = APIMessage(messageID: 20_000, opcode: 1).bytes
        let invalid: [[UInt8]] = [[], [0xf0], Array(soundDump.dropLast()), checksumFailure, foreign,
                                  identityRequest, soundDump + identityRequest, soundDump + [0]]
        for bytes in invalid {
            XCTAssertThrowsError(try SysExBankStore.messageCount(in: Data(bytes)), "\(bytes)")
        }
    }

    func testInvalidImportDoesNotLoseExistingBankOrCreateAPartialFile() throws {
        try withStore { store, root in
            let originalBytes = Data(soundDump + kitDump)
            let saved = try store.importFile(file(originalBytes, named: "Saved.syx", in: root))
            let fileNamesBefore = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
            var corrupt = kitDump
            corrupt[16] = 7 // Wrong encoded length count.
            let invalid = try file(Data(soundDump + corrupt), named: "Corrupt.syx", in: root)
            XCTAssertThrowsError(try store.importFile(invalid))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), fileNamesBefore)
            XCTAssertEqual(try store.load().count, 1)
            XCTAssertEqual(try store.data(for: saved), originalBytes)
        }
    }

    func testCorruptStoredFileIsReportedAndNeverReplacedByReimport() throws {
        try withStore { store, root in
            let input = try file(Data(soundDump), named: "Original.syx", in: root)
            let saved = try store.importFile(input)
            var corrupt = soundDump
            corrupt[11] = 0x7e
            let damagedBytes = Data(corrupt)
            let storedURL = store.directory.appendingPathComponent(saved.fileName)
            try damagedBytes.write(to: storedURL)
            XCTAssertThrowsError(try store.data(for: saved))
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.importFile(input))
            XCTAssertEqual(try Data(contentsOf: storedURL), damagedBytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count, 1)
        }
    }
}
