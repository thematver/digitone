import Foundation

public enum MIDIFileError: Error, LocalizedError, Equatable {
    case tooLarge(bytes: Int)
    case notMIDIFile
    case malformedHeader
    case unsupportedFormat(Int)
    case smpteTiming
    case truncatedChunk(offset: Int)
    case malformedEvent(track: Int, offset: Int)
    case variableLengthOverflow(track: Int, offset: Int)
    case tooManyNotes(limit: Int)
    case tooManyLanes(limit: Int)
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes):
            return "MIDI-файл слишком большой: \(bytes) байт, допустимо не более \(MIDIFile.maximumFileSize)."
        case .notMIDIFile: return "Это не Standard MIDI File: нет заголовка MThd."
        case .malformedHeader: return "Повреждён заголовок MIDI-файла."
        case .unsupportedFormat(let format): return "MIDI-файл формата \(format) не поддерживается; поддерживаются форматы 0 и 1."
        case .smpteTiming: return "MIDI-файлы с SMPTE-временем не поддерживаются; нужно деление в долях четверти (PPQ)."
        case .truncatedChunk(let offset): return "Блок MIDI-файла по смещению \(offset) выходит за конец файла."
        case .malformedEvent(let track, let offset):
            return "Повреждённое событие в дорожке \(track + 1), смещение \(offset)."
        case .variableLengthOverflow(let track, let offset):
            return "Слишком длинное число переменной длины в дорожке \(track + 1), смещение \(offset)."
        case .tooManyNotes(let limit): return "В MIDI-файле больше \(limit) нот."
        case .tooManyLanes(let limit): return "В MIDI-файле больше \(limit) дорожек с нотами."
        case .tooLong: return "MIDI-файл длиннее максимальной длины последовательности."
        }
    }
}

/// Standard MIDI File import and export for `NoteSequence`.
///
/// Reading accepts formats 0 and 1 with PPQ timing. Every (MTrk, channel)
/// pair that carries notes becomes one lane; ticks are rescaled to
/// `MusicalTime.ticksPerQuarter`. Only notes, the first tempo, the first time
/// signature and track names are kept; controllers, program changes, SysEx
/// and other meta events are skipped.
///
/// Writing produces format 1 at 96 PPQ: a conductor track with the sequence
/// name, tempo and time signature, then one track per lane (muted lanes too)
/// with its name, a channel prefix and explicit 0x80 note-offs. Lane mute
/// state and Digitone track binding are not stored in the file.
public enum MIDIFile {
    public static let maximumFileSize = 8 * 1024 * 1024
    public static let maximumNoteCount = 200_000
    public static let maximumLaneCount = 1024
    public static let maximumVariableLength = 0x0FFF_FFFF

    // MARK: Reading

    /// Decodes a Standard MIDI File. `fallbackName` names the sequence when
    /// the file carries no conductor or format-0 track name.
    public static func read(_ data: Data, fallbackName: String = "MIDI") throws -> NoteSequence {
        guard data.count <= maximumFileSize else { throw MIDIFileError.tooLarge(bytes: data.count) }
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<4]) == Array("MThd".utf8) else { throw MIDIFileError.notMIDIFile }
        let headerLength = Int(u32(bytes, 4))
        guard headerLength >= 6, headerLength <= bytes.count - 8 else { throw MIDIFileError.malformedHeader }
        let format = Int(u16(bytes, 8))
        let declaredTracks = Int(u16(bytes, 10))
        let division = Int(u16(bytes, 12))
        guard format <= 1 else { throw MIDIFileError.unsupportedFormat(format) }
        guard division & 0x8000 == 0 else { throw MIDIFileError.smpteTiming }
        guard division > 0 else { throw MIDIFileError.malformedHeader }
        guard declaredTracks > 0, format != 0 || declaredTracks == 1 else { throw MIDIFileError.malformedHeader }

        var tracks: [ParsedTrack] = []
        var noteCount = 0
        var offset = 8 + headerLength
        // Fewer than eight trailing bytes cannot hold a chunk; some writers pad files.
        while bytes.count - offset >= 8 {
            let length = Int(u32(bytes, offset + 4))
            let body = offset + 8
            guard length <= bytes.count - body else { throw MIDIFileError.truncatedChunk(offset: offset) }
            if Array(bytes[offset..<(offset + 4)]) == Array("MTrk".utf8) {
                var parser = TrackParser(bytes: bytes, range: body..<(body + length), index: tracks.count)
                let track = try parser.parse(noteBudget: maximumNoteCount - noteCount)
                noteCount += track.notes.count
                tracks.append(track)
            }
            offset = body + length
        }
        guard tracks.count == declaredTracks else { throw MIDIFileError.malformedHeader }
        return try sequence(from: tracks, format: format, division: division, fallbackName: fallbackName)
    }

    private static func sequence(from tracks: [ParsedTrack], format: Int, division: Int, fallbackName: String) throws -> NoteSequence {
        func rescale(_ tick: Int) -> Int { (tick * MusicalTime.ticksPerQuarter * 2 + division) / (division * 2) }

        let tempo = tracks.enumerated()
            .compactMap { index, track in track.tempo.map { (tick: $0.tick, index: index, value: $0.value) } }
            .min { ($0.tick, $0.index) < ($1.tick, $1.index) }
            .map { (60_000_000 / Double($0.value) * 1000).rounded() / 1000 } ?? 120
        let timeSignature = tracks.enumerated()
            .compactMap { index, track in track.timeSignature.map { (tick: $0.tick, index: index, value: $0.value) } }
            .min { ($0.tick, $0.index) < ($1.tick, $1.index) }?.value ?? TimeSignature()

        var lanes: [SequenceLane] = []
        var lastNoteEnd = 0
        for track in tracks {
            let channels = Set(track.notes.map(\.channel)).sorted()
            if channels.isEmpty, let channel = track.channelPrefix, track.index > 0 || format == 0 {
                lanes.append(SequenceLane(name: laneName(track.name, channel: channel, shared: false), channel: channel))
            }
            for channel in channels {
                let notes = track.notes.filter { $0.channel == channel }.map { raw in
                    let start = rescale(raw.start)
                    return SequenceNote(pitch: raw.pitch, velocity: raw.velocity, start: start, duration: max(1, rescale(raw.end) - start))
                }.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
                lastNoteEnd = max(lastNoteEnd, notes.map(\.end).max() ?? 0)
                lanes.append(SequenceLane(name: laneName(track.name, channel: channel, shared: channels.count > 1),
                                          channel: channel, notes: notes))
            }
            guard lanes.count <= maximumLaneCount else { throw MIDIFileError.tooManyLanes(limit: maximumLaneCount) }
        }

        // Loop length: whole bars covering the last note and the latest
        // end-of-track (clip exports mark the loop end there).
        guard lastNoteEnd <= NoteSequence.maximumLength else { throw MIDIFileError.tooLong }
        let lastEndOfTrack = rescale(tracks.map(\.endTick).max() ?? 0)
        guard lastEndOfTrack <= NoteSequence.maximumLength else { throw MIDIFileError.tooLong }
        let bar = timeSignature.ticksPerBar
        let bars = max(1, (max(lastNoteEnd, lastEndOfTrack) + bar - 1) / bar)
        let conductor = tracks.first.flatMap { format == 0 || $0.notes.isEmpty ? $0.name : nil }
        return NoteSequence(name: conductor ?? fallbackName, tempo: tempo, timeSignature: timeSignature,
                            length: min(bars * bar, NoteSequence.maximumLength), lanes: lanes)
    }

    private static func laneName(_ trackName: String?, channel: Int, shared: Bool) -> String {
        guard let trackName else { return "Канал \(channel + 1)" }
        return shared ? "\(trackName) · канал \(channel + 1)" : trackName
    }

    // MARK: Writing

    /// Encodes the sequence as a format-1 file at 96 PPQ. Values outside the
    /// MIDI ranges are clamped; negative starts move to tick 0.
    public static func write(_ sequence: NoteSequence) throws -> Data {
        guard sequence.lanes.count <= maximumLaneCount else { throw MIDIFileError.tooManyLanes(limit: maximumLaneCount) }
        var noteCount = 0
        for lane in sequence.lanes {
            guard lane.notes.count <= maximumNoteCount - noteCount else { throw MIDIFileError.tooManyNotes(limit: maximumNoteCount) }
            noteCount += lane.notes.count
        }
        guard sequence.length <= NoteSequence.maximumLength,
              sequence.lanes.allSatisfy({ $0.notes.allSatisfy { max(0, $0.start) <= NoteSequence.maximumLength - min(NoteSequence.maximumLength + 1, max(1, $0.duration)) } }) else {
            throw MIDIFileError.tooLong
        }
        let laneEvents = sequence.lanes.map(events(for:))
        let lastNote = laneEvents.compactMap { $0.last?.tick }.max() ?? 0
        let end = min(maximumVariableLength, max(lastNote, sequence.length))

        var file = Array("MThd".utf8) + be32(6) + be16(1) + be16(sequence.lanes.count + 1) + be16(MusicalTime.ticksPerQuarter)
        var conductor = textMeta(0x03, sequence.name)
        let tempo = sequence.tempo.isFinite && sequence.tempo > 0 ? sequence.tempo : 120
        let microseconds = Int(min(Double(0xFF_FFFF), max(1, (60_000_000 / tempo).rounded())))
        conductor += [0, 0xFF, 0x51, 3, UInt8(microseconds >> 16), UInt8((microseconds >> 8) & 0xFF), UInt8(microseconds & 0xFF)]
        let signature = sequence.timeSignature
        let unit = min(64, max(1, signature.unit))
        let unitPower = (0...6).min { abs((1 << $0) - unit) < abs((1 << $1) - unit) } ?? 2
        conductor += [0, 0xFF, 0x58, 4, UInt8(min(255, max(1, signature.beats))), UInt8(unitPower), 24, 8]
        conductor += vlq(end) + [0xFF, 0x2F, 0]
        file += chunk(conductor)

        for (lane, events) in zip(sequence.lanes, laneEvents) {
            let channel = UInt8(min(15, max(0, lane.channel)))
            var track = textMeta(0x03, lane.name) + [0, 0xFF, 0x20, 1, channel]
            var tick = 0
            for event in events {
                track += vlq(event.tick - tick)
                track += event.isOn ? [0x90 | channel, event.pitch, event.velocity] : [0x80 | channel, event.pitch, 0x40]
                tick = event.tick
            }
            track += vlq(end - tick) + [0xFF, 0x2F, 0]
            file += chunk(track)
        }
        guard file.count <= maximumFileSize else { throw MIDIFileError.tooLarge(bytes: file.count) }
        return Data(file)
    }

    private struct WriteEvent {
        var tick: Int
        var isOn: Bool
        var pitch: UInt8
        var velocity: UInt8
    }

    /// Note events sorted by tick, note-offs before note-ons at the same tick.
    private static func events(for lane: SequenceLane) -> [WriteEvent] {
        lane.notes.flatMap { note -> [WriteEvent] in
            let pitch = UInt8(min(127, max(0, note.pitch)))
            let velocity = UInt8(min(127, max(1, note.velocity)))
            let start = min(maximumVariableLength - 1, max(0, note.start))
            let end = min(maximumVariableLength, start + max(1, note.duration))
            return [WriteEvent(tick: start, isOn: true, pitch: pitch, velocity: velocity),
                    WriteEvent(tick: end, isOn: false, pitch: pitch, velocity: 0)]
        }.sorted { ($0.tick, $0.isOn ? 1 : 0, $0.pitch) < ($1.tick, $1.isOn ? 1 : 0, $1.pitch) }
    }

    /// A delta-0 text meta event, cut to 255 bytes at a character boundary.
    private static func textMeta(_ type: UInt8, _ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for character in text {
            let encoded = Array(String(character).utf8)
            guard bytes.count + encoded.count <= 255 else { break }
            bytes += encoded
        }
        return [0, 0xFF, type] + vlq(bytes.count) + bytes
    }

    private static func chunk(_ body: [UInt8]) -> [UInt8] { Array("MTrk".utf8) + be32(body.count) + body }

    static func vlq(_ value: Int) -> [UInt8] {
        var value = min(maximumVariableLength, max(0, value))
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }

    private static func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    private static func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value) }
    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 { UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]) }
    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(u16(bytes, offset)) << 16 | UInt32(u16(bytes, offset + 2))
    }
}

// MARK: - Track parsing

private struct RawNote {
    var channel: Int
    var pitch: Int
    var velocity: Int
    var start: Int
    var end: Int
}

private struct ParsedTrack {
    var index: Int
    var name: String?
    var channelPrefix: Int?
    var tempo: (tick: Int, value: Int)?
    var timeSignature: (tick: Int, value: TimeSignature)?
    var notes: [RawNote] = []
    var endTick = 0
}

private struct TrackParser {
    let bytes: [UInt8]
    let range: Range<Int>
    let index: Int
    private var position: Int

    init(bytes: [UInt8], range: Range<Int>, index: Int) {
        self.bytes = bytes
        self.range = range
        self.index = index
        position = range.lowerBound
    }

    mutating func parse(noteBudget: Int) throws -> ParsedTrack {
        var track = ParsedTrack(index: index)
        var tick = 0
        var runningStatus: UInt8?
        // Sounding notes per (channel, pitch), closed first-in first-out.
        var open: [Int: [(start: Int, velocity: Int)]] = [:]
        var openCount = 0

        func close(channel: Int, pitch: Int, at tick: Int) {
            let key = channel << 7 | pitch
            guard var queue = open[key], !queue.isEmpty else { return }
            let started = queue.removeFirst()
            open[key] = queue
            openCount -= 1
            track.notes.append(RawNote(channel: channel, pitch: pitch, velocity: started.velocity, start: started.start, end: tick))
        }

        events: while position < range.upperBound {
            tick += try variableLength()
            let eventOffset = position
            var status = try byte()
            if status < 0x80 {
                guard let running = runningStatus else { throw malformed(eventOffset) }
                status = running
                position -= 1
            }
            switch status {
            case 0xFF:
                runningStatus = nil
                let type = try byte()
                let length = try variableLength()
                let data = Array(try take(length))
                switch type {
                case 0x2F: break events
                case 0x03 where track.name == nil: track.name = Self.text(data)
                case 0x20 where data.count == 1 && data[0] < 16: track.channelPrefix = Int(data[0])
                case 0x51 where data.count == 3 && track.tempo == nil:
                    let value = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
                    if value > 0 { track.tempo = (tick, value) }
                case 0x58 where data.count >= 2 && track.timeSignature == nil:
                    if data[0] > 0, data[1] <= 6 { track.timeSignature = (tick, TimeSignature(beats: Int(data[0]), unit: 1 << Int(data[1]))) }
                default: break
                }
            case 0xF0, 0xF7:
                runningStatus = nil
                _ = try take(try variableLength())
            case 0x80...0xEF:
                runningStatus = status
                let kind = status & 0xF0
                let first = try dataByte()
                let second = kind == 0xC0 || kind == 0xD0 ? 0 : try dataByte()
                let channel = Int(status & 0x0F)
                if kind == 0x90, second > 0 {
                    guard track.notes.count + openCount < noteBudget else {
                        throw MIDIFileError.tooManyNotes(limit: MIDIFile.maximumNoteCount)
                    }
                    open[channel << 7 | first, default: []].append((tick, second))
                    openCount += 1
                } else if kind == 0x80 || kind == 0x90 {
                    close(channel: channel, pitch: first, at: tick)
                }
            default:
                throw malformed(eventOffset)
            }
        }
        // Hanging notes end where the track ends.
        for key in open.keys.sorted() {
            while open[key]?.isEmpty == false { close(channel: key >> 7, pitch: key & 0x7F, at: tick) }
        }
        track.endTick = tick
        return track
    }

    private mutating func byte() throws -> UInt8 {
        guard position < range.upperBound else { throw malformed(position) }
        defer { position += 1 }
        return bytes[position]
    }

    private mutating func dataByte() throws -> Int {
        let offset = position
        let value = try byte()
        guard value < 0x80 else { throw malformed(offset) }
        return Int(value)
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= range.upperBound - position else { throw malformed(position) }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    /// At most four bytes, 28 bits.
    private mutating func variableLength() throws -> Int {
        let offset = position
        var value = 0
        for _ in 0..<4 {
            let next = try byte()
            value = value << 7 | Int(next & 0x7F)
            if next & 0x80 == 0 { return value }
        }
        throw MIDIFileError.variableLengthOverflow(track: index, offset: offset)
    }

    private func malformed(_ offset: Int) -> MIDIFileError { .malformedEvent(track: index, offset: offset) }

    private static func text(_ data: [UInt8]) -> String? {
        let trimmed = data.prefix { $0 != 0 }
        let text = String(bytes: trimmed, encoding: .utf8) ?? String(bytes: trimmed, encoding: .windowsCP1252) ?? ""
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
