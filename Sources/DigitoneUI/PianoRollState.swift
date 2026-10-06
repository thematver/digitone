import SwiftUI
import DigitoneCore

/// Interaction state of the piano roll: tool, grid, zoom/scroll, what is held
/// and what is being recorded. The notes themselves live in `WorkspaceModel`.
@MainActor
final class PianoRollState: ObservableObject {
    enum Tool { case pointer, pencil }

    @Published var tool: Tool = .pointer
    @Published var snap: PianoRollSnap = .sixteenth
    /// Horizontal zoom; 1 shows the whole loop.
    @Published var zoom: Double = 1
    @Published var originTick: Double = 0
    /// Row height override; nil uses the idiom default.
    @Published var rowHeight: CGFloat?
    /// Vertical scroll; nil centres the lane's notes.
    @Published var topPitch: Double?
    @Published var typing = MusicalTyping()
    /// Key held with the pointer on the on-screen keyboard.
    @Published var pointerPitch: Int?
    /// Keys the Digitone is playing on the current lane.
    @Published var incoming: Set<Int> = []
    @Published var isRecording = false {
        didSet { if isRecording != oldValue { takeOpen = false } }
    }
    @Published var step = StepInput()
    /// Notes held during live recording, keyed by MIDI channel and pitch.
    @Published var pending: [Int: PianoRollRecorder.Pending] = [:]
    @Published var marquee: CGRect?
    /// ⌘ held: the pointer acts as the pencil (Logic).
    @Published var commandHeld = false
    /// Loop end frozen while its handle is dragged, so the zoom stays put.
    @Published var frozenExtent: Int?
    var recorder = PianoRollRecorder()
    /// Lane each pending recorded note goes to, keyed by MIDI channel and pitch.
    var pendingLane: [Int: Int] = [:]
    /// Channel each note played from this surface sounds on, by pitch.
    var sounding: [Int: Int] = [:]
    /// Audition generations by channel/pitch, so an old release cannot cut off a new audition.
    var previews: [Int: UUID] = [:]
    /// The first recorded note of a take records the undo step.
    var takeOpen = false
    /// Length of the last created or resized note (Logic's "last length").
    var lastLength = MusicalTime.ticksPerStep
    /// Two-finger scroll or pinch in progress (touch): single-finger edits pause.
    var multiTouch = false
    /// A playhead shown while nothing plays; used only by snapshot scenes.
    var demoPlayhead: Double?

    var effectiveTool: Tool { commandHeld ? .pencil : tool }

    /// Pitches this surface currently holds down (typing and pointer).
    var heldPitches: Set<Int> {
        var pitches = Set(typing.held.values)
        if let pointerPitch { pitches.insert(pointerPitch) }
        return pitches
    }

    func resetView() {
        zoom = 1; originTick = 0; topPitch = nil
        step.reset(to: 0); pending = [:]; pendingLane = [:]
        recorder = PianoRollRecorder()
    }
}
