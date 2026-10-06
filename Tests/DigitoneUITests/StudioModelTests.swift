import Foundation
import XCTest
import DigitoneCore
@testable import DigitoneUI

final class StudioModelTests: XCTestCase {
    @MainActor
    private func withLibrary(_ body: (StudioModel, SnapshotStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("digitone-model-tests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(StudioModel(directory: directory, startMIDI: false), SnapshotStore(directory: directory))
    }

    @MainActor
    func testSavingFavoriteAndMetadataSurvivesReopeningAndFiltering() throws {
        try withLibrary { model, store in
            let frequency = try XCTUnwrap(ParameterCatalog.common.first { $0.id == "filter.frequency" })
            model.channel = 9
            model.machine = .wavetone
            model.change(frequency, to: 77)
            model.snapshotName = "  Glass pad  "
            model.snapshotTags = "Pad, Space, pad, ,"
            model.saveSnapshot()
            let saved = try XCTUnwrap(model.snapshots.first)
            XCTAssertEqual(saved.name, "Glass pad")
            XCTAssertEqual(saved.channel, 9)
            XCTAssertEqual(saved.machine, .wavetone)
            XCTAssertEqual(saved.parameters, ["filter.frequency": 77])
            XCTAssertEqual(saved.tags, ["Pad", "Space"])
            model.toggleFavorite(saved)
            XCTAssertTrue(try XCTUnwrap(store.load().first).isFavorite)

            let reopened = StudioModel(directory: store.directory, startMIDI: false)
            reopened.favoritesOnly = true
            reopened.libraryMachine = .wavetone
            reopened.libraryTag = "pad"
            reopened.search = "glass"
            XCTAssertEqual(reopened.filteredSnapshots.map(\.id), [saved.id])
            reopened.libraryMachine = .fmTone
            XCTAssertTrue(reopened.filteredSnapshots.isEmpty)
            reopened.resetLibraryFilters()
            XCTAssertFalse(reopened.hasLibraryFilters)
            XCTAssertEqual(reopened.filteredSnapshots.count, 1)

            XCTAssertTrue(reopened.updateSnapshot(saved.id, name: "  Ice  ", tags: "Cold, Glass, cold"))
            let persisted = try XCTUnwrap(store.load().first)
            XCTAssertEqual(persisted.id, saved.id)
            XCTAssertEqual(persisted.name, "Ice")
            XCTAssertEqual(persisted.tags, ["Cold", "Glass"])
            XCTAssertTrue(persisted.isFavorite)
            XCTAssertEqual(persisted.parameters, saved.parameters)
        }
    }

    @MainActor
    func testSnapshotImportSkipsDuplicatesAndRejectedImportPreservesMemoryAndDisk() throws {
        try withLibrary { model, store in
            let snapshot = SoundSnapshot(name: "Bass", machine: .fmTone, channel: 3,
                                         parameters: ["filter.frequency": 31], tags: ["Bass"], isFavorite: true)
            let archive = try SnapshotArchive.encode([snapshot])
            model.importSnapshots(archive)
            XCTAssertEqual(model.snapshots, [snapshot])
            XCTAssertEqual(try store.load(), [snapshot])
            let storedBytes = try Data(contentsOf: store.fileURL)
            model.importSnapshots(archive)
            XCTAssertEqual(model.snapshots, [snapshot])
            XCTAssertEqual(try Data(contentsOf: store.fileURL), storedBytes)

            let invalidArchives = [Data("{broken JSON".utf8),
                                   Data("{\"schemaVersion\":999,\"snapshots\":[]}".utf8)]
            for invalid in invalidArchives {
                model.importSnapshots(invalid)
                XCTAssertNotNil(model.error)
                XCTAssertEqual(model.snapshots, [snapshot])
                XCTAssertEqual(try Data(contentsOf: store.fileURL), storedBytes)
            }
        }
    }

    @MainActor
    func testCorruptExistingLibraryIsRetainedWhenTheUserTriesToSave() throws {
        try withLibrary { _, store in
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let original = Data("{\"schemaVersion\":42,\"snapshots\":[]}".utf8)
            try original.write(to: store.fileURL)
            let reopened = StudioModel(directory: store.directory, startMIDI: false)
            XCTAssertFalse(reopened.storageAvailable)
            XCTAssertNotNil(reopened.error)
            reopened.values[reopened.route] = ["filter.frequency": KnownParameter(value: 20, origin: .draft)]
            reopened.snapshotName = "Recoverable draft"
            reopened.saveSnapshot()
            reopened.importSnapshots(try SnapshotArchive.encode([
                SoundSnapshot(name: "Imported", machine: .fmTone, channel: 0, parameters: [:])
            ]))
            XCTAssertTrue(reopened.snapshots.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
            XCTAssertEqual(reopened.known["filter.frequency"]?.value, 20)
        }
    }

    @MainActor
    func testLoadingDifferentChannelAndMachineKeepsThePreviousRouteValues() throws {
        try withLibrary { model, _ in
            let originalRoute = "0:fmTone"
            model.values[originalRoute] = [
                "filter.frequency": KnownParameter(value: 25, origin: .received),
                "amp.volume": KnownParameter(value: 50, origin: .sent)
            ]
            model.values["9:fmTone"] = ["filter.frequency": KnownParameter(value: 12, origin: .received)]
            let snapshot = SoundSnapshot(name: "Wave", machine: .wavetone, channel: 9,
                                         parameters: ["filter.frequency": 73, "syn.1.a": 40])
            model.load(snapshot)
            XCTAssertEqual(model.channel, 9)
            XCTAssertEqual(model.machine, .wavetone)
            XCTAssertEqual(model.route, "9:wavetone")
            XCTAssertEqual(model.known.mapValues(\.value), snapshot.parameters)
            XCTAssertTrue(model.known.values.allSatisfy { $0.origin == .draft })
            XCTAssertEqual(model.values[originalRoute]?["filter.frequency"]?.value, 25)
            XCTAssertEqual(model.values[originalRoute]?["filter.frequency"]?.origin, .received)
            XCTAssertEqual(model.values[originalRoute]?["amp.volume"]?.value, 50)
            XCTAssertEqual(model.values[originalRoute]?["amp.volume"]?.origin, .sent)
            XCTAssertFalse(model.canApply)
        }
    }

    @MainActor
    func testABCheckpointDoesNotApplyToAnotherMidiRoute() throws {
        try withLibrary { model, _ in
            model.values[model.route] = ["filter.frequency": KnownParameter(value: 25, origin: .draft)]
            model.checkpoint("A")
            XCTAssertTrue(model.hasCheckpoint("A"))
            model.channel = 9
            model.values[model.route] = ["filter.frequency": KnownParameter(value: 90, origin: .draft)]
            XCTAssertFalse(model.hasCheckpoint("A"))
            model.useCheckpoint("A")
            XCTAssertEqual(model.known["filter.frequency"]?.value, 90)
            model.channel = 0
            model.values[model.route] = ["filter.frequency": KnownParameter(value: 60, origin: .draft)]
            model.useCheckpoint("A")
            XCTAssertEqual(model.known["filter.frequency"]?.value, 25)
            XCTAssertEqual(model.known["filter.frequency"]?.origin, .draft)
        }
    }
}
