import Foundation
import Combine
import DigitoneCore
import DigitoneMIDI

extension DNPage {
    /// The device button a page belongs to: "SYN" for SYN1...SYN4, "FLTR", "MOD"…
    var group: String { title.trimmingCharacters(in: .decimalDigits) }
    /// 1...4 for numbered pages, nil for single pages.
    var subpage: Int? { Int(title.drop { !$0.isNumber }) }
}

/// Full control of the Digitone II from this computer: selected track, machines,
/// MIDI channel map, page, every parameter value with its origin, mutes,
/// the device's transport and pattern, and an audition keyboard.
///
/// Values are kept per (track, parameter) and globally for the FX CONTROL CH pages.
/// Nothing is known at start: local edits stay `draft` until a MIDI send succeeds, then become `sent`, and
/// `received` when the device reports it (PARAM OUTPUT + ENCODER DEST INT+EXT).
@MainActor
final class ControlModel: ObservableObject {
    static let trackCount = 16
    /// At most this many messages per second and parameter while a knob moves.
    static let sendRate = 60.0

    @Published private(set) var selectedTrack: Int
    @Published private(set) var machines: [DNMachine]
    @Published private(set) var channelMap: DNChannelMap
    @Published private(set) var page: DNPage
    @Published private(set) var values: [ControlKey: ControlValue] = [:]
    /// Running state of the Digitone's own sequencer; nil until started/stopped or reported.
    @Published private(set) var transport: Observed<Bool>?
    /// Last requested/reported pattern program 0...127; `sent` does not confirm the device has switched.
    @Published private(set) var program: Observed<Int>?
    /// Tempo of the device's MIDI clock while it is received (CLOCK SEND).
    @Published private(set) var tempo: Double?
    /// Sixteenth within the bar while the device's clock runs.
    @Published private(set) var clockStep: Int?
    @Published private(set) var heldNotes: Set<Int> = []
    /// Notes the device plays on the selected track's channel.
    @Published private(set) var incomingNotes: Set<Int> = []
    /// True once any CC/NRPN arrived: the device's parameter output is configured.
    @Published private(set) var feedbackSeen = false
    @Published private(set) var isApplying = false
    @Published private(set) var setupChecks: Set<String>
    @Published var muteMode = false
    @Published var inputRouting: ControlInputRouting { didSet { defaults?.set(inputRouting.rawValue, forKey: Store.inputRouting) } }
    /// Lowest C of the on-screen keyboard.
    @Published var keyboardBase: Int {
        didSet {
            let clamped = min(96, max(0, keyboardBase / 12 * 12))
            if clamped != keyboardBase { keyboardBase = clamped } else { defaults?.set(keyboardBase, forKey: Store.keyboard) }
        }
    }
    /// Track names from the last pattern read from the device.
    @Published var trackNames: [String] = []

    let catalog: ControlCatalog
    var onError: ((String) -> Void)?
    private let output: ControlOutput
    private let defaults: UserDefaults?
    private let now: () -> Double
    private var throttle = SendThrottle<ControlKey, ControlMessage>(interval: 1 / ControlModel.sendRate)
    private var flushTask: Task<Void, Never>?
    private var clock = IncomingClock()
    private var clockWatch: Task<Void, Never>?
    private var noteChannels: [Int: Int] = [:]
    private var pageMemory: [String: DNPage] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private weak var studio: StudioModel?
    private var followingStudio = false
    private var replacingSoundDraft = false
    private var confirmedProgram: Int?
    private var synchronizingRoute = false
    /// Intentionally staged values must survive reconnect feedback until explicitly applied.
    private var awaitingApply = Set<ControlKey>()

    private enum Store {
        static let machines = "control.machines"
        static let channels = "control.channels"
        static let track = "control.track"
        static let page = "control.page"
        static let checks = "control.setupChecks"
        static let keyboard = "control.keyboardBase"
        static let inputRouting = "control.inputRouting"
    }

    /// `defaults` nil keeps everything in memory (tests, previews).
    init(output: ControlOutput, catalog: ControlCatalog = .hardware, defaults: UserDefaults? = .standard,
         channels: DNChannelMap? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.output = output
        self.catalog = catalog
        self.defaults = defaults
        self.now = now
        let storedMachines = (defaults?.stringArray(forKey: Store.machines) ?? []).map { DNMachine(rawValue: $0) ?? .fmTone }
        machines = (0..<Self.trackCount).map { storedMachines.indices.contains($0) ? storedMachines[$0] : .fmTone }
        let storedMap = defaults?.data(forKey: Store.channels).flatMap { try? JSONDecoder().decode(DNChannelMap.self, from: $0) }
        channelMap = Self.sanitized(channels ?? storedMap ?? HardwareCatalog.factoryChannels)
        selectedTrack = min(Self.trackCount - 1, max(0, defaults?.integer(forKey: Store.track) ?? 0))
        page = defaults?.string(forKey: Store.page).flatMap(DNPage.init(rawValue:)) ?? .syn1
        setupChecks = Set(defaults?.stringArray(forKey: Store.checks) ?? [])
        inputRouting = defaults?.string(forKey: Store.inputRouting).flatMap(ControlInputRouting.init(rawValue:)) ?? .autoChannel
        keyboardBase = (defaults?.object(forKey: Store.keyboard) as? Int).map { min(96, max(0, $0 / 12 * 12)) } ?? 48
        validatePage()
    }

    // MARK: Structure

    var machine: DNMachine { machines[selectedTrack] }
    var pages: [DNPage] { catalog.pages(machine) }
    var globalPages: [DNPage] { DNPage.allCases.filter(\.isGlobal) }
    var allPages: [DNPage] { pages + globalPages }

    func parameters(on page: DNPage) -> [DNParameter] {
        catalog.parameters(page, machine).sorted { $0.slot < $1.slot }
    }

    var pageParameters: [DNParameter] { parameters(on: page) }

    func scope(for page: DNPage) -> ControlScope { page.isGlobal ? .global : .track(selectedTrack) }

    func channel(for page: DNPage) -> Int? { ControlRouting.channel(for: scope(for: page), in: channelMap) }

    var canSend: Bool { output.isAvailable }

    /// Disconnected and channel-OFF edits are useful local drafts; sending has separate requirements.
    func canEdit(_ page: DNPage) -> Bool { !isApplying && studio?.busy != true && !parameters(on: page).isEmpty }

    func value(_ parameter: DNParameter) -> ControlValue? {
        values[ControlKey(scope: scope(for: parameter.page), id: parameter.id)]
    }

    /// The fader beside the knobs, like the device's LEVEL knob: track level, or VOL on global pages.
    func levelParameter(for page: DNPage) -> DNParameter? {
        if page.isGlobal { return parameters(on: page).first { $0.label.uppercased() == "VOL" && $0.slot > 7 } }
        return parameters(on: .track).first { $0.cc == 95 || ["LEV", "LEVEL"].contains($0.label.uppercased()) }
    }

    // MARK: Navigation

    func selectTrack(_ track: Int) {
        guard (0..<Self.trackCount).contains(track), track != selectedTrack else { return }
        releaseKeys()
        flushAll()
        selectedTrack = track
        incomingNotes = []
        validatePage()
        defaults?.set(track, forKey: Store.track)
        syncStudio()
    }

    func step(track delta: Int) {
        selectTrack(((selectedTrack + delta) % Self.trackCount + Self.trackCount) % Self.trackCount)
    }

    func select(page: DNPage) {
        guard allPages.contains(page), page != self.page else { return }
        flushAll()
        self.page = page
        pageMemory[page.group] = page
        defaults?.set(page.rawValue, forKey: Store.page)
    }

    /// Selects a page group as the device's page buttons do: first press opens the
    /// last used page of the group, further presses cycle through its pages.
    func select(group: String) {
        let members = allPages.filter { $0.group == group }
        guard let first = members.first else { return }
        if page.group == group, let index = members.firstIndex(of: page) {
            select(page: members[(index + 1) % members.count])
        } else {
            select(page: pageMemory[group].flatMap { members.contains($0) ? $0 : nil } ?? first)
        }
    }

    func step(page delta: Int) {
        let list = allPages
        guard !list.isEmpty else { return }
        let index = list.firstIndex(of: page) ?? 0
        select(page: list[((index + delta) % list.count + list.count) % list.count])
    }

    func setMachine(_ machine: DNMachine, track: Int) {
        guard machines.indices.contains(track), machines[track] != machine else { return }
        machines[track] = machine
        defaults?.set(machines.map(\.rawValue), forKey: Store.machines)
        if track == selectedTrack { validatePage(); syncStudio() }
    }

    private func validatePage() {
        guard !page.isGlobal, !pages.contains(page) else { return }
        page = pages.first { $0.group == page.group } ?? pages.first ?? globalPages[0]
    }

    // MARK: Parameters

    /// Saves an edit locally, then sends it when connected and routed. Offline edits never auto-apply.
    func set(_ parameter: DNParameter, to value14: Int) {
        guard canEdit(parameter.page) else { return }
        let scope = scope(for: parameter.page)
        if case .track(let track) = scope, parameter.id == muteParameter(track: track).id {
            setMute(track: track, muted: ControlMute.isMuted(value14))
            return
        }
        let key = ControlKey(scope: scope, id: parameter.id)
        let value = ControlEncoding.clamp(value14, for: parameter)
        if values[key]?.value == value { return }
        values[key] = ControlValue(value: value, origin: .draft)
        mirrorToStudio(key: key, value: values[key]!)
        guard output.isAvailable, let channel = ControlRouting.channel(for: scope, in: channelMap),
              let message = ControlEncoding.message(for: parameter, value14: value, channel: channel) else {
            awaitingApply.insert(key)
            return
        }
        awaitingApply.remove(key)
        if let ready = throttle.offer(message, for: key, at: now()) { transmit(ready, key: key) } else { scheduleFlush() }
    }

    /// Stages a deliberate parameter recipe without touching the instrument, even while connected.
    /// Values are 14-bit, as in `set`; unmentioned parameters keep their existing values/origins.
    func stage(_ parameters: [DNParameter: Int]) {
        guard !isApplying, studio?.busy != true else { return }
        flushTask?.cancel()
        flushTask = nil
        throttle = SendThrottle(interval: 1 / Self.sendRate)
        for (parameter, amount) in parameters {
            let key = ControlKey(scope: scope(for: parameter.page), id: parameter.id)
            let value = ControlValue(value: ControlEncoding.clamp(amount, for: parameter), origin: .draft)
            values[key] = value
            awaitingApply.insert(key)
            mirrorToStudio(key: key, value: value)
        }
    }

    var draftCount: Int { draftParameters.count }
    var canApplyDrafts: Bool { canSend && channel(for: page) != nil && !isApplying && studio?.busy != true && draftCount > 0 }

    private var draftParameters: [DNParameter] {
        let candidates = (page.isGlobal ? globalPages : pages).flatMap { parameters(on: $0) }
        return candidates.filter { value($0)?.origin == .draft }
    }

    /// Applies only the current track's drafts, or global FX drafts when a global page is selected.
    /// Fine NRPN steps are preserved. Successful sends are `sent`, never fabricated readback.
    func applyDrafts() async {
        guard canApplyDrafts, let channel = channel(for: page) else { return }
        let targetScope = scope(for: page)
        let changes = draftParameters.compactMap { parameter -> (ControlKey, ControlMessage, Int)? in
            guard let value = value(parameter), let encoded = ControlEncoding.message(for: parameter, value14: value.value, channel: channel) else { return nil }
            let message = parameter.cc == ControlEncoding.muteController ? ControlEncoding.mute(ControlMute.isMuted(value.value), channel: channel) : encoded
            return (ControlKey(scope: targetScope, id: parameter.id), message, value.value)
        }
        isApplying = true
        defer { isApplying = false }
        // Any existing queued drag values are included in the explicit draft list above.
        flushTask?.cancel()
        flushTask = nil
        throttle = SendThrottle(interval: 1 / Self.sendRate)
        var count = 0
        for change in changes {
            guard output.isAvailable, ControlRouting.channel(for: targetScope, in: channelMap) == channel else { break }
            guard values[change.0] == ControlValue(value: change.2, origin: .draft) else { continue }
            guard transmit(change.1, key: change.0) else { break }
            count += 1
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { break }
        }
        if count > 0 { studio?.notice = "Отправлено \(count) параметров в MIDI-канал \(channel + 1). Подтверждение значений придёт от прибора." }
    }

    /// End of a gesture: a value still waiting for its slot is sent now.
    func endEdit(_ parameter: DNParameter) {
        let key = ControlKey(scope: scope(for: parameter.page), id: parameter.id)
        if let message = throttle.flush(key, at: now()) { transmit(message, key: key) }
    }

    func reset(_ parameter: DNParameter) {
        set(parameter, to: parameter.defaultValue14)
        endEdit(parameter)
    }

    /// Sends values whose rate-limit slot has come.
    func flushDue() {
        for item in throttle.due(at: now()) { transmit(item.payload, key: item.key) }
        scheduleFlush()
    }

    func flushAll() {
        flushTask?.cancel()
        flushTask = nil
        for item in throttle.flushAll(at: now()) { transmit(item.payload, key: item.key) }
    }

    private func scheduleFlush() {
        guard flushTask == nil, let due = throttle.nextDue else { return }
        let delay = max(0.001, due - now())
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            self.flushDue()
        }
    }

    @discardableResult
    private func transmit(_ message: ControlMessage, key: ControlKey? = nil) -> Bool {
        guard output.isAvailable else { return false }
        do {
            try output.send(message)
            if let key, var value = values[key] {
                awaitingApply.remove(key)
                value.origin = .sent
                values[key] = value
                mirrorToStudio(key: key, value: value)
            }
            return true
        } catch {
            if let key { awaitingApply.insert(key) }
            onError?(error.localizedDescription)
            return false
        }
    }

    // MARK: Mutes

    func muteParameter(track: Int) -> DNParameter {
        ControlMute.parameter(machine: machines.indices.contains(track) ? machines[track] : .fmTone, catalog: catalog)
    }

    func mute(track: Int) -> Observed<Bool>? {
        values[ControlKey(scope: .track(track), id: muteParameter(track: track).id)]
            .map { Observed(value: ControlMute.isMuted($0.value), origin: $0.origin) }
    }

    func canMute(track: Int) -> Bool { output.isAvailable && channelMap.channel(forTrack: track) != nil }

    func toggleMute(track: Int) { setMute(track: track, muted: !(mute(track: track)?.value ?? false)) }

    func setMute(track: Int, muted: Bool) {
        guard !isApplying, (0..<Self.trackCount).contains(track) else { return }
        let key = ControlKey(scope: .track(track), id: muteParameter(track: track).id)
        values[key] = ControlValue(value: (muted ? 127 : 0) << 7, origin: .draft)
        mirrorToStudio(key: key, value: values[key]!)
        guard output.isAvailable, let channel = channelMap.channel(forTrack: track) else {
            awaitingApply.insert(key)
            return
        }
        transmit(ControlEncoding.mute(muted, channel: channel), key: key)
    }

    // MARK: Transport and patterns

    var isPlaying: Bool { transport?.value == true }

    func togglePlay() { isPlaying ? stop() : start() }

    func start() {
        guard output.isAvailable else { return }
        guard transmit(.start) else { return }
        clock.receive(.start)
        transport = Observed(value: true, origin: .sent)
    }

    func stop() {
        guard output.isAvailable else { return }
        guard transmit(.stop) else { return }
        clock.receive(.stop)
        transport = Observed(value: false, origin: .sent)
        clockStep = nil
    }

    /// Switches the device to a pattern (PRG CH RECEIVE on PROGRAM CHG IN CH).
    func selectPattern(_ program: Int) {
        guard output.isAvailable else { return }
        let program = min(127, max(0, program))
        guard transmit(.programChange(channel: channelMap.effectiveProgramChangeChannel, program: program)) else { return }
        if self.program?.value != program { invalidatePatternValues() }
        self.program = Observed(value: program, origin: .sent)
    }

    /// A new pattern can replace every sound and FX setting. Keep intentional local drafts;
    /// queued edits from the old pattern require an explicit apply on the new one.
    private func invalidatePatternValues() {
        flushTask?.cancel()
        flushTask = nil
        throttle = SendThrottle(interval: 1 / Self.sendRate)
        values = values.filter { $0.value.origin == .draft }
        if let studio {
            for channel in Set(channelMap.trackChannels.compactMap { $0 }) { studio.clearObservedValues(channel: channel) }
        }
    }

    // MARK: Keyboard

    var keyboardChannel: Int? { channelMap.channel(forTrack: selectedTrack) }

    func noteOn(_ note: Int, velocity: Int) {
        guard output.isAvailable, let channel = keyboardChannel, (0..<128).contains(note) else { return }
        if let previous = noteChannels[note] { output.noteOff(channel: previous, note: note) }
        output.noteOn(channel: channel, note: note, velocity: velocity)
        noteChannels[note] = channel
        heldNotes.insert(note)
    }

    func noteOff(_ note: Int) {
        guard let channel = noteChannels.removeValue(forKey: note) else { return }
        heldNotes.remove(note)
        output.noteOff(channel: channel, note: note)
    }

    func releaseKeys() {
        for note in Array(noteChannels.keys) { noteOff(note) }
    }

    // MARK: Channel map and setup

    func setTrackChannel(_ channel: Int?, track: Int) {
        guard (0..<Self.trackCount).contains(track) else { return }
        releaseKeys()
        flushAll()
        let drafts = values.filter { $0.key.scope == .track(track) && $0.value.origin == .draft }
        var map = channelMap
        map.trackChannels[track] = channel.map { min(15, max(0, $0)) }
        // A new MIDI route may have no archive values yet. Preserve deliberate per-track
        // drafts while switching/mirroring so an OFF → channel assignment cannot erase them.
        synchronizingRoute = true
        store(map)
        if track == selectedTrack { syncStudio() }
        for (key, value) in drafts { mirrorToStudio(key: key, value: value) }
        synchronizingRoute = false
        if track == selectedTrack, let studio { followStudioValues(studio.values) }
    }

    func setFXChannel(_ channel: Int?) { flushAll(); var map = channelMap; map.fxControlChannel = channel.map { min(15, max(0, $0)) }; store(map) }
    func setAutoChannel(_ channel: Int) { var map = channelMap; map.autoChannel = min(15, max(0, channel)); store(map) }
    func setProgramChannel(_ channel: Int?) { var map = channelMap; map.programChangeChannel = channel.map { min(15, max(0, $0)) }; store(map) }
    func resetChannels() { releaseKeys(); flushAll(); store(Self.sanitized(HardwareCatalog.factoryChannels)); syncStudio() }

    private func store(_ map: DNChannelMap) {
        channelMap = map
        if let data = try? JSONEncoder().encode(map) { defaults?.set(data, forKey: Store.channels) }
    }

    private static func sanitized(_ map: DNChannelMap) -> DNChannelMap {
        var map = map
        map.trackChannels = (0..<trackCount).map { index in
            map.trackChannels.indices.contains(index) ? map.trackChannels[index].flatMap { (0..<16).contains($0) ? $0 : nil } : nil
        }
        map.fxControlChannel = map.fxControlChannel.flatMap { (0..<16).contains($0) ? $0 : nil }
        map.autoChannel = min(15, max(0, map.autoChannel))
        map.programChangeChannel = map.programChangeChannel.flatMap { (0..<16).contains($0) ? $0 : nil }
        return map
    }

    func toggleCheck(_ id: String) {
        if setupChecks.contains(id) { setupChecks.remove(id) } else { setupChecks.insert(id) }
        defaults?.set(setupChecks.sorted(), forKey: Store.checks)
    }

    // MARK: Incoming MIDI

    /// A CC/NRPN from the device: resolved to the track (or FX page) it belongs to and marked received.
    func receive(_ event: ParameterEvent) {
        feedbackSeen = true
        guard let resolved = ControlRouting.resolve(event, map: channelMap, machines: machines,
                                                    selectedTrack: selectedTrack, catalog: catalog, preferAuto: inputRouting == .autoChannel) else { return }
        // A local edit waiting for its send slot is newer than anything the device reports now.
        guard throttle.pending[resolved.key] == nil, !awaitingApply.contains(resolved.key) else { return }
        // The instrument is authoritative. Do not clamp feedback to assumed option lists.
        let value = resolved.parameter.isHighResolution ? resolved.value : (resolved.value >> 7) << 7
        let update = ControlValue(value: value, origin: .received)
        values[resolved.key] = update
        mirrorToStudio(key: resolved.key, value: update)
    }

    func receive(_ event: MIDIInputEvent) {
        switch event {
        case .note(let note):
            guard note.channel == keyboardChannel || (inputRouting == .autoChannel && note.channel == channelMap.autoChannel) else { return }
            if note.isOn { incomingNotes.insert(note.note) } else { incomingNotes.remove(note.note) }
        case .programChange(let channel, let program):
            guard channel == channelMap.effectiveProgramChangeChannel else { return }
            if confirmedProgram != program { invalidatePatternValues() }
            confirmedProgram = program
            self.program = Observed(value: program, origin: .received)
        case .transport(let command):
            clock.receive(command)
            switch command {
            case .start, .continue: transport = Observed(value: true, origin: .received)
            case .stop: transport = Observed(value: false, origin: .received); clockStep = nil
            case .songPosition: break
            }
            publishClock()
        case .clock(let hostTime):
            clock.pulse(at: hostTime)
            publishClock()
            watchClock()
        }
    }

    private func publishClock() {
        if let bpm = clock.bpm {
            let rounded = (bpm * 10).rounded() / 10
            if tempo.map({ abs($0 - rounded) >= 0.15 }) ?? true { tempo = rounded }
        }
        let step = clock.isRunning && clock.lastPulseHostTime != nil ? (max(0, clock.position - 1) / 6) % 16 : nil
        if step != clockStep { clockStep = step }
    }

    private func watchClock() {
        guard clockWatch == nil else { return }
        clockWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                if !self.clock.isReceiving(at: HostClock.now, timeout: 0.6) {
                    let running = self.clock.isRunning
                    self.clock.reset()
                    if running { self.clock.receive(.start) }
                    self.tempo = nil
                    self.clockStep = nil
                    self.clockWatch = nil
                    return
                }
            }
        }
    }

    // MARK: Studio binding

    /// Follows the studio's MIDI input and connection, and keeps its editor channel/machine on the selected track.
    func bind(to studio: StudioModel) {
        subscriptions.removeAll()
        self.studio = studio
        onError = { [weak studio] in studio?.error = $0 }
        studio.parameterInput.sink { [weak self] in self?.receive($0) }.store(in: &subscriptions)
        studio.midiInput.sink { [weak self] in self?.receive($0) }.store(in: &subscriptions)
        studio.$channel.dropFirst().removeDuplicates().sink { [weak self] in self?.followStudioChannel($0) }.store(in: &subscriptions)
        studio.$machine.dropFirst().removeDuplicates().sink { [weak self] machine in
            guard let self, let hardware = DNMachine(rawValue: machine.rawValue) else { return }
            self.followingStudio = true
            self.setMachine(hardware, track: self.selectedTrack)
            self.followingStudio = false
        }.store(in: &subscriptions)
        studio.$values.sink { [weak self] in self?.followStudioValues($0) }.store(in: &subscriptions)
        studio.$identity.map { $0?.isDigitoneII == true }.removeDuplicates().dropFirst()
            .sink { [weak self] connected in if !connected { self?.connectionEnded() } }.store(in: &subscriptions)
        studio.$pattern.map { $0?.trackNames ?? [] }.removeDuplicates()
            .sink { [weak self] in self?.trackNames = $0 }.store(in: &subscriptions)
        // Views attach during their update; change the studio afterwards.
        Task { @MainActor [weak self] in self?.syncStudio() }
    }

    var hasDrafts: Bool { values.contains { $0.key.scope == .track(selectedTrack) && $0.value.origin == .draft } }
    var canSaveSound: Bool { machine != .midi && channelMap.channel(forTrack: selectedTrack) != nil }

    /// Sound archives and A/B checkpoints deliberately replace live fine values with their coarse drafts.
    func prepareSoundDraftReplacement() { replacingSoundDraft = true }

    /// Legacy sound archives are coarse track parameters; global FX values are excluded.
    private func mirrorToStudio(key: ControlKey, value: ControlValue) {
        guard let studio, case .track(let track) = key.scope,
              machines.indices.contains(track), let channel = channelMap.channel(forTrack: track),
              let machine = SynthMachine(rawValue: machines[track].rawValue),
              let parameter = HardwareCatalog.parameter(id: key.id),
              let definition = ParameterCatalog.definition(for: parameter, machine: machine) else { return }
        let origin: ParameterOrigin = value.origin == .received ? .received : value.origin == .sent ? .sent : .draft
        let route = "\(channel):\(machine.id)"
        let update = KnownParameter(value: DNParameter.coarse(value.value), origin: origin)
        if let existing = studio.values[route]?[definition.id], existing.value == update.value, existing.origin == update.origin { return }
        studio.values[route, default: [:]][definition.id] = update
    }

    private func followStudioValues(_ routes: [String: [String: KnownParameter]]) {
        guard !synchronizingRoute, let studio, machine != .midi, let synth = SynthMachine(rawValue: machine.rawValue),
              let channel = channelMap.channel(forTrack: selectedTrack), studio.channel == channel, studio.machine == synth else { return }
        let route = "\(channel):\(synth.id)"
        let replaceFineDrafts = replacingSoundDraft
        replacingSoundDraft = false
        let definitions = ParameterCatalog.parameters(for: synth)
        let retained = Set(definitions.compactMap { definition -> String? in
            guard routes[route]?[definition.id] != nil else { return nil }
            return ParameterCatalog.hardwareParameter(for: definition, machine: synth)?.id
        })
        for key in Array(values.keys) where key.scope == .track(selectedTrack) && !retained.contains(key.id) && throttle.pending[key] == nil {
            values[key] = nil
        }
        for definition in definitions {
            guard let observed = routes[route]?[definition.id],
                  let parameter = ParameterCatalog.hardwareParameter(for: definition, machine: synth) else { continue }
            let key = ControlKey(scope: .track(selectedTrack), id: parameter.id)
            guard throttle.pending[key] == nil else { continue }
            let origin: ControlOrigin = observed.origin == .received ? .received : observed.origin == .sent ? .sent : .draft
            if origin == .draft { awaitingApply.insert(key) } else { awaitingApply.remove(key) }
            // Mirroring our own coarse archive update must preserve a fine NRPN value.
            if let current = values[key], DNParameter.coarse(current.value) == observed.value {
                if origin == .sent, current.origin == .draft {
                    values[key] = ControlValue(value: current.value, origin: .sent)
                    continue
                }
                if current.origin == origin, !(replaceFineDrafts && origin == .draft) { continue }
            }
            values[key] = ControlValue(value: observed.value << 7, origin: origin)
        }
        awaitingApply.formIntersection(values.keys)
    }

    private func followStudioChannel(_ channel: Int) {
        guard channelMap.channel(forTrack: selectedTrack) != channel,
              let track = channelMap.trackChannels.firstIndex(of: channel) else { return }
        followingStudio = true
        selectTrack(track)
        followingStudio = false
    }

    private func syncStudio() {
        guard let studio, !studio.busy, !followingStudio else { return }
        if let channel = channelMap.channel(forTrack: selectedTrack), studio.channel != channel { studio.channel = channel }
        if let synth = SynthMachine(rawValue: machine.rawValue), studio.machine != synth { studio.machine = synth }
        followStudioValues(studio.values)
    }

    /// The device may change while disconnected, so nothing stays known.
    func connectionEnded() {
        flushTask?.cancel()
        flushTask = nil
        clockWatch?.cancel()
        clockWatch = nil
        throttle = SendThrottle(interval: 1 / Self.sendRate)
        values = values.filter { $0.value.origin == .draft }
        awaitingApply.formIntersection(values.keys)
        transport = nil
        program = nil
        confirmedProgram = nil
        tempo = nil
        clockStep = nil
        clock.reset()
        noteChannels.removeAll()
        heldNotes = []
        incomingNotes = []
        feedbackSeen = false
    }
}

// MARK: - One control model per studio

private struct ControlAttachment {
    weak var studio: StudioModel?
    let control: ControlModel
}

extension ControlModel {
    private static var attachments: [ObjectIdentifier: ControlAttachment] = [:]

    /// Read-only lookup used to let the mapped control model own incoming routing.
    static func existing(for studio: StudioModel) -> ControlModel? {
        let attachment = attachments[ObjectIdentifier(studio)]
        return attachment?.studio === studio ? attachment?.control : nil
    }

    /// The control model shared by every view of `studio` (surface, transport bar, connection panel).
    static func attached(to studio: StudioModel) -> ControlModel {
        attachments = attachments.filter { $0.value.studio != nil }
        if let existing = attachments[ObjectIdentifier(studio)], existing.studio === studio { return existing.control }
        let control = ControlModel(output: StudioControlOutput(studio: studio))
        control.bind(to: studio)
        attachments[ObjectIdentifier(studio)] = ControlAttachment(studio: studio, control: control)
        return control
    }

    /// Injects a model for `studio` (previews and snapshot scenes).
    static func attach(_ control: ControlModel, to studio: StudioModel) {
        attachments[ObjectIdentifier(studio)] = ControlAttachment(studio: studio, control: control)
    }
}
