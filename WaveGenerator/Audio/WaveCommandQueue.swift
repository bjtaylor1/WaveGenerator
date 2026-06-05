import Synchronization

final class WaveCommandQueue {
    private let capacity: Int
    private let mask: Int
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private let buffer: UnsafeMutableBufferPointer<WaveCommand>

    init(capacityPowerOfTwo: Int = 1024) {
        precondition(capacityPowerOfTwo > 1 && (capacityPowerOfTwo & (capacityPowerOfTwo - 1)) == 0)
        self.capacity = capacityPowerOfTwo
        self.mask = capacityPowerOfTwo - 1
        self.buffer = UnsafeMutableBufferPointer<WaveCommand>.allocate(capacity: capacityPowerOfTwo)
        self.buffer.initialize(
            repeating: WaveCommand(
                kind: WaveCommandKind.setMasterGain.rawValue,
                channelIndex: 0,
                componentIndex: 0,
                value: 0,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: 0
            )
        )
    }

    deinit {
        buffer.deinitialize()
        buffer.deallocate()
    }

    @discardableResult
    func enqueue(_ command: WaveCommand) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        if write - read >= capacity {
            return false
        }

        buffer[write & mask] = command
        writeIndex.store(write + 1, ordering: .releasing)
        return true
    }

    func isFull() -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        return write - read >= capacity
    }

    func dequeue() -> WaveCommand? {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read < write else {
            return nil
        }

        let command = buffer[read & mask]
        readIndex.store(read + 1, ordering: .releasing)
        return command
    }
}
