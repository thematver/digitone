import Foundation

public enum AgentToolCatalog {
    static func text(_ description: String = "") -> JSONValue { .object(["type": .string("string"), "description": .string(description)]) }
    static func integer(_ low: Int, _ high: Int, _ description: String = "") -> JSONValue {
        .object(["type": .string("integer"), "minimum": .integer(low), "maximum": .integer(high), "description": .string(description)])
    }
    static func number(_ low: Double, _ high: Double, _ description: String = "") -> JSONValue {
        .object(["type": .string("number"), "minimum": .number(low), "maximum": .number(high), "description": .string(description)])
    }
    static func choice(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))]) }
    static let boolean: JSONValue = .object(["type": .string("boolean")])
    static let channel = integer(1, 16, "Exact MIDI CONFIG → CHANNELS track channel on Digitone. Channel 1 is encoded as 0 internally.")
    static let track = integer(1, 16, "Digitone audio track number. Track does not imply a MIDI channel: set midiChannel explicitly.")
    static let machine = choice(["fmTone", "fmDrum", "wavetone", "swarmer"])
    static let parameters: JSONValue = .object(["type": .string("object"), "maxProperties": .integer(256),
        "additionalProperties": integer(0, 127), "description": .string("HardwareCatalog ID → coarse MIDI value. Discover valid IDs and narrower ranges using digitone_parameter_catalog. Unspecified parameters stay unknown.")])
    static let note: JSONValue = .object(["type": .string("object"), "additionalProperties": .bool(false),
        "properties": .object(["pitch": integer(0, 127), "velocity": integer(1, 127),
                               "step": number(1, 65536, "1-based sixteenth-note step; fractional steps allow microtiming."),
                               "length": number(1.0 / 24, 65536, "Duration measured in sixteenth-note steps.")]),
        "required": .array(["pitch", "step", "length"].map(JSONValue.string))])

    static func tool(_ name: String, _ description: String, properties: [String: JSONValue] = [:], required: [String] = [],
                     readOnly: Bool = false, destructive: Bool = false) -> JSONValue {
        .object(["name": .string(name), "description": .string(description),
                 "inputSchema": .object(["type": .string("object"), "properties": .object(properties),
                                         "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)]),
                 "annotations": .object(["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                                         "openWorldHint": .bool(false)])])
    }

    public static let tools: [JSONValue] = [
        tool("digitone_list_devices", "List exact CoreMIDI input and output endpoint IDs. Does not connect or send MIDI.", readOnly: true),
        tool("digitone_connect", "Connect exact endpoint IDs and identify a Digitone II. Sends identity/version requests, no sound changes.",
             properties: ["sourceID": integer(Int(Int32.min), Int(Int32.max)), "destinationID": integer(Int(Int32.min), Int(Int32.max))], required: ["sourceID", "destinationID"]),
        tool("digitone_status", "Connection/playback status and local project summary. No hardware readback of sounds is claimed.", readOnly: true),
        tool("digitone_disconnect", "Stop playback, release notes and disconnect MIDI."),
        tool("digitone_parameter_catalog", "Discover machine-specific MIDI parameters and exact allowed coarse ranges, defaults and option labels. Machine choice is a declaration; select SYN/FLTR machine separately on hardware.",
             properties: ["machine": machine, "page": text("Optional page key, e.g. syn1, amp or fltr1.")], required: ["machine"], readOnly: true),
        tool("digitone_sound_create", "Create a partial local sound draft, without sending MIDI. Use catalog IDs, exact track MIDI channel and the machine already selected on Digitone.",
             properties: ["name": text(), "track": track, "midiChannel": channel, "machine": machine, "parameters": parameters], required: ["name", "track", "midiChannel", "machine", "parameters"]),
        tool("digitone_sound_update", "Merge parameter values into an existing local sound draft. Optional name/channel changes. Does not send MIDI.",
             properties: ["soundID": text(), "parameters": parameters, "name": text(), "midiChannel": channel], required: ["soundID", "parameters"]),
        tool("digitone_sound_get", "Read a local sound draft and its display values. These are authored values, not a hardware preset dump.", properties: ["soundID": text()], required: ["soundID"], readOnly: true),
        tool("digitone_sound_apply", "Explicit hardware action: send the draft's known values by NRPN/CC to its declared MIDI channel. Select its SYN/FLTR machine and match MIDI CONFIG → CHANNELS on hardware first. Changes the live sound; does not save a hardware preset. Partial failure can leave a partially changed sound.",
             properties: ["soundID": text()], required: ["soundID"], destructive: true),
        tool("digitone_pattern_create", "Create or replace the local editable pattern and stop previous playback. Fixed 4/4, 96 PPQ, 24 ticks per sixteenth. Does not write hardware pattern memory.",
             properties: ["name": text(), "tempo": number(20, 999), "bars": integer(1, 256)], required: ["name"]),
        tool("digitone_pattern_set_track", "Create/replace a lane's notes and explicit track/channel routing. Editing changes the local draft; play again to hear it. Fractional step positions are rounded to 1/96 quarter ticks. Hardware pattern SysEx writing is unavailable.",
             properties: ["track": track, "midiChannel": channel, "name": text(), "notes": .object(["type": .string("array"), "items": note, "maxItems": .integer(AgentProject.maximumNotes)])], required: ["track", "midiChannel", "notes"]),
        tool("digitone_pattern_edit", "Edit local notes: transpose, quantize, velocity, mute or unmute. Optional track limits the edit. Hardware playback uses the last explicitly played draft.",
             properties: ["action": choice(["transpose", "quantize", "velocity", "mute", "unmute"]), "track": track,
                          "semitones": integer(-127, 127), "gridSteps": number(1.0 / 24, 64), "velocity": integer(1, 127)], required: ["action"]),
        tool("digitone_pattern_route_lane", "Assign an existing lane, including an imported MIDI lane, to a Digitone track and its exact MIDI channel. Does not change notes or send MIDI. Track bindings must remain unique.",
             properties: ["laneID": text(), "track": track, "midiChannel": channel], required: ["laneID", "track", "midiChannel"]),
        tool("digitone_beat", "Replace one lane with a deterministic rhythm across the current pattern: four_on_floor, backbeat, eighths, sixteenths or euclidean. Pitch triggers the sound already on that Digitone track; this tool does not select a drum machine or design a drum sound.",
             properties: ["track": track, "midiChannel": channel, "style": choice(["four_on_floor", "backbeat", "eighths", "sixteenths", "euclidean"]),
                          "pitch": integer(0, 127), "velocity": integer(1, 127), "hits": integer(0, 16), "rotation": integer(0, 15), "swing": number(0, 0.49)], required: ["track", "midiChannel", "style"]),
        tool("digitone_pattern_get", "Read current local pattern with 1-based tracks, channels and sixteenth steps.", readOnly: true),
        tool("digitone_pattern_play", "Explicit hardware action: loop the local pattern through timestamped MIDI notes. Does not write Digitone sequencer memory. Optional sendsClock also sends MIDI clock/start/stop; ensure hardware CLOCK RECEIVE is configured before using it.",
             properties: ["sendsClock": boolean]),
        tool("digitone_pattern_stop", "Stop local playback, flush queued notes and release active notes."),
        tool("digitone_project_get", "Get current editable project, pattern and sound drafts. Tool responses use human 1-based routing; native project files use 0-based indices.", readOnly: true),
        tool("digitone_project_save", "Save a validated .digitone.json project for import in Digitone Studio. Absolute path; refuses overwrite unless overwrite=true.", properties: ["path": text(), "overwrite": boolean], required: ["path"]),
        tool("digitone_project_load", "Load a validated .digitone.json project and stop playback. Does not send sound changes or play notes.", properties: ["path": text()], required: ["path"]),
        tool("digitone_midi_export", "Export the local pattern as a Standard MIDI File at 96 PPQ. Sound drafts are not part of MIDI files. Absolute path; refuses overwrite unless overwrite=true.", properties: ["path": text(), "overwrite": boolean], required: ["path"]),
        tool("digitone_midi_import", "Import a Standard MIDI File as the local pattern and stop playback. Original MIDI channels are retained; track bindings remain unassigned until digitone_pattern_route_lane. Bounded validation applies.", properties: ["path": text()], required: ["path"])
    ]

    public static var names: Set<String> { Set(tools.compactMap { $0["name"]?.string }) }
}
