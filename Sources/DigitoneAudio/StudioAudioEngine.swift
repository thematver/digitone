import AVFoundation
import Observation
import DigitoneDSP

/// The app's audio graph: Digitone (or any) input → monitoring, retrospective
/// capture and recording; players, hosted DSP sources and the monitor path →
/// master mixer → the computer's output.
///
/// macOS: the output is an AVAudioEngine on the system default output (it
/// follows headphones being plugged in); the input is a separate HAL unit on
/// the Digitone feeding a drift-corrected ring, because AVAudioEngine can only
/// run input and output on one device. iOS: one engine on the session route.
@MainActor
@Observable
public final class StudioAudioEngine {
    public enum State: Sendable, Equatable { case stopped, running, interrupted }

    public struct Options: Sendable {
        /// IO buffer requested on both devices (macOS); raised automatically on overloads.
        public var bufferFrames: Int
        /// Apps must declare NSMicrophoneUsageDescription; command-line tools run without a bundle.
        public var requiresUsageDescription: Bool
        public init(bufferFrames: Int = 128, requiresUsageDescription: Bool = true) {
            self.bufferFrames = bufferFrames
            self.requiresUsageDescription = requiresUsageDescription
        }
    }

    public let devices: AudioDeviceCatalog
    public let options: Options
    /// Output graph state.
    public internal(set) var state: State = .stopped
    public internal(set) var isInputRunning = false
    public internal(set) var isStarting = false
    public internal(set) var permission: RecordPermission
    public internal(set) var lastError: AudioEngineError? {
        didSet { if let lastError, lastError != oldValue { onError?(lastError) } }
    }
    public internal(set) var inputDevice: AudioDevice?
    public internal(set) var outputDevice: AudioDevice?
    public internal(set) var inputFormat: StreamFormat?
    public internal(set) var outputFormat: StreamFormat?
    public internal(set) var isRecording = false
    public internal(set) var lastRecording: Recording? {
        didSet { if let lastRecording, lastRecording != oldValue { onRecordingFinished?(lastRecording) } }
    }
    public internal(set) var isPlaying = false
    public internal(set) var attachedSourceCount = 0
    /// Why monitoring cannot run; nil when it can.
    public internal(set) var monitorBlock: MonitorBlock?
    /// Estimated Digitone → speakers delay while input and output run.
    public internal(set) var monitorLatency: MonitorLatency?
    /// IO buffer sizes in effect (frames).
    public internal(set) var inputBufferFrames = 0
    public internal(set) var outputBufferFrames = 0
    /// App-level hooks, also delivered when a take ends during a route change
    /// or interruption. Both run on the main actor.
    @ObservationIgnored public var onRecordingFinished: (@MainActor (Recording) -> Void)?
    @ObservationIgnored public var onError: (@MainActor (AudioEngineError) -> Void)?

    /// "Слушать Digitone": hear the input through the output. On by default
    /// and remembered; forced silent while `monitorBlock` is set.
    public var isMonitoringInput: Bool {
        didSet {
            guard oldValue != isMonitoringInput else { return }
            settings.isEnabled = isMonitoringInput
            applyMonitoring()
        }
    }

    /// Monitor level 0...1, separate from `masterGain`; remembered.
    public var monitorGain: Float {
        didSet {
            let clamped = MonitorSettings.clamp(monitorGain)
            if clamped != monitorGain { monitorGain = clamped; return }
            settings.gain = monitorGain
            applyMonitoring()
        }
    }

    /// Master output level, 0...1.
    public var masterGain: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = min(max(masterGain, 0), 1) }
    }

    /// True while the Digitone is actually audible through the output.
    public var isMonitorActive: Bool {
        isMonitoringInput && monitorGain > 0 && monitorBlock == nil && isInputRunning && state == .running
    }

    @ObservationIgnored public nonisolated let pipeline = InputPipeline()
    @ObservationIgnored let engine = AVAudioEngine()
    @ObservationIgnored let playback = AudioPlayback()
    @ObservationIgnored nonisolated let inputMeter = StereoMeter()
    @ObservationIgnored var settings: MonitorSettings
    @ObservationIgnored var hosted: [ObjectIdentifier: HostedSource] = [:]
    @ObservationIgnored var tokens: [AnyObject] = []
    @ObservationIgnored var catalogHandler: UUID?
    @ObservationIgnored var policy = AudioRoutePolicy()
    @ObservationIgnored var pinnedInputName: String?
    @ObservationIgnored var pinnedOutputName: String?
    @ObservationIgnored var lifecycleGeneration: UInt = 0
    @ObservationIgnored var playbackRequestGeneration: UInt = 0
    @ObservationIgnored var isRebuilding = false
    @ObservationIgnored var startTask: Task<Void, Error>?
    @ObservationIgnored var startRequestID: UUID?
    @ObservationIgnored var autoStartTask: Task<Void, Never>?
    @ObservationIgnored var autoStartRequestID: UUID?
    /// Set by `autoStart` and explicit input starts; hot-plugging a Digitone then starts input.
    @ObservationIgnored var autoStartArmed = false
    @ObservationIgnored var overloadTimes: [Double] = []
    @ObservationIgnored public private(set) var overloadCount = 0
    #if os(macOS)
    @ObservationIgnored var halInput: HALInput?
    @ObservationIgnored let monitorRing = MonitorRing()
    @ObservationIgnored var monitorSource: MonitorSource?
    @ObservationIgnored var monitorNode: AVAudioSourceNode?
    @ObservationIgnored var requestedInputFrames: Int
    @ObservationIgnored var requestedOutputFrames: Int
    @ObservationIgnored var inputOverloadToken: AnyObject?
    @ObservationIgnored var inputFormatToken: AnyObject?
    @ObservationIgnored var outputOverloadToken: AnyObject?
    #else
    @ObservationIgnored let monitorMixer = AVAudioMixerNode()
    @ObservationIgnored var inputRequested = false
    @ObservationIgnored var tapInstalled = false
    @ObservationIgnored var monitorConnected = false
    #endif

    struct HostedSource {
        let source: any AudioRenderSource
        var node: AVAudioSourceNode
        var sampleRate: Double
    }

    public init(devices: AudioDeviceCatalog? = nil, settings: MonitorSettings = MonitorSettings(), options: Options = Options()) {
        self.devices = devices ?? AudioDeviceCatalog()
        self.settings = settings
        self.options = options
        isMonitoringInput = settings.isEnabled
        monitorGain = settings.gain
        permission = RecordPermission.current
        #if os(macOS)
        requestedInputFrames = options.bufferFrames
        requestedOutputFrames = options.bufferFrames
        #else
        policy.treatUSBPairAsSameDevice = true
        policy.followsSessionOutput = true
        engine.attach(monitorMixer)
        #endif
        engine.attach(playback.node)
        observeSystem()
        catalogHandler = self.devices.onChange { [weak self] in self?.devicesChanged() }
        inputDevice = resolveInput()
        outputDevice = resolveOutput()
        refreshMonitor()
        pipeline.setErrorHandler { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                // A delayed worker error must not close a newly started take.
                if self.pipeline.recorder.failure != nil { self.finishRecording() }
                self.lastError = error
            }
        }
    }

    // MARK: Lifecycle

    /// Starts the output graph and, with `enableInput`, the input and monitoring.
    /// Input asks for record permission first; a missing permission or input
    /// device is an error. Without `enableInput` a running input is kept: pads
    /// and take playback never interrupt what the user is hearing.
    public func start(enableInput: Bool = true) async throws {
        if enableInput { autoStartArmed = true }
        while let pending = startTask { _ = await pending.result }
        try Task.checkCancellation()
        guard !isSatisfied(enableInput: enableInput) else { return }
        let requestID = UUID()
        startRequestID = requestID
        let task = Task { @MainActor in
            defer {
                if self.startRequestID == requestID {
                    self.startTask = nil
                    self.startRequestID = nil
                }
            }
            try await self.performStart(enableInput: enableInput)
        }
        startTask = task
        let result = await withTaskCancellationHandler { await task.result } onCancel: { task.cancel() }
        try result.get()
    }

    /// Starts input, monitoring and output when a Digitone audio input is
    /// present, asking for input permission once. Idempotent: views call it on
    /// appear; later hot-plugs of the Digitone start it again by themselves.
    public func autoStart() async {
        autoStartArmed = true
        if let running = autoStartTask { await running.value; return }
        let requestID = UUID()
        autoStartRequestID = requestID
        let task = Task { @MainActor in
            defer {
                if self.autoStartRequestID == requestID {
                    self.autoStartTask = nil
                    self.autoStartRequestID = nil
                }
            }
            await self.performAutoStart()
        }
        autoStartTask = task
        await task.value
    }

    public func stop() {
        lifecycleGeneration &+= 1
        playbackRequestGeneration &+= 1
        autoStartArmed = false
        startTask?.cancel()
        autoStartTask?.cancel()
        playback.stop()
        isPlaying = false
        stopInput(failure: AudioEngineError.notRunning)
        engine.stop()
        state = .stopped
        monitorLatency = nil
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { lastError = Self.wrap(error, "остановка аудиосессии") }
        #endif
        refreshMonitor()
    }

    public func requestPermission() async -> RecordPermission {
        permission = await RecordPermission.request()
        refreshMonitor()
        return permission
    }

    /// `nil` returns to automatic selection (Digitone, else the system input).
    public func selectInput(_ device: AudioDevice?) throws {
        try select(device, input: true)
    }

    /// `nil` returns to the system output. Only a pinned output can be the
    /// Digitone; monitoring then switches off to avoid a loop. On iOS only the
    /// built-in speaker override is honoured; other outputs follow the route.
    public func selectOutput(_ device: AudioDevice?) throws {
        try select(device, input: false)
    }

    // MARK: Monitoring and capture

    /// Input L/R peak and RMS with ballistics; poll at display rate.
    public nonisolated func inputLevels() -> StereoLevels { inputMeter.read() }

    /// Levels of what the monitor path plays (after monitor gain, before master).
    public func monitorPathLevels() -> StereoLevels {
        #if os(macOS)
        monitorSource?.meter.read() ?? .silent
        #else
        guard isMonitorActive else { return .silent }
        let levels = inputMeter.read()
        return StereoLevels(left: ChannelLevel(peak: levels.left.peak * monitorGain, rms: levels.left.rms * monitorGain),
                            right: ChannelLevel(peak: levels.right.peak * monitorGain, rms: levels.right.rms * monitorGain))
        #endif
    }

    /// Latest levels, scope and spectrum; cheap enough to call every frame.
    public nonisolated func meterSnapshot() -> MeterSnapshot { pipeline.meters.snapshot }

    /// The last `seconds` of input (at most 30), stereo.
    public nonisolated func captureLast(seconds: Double) -> SampleBuffer {
        pipeline.captureLast(seconds: seconds)
    }

    /// Seconds written by the current recording.
    public nonisolated var recordedDuration: Double { pipeline.recorder.recordedDuration }

    public func startRecording(to url: URL, format: RecordingFormat = .wav24) throws {
        guard isInputRunning, let inputFormat else { throw AudioEngineError.notRunning }
        try pipeline.startRecording(to: url, format: format,
                                    sampleRate: inputFormat.sampleRate, channelCount: inputFormat.channelCount)
        isRecording = true
    }

    @discardableResult
    public func stopRecording() throws -> Recording? {
        defer { isRecording = false }
        do {
            let recording = try pipeline.stopRecording()
            if let recording { lastRecording = recording }
            return recording
        } catch {
            if let recording = pipeline.recorder.lastFinishedRecording { lastRecording = recording }
            lastError = Self.wrap(error, "запись")
            throw error
        }
    }

    /// Records the next `duration` seconds of input into memory (stereo), e.g. for auto-sampling.
    public func recordSegment(duration: Double) async throws -> SampleBuffer {
        guard isInputRunning, let inputFormat else { throw AudioEngineError.notRunning }
        guard duration.isFinite, (0...300).contains(duration) else {
            throw AudioEngineError.formatUnsupported("длина сэмпла должна быть от 0 до 300 секунд")
        }
        guard duration * inputFormat.sampleRate <= 25_000_000 else {
            throw AudioEngineError.formatUnsupported("слишком большой сэмпл для записи в память")
        }
        let frames = Int((max(0, duration) * inputFormat.sampleRate).rounded())
        let request = SegmentRequest(id: UUID(), frames: frames)
        let pipeline = pipeline
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.install { continuation.resume(with: $0) }
                pipeline.addSegment(request)
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
            pipeline.cancelSegment(id: request.id)
        }
    }

    // MARK: Playback

    /// Plays `buffer` from `start` seconds; with `loop` the region repeats until stopped.
    public func play(_ buffer: SampleBuffer, from start: Double = 0, loop: Range<Double>? = nil) throws {
        guard state == .running else { throw AudioEngineError.notRunning }
        guard start.isFinite, loop.map({ $0.lowerBound.isFinite && $0.upperBound.isFinite }) ?? true,
              buffer.sampleRate.isFinite, buffer.sampleRate > 0, buffer.frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: buffer.sampleRate,
                                         channels: AVAudioChannelCount(buffer.channelCount)) else {
            throw AudioEngineError.formatUnsupported("пустой буфер")
        }
        playbackRequestGeneration &+= 1
        playback.stop()
        if playback.format != format {
            engine.disconnectNodeOutput(playback.node)
            engine.connect(playback.node, to: engine.mainMixerNode, format: format)
            playback.format = format
        }
        let frame = { (seconds: Double) in
            Int(min(max(0, seconds * buffer.sampleRate), Double(buffer.frameCount)).rounded())
        }
        let timeline = PlaybackTimeline(frameCount: buffer.frameCount, start: frame(start),
                                        loop: loop.map { frame($0.lowerBound)..<frame($0.upperBound) })
        try playback.schedule(buffer, timeline: timeline) { [weak self] in self?.isPlaying = false }
        isPlaying = true
    }

    /// Decodes the file off the main actor, then plays it.
    public func play(contentsOf url: URL, loop: Range<Double>? = nil) async throws {
        playbackRequestGeneration &+= 1
        let generation = playbackRequestGeneration
        let buffer = try await Task.detached { try AudioFileIO.load(url) }.value
        try Task.checkCancellation()
        guard generation == playbackRequestGeneration else { throw CancellationError() }
        try play(buffer, loop: loop)
    }

    public func stopPlayback() {
        playbackRequestGeneration &+= 1
        playback.stop()
        isPlaying = false
    }

    /// Seconds into the playing buffer; poll at display rate. Nil when idle.
    public var playhead: Double? { playback.playhead }

    // MARK: Hosting

    /// Mixes `source` into the master output. Re-prepared whenever the output rate changes.
    public func attach(_ source: any AudioRenderSource) {
        let key = ObjectIdentifier(source)
        guard hosted[key] == nil else { return }
        let rate = outputFormat?.sampleRate ?? DigitoneAudioModule.preferredSampleRate
        hosted[key] = HostedSource(source: source, node: makeSourceNode(source, sampleRate: rate), sampleRate: rate)
        attachedSourceCount = hosted.count
    }

    public func detach(_ source: any AudioRenderSource) {
        guard let entry = hosted.removeValue(forKey: ObjectIdentifier(source)) else { return }
        engine.disconnectNodeOutput(entry.node)
        engine.detach(entry.node)
        attachedSourceCount = hosted.count
    }

    // MARK: Shared internals

    func isSatisfied(enableInput: Bool) -> Bool {
        state == .running && (isInputRunning || !enableInput)
    }

    private func performStart(enableInput: Bool) async throws {
        isStarting = true
        defer { isStarting = false }
        let generation = lifecycleGeneration
        if enableInput {
            if options.requiresUsageDescription {
                guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
                      !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    lastError = .permissionConfigurationMissing
                    throw AudioEngineError.permissionConfigurationMissing
                }
                permission = await RecordPermission.request()
            } else {
                permission = RecordPermission.current == .undetermined ? await RecordPermission.request() : RecordPermission.current
            }
            refreshMonitor()
            guard generation == lifecycleGeneration, !Task.isCancelled else { throw CancellationError() }
            guard permission == .granted else {
                lastError = .permissionDenied
                throw AudioEngineError.permissionDenied
            }
        }
        try Task.checkCancellation()
        do {
            try startPlatform(enableInput: enableInput)
            lastError = nil
        } catch {
            let wrapped = Self.wrap(error, "запуск аудио")
            lastError = wrapped
            refreshMonitor()
            throw wrapped
        }
        refreshMonitor()
    }

    private func performAutoStart() async {
        devices.refresh()
        refreshMonitor()
        guard isMonitoringInput, wantsAutomaticInput, !isSatisfied(enableInput: true) else { return }
        guard permission != .denied else { return }
        do { try await start(enableInput: true) } catch {}
    }

    /// A Digitone audio input (or a pinned input) is present.
    var wantsAutomaticInput: Bool {
        policy.pinnedInputID != nil ? resolveInput() != nil : devices.inputs.contains(where: \.isDigitone)
    }

    func resolveInput() -> AudioDevice? {
        policy.input(in: devices.devices, defaultID: devices.defaultInputID)
    }

    func resolveOutput() -> AudioDevice? {
        policy.output(in: devices.devices, defaultID: devices.defaultOutputID)
    }

    /// Recomputes the feedback guard and applies the monitor level.
    func refreshMonitor() {
        let input = isInputRunning ? inputDevice : resolveInput()
        let output = state == .running ? outputDevice : resolveOutput()
        let block = policy.monitorBlock(input: input, output: output, permission: permission)
        if block != monitorBlock { monitorBlock = block }
        applyMonitoring()
    }

    var monitorAudible: Bool { isMonitoringInput && monitorBlock == nil }

    private func select(_ device: AudioDevice?, input: Bool) throws {
        devices.refresh()
        if let device {
            guard let current = devices.device(id: device.id), input ? current.hasInput : current.hasOutput else {
                throw AudioEngineError.deviceMissing(device.name)
            }
        }
        if input {
            policy.pinnedInputID = device?.id
            pinnedInputName = device?.name
        } else {
            policy.pinnedOutputID = device?.id
            pinnedOutputName = device?.name
        }
        try reroute(input: input)
        refreshMonitor()
    }

    func finishRecording() {
        guard pipeline.recorder.isRecording else { return }
        do {
            if let recording = try pipeline.stopRecording() { lastRecording = recording }
        } catch {
            if let recording = pipeline.recorder.lastFinishedRecording { lastRecording = recording }
            lastError = Self.wrap(error, "запись")
        }
        isRecording = false
    }

    /// Closes a take that cannot continue in a new input format.
    func checkRecordingFormat(_ format: StreamFormat) {
        if let recordingRate = pipeline.recorder.activeSampleRate,
           recordingRate != format.sampleRate || pipeline.recorder.activeChannelCount != min(format.channelCount, 2) {
            finishRecording()
            lastError = .formatUnsupported("частота входа изменилась во время записи")
        }
    }

    /// Output side shared by both platforms: master mixer, player and hosted sources at the hardware rate.
    func buildOutputGraph() throws {
        let hardwareOut = engine.outputNode.outputFormat(forBus: 0)
        guard hardwareOut.sampleRate.isFinite, hardwareOut.sampleRate > 0, hardwareOut.channelCount > 0 else {
            throw AudioEngineError.noOutputDevice
        }
        let rate = hardwareOut.sampleRate
        outputFormat = StreamFormat(sampleRate: rate, channelCount: Int(hardwareOut.channelCount))
        let mixer = engine.mainMixerNode
        mixer.outputVolume = min(max(masterGain, 0), 1)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        if playback.format == nil { playback.format = Self.stereo(rate) }
        engine.connect(playback.node, to: mixer, format: playback.format)
        for (key, entry) in hosted where entry.sampleRate != rate {
            engine.disconnectNodeOutput(entry.node)
            engine.detach(entry.node)
            hosted[key] = HostedSource(source: entry.source, node: makeSourceNode(entry.source, sampleRate: rate), sampleRate: rate)
        }
    }

    private func makeSourceNode(_ source: any AudioRenderSource, sampleRate: Double) -> AVAudioSourceNode {
        let format = Self.stereo(sampleRate)
        source.prepare(sampleRate: sampleRate, maximumFrames: RenderSourceHost.maximumFrames)
        let node = RenderSourceHost.makeNode(for: source, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        return node
    }

    /// Several overloads within 10 s: double that device's IO buffer (up to 1024).
    func noteOverload(input: Bool) {
        overloadCount += 1
        let now = ProcessInfo.processInfo.systemUptime
        overloadTimes = overloadTimes.filter { now - $0 < 10 } + [now]
        guard overloadTimes.count >= 3 else { return }
        overloadTimes.removeAll()
        enlargeBuffer(input: input)
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        tokens.append(NotificationToken(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        }))
        #if os(iOS)
        tokens.append(NotificationToken(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.handleInterruption(type, shouldResume: options.contains(.shouldResume)) }
        }))
        #endif
    }

    // MARK: Helpers

    static func stereo(_ sampleRate: Double) -> AVAudioFormat {
        // Rates originate from a validated hardware format or the 48 kHz default.
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    static func wrap(_ error: Error, _ operation: String) -> AudioEngineError {
        if let error = error as? AudioEngineError { return error }
        return .system(operation, Int32(truncatingIfNeeded: (error as NSError).code))
    }
}

/// Removes a block-based notification observer when released.
final class NotificationToken {
    private let observer: NSObjectProtocol
    init(_ observer: NSObjectProtocol) { self.observer = observer }
    deinit { NotificationCenter.default.removeObserver(observer) }
}
