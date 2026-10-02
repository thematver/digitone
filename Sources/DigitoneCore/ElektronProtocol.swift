import Foundation

public enum ProtocolError: Error, LocalizedError, Equatable {
    case malformed(String)
    case checksum
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let reason): return "Повреждённые данные: \(reason)"
        case .checksum: return "Контрольная сумма передачи не совпала."
        case .unsupported(let reason): return "Неподдерживаемый формат: \(reason)"
        }
    }
}

public enum SevenBit {
    public static func encode(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + (bytes.count + 6) / 7)
        for start in stride(from: 0, to: bytes.count, by: 7) {
            let count = min(7, bytes.count - start)
            var highBits: UInt8 = 0
            for i in 0..<count { highBits |= ((bytes[start + i] >> 7) & 1) << (6 - i) }
            output.append(highBits)
            for i in 0..<count { output.append(bytes[start + i] & 0x7f) }
        }
        return output
    }

    public static func decode(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.allSatisfy({ $0 < 128 }) else { throw ProtocolError.malformed("7-bit payload") }
        var output: [UInt8] = []
        for start in stride(from: 0, to: bytes.count, by: 8) {
            let count = min(7, bytes.count - start - 1)
            guard count > 0 else { throw ProtocolError.malformed("empty packing group") }
            let mask = bytes[start]
            let unusedMask = UInt8((1 << (7 - count)) - 1)
            guard mask & unusedMask == 0 else { throw ProtocolError.malformed("unused packing bits") }
            for i in 0..<count { output.append(bytes[start + i + 1] | (((mask >> (6 - i)) & 1) << 7)) }
        }
        return output
    }
}

public struct APIMessage: Equatable, Sendable {
    public let messageID: UInt16
    public let responseID: UInt16
    public let opcode: UInt8
    public let arguments: [UInt8]

    public init(messageID: UInt16, responseID: UInt16 = 0, opcode: UInt8, arguments: [UInt8] = []) {
        self.messageID = messageID
        self.responseID = responseID
        self.opcode = opcode
        self.arguments = arguments
    }

    public var bytes: [UInt8] {
        let body = [UInt8(messageID >> 8), UInt8(messageID & 255), UInt8(responseID >> 8), UInt8(responseID & 255), opcode] + arguments
        return [0xf0, 0, 0x20, 0x3c, 0x10, 0] + SevenBit.encode(body) + [0xf7]
    }
}

public struct DumpMessage: Equatable, Sendable {
    public let family: UInt8
    public let type: UInt8
    public let version: [UInt8]
    public let index: UInt8
    public let payload: [UInt8]
    public let raw: [UInt8]
}

public enum ElektronMessage: Equatable, Sendable {
    case api(APIMessage)
    case dump(DumpMessage)
}

public enum ElektronProtocol {
    public static let digitoneFamily: UInt8 = 0x15
    public static let digitoneProduct: UInt8 = 43

    // Read requests have an empty payload. Payload-bearing dumps write hardware;
    // their construction is deliberately absent from the public transport API.
    public static func dumpRequest(type: UInt8 = 0x60, index: UInt8) throws -> [UInt8] {
        guard (0x60...0x64).contains(type), index < 128 else {
            throw ProtocolError.unsupported("read request")
        }
        return [0xf0, 0, 0x20, 0x3c, digitoneFamily, 0, type, 1, 1, index, 0, 0, 0, 5, 0xf7]
    }

    public static func parse(_ raw: [UInt8]) throws -> ElektronMessage {
        guard raw.count >= 8, raw.first == 0xf0, raw.last == 0xf7,
              Array(raw[1..<4]) == [0, 0x20, 0x3c], raw[5] == 0,
              raw.dropFirst().dropLast().allSatisfy({ $0 < 128 }) else {
            throw ProtocolError.malformed("SysEx header or framing")
        }
        if raw[4] == 0x10 {
            let body = try SevenBit.decode(Array(raw[6..<(raw.count - 1)]))
            guard body.count >= 5 else { throw ProtocolError.malformed("API body") }
            return .api(APIMessage(messageID: u16(body, 0), responseID: u16(body, 2), opcode: body[4], arguments: Array(body.dropFirst(5))))
        }
        guard raw.count >= 15 else { throw ProtocolError.malformed("dump size") }
        let encoded = Array(raw[10..<(raw.count - 5)])
        let checksum = Int(raw[raw.count - 5]) * 128 + Int(raw[raw.count - 4])
        let count = Int(raw[raw.count - 3]) * 128 + Int(raw[raw.count - 2])
        guard encoded.reduce(0, { $0 + Int($1) }) & 0x3fff == checksum,
              (encoded.count + 5) & 0x3fff == count else { throw ProtocolError.checksum }
        return .dump(DumpMessage(family: raw[4], type: raw[6], version: Array(raw[7...8]), index: raw[9], payload: try SevenBit.decode(encoded), raw: raw))
    }

    public static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    public static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[offset + $1]) }
    }

    public static func cString(_ bytes: [UInt8], offset: Int = 0) throws -> (String, Int) {
        guard offset >= 0, offset < bytes.count,
              let end = bytes[offset...].firstIndex(of: 0) else { throw ProtocolError.malformed("unterminated string") }
        return (String(bytes: bytes[offset..<end], encoding: .windowsCP1252) ?? "", end + 1)
    }
}

public struct DeviceIdentity: Equatable, Codable, Sendable {
    public let productID: UInt8
    public let name: String
    public let version: String
    public let build: String
    public let supportedOpcodes: [UInt8]
    public var isDigitoneII: Bool { productID == ElektronProtocol.digitoneProduct }
    public var hasKnownPatternFormat: Bool { isDigitoneII && version == "1.10D" && build == "0049" }

    public init(deviceReply: [UInt8], versionReply: [UInt8]) throws {
        guard deviceReply.count >= 3 else { throw ProtocolError.malformed("identity") }
        let count = Int(deviceReply[1])
        guard deviceReply.count > 2 + count else { throw ProtocolError.malformed("identity capabilities") }
        productID = deviceReply[0]
        supportedOpcodes = Array(deviceReply[2..<(2 + count)])
        name = try ElektronProtocol.cString(deviceReply, offset: 2 + count).0
        let (buildString, next) = try ElektronProtocol.cString(versionReply)
        build = buildString
        version = try ElektronProtocol.cString(versionReply, offset: next).0
    }
}
