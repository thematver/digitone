import XCTest
@testable import DigitoneUI
#if canImport(Carbon)
import Carbon.HIToolbox
#endif

final class MusicalTypingTests: XCTestCase {
    func testHomeRowPlaysWhiteKeysAndUpperRowBlackKeysFromC4() {
        var typing = MusicalTyping()
        let keys: [Character] = ["a", "w", "s", "e", "d", "f", "t", "g", "y", "h", "u", "j", "k", "o", "l", "p", ";", "'"]
        for (offset, key) in keys.enumerated() {
            XCTAssertEqual(typing.keyDown(key), .noteOn(60 + offset, velocity: 100), "\(key)")
        }
        XCTAssertEqual(Set(typing.held.values), Set(60...77))
        XCTAssertFalse(PianoRollNames.isBlack(60 + 0))
        XCTAssertTrue(PianoRollNames.isBlack(60 + 1))
        XCTAssertEqual(typing.label, "C4 · 100")
    }

    func testKeyRepeatDoesNotRetriggerAndKeyUpEndsTheStartedPitch() {
        var typing = MusicalTyping()
        XCTAssertEqual(typing.keyDown("a"), .noteOn(60, velocity: 100))
        XCTAssertNil(typing.keyDown("a"))
        XCTAssertEqual(typing.keyDown("x"), .octave(72))
        // The held key still releases the pitch it started, not the new octave.
        XCTAssertEqual(typing.keyUp("a"), .noteOff(60))
        XCTAssertNil(typing.keyUp("a"))
        XCTAssertEqual(typing.keyDown("a"), .noteOn(72, velocity: 100))
        XCTAssertNil(typing.keyUp("q"))
    }

    func testOctaveAndVelocityStayInRange() {
        var typing = MusicalTyping()
        for _ in 0..<12 { _ = typing.keyDown("z") }
        XCTAssertEqual(typing.base, 0)
        XCTAssertEqual(typing.label, "C-1 · 100")
        for _ in 0..<12 { _ = typing.keyDown("x") }
        XCTAssertEqual(typing.base, 108)
        // The top octave still reaches only valid MIDI notes (base 108 + 17 = 125).
        XCTAssertEqual(typing.keyDown("j"), .noteOn(119, velocity: 100))
        XCTAssertEqual(typing.keyDown("'"), .noteOn(125, velocity: 100))
        XCTAssertEqual(typing.held.count, 2)
        XCTAssertEqual(typing.keyDown("c"), .velocity(90))
        for _ in 0..<20 { _ = typing.keyDown("c") }
        XCTAssertEqual(typing.velocity, 1)
        for _ in 0..<20 { _ = typing.keyDown("v") }
        XCTAssertEqual(typing.velocity, 127)
        XCTAssertEqual(typing.keyDown("a"), .noteOn(108, velocity: 127))
        XCTAssertEqual(typing.releaseAll(), [108, 119, 125])
        XCTAssertTrue(typing.held.isEmpty)
    }

    func testPhysicalKeyCodesFollowTheANSILayout() {
        XCTAssertEqual(PianoRollKey(keyCode: 0), .key("a"))
        XCTAssertEqual(PianoRollKey(keyCode: 41), .key(";"))
        XCTAssertEqual(PianoRollKey(keyCode: 39), .key("'"))
        XCTAssertEqual(PianoRollKey(keyCode: 49), .space)
        XCTAssertEqual(PianoRollKey(keyCode: 51), .delete)
        XCTAssertEqual(PianoRollKey(keyCode: 126), .up)
        XCTAssertNil(PianoRollKey(keyCode: 18))
        #if canImport(Carbon)
        let carbon: [(Int, Character)] = [
            (kVK_ANSI_A, "a"), (kVK_ANSI_W, "w"), (kVK_ANSI_S, "s"), (kVK_ANSI_E, "e"), (kVK_ANSI_D, "d"), (kVK_ANSI_F, "f"),
            (kVK_ANSI_T, "t"), (kVK_ANSI_G, "g"), (kVK_ANSI_Y, "y"), (kVK_ANSI_H, "h"), (kVK_ANSI_U, "u"), (kVK_ANSI_J, "j"),
            (kVK_ANSI_K, "k"), (kVK_ANSI_O, "o"), (kVK_ANSI_L, "l"), (kVK_ANSI_P, "p"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"), (kVK_ANSI_Z, "z"), (kVK_ANSI_X, "x"), (kVK_ANSI_C, "c"), (kVK_ANSI_V, "v"),
            (kVK_ANSI_Q, "q"), (kVK_ANSI_R, "r")
        ]
        for (code, character) in carbon { XCTAssertEqual(PianoRollKey(keyCode: UInt16(code)), .key(character), "\(character)") }
        XCTAssertEqual(PianoRollKey(keyCode: UInt16(kVK_LeftArrow)), .left)
        XCTAssertEqual(PianoRollKey(keyCode: UInt16(kVK_RightArrow)), .right)
        XCTAssertEqual(PianoRollKey(keyCode: UInt16(kVK_DownArrow)), .down)
        XCTAssertEqual(PianoRollKey(keyCode: UInt16(kVK_ForwardDelete)), .delete)
        XCTAssertEqual(PianoRollKey(keyCode: UInt16(kVK_Escape)), .escape)
        #endif
    }

    func testRussianLayoutCharactersMapToTheSameKeys() {
        XCTAssertEqual(PianoRollKey(character: "ф"), .key("a"))
        XCTAssertEqual(PianoRollKey(character: "Ц"), .key("w"))
        XCTAssertEqual(PianoRollKey(character: "ж"), .key(";"))
        XCTAssertEqual(PianoRollKey(character: "э"), .key("'"))
        XCTAssertEqual(PianoRollKey(character: "я"), .key("z"))
        XCTAssertEqual(PianoRollKey(character: "A"), .key("a"))
        XCTAssertEqual(PianoRollKey(character: " "), .space)
        XCTAssertNil(PianoRollKey(character: "1"))
        XCTAssertNil(PianoRollKey(character: "ab"))
    }

    func testCommandsMatchLogicKeyCommands() {
        func command(_ key: PianoRollKey, _ modifiers: PianoRollModifiers = []) -> PianoRollCommand? {
            PianoRollCommand.command(for: key, modifiers: modifiers)
        }
        XCTAssertEqual(command(.key("a")), .note("a"))
        XCTAssertEqual(command(.key("a"), .shift), .note("a"))
        XCTAssertEqual(command(.key("a"), .command), .selectAll)
        XCTAssertEqual(command(.key("c"), .command), .copy)
        XCTAssertEqual(command(.key("x"), .command), .cut)
        XCTAssertEqual(command(.key("v"), .command), .paste)
        XCTAssertEqual(command(.key("d"), .command), .duplicate)
        XCTAssertEqual(command(.key("z"), .command), .undo)
        XCTAssertEqual(command(.key("z"), [.command, .shift]), .redo)
        XCTAssertEqual(command(.key("z")), .octaveDown)
        XCTAssertEqual(command(.key("x")), .octaveUp)
        XCTAssertEqual(command(.key("c")), .velocityDown)
        XCTAssertEqual(command(.key("v")), .velocityUp)
        XCTAssertEqual(command(.key("q")), .quantize)
        XCTAssertEqual(command(.key("r")), .record)
        XCTAssertEqual(command(.space), .playStop)
        XCTAssertEqual(command(.delete), .delete)
        XCTAssertEqual(command(.escape), .deselect)
        XCTAssertEqual(command(.up), .transpose(1))
        XCTAssertEqual(command(.down, .shift), .transpose(-12))
        XCTAssertEqual(command(.left), .nudge(-1))
        XCTAssertEqual(command(.right), .nudge(1))
        XCTAssertNil(command(.key("a"), .control))
        XCTAssertNil(command(.key("a"), .option))
        XCTAssertNil(command(.key("b")))
        XCTAssertNil(command(.key("q"), .command))
    }
    func testKeyUpOwnershipSurvivesAChangeOfFocusAndClearsOnResign() {
        var keys = PianoRollKeyOwnership()
        keys.press(.key("a"))
        keys.press(.key("s"))
        keys.press(.key("a")) // repeat
        XCTAssertEqual(keys.held.count, 2)
        // A text-field key-up that did not begin on the roll passes through.
        XCTAssertFalse(keys.release(.key("e")))
        XCTAssertTrue(keys.release(.key("a")))
        XCTAssertFalse(keys.release(.key("a")))
        keys.releaseAll()
        XCTAssertTrue(keys.held.isEmpty)
        XCTAssertFalse(keys.release(.key("s")))
    }

}
