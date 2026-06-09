import Foundation

final class WaveSessionRecorder {
    private var startedAt: Date?
    private var startFramePosition: Int64?
    private var sampleRate: Double?
    private var initialSettings: WaveGeneratorSettings?
    private var events: [WaveSessionEvent] = []

    func beginSession(
        initialSettings: WaveGeneratorSettings,
        timeline: WaveAudioTimelineSnapshot,
        transitionFrameCount: Int64,
        startedAt date: Date = Date()
    ) {
        startedAt = date
        startFramePosition = timeline.framePosition
        sampleRate = timeline.sampleRate
        self.initialSettings = initialSettings
        events = [
            WaveSessionEvent(
                kind: .startPlayback,
                frameOffset: 0,
                transitionFrameCount: transitionFrameCount
            )
        ]
    }

    func record(
        kind: WaveSessionEventKind,
        channel: WaveChannel? = nil,
        pulseID: UUID? = nil,
        pulseIndex: Int? = nil,
        carrierHz: Double? = nil,
        frequency: Double? = nil,
        wetness: Double? = nil,
        volume: Double? = nil,
        transitionFrameCount: Int64? = nil,
        timeline: WaveAudioTimelineSnapshot
    ) {
        guard let startFramePosition else { return }

        events.append(
            WaveSessionEvent(
                kind: kind,
                frameOffset: max(0, timeline.framePosition - startFramePosition),
                channel: channel,
                pulseID: pulseID,
                pulseIndex: pulseIndex,
                carrierHz: carrierHz,
                frequency: frequency,
                wetness: wetness,
                volume: volume,
                transitionFrameCount: transitionFrameCount
            )
        )
    }

    func finishSession(
        timeline: WaveAudioTimelineSnapshot,
        transitionFrameCount: Int64
    ) -> WaveSessionRecord? {
        guard let startedAt, let startFramePosition, let sampleRate, let initialSettings else { return nil }

        record(
            kind: .stopPlayback,
            transitionFrameCount: transitionFrameCount,
            timeline: timeline
        )

        let record = WaveSessionRecord(
            id: UUID(),
            startedAt: startedAt,
            sampleRate: sampleRate,
            durationFrames: max(0, timeline.framePosition - startFramePosition),
            initialSettings: initialSettings,
            events: events
        )
        clear()
        return record
    }

    private func clear() {
        startedAt = nil
        startFramePosition = nil
        sampleRate = nil
        initialSettings = nil
        events = []
    }
}
