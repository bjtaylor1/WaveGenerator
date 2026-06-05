import Synchronization

final class WaveRecordingBuffer {
    let sampleRate: Double
    let channelCount: Int

    private let capacityFrames: Int
    private let buffer: UnsafeMutableBufferPointer<Float>
    private let writeFrameCount = Atomic<Int64>(0)

    init(sampleRate: Double, channelCount: Int, durationSeconds: Double) {
        self.sampleRate = sampleRate
        self.channelCount = max(1, channelCount)
        self.capacityFrames = max(1, Int((sampleRate * durationSeconds).rounded()))
        self.buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: capacityFrames * self.channelCount)
        self.buffer.initialize(repeating: 0)
    }

    deinit {
        buffer.deinitialize()
        buffer.deallocate()
    }

    func append(_ sample: Float) {
        let write = writeFrameCount.load(ordering: .relaxed)
        let frameIndex = Int(write % Int64(capacityFrames))
        let offset = frameIndex * channelCount
        for channel in 0..<channelCount {
            buffer[offset + channel] = sample
        }
        writeFrameCount.store(write + 1, ordering: .releasing)
    }

    func append(left: Float, right: Float) {
        let write = writeFrameCount.load(ordering: .relaxed)
        let frameIndex = Int(write % Int64(capacityFrames))
        let offset = frameIndex * channelCount

        if channelCount == 1 {
            buffer[offset] = (left + right) * 0.5
        } else {
            buffer[offset] = left
            buffer[offset + 1] = right
            if channelCount > 2 {
                for channel in 2..<channelCount {
                    buffer[offset + channel] = right
                }
            }
        }

        writeFrameCount.store(write + 1, ordering: .releasing)
    }

    func snapshot() -> WaveRecordingSnapshot {
        let end = writeFrameCount.load(ordering: .acquiring)
        let frameCount = min(Int(end), capacityFrames)
        let start = end - Int64(frameCount)
        var samples = [Float](repeating: 0, count: frameCount * channelCount)

        for frameOffset in 0..<frameCount {
            let sourceFrame = Int((start + Int64(frameOffset)) % Int64(capacityFrames))
            let sourceOffset = sourceFrame * channelCount
            let destinationOffset = frameOffset * channelCount
            for channel in 0..<channelCount {
                samples[destinationOffset + channel] = buffer[sourceOffset + channel]
            }
        }

        return WaveRecordingSnapshot(
            samples: samples,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }
}
