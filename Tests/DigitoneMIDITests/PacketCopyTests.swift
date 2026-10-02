import XCTest
import CoreMIDI
@testable import DigitoneMIDI

final class PacketCopyTests: XCTestCase {
    func testCopiesVariableLengthPacketsWithoutTruncatingToImportedTuple() throws {
        let messages: [[UInt8]] = [(0..<4096).map { UInt8($0 % 256) }, [0xb0, 16, 75], (0..<513).map { UInt8(($0 * 7) % 256) }]
        let capacity = 8192
        let memory = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: MIDIPacketList.self, capacity: 1)
        var current = MIDIPacketListInit(list)
        for (index, message) in messages.enumerated() {
            let next = message.withUnsafeBufferPointer { buffer in
                MIDIPacketListAdd(list, capacity, current, MIDITimeStamp(index + 1), message.count, buffer.baseAddress!)
            }
            current = try XCTUnwrap(next)
        }
        XCTAssertEqual(MIDITransport.copyPackets(from: UnsafePointer(list)), messages)
    }

    func testEmptyPacketList() {
        var list = MIDIPacketList()
        _ = MIDIPacketListInit(&list)
        XCTAssertEqual(MIDITransport.copyPackets(from: &list), [])
    }
}
