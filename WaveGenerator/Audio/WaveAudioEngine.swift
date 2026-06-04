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
    case setStereoEnabled = 6
    case removeAllPulses = 7
}

private struct WaveCommand {
    var kind: Int32
    var channelIndex: Int32
    var componentIndex: Int32
    var value: Double
    var value2: Double
    var value3: Double
    var value4: Double
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

private struct WaveRecordingSnapshot {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int

    var frameCount: Int {
        guard channelCount > 0 else { return 0 }
        return samples.count / channelCount
    }
}

private final class WaveRecordingBuffer {
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

final class WaveAudioEngine {
    private static let carrierComponentIndex = 0

    private let engine = AVAudioEngine()
    private let commandQueue = WaveCommandQueue()

    private var sourceNode: AVAudioSourceNode?
    private var recordingBuffer: WaveRecordingBuffer?
    private var isConfigured = false
    private var isRecordingEnabled = false
    private var isStereoOutputEnabled = false

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
        var isStereo = false
        var channels: [ChannelState]

        let masterGain = RampedParameter(initialValue: 0)

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
            self.channels = [
                ChannelState(),
                ChannelState(),
            ]
        }
    }

    private final class ChannelState {
        var components: [ComponentState]

        init() {
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
                    minimumFrequency: 0,
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
                let uiLeftSample = self.renderSample(
                    from: state.channels[0],
                    at: currentFrame,
                    sampleRate: state.sampleRate,
                    gain: gain
                )
                let uiRightSample = state.isStereo
                    ? self.renderSample(
                        from: state.channels[1],
                        at: currentFrame,
                        sampleRate: state.sampleRate,
                        gain: gain
                    )
                    : uiLeftSample
                let outputLeftSample = state.isStereo ? uiRightSample : uiLeftSample
                let outputRightSample = state.isStereo ? uiLeftSample : uiRightSample

                if state.isStereo {
                    self.recordingBuffer?.append(left: outputLeftSample, right: outputRightSample)
                } else {
                    self.recordingBuffer?.append(outputLeftSample)
                }

                for (channelIndex, buffer) in bufferList.enumerated() {
                    guard let mData = buffer.mData else { continue }
                    let channel = mData.assumingMemoryBound(to: Float.self)
                    channel[frameOffset] = channelIndex == 0 ? outputLeftSample : outputRightSample
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
            channelIndex: 0,
            componentIndex: Self.carrierComponentIndex,
            value: max(200, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func setPulseHz(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueFrequency(
            channelIndex: 0,
            componentIndex: 1,
            value: max(0, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func setWetness(_ value: Double, durationSeconds: Double = 2.0) -> Bool {
        enqueueWetness(
            channelIndex: 0,
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
    func applyCarrierHz(
        _ value: Double,
        channelIndex: Int = 0,
        durationSeconds: Double = 2.0
    ) -> Bool {
        enqueueFrequency(
            channelIndex: channelIndex,
            componentIndex: Self.carrierComponentIndex,
            value: max(200, value),
            durationSeconds: durationSeconds
        )
    }

    @discardableResult
    func applyPulse(
        at pulseIndex: Int,
        channelIndex: Int = 0,
        frequency: Double,
        wetness: Double,
        volume: Double,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.applyParameters.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: Int32(pulseIndex + 1),
                value: max(0, frequency),
                value2: min(1, max(0, wetness)),
                value3: min(1, max(0, volume)),
                value4: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    @discardableResult
    func addPulse(
        channelIndex: Int = 0,
        frequency: Double,
        wetness: Double,
        targetVolume: Double,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.addPulse.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: 0,
                value: max(0, frequency),
                value2: min(1, max(0, wetness)),
                value3: min(1, max(0, targetVolume)),
                value4: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    @discardableResult
    func removePulse(
        at pulseIndex: Int,
        channelIndex: Int = 0,
        durationSeconds: Double = 2.0
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.removePulse.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: Int32(pulseIndex + 1),
                value: 0,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    @discardableResult
    func removeAllPulses(channelIndex: Int = 0) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.removeAllPulses.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: 0,
                value: 0,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: 0
            )
        )
    }

    @discardableResult
    func setStereoEnabled(_ isEnabled: Bool) -> Bool {
        isStereoOutputEnabled = isEnabled
        if isRecordingEnabled {
            setRecordingEnabled(true)
        }

        return commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setStereoEnabled.rawValue,
                channelIndex: 0,
                componentIndex: 0,
                value: isEnabled ? 1 : 0,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: 0
            )
        )
    }

    func isCommandQueueFull() -> Bool {
        commandQueue.isFull()
    }

    func setRecordingEnabled(_ isEnabled: Bool) {
        isRecordingEnabled = isEnabled
        guard isEnabled else {
            recordingBuffer = nil
            return
        }

        let sampleRate = renderState?.sampleRate ?? AVAudioSession.sharedInstance().sampleRate
        recordingBuffer = WaveRecordingBuffer(
            sampleRate: sampleRate > 0 ? sampleRate : 48_000,
            channelCount: isStereoOutputEnabled ? 2 : 1,
            durationSeconds: 60
        )
    }

    func saveLastMinuteWAV() throws -> URL {
        guard let recordingBuffer else {
            throw NSError(
                domain: "WaveAudioEngine",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio engine is not configured."]
            )
        }

        let snapshot = recordingBuffer.snapshot()
        guard snapshot.frameCount > 0 else {
            throw NSError(
                domain: "WaveAudioEngine",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "No generated audio has been recorded yet."]
            )
        }

        let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let filename = "WaveGenerator-\(Self.recordingTimestamp())-\(UUID().uuidString.prefix(8)).wav"
        let url = directory.appendingPathComponent(filename)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: snapshot.sampleRate,
            channels: AVAudioChannelCount(snapshot.channelCount),
            interleaved: false
        )!
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(snapshot.frameCount)
        ) else {
            throw NSError(
                domain: "WaveAudioEngine",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Could not create WAV buffer."]
            )
        }

        pcmBuffer.frameLength = AVAudioFrameCount(snapshot.frameCount)
        if let channelData = pcmBuffer.floatChannelData {
            for frame in 0..<snapshot.frameCount {
                let sourceOffset = frame * snapshot.channelCount
                for channel in 0..<snapshot.channelCount {
                    channelData[channel][frame] = snapshot.samples[sourceOffset + channel]
                }
            }
        }

        try file.write(from: pcmBuffer)
        return url
    }

    private func enqueueFrequency(
        channelIndex: Int,
        componentIndex: Int,
        value: Double,
        durationSeconds: Double
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setComponentFrequency.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: Int32(componentIndex),
                value: value,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    private func enqueueWetness(
        channelIndex: Int,
        componentIndex: Int,
        value: Double,
        durationSeconds: Double
    ) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setComponentWetness.rawValue,
                channelIndex: Int32(channelIndex),
                componentIndex: Int32(componentIndex),
                value: value,
                value2: 0,
                value3: 0,
                value4: 0,
                durationSeconds: durationSeconds
            )
        )
    }

    private func enqueueMasterGain(value: Double, durationSeconds: Double) -> Bool {
        commandQueue.enqueue(
            WaveCommand(
                kind: WaveCommandKind.setMasterGain.rawValue,
                channelIndex: 0,
                componentIndex: 0,
                value: value,
                value2: 0,
                value3: 0,
                value4: 0,
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
                guard let channel = state.channels[safe: Int(command.channelIndex)],
                      let component = channel.components[safe: Int(command.componentIndex)] else {
                    continue
                }
                component.frequency.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setComponentWetness:
                guard let channel = state.channels[safe: Int(command.channelIndex)],
                      let component = channel.components[safe: Int(command.componentIndex)] else {
                    continue
                }
                component.wetness.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .setStereoEnabled:
                state.isStereo = command.value > 0
            case .setMasterGain:
                state.masterGain.scheduleTransition(
                    frame: now,
                    targetValue: command.value,
                    durationFrames: durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                )
            case .applyParameters:
                guard let channel = state.channels[safe: Int(command.channelIndex)],
                      let component = channel.components[safe: Int(command.componentIndex)] else {
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
                guard let channel = state.channels[safe: Int(command.channelIndex)] else {
                    continue
                }

                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                let pulse = ComponentState(
                    mode: .unipolarPulse,
                    minimumFrequency: 0,
                    initialFrequency: command.value,
                    initialWetness: command.value2,
                    initialVolume: 0
                )
                pulse.volume.scheduleTransition(
                    frame: now,
                    targetValue: command.value3,
                    durationFrames: durationFrames
                )
                channel.components.append(pulse)
            case .removePulse:
                guard let channel = state.channels[safe: Int(command.channelIndex)],
                      Int(command.componentIndex) > Self.carrierComponentIndex,
                      let component = channel.components[safe: Int(command.componentIndex)] else {
                    continue
                }

                let durationFrames = durationToFrames(command.durationSeconds, sampleRate: state.sampleRate)
                if durationFrames == 0 {
                    removeComponent(at: Int(command.componentIndex), from: channel)
                } else {
                    component.volume.scheduleTransition(
                        frame: now,
                        targetValue: 0,
                        durationFrames: durationFrames
                    )
                    component.pendingRemovalFrame = now + durationFrames
                }
            case .removeAllPulses:
                guard let channel = state.channels[safe: Int(command.channelIndex)] else {
                    continue
                }
                removeAllPulses(from: channel)
            }
        }
    }

    private func removeExpiredComponents(from state: RenderState) {
        let now = state.framePosition
        for channel in state.channels {
            var index = channel.components.count - 1
            while index > Self.carrierComponentIndex {
                let component = channel.components[index]
                if component.mode == .unipolarPulse,
                   let pendingRemovalFrame = component.pendingRemovalFrame,
                   now >= pendingRemovalFrame {
                    removeComponent(at: index, from: channel)
                }

                index -= 1
            }
        }
    }

    private func removeComponent(at index: Int, from channel: ChannelState) {
        guard channel.components.indices.contains(index) else { return }

        channel.components.remove(at: index)
    }

    private func removeAllPulses(from channel: ChannelState) {
        guard channel.components.count > 1 else { return }
        channel.components.removeSubrange(1..<channel.components.count)
    }

    private func renderSample(
        from channel: ChannelState,
        at currentFrame: Int64,
        sampleRate: Double,
        gain: Double
    ) -> Float {
        let mixedAmplitude = channel.components.reduce(1.0) { partial, component in
            partial * component.amplitude(at: currentFrame, sampleRate: sampleRate)
        }

        return Float(min(1, max(-1, gain * mixedAmplitude)))
    }

    private func durationToFrames(_ seconds: Double, sampleRate: Double) -> Int64 {
        Int64(max(0, (seconds * sampleRate).rounded()))
    }

    private static func recordingTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
