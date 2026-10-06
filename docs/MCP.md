# Digitone Studio MCP

`digitone-mcp` lets an agent compose a local pattern, author partial Digitone II sound drafts, save a portable project, and explicitly apply/play that work on a connected instrument. It is a native Swift stdio server. No Python, Node, network service or third-party package is required.

## Run and connect

Build the executable on macOS:

```sh
swift build -c release --product digitone-mcp
```

The resulting command is `.build/release/digitone-mcp`. The macOS application bundle also includes `Contents/MacOS/digitone-mcp` when built with `scripts/build-app.sh`. Point a stdio-capable MCP client at the absolute executable path. A client using the common JSON configuration envelope can use:

```json
{
  "mcpServers": {
    "digitone-studio": {
      "command": "/absolute/path/to/digitone-mcp",
      "args": []
    }
  }
}
```

Use `"args": ["--offline"]` to compose sounds, patterns and files with all hardware I/O disabled. No MIDI client is opened in offline mode. `--help` writes usage to stderr.

The app and server have separate local sessions. Share work through **Export agent project / Import agent project** in Studio, or the server's project tools. Keep one MIDI transport playing at a time. The app does not silently mirror an agent's live parameter changes.

## First hardware session

1. On Digitone II, enable USB MIDI and parameter/note reception. Assign the required SYN machine on each audio track. The server cannot select or verify SYN/FLTR machines through MIDI.
2. Call `digitone_list_devices`. Pass its exact input/output IDs to `digitone_connect`. The server verifies that the endpoint answers as a Digitone II.
3. Match each sound/lane's `midiChannel` to the instrument's **MIDI CONFIG → CHANNELS → TRACK n CHANNEL**. Tool `track`, `midiChannel` and `step` arguments are **1-based**. Track number does not imply a MIDI channel, and the server never substitutes AUTO CHANNEL.
4. Discover `digitone_parameter_catalog` for the track's machine. Create/update a sound draft using those IDs and allowed values. These edits remain local until `digitone_sound_apply`.
5. Compose notes or rhythm lanes. Call `digitone_pattern_play` to stream the local pattern and `digitone_pattern_stop` to release notes.

Sound apply uses published NRPN addresses where available (`coarseValue << 7`, fine value zero), otherwise CC. Parameter sends are paced. An output failure reports how many values were sent because a partially applied sound cannot be rolled back without hardware readback.

## What the tools actually change

| Tool group | Effect |
| --- | --- |
| `digitone_list_devices`, `digitone_status`, `digitone_parameter_catalog` | Device discovery/status or local catalog; no sound writes |
| `digitone_connect`, `digitone_disconnect` | Exact MIDI endpoint connection and identity negotiation; disconnect stops playback |
| `digitone_sound_create`, `digitone_sound_update`, `digitone_sound_get` | Partial local sound drafts; unspecified values stay unknown |
| `digitone_sound_apply` | Changes the known live track parameters on the declared MIDI channel |
| `digitone_pattern_create`, `digitone_pattern_set_track`, `digitone_pattern_edit`, `digitone_pattern_route_lane`, `digitone_beat`, `digitone_pattern_get` | Editable local note sequence |
| `digitone_pattern_play`, `digitone_pattern_stop` | Timestamped MIDI note playback, with optional MIDI clock/start/stop |
| `digitone_project_get`, `digitone_project_save`, `digitone_project_load` | Portable `.digitone.json` project with sound drafts and sequence |
| `digitone_midi_export`, `digitone_midi_import` | Standard MIDI File containing notes, tempo, time signature and lane channels |

**A local pattern streams notes through MIDI. It is not written into Digitone's internal sequencer memory.** The server does not implement unsupported pattern SysEx writes, hardware sound-pool saving, or a complete sound preset dump. Save a live sound on the device if it should remain in its sound pool. Choose SYN and FLTR machines on the device before applying a draft.

All sound parameter values are coarse MIDI indices. Discover the parameter's `minimum`, `maximum` and `options`; an algorithm/waveform can have a narrower range than 0–127. `catalogDefault` describes the source-backed catalog, not an observed hardware value. No unspecified defaults are automatically sent.

Creating a new pattern, importing MIDI or loading a project stops previous playback. Other draft edits are heard on the next explicit `digitone_pattern_play`. `sendsClock` defaults to false. Enabling it sends hardware transport messages as well as notes; use the instrument's CLOCK RECEIVE settings deliberately.

## Example: a kick lane and a second rhythm

These are `tools/call` argument objects, after normal MCP initialization. First discover valid FM Drum controls:

```json
{"name":"digitone_parameter_catalog","arguments":{"machine":"fmDrum","page":"syn1"}}
```

Create a partial sound on track 1, assuming that track already uses FM Drum and its MIDI channel is 1:

```json
{"name":"digitone_sound_create","arguments":{"name":"Low drum draft","track":1,"midiChannel":1,"machine":"fmDrum","parameters":{"fmDrum.syn1.tune":52,"fmDrum.syn1.sweepTime":20,"fmDrum.syn1.sweepDepth":35,"fmDrum.syn1.feedback":12}}}
```

The result contains a `soundID`. Applying that ID is the explicit hardware write:

```json
{"name":"digitone_sound_apply","arguments":{"soundID":"UUID-FROM-CREATE"}}
```

Compose a two-bar pattern and two separately routed rhythm lanes:

```json
{"name":"digitone_pattern_create","arguments":{"name":"First groove","tempo":128,"bars":2}}
{"name":"digitone_beat","arguments":{"track":1,"midiChannel":1,"style":"four_on_floor","pitch":60,"velocity":112}}
{"name":"digitone_beat","arguments":{"track":2,"midiChannel":6,"style":"euclidean","hits":5,"rotation":2,"pitch":60,"velocity":80}}
{"name":"digitone_pattern_play","arguments":{"sendsClock":false}}
```

Rhythm tools trigger the sound already assigned to each track; they do not turn a pitched synth into a drum. Available rhythms are `four_on_floor`, `backbeat`, `eighths`, `sixteenths` and `euclidean`. Euclidean hits and rotation use a repeating 16-step cell. Swing delays odd zero-based sixteenth positions by up to 0.49 of a step, deterministically.

For a melody, replace a track's full note list. `step` starts at 1; `length` is measured in sixteenths. Fractional positions round to the closest tick (24 ticks per sixteenth, 96 per quarter):

```json
{"name":"digitone_pattern_set_track","arguments":{"track":3,"midiChannel":8,"name":"Bass","notes":[{"pitch":36,"step":1,"length":2,"velocity":105},{"pitch":43,"step":7.5,"length":1.5,"velocity":88}]}}
```

An imported MIDI lane retains its source MIDI channel and has no Digitone track binding. Use its returned `laneID` with `digitone_pattern_route_lane` to assign an exact track/channel without duplicating its notes.

Save and import the project in Studio:

```json
{"name":"digitone_project_save","arguments":{"path":"/absolute/path/First groove.digitone.json"}}
```

File tools require absolute paths. They never run a shell or expand `~`. Save/export refuses to overwrite an existing file unless `overwrite: true` is supplied. Loading/importing validates the entire replacement before changing the current local project. MIDI files do not retain sound drafts, mute state or Digitone track bindings; use the project format for those.

## Shared Swift project API

`DigitoneAgent` is also a library used by Studio:

```swift
let project = try AgentProject.read(data)
let sequence = project.sequence
for draft in project.sounds {
    let trackIndex = draft.track
    let channelIndex = draft.midiChannel
    let librarySound = draft.snapshot
}
let portableData = try project.data()
```

Native project schema version 1 contains `formatVersion`, `name`, `sequence: NoteSequence` and `sounds: [AgentSoundDraft]`. File track/channel indices are **0-based**, like the core types. Sound `parameters` use `HardwareCatalog` IDs and coarse values. `draft.snapshot` maps them into the app library's stable `SoundSnapshot` IDs. These are partial authored drafts, not recovered full presets.

Projects are capped at 8 MiB, 256 sounds, 16 lanes and 16,384 notes. Tempo is 20–999 BPM. Sequence names are bounded, lane/note/sound IDs are distinct, track bindings are unique, and note ranges/timing/routing are validated. Note tails may cross a loop boundary, matching `SequenceScheduler` behavior.

## Protocol and lifecycle

The implementation follows the published MCP [stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [initialization lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) and [tools specification](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).

Supported revisions are `2025-11-25`, `2025-06-18`, `2025-03-26` and `2024-11-05`. A recognized requested version is echoed; an unknown version negotiates `2025-11-25`. The server advertises only tools. JSON structured tool results are supplied for June/November 2025 clients; earlier clients receive the same JSON as text content. There are no remote endpoints or server-side client requests.

Messages are UTF-8 JSON-RPC objects, one per line. Initialize with `protocolVersion`, `capabilities` and `clientInfo`, then send `notifications/initialized`. `ping`, `tools/list` and `tools/call` are supported. There is one tool page. Malformed JSON/envelopes and unknown methods/tools return JSON-RPC errors. Valid tool execution/argument failures return `isError: true`. Notifications receive no response and cannot trigger a tool side effect. Requests run in arrival order; cancellation notifications for already completed/uninterruptible operations are ignored.

Input is limited to 1 MiB per message. Oversized lines are drained before the next message. Blocking stdin reads run away from the main actor so identification callbacks and sequence playback continue while the client is idle. Stdout contains only MCP protocol messages; diagnostics use stderr. Closing stdin, SIGTERM and SIGINT stop playback and disconnect MIDI before exit. MIDI endpoint loss stops playback through the session disconnect callback.

Tests use a fake hardware boundary, so no unit test connects to an instrument or sends actual hardware messages. Run `swift test --filter DigitoneAgentTests` for protocol, authoring, range validation, routing, partial-send errors, deterministic rhythms, file round trips, no-clobber, bounded line parsing and EOF checks.
