import Foundation
import DigitoneCore

@MainActor
public final class AgentWorkspace {
    public private(set) var project: AgentProject
    public let hardware: any AgentHardware

    public init(hardware: any AgentHardware, project: AgentProject = AgentProject()) {
        self.hardware = hardware; self.project = project
    }

    public func call(_ name: String, arguments values: [String: JSONValue]) async throws -> JSONValue {
        switch name {
        case "digitone_list_devices":
            _ = try AgentArguments(values, allowed: []); return try hardware.listDevices()
        case "digitone_connect":
            let args = try AgentArguments(values, allowed: ["sourceID", "destinationID"])
            return try await hardware.connect(sourceID: Int32(args.int("sourceID", range: Int(Int32.min)...Int(Int32.max))),
                                              destinationID: Int32(args.int("destinationID", range: Int(Int32.min)...Int(Int32.max))))
        case "digitone_status":
            _ = try AgentArguments(values, allowed: [])
            return .object(["hardware": hardware.status(), "project": summary()])
        case "digitone_disconnect":
            _ = try AgentArguments(values, allowed: []); hardware.disconnect(); return hardware.status()
        case "digitone_parameter_catalog": return try catalog(values)
        case "digitone_sound_create": return try createSound(values)
        case "digitone_sound_update": return try updateSound(values)
        case "digitone_sound_get":
            let args = try AgentArguments(values, allowed: ["soundID"])
            return soundView(try sound(args.uuid("soundID")))
        case "digitone_sound_apply": return try await applySound(values)
        case "digitone_pattern_create":
            let args = try AgentArguments(values, allowed: ["name", "tempo", "bars"])
            let sequence = NoteSequence(name: try args.string("name"), tempo: try args.number("tempo", range: 20...999, default: 120),
                                        length: try args.int("bars", range: 1...256, default: 1) * MusicalTime.ticksPerBar)
            try AgentProject.validate(sequence); hardware.stop(); project.sequence = sequence; project.name = sequence.name
            return patternView()
        case "digitone_pattern_set_track": return try setTrack(values)
        case "digitone_pattern_edit": return try editPattern(values)
        case "digitone_pattern_route_lane":
            let args = try AgentArguments(values, allowed: ["laneID", "track", "midiChannel"])
            let id = try args.uuid("laneID")
            guard let index = project.sequence.lanes.firstIndex(where: { $0.id == id }) else { throw AgentError("Lane ID was not found.") }
            var sequence = project.sequence
            sequence.lanes[index].track = try args.int("track", range: 1...16) - 1
            sequence.lanes[index].channel = try args.int("midiChannel", range: 1...16) - 1
            try AgentProject.validate(sequence); project.sequence = sequence
            return patternView()
        case "digitone_beat": return try beat(values)
        case "digitone_pattern_get":
            _ = try AgentArguments(values, allowed: []); return patternView()
        case "digitone_pattern_play":
            let args = try AgentArguments(values, allowed: ["sendsClock"])
            try AgentProject.validate(project.sequence)
            guard project.sequence.lanes.contains(where: { !$0.isMuted && !$0.notes.isEmpty }) else { throw AgentError("Pattern has no unmuted notes.") }
            try hardware.play(sequence: project.sequence, sendsClock: args.bool("sendsClock")); return hardware.status()
        case "digitone_pattern_stop":
            _ = try AgentArguments(values, allowed: []); hardware.stop(); return hardware.status()
        case "digitone_project_get":
            _ = try AgentArguments(values, allowed: []); return projectView()
        case "digitone_project_save", "digitone_midi_export":
            let args = try AgentArguments(values, allowed: ["path", "overwrite"])
            let url = try args.fileURL(); let overwrite = try args.bool("overwrite")
            let data = try name == "digitone_project_save" ? project.data() : MIDIFile.write(project.sequence)
            try data.write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
            return .object(["path": .string(url.path), "bytes": .integer(data.count)])
        case "digitone_project_load", "digitone_midi_import":
            let args = try AgentArguments(values, allowed: ["path"]); let url = try args.fileURL()
            let data = try readFile(url)
            var loaded: AgentProject
            if name == "digitone_project_load" { loaded = try AgentProject.read(data) }
            else {
                loaded = project
                loaded.sequence = try MIDIFile.read(data, fallbackName: url.deletingPathExtension().lastPathComponent)
                loaded.name = loaded.sequence.name
                try loaded.validate()
            }
            hardware.stop(); project = loaded; return projectView()
        default: throw AgentError("Unknown tool '\(name)'.")
        }
    }

    private func readFile(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: AgentProject.maximumFileSize + 1) ?? Data()
        guard data.count <= AgentProject.maximumFileSize else { throw AgentError("Input file exceeds 8 MiB.") }
        return data
    }

    private func machine(_ args: AgentArguments) throws -> SynthMachine {
        guard let machine = SynthMachine(rawValue: try args.string("machine")) else {
            throw AgentError("machine must be fmTone, fmDrum, wavetone or swarmer.")
        }
        return machine
    }

    private func catalog(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["machine", "page"]); let machine = try machine(args)
        var parameters = HardwareCatalog.parameters(for: DNMachine(rawValue: machine.rawValue)!)
        if values["page"] != nil {
            guard let page = DNPage(rawValue: try args.string("page")), !page.isGlobal else {
                throw AgentError("page must be a track page key in the returned catalog.")
            }
            parameters = parameters.filter { $0.page == page }
            guard !parameters.isEmpty else { throw AgentError("Page is unavailable for this machine.") }
        }
        return .object(["machine": .string(machine.rawValue), "hardwareMachineMustBeSelectedSeparately": .bool(true),
                        "valueUnit": .string("coarse MIDI value; not Hz, milliseconds or hardware readback"),
                        "parameters": .array(parameters.filter { $0.cc != nil || $0.nrpn != nil }.map(parameterView))])
    }

    private func parameterView(_ parameter: DNParameter) -> JSONValue {
        let range = AgentParameterRange.coarse(for: parameter)
        var values: [String: JSONValue] = ["id": .string(parameter.id), "name": .string(parameter.name), "page": .string(parameter.page.rawValue),
            "minimum": .integer(range.lowerBound), "maximum": .integer(range.upperBound),
            "catalogDefault": .integer(min(range.upperBound, max(range.lowerBound, parameter.defaultValue))),
            "hasFineResolution": .bool(parameter.isHighResolution)]
        if let cc = parameter.cc { values["cc"] = .integer(cc) }
        if let nrpn = parameter.nrpn { values["nrpn"] = .integer(nrpn) }
        if case .options(let labels) = parameter.format { values["options"] = .array(labels.map(JSONValue.string)) }
        return .object(values)
    }

    private func createSound(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["name", "track", "midiChannel", "machine", "parameters"])
        guard project.sounds.count < 256 else { throw AgentError("Project already has 256 sounds.") }
        let sound = AgentSoundDraft(name: try args.string("name"), track: try args.int("track", range: 1...16) - 1,
                                    midiChannel: try args.int("midiChannel", range: 1...16) - 1,
                                    machine: try machine(args), parameters: try args.parameters())
        try sound.validate(); project.sounds.append(sound); return soundView(sound)
    }

    private func sound(_ id: UUID) throws -> AgentSoundDraft {
        guard let sound = project.sounds.first(where: { $0.id == id }) else { throw AgentError("Sound draft ID was not found.") }
        return sound
    }

    private func updateSound(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["soundID", "parameters", "name", "midiChannel"])
        let id = try args.uuid("soundID"); var sound = try sound(id)
        sound.parameters.merge(try args.parameters()) { _, next in next }
        if values["name"] != nil { sound.name = try args.string("name") }
        if values["midiChannel"] != nil { sound.midiChannel = try args.int("midiChannel", range: 1...16) - 1 }
        try sound.validate()
        project.sounds[project.sounds.firstIndex(where: { $0.id == id })!] = sound
        return soundView(sound)
    }

    private func applySound(_ values: [String: JSONValue]) async throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["soundID"]); let sound = try sound(args.uuid("soundID"))
        try sound.validate()
        guard !sound.parameters.isEmpty else { throw AgentError("Sound draft is empty. No hardware values were sent.") }
        let parameters = HardwareCatalog.parameters(for: DNMachine(rawValue: sound.machine.rawValue)!)
        var sent = 0
        for parameter in parameters {
            guard let value = sound.parameters[parameter.id] else { continue }
            do { try hardware.send(parameter: parameter, coarseValue: value, channel: sound.midiChannel) }
            catch { throw AgentError("Sent \(sent) of \(sound.parameters.count) values; hardware may be partially changed. \(error.localizedDescription)") }
            sent += 1
            try await Task.sleep(for: .milliseconds(6))
        }
        return .object(["soundID": .string(sound.id.uuidString), "sentParameters": .integer(sent),
                        "track": .integer(sound.track + 1), "midiChannel": .integer(sound.midiChannel + 1),
                        "message": .string("Known values sent to the live sound. Machine selection and saving a hardware preset remain device operations.")])
    }

    private func setTrack(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["track", "midiChannel", "name", "notes"])
        let track = try args.int("track", range: 1...16) - 1; let channel = try args.int("midiChannel", range: 1...16) - 1
        guard let notes = values["notes"]?.array, notes.count <= AgentProject.maximumNotes else { throw AgentError("notes must be a bounded array.") }
        let steps = Double(project.sequence.length) / Double(MusicalTime.ticksPerStep)
        let parsed = try notes.map { value -> SequenceNote in
            guard let object = value.object else { throw AgentError("Each note must be an object.") }
            let args = try AgentArguments(object, allowed: ["pitch", "velocity", "step", "length"])
            let start = Int(((try args.number("step", range: 1...(steps + 1)) - 1) * 24).rounded())
            let duration = Int((try args.number("length", range: (1.0 / 24)...steps) * 24).rounded())
            return SequenceNote(pitch: try args.int("pitch", range: 0...127), velocity: try args.int("velocity", range: 1...127, default: 100), start: start, duration: duration)
        }
        try replaceLane(track: track, channel: channel, name: args.string("name", default: "Track \(track + 1)"), notes: parsed)
        return patternView()
    }

    private func replaceLane(track: Int, channel: Int, name: String, notes: [SequenceNote]) throws {
        var sequence = project.sequence
        if let index = sequence.lanes.firstIndex(where: { $0.track == track }) {
            sequence.lanes[index].name = name; sequence.lanes[index].channel = channel
            sequence.lanes[index].notes = notes.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        } else { sequence.lanes.append(SequenceLane(name: name, track: track, channel: channel, notes: notes)) }
        try AgentProject.validate(sequence); project.sequence = sequence
    }

    private func editPattern(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["action", "track", "semitones", "gridSteps", "velocity"])
        var sequence = project.sequence
        let track = values["track"] == nil ? nil : try args.int("track", range: 1...16) - 1
        let selected = sequence.lanes.filter { track == nil || $0.track == track }
        guard !selected.isEmpty else { throw AgentError("No lane matches the selected track.") }
        let selection = NoteSelection.lanes(Set(selected.map(\.id)))
        let action = try args.string("action")
        switch action {
        case "transpose": sequence.transpose(semitones: try args.int("semitones", range: -127...127), selection: selection)
        case "quantize":
            sequence.quantize(grid: Int((try args.number("gridSteps", range: (1.0 / 24)...64, default: 1) * 24).rounded()), selection: selection)
        case "velocity": sequence.setVelocity(try args.int("velocity", range: 1...127), selection: selection)
        case "mute", "unmute":
            for index in sequence.lanes.indices where selection.includes(lane: sequence.lanes[index].id) { sequence.lanes[index].isMuted = action == "mute" }
        default: throw AgentError("Unknown pattern edit action.")
        }
        try AgentProject.validate(sequence); project.sequence = sequence; return patternView()
    }

    private func beat(_ values: [String: JSONValue]) throws -> JSONValue {
        let args = try AgentArguments(values, allowed: ["track", "midiChannel", "style", "pitch", "velocity", "hits", "rotation", "swing"])
        let track = try args.int("track", range: 1...16) - 1, channel = try args.int("midiChannel", range: 1...16) - 1
        let style = try args.string("style"); let pitch = try args.int("pitch", range: 0...127, default: 60)
        let velocity = try args.int("velocity", range: 1...127, default: 100)
        let rotation = try args.int("rotation", range: 0...15, default: 0), swing = try args.number("swing", range: 0...0.49, default: 0)
        let positions: Set<Int>
        switch style {
        case "four_on_floor": positions = [0, 4, 8, 12]
        case "backbeat": positions = [4, 12]
        case "eighths": positions = Set(stride(from: 0, to: 16, by: 2))
        case "sixteenths": positions = Set(0..<16)
        case "euclidean":
            let hits = try args.int("hits", range: 0...16)
            positions = Set((0..<16).filter { hits > 0 && ($0 * hits) % 16 < hits })
        default: throw AgentError("Unknown beat style.")
        }
        let rotated = Set(positions.map { ($0 + rotation) % 16 })
        let steps = (project.sequence.length + 23) / 24
        let notes = (0..<steps).filter { rotated.contains($0 % 16) }.compactMap { step -> SequenceNote? in
            let start = step * 24 + (step % 2 == 1 ? Int((swing * 24).rounded()) : 0)
            guard start < project.sequence.length else { return nil }
            return SequenceNote(pitch: pitch, velocity: velocity, start: start, duration: min(12, project.sequence.length - start))
        }
        try replaceLane(track: track, channel: channel, name: "Track \(track + 1) · \(style)", notes: notes)
        return patternView()
    }

    private func soundView(_ sound: AgentSoundDraft) -> JSONValue {
        let parameters = HardwareCatalog.parameters(for: DNMachine(rawValue: sound.machine.rawValue)!)
        var display: [String: JSONValue] = [:]
        for parameter in parameters {
            if let value = sound.parameters[parameter.id] { display[parameter.id] = .string(HardwareCatalog.display(value, format: parameter.format)) }
        }
        return .object(["soundID": .string(sound.id.uuidString), "name": .string(sound.name), "track": .integer(sound.track + 1),
                        "midiChannel": .integer(sound.midiChannel + 1), "machine": .string(sound.machine.rawValue),
                        "parameters": .object(sound.parameters.mapValues(JSONValue.integer)), "displayValues": .object(display),
                        "origin": .string("local partial draft; unspecified values unknown")])
    }

    private func summary() -> JSONValue {
        .object(["name": .string(project.name), "soundCount": .integer(project.sounds.count), "laneCount": .integer(project.sequence.lanes.count),
                 "noteCount": .integer(project.sequence.noteCount), "tempo": .number(project.sequence.tempo)])
    }
    private func projectView() -> JSONValue {
        .object(["project": summary(), "pattern": patternView(), "sounds": .array(project.sounds.map(soundView))])
    }
    private func patternView() -> JSONValue {
        let sequence = project.sequence
        return .object(["patternID": .string(sequence.id.uuidString), "name": .string(sequence.name), "tempo": .number(sequence.tempo),
                        "lengthTicks": .integer(sequence.length), "steps": .number(Double(sequence.length) / 24),
                        "ticksPerQuarter": .integer(96), "ticksPerStep": .integer(24),
                        "playback": .string("Local MIDI stream; hardware sequencer memory is unchanged"),
                        "lanes": .array(sequence.lanes.map { lane in
            .object(["laneID": .string(lane.id.uuidString), "name": .string(lane.name), "track": lane.track.map { .integer($0 + 1) } ?? .null,
                     "midiChannel": .integer(lane.channel + 1), "muted": .bool(lane.isMuted), "notes": .array(lane.notes.map { note in
                .object(["noteID": .string(note.id.uuidString), "pitch": .integer(note.pitch), "velocity": .integer(note.velocity),
                         "step": .number(Double(note.start) / 24 + 1), "length": .number(Double(note.duration) / 24)])
            })])
        })])
    }
}
