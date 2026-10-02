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
