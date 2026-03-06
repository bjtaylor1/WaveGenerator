import AVFoundation
import Foundation
import Synchronization

private enum WaveCommandKind: Int32 {
    case setCarrierHz = 0
    case setPulseHz = 1
    case setWetness = 2
    case setMasterGain = 3
    case applyParameters = 4
}

private struct WaveCommand {
    var kind: Int32
    var value: Double
    var value2: Double
    var value3: Double
    var durationSeconds: Double
}

private final class WaveCommandQueue {
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
                value: 0,
                value2: 0,
                value3: 0,
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

final class WaveAudioEngine {
    private static let minCarrierHz: Double = 200

    private let engine = AVAudioEngine()
    private let commandQueue = WaveCommandQueue()

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false

    private final class RenderState {
        let sampleRate: Double
        var framePosition: Int64 = 0
        var carrierPhase: Double = 0
        var pulsePhase: Double = 0

        let carrierHz = RampedParameter(initialValue: 256)
        let pulseHz = RampedParameter(initialValue: 1)
        let wetness = RampedParameter(initialValue: 0)
        let masterGain = RampedParameter(initialValue: 0)

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
        }
    }

    private var renderState: RenderState?

    func startEngineIfNeeded() throws {
        guard !isConfigured else {
            if !engine.isRunning {
                try engine.start()
            }
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.allowBluetoothA2DP, .allowBluetooth])
        try session.setActive(true)

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let state = RenderState(sampleRate: outputFormat.sampleRate)
        self.renderState = state

        let source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self, let state = self.renderState else { return noErr }

            self.drainCommands(into: state)

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            for frameOffset in 0..<frames {
                let currentFrame = state.framePosition + Int64(frameOffset)

                let carrierHz = max(Self.minCarrierHz, state.carrierHz.value(at: currentFrame))
                let pulseHz = max(0, state.pulseHz.value(at: currentFrame))
                let wetness = min(1, max(0, state.wetness.value(at: currentFrame)))
                let gain = min(1, max(0, state.masterGain.value(at: currentFrame)))

                state.carrierPhase += 2 * .pi * carrierHz / state.sampleRate
                state.pulsePhase += 2 * .pi * pulseHz / state.sampleRate

                if state.carrierPhase >= 2 * .pi { state.carrierPhase.formTruncatingRemainder(dividingBy: 2 * .pi) }
                if state.pulsePhase >= 2 * .pi { state.pulsePhase.formTruncatingRemainder(dividingBy: 2 * .pi) }

                let pulse = (sin(state.pulsePhase) + 1) * 0.5
                let envelope = wetness + (1 - wetness) * pulse
                let sample = Float(gain * envelope * sin(state.carrierPhase))

                for buffer in bufferList {
                    guard let mData = buffer.mData else { continue }
                    let channel = mData.assumingMemoryBound(to: Float.self)
                    channel[frameOffset] = sample
                }
            }

            state.framePosition += Int64(frames)
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: outputFormat)
        sourceNode = source

        try engine.start()
        isConfigured = true
    }

    @discardableResult
    func startTone(rampSeconds: Double = 1.0) -> Bool {
        enqueue(kind: .setMasterGain, value: 0.25, durationSeconds: rampSeconds)
    }

    @discardableResult
    func stopTone(rampSeconds: Double = 1.0) -> Bool {
        enqueue(kind: .setMasterGain, value: 0.0, durationSeconds: rampSeconds)
    }

    @discardableResult
    func setCarrierHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueue(kind: .setCarrierHz, value: max(Self.minCarrierHz, value), durationSeconds: durationSeconds)
    }

    @discardableResult
    func setPulseHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueue(kind: .setPulseHz, value: max(0, value), durationSeconds: durationSeconds)
    }

    @discardableResult
    func setWetness(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueue(kind: .setWetness, value: min(1, max(0, value)), durationSeconds: durationSeconds)
    }

    @discardableResult
    func applyParameters(
        carrierHz: Double,
        pulseHz: Double,
        wetness: Double,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.applyParameters.rawValue,
                value: max(Self.minCarrierHz, carrierHz),
                value2: max(0, pulseHz),
                value3: min(1, max(0, wetness)),
                durationSeconds: durationSeconds
            )
        )
    }

    func isCommandQueueFull() -> Bool {
        commandQueue.isFull()
    }

    private func enqueue(kind: WaveCommandKind, value: Double, durationSeconds: Double) -> Bool {
        commandQueue.enqueue(
            WaveCommand(kind: kind.rawValue, value: value, value2: 0, value3: 0, durationSeconds: durationSeconds)
        )
    }

    private func drainCommands(into state: RenderState) {
        let now = state.framePosition

        while let command = commandQueue.dequeue() {
            guard let kind = WaveCommandKind(rawValue: command.kind) else {
                continue
            }

            switch kind {
            case .setCarrierHz:
                state.carrierHz.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setPulseHz:
                state.pulseHz.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setWetness:
                state.wetness.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setMasterGain:
                state.masterGain.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .applyParameters:
                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                state.carrierHz.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationFrames
                )
                state.pulseHz.scheduleTransition(
                    frame: now,
                    targetValue: command.value2,
                    durationFrames: durationFrames
                )
                state.wetness.scheduleTransition(
                    frame: now,
                    targetValue: command.value3,
                    durationFrames: durationFrames
                )
            }
        }
    }

    private func durationToFrames(_ seconds: Double, sampleRate: Double) -> Int64 {
        Int64(max(1, (seconds * sampleRate).rounded()))
    }
}
