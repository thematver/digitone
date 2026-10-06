import Foundation
import XCTest
@testable import DigitoneCore

final class SnapshotStoreTests: XCTestCase {
    private func withStore(_ body: (SnapshotStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digitone-snapshot-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SnapshotStore(directory: directory))
    }

    private func snapshot(channel: Int = 15, parameters: [String: Int] = ["syn.1.a": 0, "filter.frequency": 127]) -> SoundSnapshot {
        SoundSnapshot(name: "Стекло", machine: .fmTone, channel: channel, parameters: parameters,
                      createdAt: Date(timeIntervalSinceReferenceDate: 12345.125), tags: ["Pad", "Холодный"])
    }

    func testMissingLibraryIsEmptyAndRoundTripPreservesAllFields() throws {
        try withStore { store in
            XCTAssertEqual(try store.load(), [])
            let sound = snapshot()
            try store.save([sound])
            XCTAssertEqual(try store.load(), [sound])
            try store.save([])
            XCTAssertEqual(try store.load(), [])
        }
    }

    func testFavoriteRoundTripKeepsSchemaOne() throws {
        try withStore { store in
            var sound = snapshot()
            XCTAssertFalse(sound.isFavorite)
            sound.isFavorite = true
            try store.save([sound])
            XCTAssertEqual(try store.load(), [sound])
            let data = try Data(contentsOf: store.fileURL)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            XCTAssertEqual(try SnapshotArchive.decode(data), [sound])
        }
    }

    func testLegacyLibraryWithoutTagsAndFavoriteLoadsAndCanBeSaved() throws {
        try withStore { store in
            let sound = snapshot()
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SnapshotArchive.encode([sound])) as? [String: Any])
            var sounds = try XCTUnwrap(object["snapshots"] as? [[String: Any]])
            sounds[0].removeValue(forKey: "tags")
            sounds[0].removeValue(forKey: "isFavorite")
            object["snapshots"] = sounds
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
            var expected = sound
            expected.tags = []
            XCTAssertEqual(try store.load(), [expected])
            expected.isFavorite = true
            try store.save([expected])
            XCTAssertEqual(try store.load(), [expected])
        }
    }

    func testSchemaOneWithoutFavoritePreservesExistingTags() throws {
        let sound = snapshot()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SnapshotArchive.encode([sound])) as? [String: Any])
        var sounds = try XCTUnwrap(object["snapshots"] as? [[String: Any]])
        sounds[0].removeValue(forKey: "isFavorite")
        object["snapshots"] = sounds
        XCTAssertEqual(try SnapshotArchive.decode(JSONSerialization.data(withJSONObject: object)), [sound])
    }

    func testTagsAreTrimmedDeduplicatedAndKeepFirstSpelling() {
        XCTAssertEqual(SoundSnapshot.normalizedTags(from: "  Pad, , Холодный, pad,\nХОЛОДНЫЙ , Bass  "),
                       ["Pad", "Холодный", "Bass"])
        XCTAssertEqual(SoundSnapshot.normalizedTags(from: " , \n ,"), [])
    }

    func testArchiveRoundTripPreservesIDsAndAllMetadata() throws {
        var favorite = snapshot()
        favorite.isFavorite = true
        let another = SoundSnapshot(name: "Бас", machine: .wavetone, channel: 0,
                                    parameters: ["filter.frequency": 63], tags: ["Bass"])
        let sounds = [favorite, another]
        let decoded = try SnapshotArchive.decode(SnapshotArchive.encode(sounds))
        XCTAssertEqual(decoded, sounds)
        XCTAssertEqual(decoded.map(\.id), sounds.map(\.id))
        XCTAssertEqual(try SnapshotArchive.decode(SnapshotArchive.encode([])), [])
    }

    func testArchiveChecksSchemaBeforeReadingPayloadAndRejectsCorruptValues() throws {
        XCTAssertThrowsError(try SnapshotArchive.decode(Data("{\"schemaVersion\":99}".utf8))) {
            XCTAssertEqual($0 as? SnapshotStoreError, .unsupportedSchema(99))
        }
        XCTAssertThrowsError(try SnapshotArchive.decode(Data("{ invalid JSON".utf8))) {
            guard let error = $0 as? SnapshotStoreError, case .unreadableLibrary = error else {
                return XCTFail("Expected unreadable library, got \($0)")
            }
        }
        let sound = snapshot()
        let validData = try SnapshotArchive.encode([sound])
        let invalidFields: [[String: Any]] = [
            ["channel": 16],
            ["name": " \n "],
            ["parameters": ["filter.frequency": 128]],
            ["parameters": ["unknown": 10]],
            ["isFavorite": "yes"],
            ["tags": "Pad"]
        ]
        for fields in invalidFields {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
            var sounds = try XCTUnwrap(object["snapshots"] as? [[String: Any]])
            for (key, value) in fields { sounds[0][key] = value }
            object["snapshots"] = sounds
            XCTAssertThrowsError(try SnapshotArchive.decode(JSONSerialization.data(withJSONObject: object)),
                                 "Archive accepted corrupt fields \(fields)")
        }
        var duplicateObject = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        let encodedSound = try XCTUnwrap((duplicateObject["snapshots"] as? [[String: Any]])?.first)
        duplicateObject["snapshots"] = [encodedSound, encodedSound]
        XCTAssertThrowsError(try SnapshotArchive.decode(JSONSerialization.data(withJSONObject: duplicateObject))) {
            XCTAssertEqual($0 as? SnapshotStoreError, .invalidSnapshot("повторяющийся идентификатор"))
        }
        XCTAssertThrowsError(try SnapshotArchive.encode([snapshot(channel: -1)]))
        XCTAssertThrowsError(try SnapshotArchive.encode([sound, sound]))
    }

    func testImportSkipsIdenticalIDsAndAppendsNewSnapshots() throws {
        let original = snapshot()
        let newSound = snapshot(channel: 1)
        let result = try SnapshotArchive.merge([original, newSound], into: [original])
        XCTAssertEqual(result.snapshots, [original, newSound])
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.copiedCount, 0)
        let repeated = try SnapshotArchive.merge([original, newSound], into: result.snapshots)
        XCTAssertEqual(repeated.snapshots, result.snapshots)
        XCTAssertEqual(repeated.addedCount, 0)
        XCTAssertEqual(repeated.skippedCount, 2)
    }

    func testImportCopiesIDConflictsAndPreservesBothVersions() throws {
        let original = snapshot()
        var edited = original
        edited.name = "Импортированное стекло"
        edited.parameters["filter.frequency"] = 50
        edited.tags = ["Atmosphere"]
        edited.isFavorite = true
        let newSound = snapshot(channel: 1)
        let result = try SnapshotArchive.merge([edited, newSound], into: [original])
        XCTAssertEqual(result.snapshots.first, original)
        XCTAssertEqual(result.snapshots.last, newSound)
        let copy = try XCTUnwrap(result.snapshots.dropFirst().first)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.id, newSound.id)
        XCTAssertEqual(copy.name, edited.name)
        XCTAssertEqual(copy.machine, edited.machine)
        XCTAssertEqual(copy.channel, edited.channel)
        XCTAssertEqual(copy.parameters, edited.parameters)
        XCTAssertEqual(copy.createdAt, edited.createdAt)
        XCTAssertEqual(copy.tags, edited.tags)
        XCTAssertEqual(copy.isFavorite, edited.isFavorite)
        XCTAssertEqual(Set(result.snapshots.map(\.id)).count, result.snapshots.count)
        XCTAssertEqual(result.addedCount, 2)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(try SnapshotArchive.decode(SnapshotArchive.encode(result.snapshots)), result.snapshots)
    }

    func testFavoriteOnlyIDConflictIsCopiedAndMergeValidatesBothInputs() throws {
        let original = snapshot()
        var favorite = original
        favorite.isFavorite = true
        let result = try SnapshotArchive.merge([favorite], into: [original])
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.snapshots.count, 2)
        XCTAssertFalse(result.snapshots[0].isFavorite)
        XCTAssertTrue(result.snapshots[1].isFavorite)
        XCTAssertThrowsError(try SnapshotArchive.merge([snapshot(channel: 16)], into: [original]))
        XCTAssertThrowsError(try SnapshotArchive.merge([original, original], into: []))
        XCTAssertThrowsError(try SnapshotArchive.merge([], into: [snapshot(channel: -1)]))
    }

    func testInvalidChannelsParametersAndIDsCannotReplaceValidLibrary() throws {
        try withStore { store in
            let original = snapshot()
            try store.save([original])
            let originalData = try Data(contentsOf: store.fileURL)
            let invalid = [snapshot(channel: -1), snapshot(channel: 16), snapshot(parameters: ["filter.frequency": -1]),
                           snapshot(parameters: ["filter.frequency": 128]), snapshot(parameters: ["arbitrary.write": 50])]
            for sound in invalid {
                XCTAssertThrowsError(try store.save([sound]))
                XCTAssertEqual(try Data(contentsOf: store.fileURL), originalData)
            }
            XCTAssertThrowsError(try store.save([original, original]))
            var emptyName = original
            emptyName.name = " \n "
            XCTAssertThrowsError(try store.save([emptyName]))
        }
    }

    func testCorruptLibraryIsPreservedOnLoadAndOnSave() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let corrupt = Data("{ invalid JSON".utf8)
            try corrupt.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([snapshot()]))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
        }
    }

    func testUnknownSchemaAndInvalidStoredValuesArePreserved() throws {
        try withStore { store in
            try store.save([snapshot()])
            let valid = try Data(contentsOf: store.fileURL)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            object["schemaVersion"] = 2
            let futureData = try JSONSerialization.data(withJSONObject: object)
            try futureData.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? SnapshotStoreError, .unsupportedSchema(2)) }
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), futureData)
            object["schemaVersion"] = 1
            var sounds = try XCTUnwrap(object["snapshots"] as? [[String: Any]])
            sounds[0]["parameters"] = ["filter.frequency": 200]
            object["snapshots"] = sounds
            let invalidData = try JSONSerialization.data(withJSONObject: object)
            try invalidData.write(to: store.fileURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save([]))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), invalidData)
        }
    }

    func testCatalogUsesMachineSpecificLabelsAndDocumentedAddresses() {
        for machine in SynthMachine.allCases {
            let parameters = ParameterCatalog.parameters(for: machine)
            XCTAssertEqual(Set(parameters.map(\.id)).count, parameters.count)
            XCTAssertEqual(Array(parameters.prefix(8)).map(\.cc), (40...47).map { Optional($0) })
            XCTAssertEqual(Array(parameters.prefix(8)).map(\.nrpn), Array(201...208))
        }
        XCTAssertEqual(ParameterCatalog.parameters(for: .fmTone)[0].title, "Algorithm")
        XCTAssertEqual(ParameterCatalog.parameters(for: .wavetone)[0].title, "Osc 1 tune")
        XCTAssertEqual(ParameterCatalog.common.first { $0.id == "amp.sustain" }?.nrpn, 161)
        XCTAssertNil(ParameterCatalog.common.first { $0.id == "amp.sustain" }?.cc)
        XCTAssertEqual(ParameterCatalog.common.first { $0.id == "track.level" }?.cc, 95)
    }
}
