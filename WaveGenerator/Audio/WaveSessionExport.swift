import Foundation

struct WaveSessionExport: Codable, Sendable {
    let formatVersion: Int
    let appVersion: String?
    let appBuild: String?
    let sampleRate: Double
    let durationFrames: Int64
    let initialSettings: WaveGeneratorSettings
    let events: [WaveSessionExportEvent]

    init(session: WaveSessionRecord) {
        formatVersion = 1
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        sampleRate = session.sampleRate
        durationFrames = session.durationFrames
        initialSettings = session.initialSettings
        events = session.events.map { event in
            WaveSessionExportEvent(event: event)
        }
    }

    nonisolated var isStereo: Bool {
        initialSettings.stereo ?? false
    }

    nonisolated var renderDurationFrames: Int64 {
        let eventEndFrame = events.reduce(durationFrames) { partial, event in
            max(partial, event.frameOffset + (event.transitionFrameCount ?? 0))
        }

        return max(durationFrames, eventEndFrame)
    }

    nonisolated func channelSettings(for channel: WaveChannel) -> WaveChannelSettings {
        let monoSettings = WaveChannelSettings(
            carrierHz: initialSettings.carrierHz,
            pulses: initialSettings.pulses,
            selectedPulseID: initialSettings.selectedPulseID
        )

        guard isStereo else { return monoSettings }

        switch channel {
        case .left:
            return initialSettings.leftChannel ?? monoSettings
        case .right:
            return initialSettings.rightChannel ?? monoSettings
        }
    }

    nonisolated func seconds(forFrameCount frameCount: Int64) -> Double {
        guard sampleRate > 0 else { return 0 }
        return Double(max(0, frameCount)) / sampleRate
    }

    nonisolated func liveFrameOffset(for frameOffset: Int64, liveSampleRate: Double) -> Int64 {
        guard sampleRate > 0, liveSampleRate > 0 else { return max(0, frameOffset) }
        return Int64((Double(max(0, frameOffset)) * liveSampleRate / sampleRate).rounded())
    }
}
