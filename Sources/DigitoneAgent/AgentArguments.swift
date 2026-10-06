import Foundation

struct AgentArguments {
    let values: [String: JSONValue]
    init(_ values: [String: JSONValue], allowed: Set<String>) throws {
        guard let unexpected = Set(values.keys).subtracting(allowed).sorted().first else { self.values = values; return }
        throw AgentError("Unknown argument '\(unexpected)'.")
    }

    func string(_ key: String, default fallback: String? = nil) throws -> String {
        if values[key] == nil, let fallback { return fallback }
        guard let value = values[key]?.string, !value.isEmpty, value.utf8.count <= 4096 else {
            throw AgentError("\(key) must be a nonempty string (at most 4096 UTF-8 bytes).")
        }
        return value
    }
    func number(_ key: String, range: ClosedRange<Double>, default fallback: Double? = nil) throws -> Double {
        if values[key] == nil, let fallback { return fallback }
        guard let number = values[key]?.number, number.isFinite, range.contains(number) else {
            throw AgentError("\(key) must be a number in \(range).")
        }
        return number
    }
    func int(_ key: String, range: ClosedRange<Int>, default fallback: Int? = nil) throws -> Int {
        let value = try number(key, range: Double(range.lowerBound)...Double(range.upperBound), default: fallback.map(Double.init))
        guard value.rounded(.towardZero) == value else { throw AgentError("\(key) must be an integer.") }
        return Int(value)
    }
    func bool(_ key: String, default fallback: Bool = false) throws -> Bool {
        if values[key] == nil { return fallback }
        guard let value = values[key]?.bool else { throw AgentError("\(key) must be true or false.") }
        return value
    }
    func uuid(_ key: String) throws -> UUID {
        guard let value = UUID(uuidString: try string(key)) else { throw AgentError("\(key) must be a UUID.") }
        return value
    }
    func parameters(_ key: String = "parameters") throws -> [String: Int] {
        guard let values = values[key]?.object, values.count <= 256 else { throw AgentError("\(key) must be an object of parameter IDs and integer values.") }
        return try values.mapValues { value in
            guard let number = value.number, number.isFinite, (0...127).contains(number), number.rounded(.towardZero) == number else {
                throw AgentError("Parameter values must be integers in 0...127; catalog ranges can be smaller.")
            }
            return Int(number)
        }
    }

    /// Paths are absolute and never expanded by a shell. File writes use no-clobber by default.
    func fileURL(_ key: String = "path") throws -> URL {
        let path = try string(key)
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw AgentError("\(key) must be an absolute filesystem path.") }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
