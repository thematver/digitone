import AVFoundation
import DigitoneDSP

/// Decoding, encoding and sample-rate conversion of `SampleBuffer`s.
public enum AudioFileIO {
    public enum Encoding: Sendable, Equatable {
        case int16, int24, float32

        var bitDepth: Int {
            switch self {
            case .int16: 16
            case .int24: 24
            case .float32: 32
            }
        }
    }

    /// Loads any file AVAudioFile can read (wav, aiff, caf, m4a, mp3) as Float32
    /// non-interleaved, optionally resampled.
    public static func load(_ url: URL, resampleTo targetRate: Double? = nil) throws -> SampleBuffer {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch { throw AudioEngineError.fileRead(url.lastPathComponent) }
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw AudioEngineError.formatUnsupported(url.lastPathComponent)
        }
        guard file.length <= 50_000_000 / Int64(channelCount) else {
            throw AudioEngineError.formatUnsupported("слишком большой файл для загрузки в память")
        }
        let chunk: AVAudioFrameCount = 65_536
        guard let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw AudioEngineError.formatUnsupported(url.lastPathComponent)
        }
        var channels = [[Float]](repeating: [], count: channelCount)
        let expected = Int(max(0, file.length))
        for index in channels.indices { channels[index].reserveCapacity(expected) }
        // AVAudioFile throws on a read made after the final frame; reaching
        // the declared length is normal completion, not a read failure.
        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let requested = AVAudioFrameCount(min(Int64(chunk), remaining))
            do { try file.read(into: scratch, frameCount: requested) } catch {
                throw AudioEngineError.fileRead(url.lastPathComponent)
            }
            guard scratch.frameLength > 0 else { throw AudioEngineError.fileRead(url.lastPathComponent) }
            guard channels[0].count + Int(scratch.frameLength) <= 50_000_000 / channelCount else {
                throw AudioEngineError.formatUnsupported("слишком большой файл для загрузки в память")
            }
            append(scratch, to: &channels)
        }
        let buffer = SampleBuffer(sampleRate: format.sampleRate, channels: channels)
        guard let targetRate, targetRate != buffer.sampleRate else { return buffer }
        return try resample(buffer, to: targetRate)
    }

    /// Writes PCM; the container follows the extension (`.wav`, `.caf`, `.aif`).
    public static func write(_ buffer: SampleBuffer, to url: URL, encoding: Encoding = .int24) throws {
        guard buffer.sampleRate.isFinite, buffer.sampleRate > 0,
              buffer.frameCount <= Int(UInt32.max) else { throw AudioEngineError.formatUnsupported(url.lastPathComponent) }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: fileSettings(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount, encoding: encoding),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch { throw AudioEngineError.fileWrite(url.lastPathComponent) }
        guard buffer.frameCount > 0 else { return }
        guard let pcm = makePCMBuffer(buffer) else { throw AudioEngineError.formatUnsupported(url.lastPathComponent) }
        do { try file.write(from: pcm) } catch { throw AudioEngineError.fileWrite(url.lastPathComponent) }
    }

    public static func resample(_ buffer: SampleBuffer, to targetRate: Double) throws -> SampleBuffer {
        guard targetRate.isFinite, targetRate > 0,
              buffer.sampleRate.isFinite, buffer.sampleRate > 0 else {
            throw AudioEngineError.formatUnsupported("частота \(targetRate)")
        }
        guard targetRate != buffer.sampleRate, buffer.frameCount > 0 else {
            return SampleBuffer(sampleRate: targetRate, channels: buffer.channels)
        }
        guard let input = makePCMBuffer(buffer),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: AVAudioChannelCount(buffer.channelCount)),
              let converter = AVAudioConverter(from: input.format, to: outputFormat) else {
            throw AudioEngineError.formatUnsupported("\(Int(buffer.sampleRate)) → \(Int(targetRate)) Гц")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let expectedFrames = (Double(buffer.frameCount) * targetRate / buffer.sampleRate).rounded()
        guard expectedFrames.isFinite, expectedFrames <= Double(50_000_000 / buffer.channelCount) else {
            throw AudioEngineError.formatUnsupported("слишком большой буфер для преобразования")
        }
        let expected = Int(expectedFrames)
        let chunk = AVAudioFrameCount(max(4_096, min(expected + 1_024, 262_144)))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunk) else {
            throw AudioEngineError.formatUnsupported("\(Int(targetRate)) Гц")
        }
        let feed = ConverterFeed(input)
        var channels = [[Float]](repeating: [], count: buffer.channelCount)
        for index in channels.indices { channels[index].reserveCapacity(expected) }
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                feed.next(inputStatus)
            }
            if status == .error {
                throw AudioEngineError.formatUnsupported(conversionError?.localizedDescription ?? "ошибка конвертера")
            }
            append(output, to: &channels)
            if status == .endOfStream || (status == .inputRanDry && output.frameLength == 0) { break }
        }
        return SampleBuffer(sampleRate: targetRate, channels: channels)
    }

    // MARK: - AVAudioPCMBuffer bridging

    static func makePCMBuffer(_ buffer: SampleBuffer) -> AVAudioPCMBuffer? {
        guard buffer.sampleRate.isFinite, buffer.sampleRate > 0, buffer.frameCount <= Int(UInt32.max),
              let format = AVAudioFormat(standardFormatWithSampleRate: buffer.sampleRate, channels: AVAudioChannelCount(buffer.channelCount)),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(buffer.frameCount, 1))),
              let data = pcm.floatChannelData else { return nil }
        for (index, channel) in buffer.channels.enumerated() {
            channel.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                data[index].update(from: base, count: source.count)
            }
        }
        pcm.frameLength = AVAudioFrameCount(buffer.frameCount)
        return pcm
    }

    /// Copies a frame range of `buffer` into a new PCM buffer (used for loop regions).
    static func makePCMBuffer(_ buffer: SampleBuffer, frames: Range<Int>) -> AVAudioPCMBuffer? {
        let range = frames.clamped(to: 0..<buffer.frameCount)
        guard !range.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: buffer.sampleRate, channels: AVAudioChannelCount(buffer.channelCount)),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(range.count)),
              let data = pcm.floatChannelData else { return nil }
        for (index, channel) in buffer.channels.enumerated() {
            channel.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                data[index].update(from: base + range.lowerBound, count: range.count)
            }
        }
        pcm.frameLength = AVAudioFrameCount(range.count)
        return pcm
    }

    static func fileSettings(sampleRate: Double, channelCount: Int, encoding: Encoding) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: encoding.bitDepth,
            AVLinearPCMIsFloatKey: encoding == .float32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func append(_ pcm: AVAudioPCMBuffer, to channels: inout [[Float]]) {
        guard let data = pcm.floatChannelData else { return }
        let frames = Int(pcm.frameLength)
        for index in channels.indices where index < Int(pcm.format.channelCount) {
            channels[index].append(contentsOf: UnsafeBufferPointer(start: data[index], count: frames))
        }
    }
}

/// Hands the whole input to AVAudioConverter once, then reports end of stream.
private final class ConverterFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let pending = buffer else {
            status.pointee = .endOfStream
            return nil
        }
        buffer = nil
        status.pointee = .haveData
        return pending
    }
}
