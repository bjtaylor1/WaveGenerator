import AVFoundation
import Foundation
import Synchronization

enum WaveAudioEngineError: Error, LocalizedError {
    case audioSessionSetup(step: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .audioSessionSetup(step, underlying):
            return "Audio session failed at \(step): \(underlying.localizedDescription)"
        }
    }
}

private enum WaveCommandKind: Int32 {
    case setComponentFrequency = 0
    case setComponentWetness = 1
    case setMasterGain = 2
    case applyParameters = 3
    case addPulse = 4
    case removePulse = 5
}

private struct WaveCommand {
    var kind: Int32
    var componentIndex: Int32
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
                componentIndex: 0,
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
    private static let carrierComponentIndex = 0

    private let engine = AVAudioEngine()
    private let commandQueue = WaveCommandQueue()

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false

    private enum ComponentMode {
        case bipolarSine
        case unipolarPulse
    }

    private final class ComponentState {
        let mode: ComponentMode
        let minimumFrequency: Double
        var phase: Double = 0

        let frequency: RampedParameter
        let wetness: RampedParameter
        let volume: RampedParameter
        var pendingRemovalFrame: Int64?

        init(
            mode: ComponentMode,
            minimumFrequency: Double,
            initialFrequency: Double,
            initialWetness: Double,
            initialVolume: Double
        ) {
            self.mode = mode
            self.minimumFrequency = minimumFrequency
            self.frequency = RampedParameter(initialValue: initialFrequency)
            self.wetness = RampedParameter(initialValue: initialWetness)
            self.volume = RampedParameter(initialValue: initialVolume)
        }

        func amplitude(at frame: Int64, sampleRate: Double) -> Double {
            let hz = max(minimumFrequency, frequency.value(at: frame))
            phase += 2 * .pi * hz / sampleRate
            if phase >= 2 * .pi {
                phase.formTruncatingRemainder(dividingBy: 2 * .pi)
            }

            switch mode {
            case .bipolarSine:
                return sin(phase)
            case .unipolarPulse:
                let wetnessValue = min(1, max(0, wetness.value(at: frame)))
                let volumeValue = min(1, max(0, volume.value(at: frame)))
                let pulse = (sin(phase) + 1) * 0.5
                let envelope = wetnessValue + (1 - wetnessValue) * pulse
                return 1 + volumeValue * (envelope - 1)
            }
        }
    }

    private final class RenderState {
        let sampleRate: Double
        var framePosition: Int64 = 0
        var components: [ComponentState]

        let masterGain = RampedParameter(initialValue: 0)

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
            self.components = [
                ComponentState(
                    mode: .bipolarSine,
                    minimumFrequency: 200,
                    initialFrequency: 500,
                    initialWetness: 0,
                    initialVolume: 1
                ),
                ComponentState(
                    mode: .unipolarPulse,
                    minimumFrequency: 0.01,
                    initialFrequency: 1,
                    initialWetness: 0,
                    initialVolume: 1
                ),
            ]
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
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            throw WaveAudioEngineError.audioSessionSetup(step: "setCategory(.playback)", underlying: error)
        }

        do {
            try session.setActive(true, options: [])
        } catch {
            throw WaveAudioEngineError.audioSessionSetup(step: "setActive(true)", underlying: error)
        }

        let preferredSampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let renderFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: preferredSampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw WaveAudioEngineError.audioSessionSetup(
                step: "createRenderFormat",
                underlying: NSError(domain: "WaveAudioEngine", code: -1)
            )
        }

        let state = RenderState(sampleRate: renderFormat.sampleRate)
        self.renderState = state

        let source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self, let state = self.renderState else { return noErr }

            self.drainCommands(into: state)

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            for frameOffset in 0..<frames {
                let currentFrame = state.framePosition + Int64(frameOffset)
                let gain = min(1, max(0, state.masterGain.value(at: currentFrame)))
                let mixedAmplitude = state.components.reduce(1.0) { partial, component in
                    partial * component.amplitude(at: currentFrame, sampleRate: state.sampleRate)
                }
                let sample = Float(gain * mixedAmplitude)

                for buffer in bufferList {
                    guard let mData = buffer.mData else { continue }
                    let channel = mData.assumingMemoryBound(to: Float.self)
                    channel[frameOffset] = sample
                }
            }

            state.framePosition += Int64(frames)
            self.removeExpiredComponents(from: state)
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: renderFormat)
        sourceNode = source

        try engine.start()
        isConfigured = true
    }

    @discardableResult
    func startTone(rampSeconds: Double = 1.0) -> Bool {
        enqueueMasterGain(value: 1.0, durationSeconds: rampSeconds)
    }

    @discardableResult
    func stopTone(rampSeconds: Double = 1.0) -> Bool {
        enqueueMasterGain(value: 0.0, durationSeconds: rampSeconds)
    }

    @discardableResult
    func setCarrierHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueFrequency(
            componentIndex: Self.carrierComponentIndex,
            value: max(200, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func setPulseHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueFrequency(
            componentIndex: 1,
            value: max(0.01, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func setWetness(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueWetness(
            componentIndex: 1,
            value: min(1, max(0, value)),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func applyParameters(
        carrierHz: Double,
        pulseHz: Double,
        wetness: Double,
        pulseVolume: Double = 1,
        durationSeconds: Double = 2.0
    ) -> Bool {
        applyCarrierHz(carrierHz, durationSeconds: durationSeconds)
            && applyPulse(
                at: 0,
                frequency: pulseHz,
                wetness: wetness,
                volume: pulseVolume,
                durationSeconds: durationSeconds
            )
    }

    @discardableResult
    func applyCarrierHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueFrequency(
            componentIndex: Self.carrierComponentIndex,
            value: max(200, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func applyPulse(
        at pulseIndex: Int,
        frequency: Double,
        wetness: Double,
        volume: Double,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.applyParameters.rawValue,
                componentIndex: Int32(pulseIndex + 1),
                value: max(0.01, frequency),
                value2: min(1, max(0, wetness)),
                value3: min(1, max(0, volume)),
                durationSeconds: durationSeconds
            )
        )
    }

    @discardableResult
    func addPulse(
        frequency: Double,
        wetness: Double,
        targetVolume: Double,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.addPulse.rawValue,
                componentIndex: 0,
                value: max(0.01, frequency),
                value2: min(1, max(0, wetness)),
                value3: min(1, max(0, targetVolume)),
                durationSeconds: durationSeconds
            )
        )
    }

    @discardableResult
    func removePulse(at pulseIndex: Int, durationSeconds: Double = 2.0) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.removePulse.rawValue,
                componentIndex: Int32(pulseIndex + 1),
                value: 0,
                value2: 0,
                value3: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    func isCommandQueueFull() -> Bool {
        commandQueue.isFull()
    }

    private func enqueueFrequency(componentIndex: Int, value: Double, durationSeconds: Double) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setComponentFrequency.rawValue,
                componentIndex: Int32(componentIndex),
                value: value,
                value2: 0,
                value3: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    private func enqueueWetness(componentIndex: Int, value: Double, durationSeconds: Double) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setComponentWetness.rawValue,
                componentIndex: Int32(componentIndex),
                value: value,
                value2: 0,
                value3: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    private func enqueueMasterGain(value: Double, durationSeconds: Double) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setMasterGain.rawValue,
                componentIndex: 0,
                value: value,
                value2: 0,
                value3: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    private func drainCommands(into state: RenderState) {
        let now = state.framePosition

        while let command = commandQueue.dequeue() {
            guard let kind = WaveCommandKind(rawValue: command.kind) else {
                continue
            }

            switch kind {
            case .setComponentFrequency:
                guard let component = state.components[safe: Int(command.componentIndex)] else {
                    continue
                }
                component.frequency.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setComponentWetness:
                guard let component = state.components[safe: Int(command.componentIndex)] else {
                    continue
                }
                component.wetness.scheduleTransition(
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
                guard let component = state.components[safe: Int(command.componentIndex)] else {
                    continue
                }
                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                switch component.mode {
                case .bipolarSine:
                    component.frequency.scheduleTransition(
                        frame: now,
                        targetValue: max(200, command.value),
                        durationFrames: durationFrames
                    )
                case .unipolarPulse:
                    component.frequency.scheduleTransition(
                        frame: now,
                        targetValue: command.value,
                        durationFrames: durationFrames
                    )
                    component.wetness.scheduleTransition(
                        frame: now,
                        targetValue: command.value2,
                        durationFrames: durationFrames
                    )
                    component.volume.scheduleTransition(
                        frame: now,
                        targetValue: command.value3,
                        durationFrames: durationFrames
                    )
                }
            case .addPulse:
                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                let pulse = ComponentState(
                    mode: .unipolarPulse,
                    minimumFrequency: 0.01,
                    initialFrequency: command.value,
                    initialWetness: command.value2,
                    initialVolume: 0
                )
                pulse.volume.scheduleTransition(
                    frame: now,
                    targetValue: command.value3,
                    durationFrames: durationFrames
                )
                state.components.append(pulse)
            case .removePulse:
                guard Int(command.componentIndex) > Self.carrierComponentIndex,
                      let component = state.components[safe: Int(command.componentIndex)] else {
                    continue
                }

                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                if durationFrames == 0 {
                    state.components.remove(at: Int(command.componentIndex))
                } else {
                    component.volume.scheduleTransition(
                        frame: now,
                        targetValue: 0,
                        durationFrames: durationFrames
                    )
                    component.pendingRemovalFrame = now + durationFrames
                }
            }
        }
    }

    private func removeExpiredComponents(from state: RenderState) {
        let now = state.framePosition
        state.components.removeAll { component in
            guard component.mode == .unipolarPulse,
                  let pendingRemovalFrame = component.pendingRemovalFrame else {
                return false
            }

            return now >= pendingRemovalFrame
        }
    }

    private func durationToFrames(_ seconds: Double, sampleRate: Double) -> Int64 {
        Int64(max(0, (seconds * sampleRate).rounded()))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
