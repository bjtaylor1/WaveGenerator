import AVFoundation
import Foundation

final class WaveSessionOfflineRenderer {
    nonisolated private static let blockSize = 4_096

    nonisolated static func render(_ session: WaveSessionExport) throws -> URL {
        let sampleRate = session.sampleRate
        guard sampleRate > 0 else { throw WaveSessionFileError.invalidSampleRate }
        guard session.renderDurationFrames >= 0 else { throw WaveSessionFileError.invalidFrameCount }

        let channelCount = session.isStereo ? 2 : 1
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw WaveSessionFileError.invalidAudioFormat
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveGenerator-Rendered-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let state = makeRenderState(for: session)
        let sortedEvents = session.events.sorted { lhs, rhs in
            lhs.frameOffset < rhs.frameOffset
        }
        var eventIndex = 0
        var nextFrame: Int64 = 0

        while nextFrame < session.renderDurationFrames {
            let framesThisBlock = min(Self.blockSize, Int(session.renderDurationFrames - nextFrame))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(framesThisBlock)
            ) else {
                throw WaveSessionFileError.invalidAudioFormat
            }

            buffer.frameLength = AVAudioFrameCount(framesThisBlock)
            guard let channelData = buffer.floatChannelData else {
                throw WaveSessionFileError.invalidAudioFormat
            }

            for frameOffset in 0..<framesThisBlock {
                let frame = nextFrame + Int64(frameOffset)
                while eventIndex < sortedEvents.count,
                      sortedEvents[eventIndex].frameOffset <= frame {
                    apply(sortedEvents[eventIndex], to: state)
                    eventIndex += 1
                }

                let sample = renderOutputSample(from: state, at: frame, sampleRate: sampleRate)
                channelData[0][frameOffset] = sample.left
                if channelCount > 1 {
                    channelData[1][frameOffset] = sample.right
                }
                removeExpiredComponents(from: state, at: frame)
            }

            try file.write(from: buffer)
            nextFrame += Int64(framesThisBlock)
        }

        return url
    }

    nonisolated private static func makeRenderState(for session: WaveSessionExport) -> RenderState {
        let state = RenderState(sampleRate: session.sampleRate)
        state.isStereo = session.isStereo
        state.channels[0].components = components(from: session.channelSettings(for: .left))
        state.channels[1].components = components(from: session.channelSettings(for: .right))
        return state
    }

    nonisolated private static func components(from settings: WaveChannelSettings) -> [ComponentState] {
        let carrier = ComponentState(
            mode: .bipolarSine,
            minimumFrequency: 200,
            initialFrequency: max(200, settings.carrierHz),
            initialWetness: 0,
            initialVolume: 1
        )
        let pulses = settings.pulses.map { pulse in
            ComponentState(
                mode: .unipolarPulse,
                minimumFrequency: 0,
                initialFrequency: max(0, pulse.frequency),
                initialWetness: min(1, max(0, pulse.wetness)),
                initialVolume: min(1, max(0, pulse.volume))
            )
        }

        return [carrier] + pulses
    }

    nonisolated private static func apply(_ event: WaveSessionExportEvent, to state: RenderState) {
        let frame = max(0, event.frameOffset)
        let durationFrames = max(0, event.transitionFrameCount ?? 0)

        switch event.kind {
        case .startPlayback:
            state.masterGain.scheduleTransition(frame: frame, targetValue: 1, durationFrames: durationFrames)
        case .stopPlayback:
            state.masterGain.scheduleTransition(frame: frame, targetValue: 0, durationFrames: durationFrames)
        case .carrierChanged:
            guard let carrierHz = event.carrierHz,
                  let component = state.channels[safe: channelIndex(for: event.channel, in: state)]?.components.first else {
                return
            }
            component.frequency.scheduleTransition(
                frame: frame,
                targetValue: max(200, carrierHz),
                durationFrames: durationFrames
            )
        case .pulseChanged:
            guard let pulseIndex = event.pulseIndex,
                  let component = state.channels[safe: channelIndex(for: event.channel, in: state)]?.components[safe: pulseIndex + 1] else {
                return
            }
            if let frequency = event.frequency {
                component.frequency.scheduleTransition(
                    frame: frame,
                    targetValue: max(0, frequency),
                    durationFrames: durationFrames
                )
            }
            if let wetness = event.wetness {
                component.wetness.scheduleTransition(
                    frame: frame,
                    targetValue: min(1, max(0, wetness)),
                    durationFrames: durationFrames
                )
            }
            if let volume = event.volume {
                component.volume.scheduleTransition(
                    frame: frame,
                    targetValue: min(1, max(0, volume)),
                    durationFrames: durationFrames
                )
            }
        case .pulseAdded:
            guard let channel = state.channels[safe: channelIndex(for: event.channel, in: state)] else { return }

            let pulse = ComponentState(
                mode: .unipolarPulse,
                minimumFrequency: 0,
                initialFrequency: max(0, event.frequency ?? 0),
                initialWetness: min(1, max(0, event.wetness ?? 0)),
                initialVolume: 0
            )
            pulse.volume.scheduleTransition(
                frame: frame,
                targetValue: min(1, max(0, event.volume ?? 0)),
                durationFrames: durationFrames
            )
            channel.components.append(pulse)
        case .pulseRemoved:
            guard let pulseIndex = event.pulseIndex,
                  let channel = state.channels[safe: channelIndex(for: event.channel, in: state)] else {
                return
            }

            let componentIndex = pulseIndex + 1
            guard componentIndex > 0,
                  let component = channel.components[safe: componentIndex] else {
                return
            }

            if durationFrames == 0 {
                channel.components.remove(at: componentIndex)
            } else {
                component.volume.scheduleTransition(frame: frame, targetValue: 0, durationFrames: durationFrames)
                component.pendingRemovalFrame = frame + durationFrames
            }
        }
    }

    nonisolated private static func channelIndex(for channel: WaveChannel?, in state: RenderState) -> Int {
        state.isStereo ? (channel ?? .left).engineChannelIndex : WaveChannel.left.engineChannelIndex
    }

    nonisolated private static func renderOutputSample(
        from state: RenderState,
        at frame: Int64,
        sampleRate: Double
    ) -> (left: Float, right: Float) {
        let gain = min(1, max(0, state.masterGain.value(at: frame)))
        let uiLeftSample = renderSample(from: state.channels[0], at: frame, sampleRate: sampleRate, gain: gain)
        let uiRightSample = state.isStereo
            ? renderSample(from: state.channels[1], at: frame, sampleRate: sampleRate, gain: gain)
            : uiLeftSample
        let outputLeftSample = state.isStereo ? uiRightSample : uiLeftSample
        let outputRightSample = state.isStereo ? uiLeftSample : uiRightSample
        return (outputLeftSample, outputRightSample)
    }

    nonisolated private static func renderSample(
        from channel: ChannelState,
        at frame: Int64,
        sampleRate: Double,
        gain: Double
    ) -> Float {
        let mixedAmplitude = channel.components.reduce(1.0) { partial, component in
            partial * component.amplitude(at: frame, sampleRate: sampleRate)
        }

        return Float(min(1, max(-1, gain * mixedAmplitude)))
    }

    nonisolated private static func removeExpiredComponents(from state: RenderState, at frame: Int64) {
        for channel in state.channels {
            var index = channel.components.count - 1
            while index > 0 {
                let component = channel.components[index]
                if component.mode == .unipolarPulse,
                   let pendingRemovalFrame = component.pendingRemovalFrame,
                   frame >= pendingRemovalFrame {
                    channel.components.remove(at: index)
                }

                index -= 1
            }
        }
    }
}
