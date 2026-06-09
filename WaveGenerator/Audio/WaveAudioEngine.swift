import AVFoundation
import Foundation

final class WaveAudioEngine {
    private static let carrierComponentIndex = 0

    private let engine = AVAudioEngine()
    private let commandQueue = WaveCommandQueue()

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false
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
            let startFrame = state.framePosition

            for frameOffset in 0..<frames {
                let currentFrame = startFrame + Int64(frameOffset)
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

                for (channelIndex, buffer) in bufferList.enumerated() {
                    guard let mData = buffer.mData else { continue }
                    let channel = mData.assumingMemoryBound(to: Float.self)
                    channel[frameOffset] = channelIndex == 0 ? outputLeftSample : outputRightSample
                }
            }

            state.framePosition = startFrame + Int64(frames)
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

    func timelineSnapshot() -> WaveAudioTimelineSnapshot {
        guard let renderState else {
            return WaveAudioTimelineSnapshot(framePosition: 0, sampleRate: 48_000)
        }

        return WaveAudioTimelineSnapshot(
            framePosition: renderState.framePosition,
            sampleRate: renderState.sampleRate
        )
    }

    func durationFrames(for seconds: Double) -> Int64 {
        durationToFrames(seconds, sampleRate: timelineSnapshot().sampleRate)
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

}
