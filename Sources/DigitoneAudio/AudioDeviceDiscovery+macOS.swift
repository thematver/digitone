#if os(macOS)
import CoreAudio
import Foundation

extension AudioDeviceDiscovery {
    struct Snapshot {
        var devices: [AudioDevice]
        var defaultInputID: String?
        var defaultOutputID: String?
    }

    static func snapshot() -> Snapshot {
        let devices = deviceIDs().compactMap(device)
        return Snapshot(
            devices: devices,
            defaultInputID: defaultDevice(kAudioHardwarePropertyDefaultInputDevice).flatMap(uid),
            defaultOutputID: defaultDevice(kAudioHardwarePropertyDefaultOutputDevice).flatMap(uid)
        )
    }

    static func deviceID(forUID uid: String) -> AudioObjectID? {
        deviceIDs().first { self.uid($0) == uid }
    }

    /// Calls `onChange` on the main queue when devices or defaults change.
    /// Returns a token that removes the listeners when released.
    static func observeChanges(_ onChange: @escaping @MainActor () -> Void) -> AnyObject {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice
        ]
        for selector in selectors {
            var address = globalAddress(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        return ListenerToken(selectors: selectors, block: block)
    }

    private final class ListenerToken {
        let selectors: [AudioObjectPropertySelector]
        let block: AudioObjectPropertyListenerBlock
        init(selectors: [AudioObjectPropertySelector], block: @escaping AudioObjectPropertyListenerBlock) {
            self.selectors = selectors
            self.block = block
        }
        deinit {
            for selector in selectors {
                var address = AudioDeviceDiscovery.globalAddress(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            }
        }
    }

    // MARK: IO timing

    /// Asks for a small IO buffer, clamped to what the device allows; returns the size in effect.
    @discardableResult
    static func requestBufferFrameSize(_ frames: Int, on id: AudioObjectID) -> Int {
        var range = AudioValueRange()
        var wanted = UInt32(max(frames, 1))
        if read(id, address(kAudioDevicePropertyBufferFrameSizeRange), into: &range), range.mMaximum >= range.mMinimum {
            wanted = UInt32(min(max(Double(wanted), range.mMinimum), range.mMaximum))
        }
        var property = address(kAudioDevicePropertyBufferFrameSize)
        _ = AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wanted)
        return bufferFrameSize(id)
    }

    static func bufferFrameSize(_ id: AudioObjectID) -> Int {
        var frames: UInt32 = 0
        return read(id, address(kAudioDevicePropertyBufferFrameSize), into: &frames) ? Int(frames) : 0
    }

    /// Device, safety-offset, buffer and first-stream latency for one direction.
    static func latency(_ id: AudioObjectID, input: Bool) -> DeviceLatency {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        func value(_ selector: AudioObjectPropertySelector, _ object: AudioObjectID = id, scope: AudioObjectPropertyScope) -> Int {
            var result: UInt32 = 0
            let property = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            return read(object, property, into: &result) ? Int(result) : 0
        }
        var rate: Float64 = 0
        _ = read(id, address(kAudioDevicePropertyNominalSampleRate), into: &rate)
        var streamLatency = 0
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) {
            var ids = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(id, &streams, 0, nil, &size, &ids) == noErr, let first = ids.first {
                streamLatency = value(kAudioStreamPropertyLatency, first, scope: kAudioObjectPropertyScopeGlobal)
            }
        }
        return DeviceLatency(
            sampleRate: rate > 0 ? rate : DigitoneAudioModule.preferredSampleRate,
            deviceFrames: value(kAudioDevicePropertyLatency, scope: scope),
            safetyFrames: value(kAudioDevicePropertySafetyOffset, scope: scope),
            bufferFrames: value(kAudioDevicePropertyBufferFrameSize, scope: scope),
            streamFrames: streamLatency
        )
    }

    /// Calls `onOverload` on the main queue whenever the device reports an IO cycle overload.
    static func observeOverloads(_ id: AudioObjectID, _ onOverload: @escaping @MainActor () -> Void) -> AnyObject {
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { onOverload() } }
        var property = address(kAudioDeviceProcessorOverload)
        AudioObjectAddPropertyListenerBlock(id, &property, .main, block)
        return DeviceListenerToken(device: id, selector: kAudioDeviceProcessorOverload, block: block)
    }

    /// AUHAL input is independent of the output engine's configuration
    /// notifications, so watch changes to this device's rate and channels.
    static func observeInputFormat(_ id: AudioObjectID, _ onChange: @escaping @MainActor () -> Void) -> AnyObject {
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { onChange() } }
        let properties = [address(kAudioDevicePropertyNominalSampleRate),
                          AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                     mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)]
        for var property in properties {
            AudioObjectAddPropertyListenerBlock(id, &property, .main, block)
        }
        return InputFormatListenerToken(device: id, properties: properties, block: block)
    }

    private final class InputFormatListenerToken {
        let device: AudioObjectID
        let properties: [AudioObjectPropertyAddress]
        let block: AudioObjectPropertyListenerBlock
        init(device: AudioObjectID, properties: [AudioObjectPropertyAddress], block: @escaping AudioObjectPropertyListenerBlock) {
            self.device = device
            self.properties = properties
            self.block = block
        }
        deinit {
            for var property in properties {
                AudioObjectRemovePropertyListenerBlock(device, &property, .main, block)
            }
        }
    }

    private final class DeviceListenerToken {
        let device: AudioObjectID
        let selector: AudioObjectPropertySelector
        let block: AudioObjectPropertyListenerBlock
        init(device: AudioObjectID, selector: AudioObjectPropertySelector, block: @escaping AudioObjectPropertyListenerBlock) {
            self.device = device
            self.selector = selector
            self.block = block
        }
        deinit {
            var property = AudioDeviceDiscovery.globalAddress(selector)
            AudioObjectRemovePropertyListenerBlock(device, &property, .main, block)
        }
    }

    // MARK: HAL queries

    private static func device(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = uid(id) else { return nil }
        let inputs = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outputs = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inputs + outputs > 0 else { return nil }
        var rate: Float64 = 0
        let hasRate = read(id, address(kAudioDevicePropertyNominalSampleRate), into: &rate)
        var transport: UInt32 = 0
        _ = read(id, address(kAudioDevicePropertyTransportType), into: &transport)
        return AudioDevice(
            id: uid,
            name: string(id, kAudioObjectPropertyName) ?? uid,
            inputChannels: inputs,
            outputChannels: outputs,
            nominalSampleRate: hasRate && rate > 0 ? rate : nil,
            transport: Self.transport(transport),
            systemID: id
        )
    }

    private static func deviceIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), globalAddress(selector), into: &id),
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func uid(_ id: AudioObjectID) -> String? {
        string(id, kAudioDevicePropertyDeviceUID)
    }

    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func read<T: BitwiseCopyable>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    fileprivate static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        address(selector)
    }

    private static func transport(_ code: UInt32) -> AudioDevice.Transport {
        switch code {
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .hdmi
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        default: .other
        }
    }
}
#endif
