#if os(macOS)
import AudioToolbox
import AVFoundation
import CoreAudio

/// Input-only AUHAL on one device (the Digitone), independent of the
/// AVAudioEngine that plays to the speakers.
///
/// AVAudioEngine drives input and output through a single AUHAL on macOS:
/// selecting the Digitone for its input also moves its output to the Digitone.
/// A dedicated input unit lets the output follow the system default device.
/// The callback renders into preallocated buffers and hands them to the
/// monitor ring, the level tap and the capture queue without locks or allocation.
final class HALInput: @unchecked Sendable {
    struct Configuration: Equatable {
        var deviceID: AudioDeviceID
        var channelCount: Int
        var sampleRate: Double
    }

    let configuration: Configuration
    let clock = ClockProbe()
    private var unit: AudioUnit?
    private let context: Context
    private var running = false

    /// Everything the IO thread touches, allocated up front.
    final class Context {
        static let maximumFrames = 8_192
        var unit: AudioUnit?
        let channelCount: Int
        let bufferList: UnsafeMutableAudioBufferListPointer
        let channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
        let ring: MonitorRing
        let levels: LevelTap
        let capture: InputCaptureQueue?
        let clock: ClockProbe
        let errors = AtomicCells(count: 1)

        init(channelCount: Int, ring: MonitorRing, levels: LevelTap, capture: InputCaptureQueue?, clock: ClockProbe) {
            self.channelCount = channelCount
            self.ring = ring
            self.levels = levels
            self.capture = capture
            self.clock = clock
            bufferList = AudioBufferList.allocate(maximumBuffers: channelCount)
            channels = .allocate(capacity: channelCount)
            for channel in 0..<channelCount {
                let samples = UnsafeMutablePointer<Float>.allocate(capacity: Self.maximumFrames)
                samples.initialize(repeating: 0, count: Self.maximumFrames)
                (channels + channel).initialize(to: samples)
            }
        }

        deinit {
            for channel in 0..<channelCount { channels[channel].deallocate() }
            channels.deallocate()
            bufferList.unsafeMutablePointer.deallocate()
        }

        @inline(__always)
        func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ timeStamp: UnsafePointer<AudioTimeStamp>,
                    _ bus: UInt32, _ frameCount: UInt32) -> OSStatus {
            guard let unit else { return noErr }
            let frames = Int(frameCount)
            guard frames > 0, frames <= Self.maximumFrames else { errors.add(0, 1); return noErr }
            for channel in 0..<channelCount {
                bufferList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frameCount * 4, mData: channels[channel])
            }
            let status = AudioUnitRender(unit, flags, timeStamp, bus, frameCount, bufferList.unsafeMutablePointer)
            guard status == noErr else { errors.add(0, 1); return status }
            clock.record(timeStamp, frames: frames)
            let left = UnsafePointer(channels[0])
            let right = channelCount > 1 ? UnsafePointer(channels[1]) : nil
            ring.write(left: left, right: right, frames: frames)
            levels.accumulate(left: left, right: right, frames: frames)
            capture?.enqueue(UnsafePointer(channels), channelCount: channelCount, frames: frames)
            return noErr
        }
    }

    init(_ configuration: Configuration, ring: MonitorRing, levels: LevelTap, capture: InputCaptureQueue?) throws {
        self.configuration = configuration
        context = Context(channelCount: min(max(configuration.channelCount, 1), 2), ring: ring, levels: levels,
                          capture: capture, clock: clock)
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioEngineError.system("AUHAL не найден", -1)
        }
        var instance: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &instance), "создание аудиовхода")
        guard let instance else { throw AudioEngineError.system("создание аудиовхода", -1) }
        unit = instance
        do {
            var on: UInt32 = 1, off: UInt32 = 0
            try Self.check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4), "включение входа")
            try Self.check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4), "отключение выхода")
            var device = configuration.deviceID
            try Self.check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                &device, UInt32(MemoryLayout<AudioDeviceID>.size)), "выбор аудиовхода")
            // Client side of the input bus: Float32, non-interleaved, the device rate.
            var format = AudioStreamBasicDescription(
                mSampleRate: configuration.sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: UInt32(context.channelCount), mBitsPerChannel: 32, mReserved: 0)
            try Self.check(AudioUnitSetProperty(instance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                                &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "формат входа")
            var maximum = UInt32(Context.maximumFrames)
            _ = AudioUnitSetProperty(instance, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximum, 4)
            var callback = AURenderCallbackStruct(inputProc: Self.inputProc,
                                                  inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
            try Self.check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "обработчик входа")
            try Self.check(AudioUnitInitialize(instance), "инициализация входа")
            context.unit = instance
        } catch {
            AudioComponentInstanceDispose(instance)
            unit = nil
            throw error
        }
    }

    deinit { dispose() }

    func start() throws {
        guard let unit, !running else { return }
        try Self.check(AudioOutputUnitStart(unit), "старт аудиовхода")
        running = true
    }

    /// Stops and releases the unit; after this returns the callback no longer runs.
    func dispose() {
        guard let unit else { return }
        if running { AudioOutputUnitStop(unit) }
        running = false
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
    }

    var renderErrors: Int64 { context.errors.load(0) }

    private static let inputProc: AURenderCallback = { refCon, flags, timeStamp, bus, frames, _ in
        Unmanaged<Context>.fromOpaque(refCon)._withUnsafeGuaranteedRef { $0.render(flags, timeStamp, bus, frames) }
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw AudioEngineError.system(operation, status) }
    }
}
#endif
