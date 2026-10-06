import AVFoundation
import DigitoneDSP

/// Wraps an `AudioRenderSource` in an AVAudioSourceNode.
enum RenderSourceHost {
    /// Largest block handed to a source in one `render` call.
    static let maximumFrames = 4_096

    /// Built outside any actor so the render block carries no isolation.
    nonisolated static func makeNode(for source: any AudioRenderSource, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            render(source, frameCount: Int(frameCount), into: bufferList)
            return noErr
        }
    }

    /// Clears the output, then lets the source mix into it in blocks of at most `maximumFrames`.
    nonisolated static func render(_ source: any AudioRenderSource, frameCount: Int, into bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard frameCount > 0, buffers.count >= 2,
              buffers[0].mNumberChannels == 1, buffers[1].mNumberChannels == 1,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        let available = Int(min(buffers[0].mDataByteSize, buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
        let total = min(frameCount, available)
        var offset = 0
        while offset < total {
            let run = min(maximumFrames, total - offset)
            source.render(frameCount: run, left: left + offset, right: right + offset)
            offset += run
        }
    }
}
