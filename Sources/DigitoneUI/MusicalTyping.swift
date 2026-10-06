import Foundation

/// A physical key, independent of the active keyboard layout: Latin letters
/// name the ANSI key positions, so a Russian layout plays the same notes.
enum PianoRollKey: Hashable, Sendable {
    case key(Character)
    case space, delete, escape, left, right, up, down

    /// macOS virtual key codes (Carbon kVK_*), which follow key positions.
    init?(keyCode: UInt16) {
        switch keyCode {
        case 49: self = .space
        case 51, 117: self = .delete
        case 53: self = .escape
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default:
            guard let character = Self.positions[keyCode] else { return nil }
            self = .key(character)
        }
    }

    /// A typed character: Latin as is, Cyrillic ЙЦУКЕН mapped to its key position.
    init?(character: String) {
        guard let first = character.lowercased().first, character.count == 1 else { return nil }
        if first == " " { self = .space; return }
        if let latin = Self.cyrillic[first] { self = .key(latin); return }
        guard Self.positions.values.contains(first) else { return nil }
        self = .key(first)
    }

    private static let positions: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 45: "n", 46: "m"
    ]

    private static let cyrillic: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m"
    ]
}

struct PianoRollModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let shift = PianoRollModifiers(rawValue: 1)
    static let command = PianoRollModifiers(rawValue: 2)
    static let option = PianoRollModifiers(rawValue: 4)
    static let control = PianoRollModifiers(rawValue: 8)
}

/// Key-ups belong to the surface that consumed their key-down, even if a text
/// field gains focus in between. Unrelated editor key-ups pass through.
struct PianoRollKeyOwnership {
    private(set) var held: Set<PianoRollKey> = []

    mutating func press(_ key: PianoRollKey) { held.insert(key) }
    mutating func release(_ key: PianoRollKey) -> Bool { held.remove(key) != nil }
    mutating func releaseAll() { held.removeAll() }
}

/// Logic's Musical Typing: the home row plays white keys, the row above black
/// keys; Z/X shift the octave and C/V the velocity.
struct MusicalTyping: Equatable {
    enum Action: Equatable {
        case noteOn(Int, velocity: Int)
        case noteOff(Int)
        case octave(Int)
        case velocity(Int)
    }

    /// Semitone offsets from the octave base: A W S E D F T G Y H U J K O L P ; '.
    static let noteKeys: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8, "h": 9,
        "u": 10, "j": 11, "k": 12, "o": 13, "l": 14, "p": 15, ";": 16, "'": 17
    ]
    static let baseRange = 0...108
    static let velocityStep = 10

    /// Pitch of the A key; 60 = C4.
    private(set) var base = 60
    private(set) var velocity = 100
    /// Held keys and the pitch each one started, so key-up ends the right note
    /// even after an octave change.
    private(set) var held: [Character: Int] = [:]

    var label: String { "\(PianoRollNames.name(base)) · \(velocity)" }

    static func isNoteKey(_ key: Character) -> Bool { noteKeys[key] != nil }

    /// Nil for a key that does nothing or is already held (key repeat).
    mutating func keyDown(_ key: Character) -> Action? {
        if let offset = Self.noteKeys[key] {
            guard held[key] == nil else { return nil }
            let pitch = base + offset
            guard (0...127).contains(pitch) else { return nil }
            held[key] = pitch
            return .noteOn(pitch, velocity: velocity)
        }
        switch key {
        case "z": base = max(Self.baseRange.lowerBound, base - 12); return .octave(base)
        case "x": base = min(Self.baseRange.upperBound, base + 12); return .octave(base)
        case "c": velocity = max(1, velocity - Self.velocityStep); return .velocity(velocity)
        case "v": velocity = min(127, velocity + Self.velocityStep); return .velocity(velocity)
        default: return nil
        }
    }

    mutating func keyUp(_ key: Character) -> Action? {
        held.removeValue(forKey: key).map { .noteOff($0) }
    }

    /// Releases everything held, e.g. when the surface disappears.
    mutating func releaseAll() -> [Int] {
        defer { held.removeAll() }
        return Array(Set(held.values)).sorted()
    }

    mutating func setVelocity(_ value: Int) { velocity = min(127, max(1, value)) }
}

/// Keyboard commands of the piano roll (Logic key commands where they exist).
enum PianoRollCommand: Equatable {
    case note(Character)
    case octaveDown, octaveUp, velocityDown, velocityUp
    case delete, selectAll, copy, cut, paste, duplicate, undo, redo
    case transpose(Int)
    /// In grid steps.
    case nudge(Int)
    case quantize, playStop, record, deselect

    static func command(for key: PianoRollKey, modifiers: PianoRollModifiers) -> PianoRollCommand? {
        if modifiers.contains(.command) {
            guard case .key(let character) = key, !modifiers.contains(.control), !modifiers.contains(.option) else { return nil }
            switch character {
            case "a": return .selectAll
            case "c": return .copy
            case "x": return .cut
            case "v": return .paste
            case "d": return .duplicate
            case "z": return modifiers.contains(.shift) ? .redo : .undo
            default: return nil
            }
        }
        guard !modifiers.contains(.control) else { return nil }
        switch key {
        case .space: return .playStop
        case .delete: return .delete
        case .escape: return .deselect
        case .up: return .transpose(modifiers.contains(.shift) ? 12 : 1)
        case .down: return .transpose(modifiers.contains(.shift) ? -12 : -1)
        case .left: return .nudge(-1)
        case .right: return .nudge(1)
        case .key(let character):
            guard !modifiers.contains(.option) else { return nil }
            if MusicalTyping.isNoteKey(character) { return .note(character) }
            switch character {
            case "z": return .octaveDown
            case "x": return .octaveUp
            case "c": return .velocityDown
            case "v": return .velocityUp
            case "q": return .quantize
            case "r": return .record
            default: return nil
            }
        }
    }
}
