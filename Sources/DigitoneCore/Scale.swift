import Foundation

/// The Digitone II keyboard scales, in the order of the manual's
/// "APPENDIX E: KEYBOARD SCALES" (OS 1.12). The manual lists names only;
/// intervals are the standard definitions of those names. For names with
/// several conventions (HIRAJOSHI, PELOG, SPANISH, COMBO MINOR) the common
/// variant is used and has not been compared against the instrument.
public enum ScaleKind: String, CaseIterable, Codable, Sendable {
    case chromatic, ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian
    case pentatonicMinor, pentatonicMajor, melodicMinor, harmonicMinor, wholeTone, blues
    case comboMinor, persian, iwato, inSen, hirajoshi, pelog, phrygianDominant
    case wholeHalfDiminished, halfWholeDiminished, spanish, majorLocrian, superLocrian
    case dorianFlat2, lydianAugmented, lydianDominant, doubleHarmonicMajor, lydianSharp2Sharp6
    case ultraphrygian, hungarianMinor, oriental, ionianSharp2Sharp5, locrianDoubleFlat3DoubleFlat7

    public static let major = ScaleKind.ionian
    public static let minor = ScaleKind.aeolian

    /// The name as printed in the manual.
    public var name: String {
        switch self {
        case .chromatic: return "CHROMATIC"
        case .ionian: return "IONIAN (MAJOR)"
        case .dorian: return "DORIAN"
        case .phrygian: return "PHRYGIAN"
        case .lydian: return "LYDIAN"
        case .mixolydian: return "MIXOLYDIAN"
        case .aeolian: return "AEOLIAN (MINOR)"
        case .locrian: return "LOCRIAN"
        case .pentatonicMinor: return "PENTATONIC MINOR"
        case .pentatonicMajor: return "PENTATONIC MAJOR"
        case .melodicMinor: return "MELODIC MINOR"
        case .harmonicMinor: return "HARMONIC MINOR"
        case .wholeTone: return "WHOLE TONE"
        case .blues: return "BLUES"
        case .comboMinor: return "COMBO MINOR"
        case .persian: return "PERSIAN"
        case .iwato: return "IWATO"
        case .inSen: return "IN-SEN"
        case .hirajoshi: return "HIRAJOSHI"
        case .pelog: return "PELOG"
        case .phrygianDominant: return "PHRYGIAN DOMINANT"
        case .wholeHalfDiminished: return "WHOLE-HALF DIMINISHED"
        case .halfWholeDiminished: return "HALF-WHOLE DIMINISHED"
        case .spanish: return "SPANISH"
        case .majorLocrian: return "MAJOR LOCRIAN"
        case .superLocrian: return "SUPER LOCRIAN"
        case .dorianFlat2: return "DORIAN b2"
        case .lydianAugmented: return "LYDIAN AUGMENTED"
        case .lydianDominant: return "LYDIAN DOMINANT"
        case .doubleHarmonicMajor: return "DOUBLE HARMONIC MAJOR"
        case .lydianSharp2Sharp6: return "LYDIAN #2 #6"
        case .ultraphrygian: return "ULTRAPHRYGIAN"
        case .hungarianMinor: return "HUNGARIAN MINOR"
        case .oriental: return "ORIENTAL"
        case .ionianSharp2Sharp5: return "IONIAN #2 #5"
        case .locrianDoubleFlat3DoubleFlat7: return "LOCRIAN bb3 bb7"
        }
    }

    /// Ascending semitone offsets from the root, starting at 0.
    public var intervals: [Int] {
        switch self {
        case .chromatic: return Array(0..<12)
        case .ionian: return [0, 2, 4, 5, 7, 9, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .aeolian: return [0, 2, 3, 5, 7, 8, 10]
        case .locrian: return [0, 1, 3, 5, 6, 8, 10]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .melodicMinor: return [0, 2, 3, 5, 7, 9, 11]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .wholeTone: return [0, 2, 4, 6, 8, 10]
        case .blues: return [0, 3, 5, 6, 7, 10]
        // Natural, harmonic and melodic minor combined.
        case .comboMinor: return [0, 2, 3, 5, 7, 8, 9, 10, 11]
        case .persian: return [0, 1, 4, 5, 6, 8, 11]
        case .iwato: return [0, 1, 5, 6, 10]
        case .inSen: return [0, 1, 5, 7, 10]
        case .hirajoshi: return [0, 2, 3, 7, 8]
        case .pelog: return [0, 1, 3, 7, 8]
        case .phrygianDominant: return [0, 1, 4, 5, 7, 8, 10]
        case .wholeHalfDiminished: return [0, 2, 3, 5, 6, 8, 9, 11]
        case .halfWholeDiminished: return [0, 1, 3, 4, 6, 7, 9, 10]
        // Eight-tone Spanish; the seven-tone variant is PHRYGIAN DOMINANT.
        case .spanish: return [0, 1, 3, 4, 5, 6, 8, 10]
        case .majorLocrian: return [0, 2, 4, 5, 6, 8, 10]
        case .superLocrian: return [0, 1, 3, 4, 6, 8, 10]
        case .dorianFlat2: return [0, 1, 3, 5, 7, 9, 10]
        case .lydianAugmented: return [0, 2, 4, 6, 8, 9, 11]
        case .lydianDominant: return [0, 2, 4, 6, 7, 9, 10]
        case .doubleHarmonicMajor: return [0, 1, 4, 5, 7, 8, 11]
        case .lydianSharp2Sharp6: return [0, 3, 4, 6, 7, 10, 11]
        case .ultraphrygian: return [0, 1, 3, 4, 7, 8, 9]
        case .hungarianMinor: return [0, 2, 3, 6, 7, 8, 11]
        case .oriental: return [0, 1, 4, 5, 6, 9, 10]
        case .ionianSharp2Sharp5: return [0, 3, 4, 5, 8, 9, 11]
        case .locrianDoubleFlat3DoubleFlat7: return [0, 1, 2, 5, 6, 8, 9]
        }
    }
}

/// A scale anchored to a root pitch class.
public struct Scale: Hashable, Codable, Sendable {
    /// Pitch class of the root, 0 = C ... 11 = B.
    public var root: Int
    public var kind: ScaleKind

    public init(root: Int = 0, kind: ScaleKind) {
        self.root = Self.pitchClass(root)
        self.kind = kind
    }

    public static let chromatic = Scale(kind: .chromatic)

    public func isInScale(_ pitch: Int) -> Bool {
        kind.intervals.contains(Self.pitchClass(Self.pitchClass(pitch) - Self.pitchClass(root)))
    }

    /// The nearest in-scale pitch within 0...127; equal distances fold down.
    public func fold(_ pitch: Int) -> Int {
        let clamped = min(127, max(0, pitch))
        for distance in 0..<12 {
            for candidate in [clamped - distance, clamped + distance]
            where (0...127).contains(candidate) && isInScale(candidate) {
                return candidate
            }
        }
        return clamped // Unreachable: every scale contains its root.
    }

    private static func pitchClass(_ value: Int) -> Int { (value % 12 + 12) % 12 }
}
