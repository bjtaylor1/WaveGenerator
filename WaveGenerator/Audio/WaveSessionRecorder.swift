import Foundation

final class WaveSessionRecorder {
    private var startedAt: Date?
    private var initialSettings: WaveGeneratorSettings?
    private var events: [WaveSessionEvent] = []

    func beginSession(
        initialSettings: WaveGeneratorSettings,
        transitionSeconds: Double,
        at date: Date = Date()
    ) {
        startedAt = date
        self.initialSettings = initialSettings
        events = [
            WaveSessionEvent(
                kind: .startPlayback,
                elapsedSeconds: 0,
                occurredAt: date,
                transitionSeconds: transitionSeconds
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
        transitionSeconds: Double? = nil,
        at date: Date = Date()
    ) {
        guard let startedAt else { return }

        events.append(
            WaveSessionEvent(
                kind: kind,
                elapsedSeconds: max(0, date.timeIntervalSince(startedAt)),
                occurredAt: date,
                channel: channel,
                pulseID: pulseID,
                pulseIndex: pulseIndex,
                carrierHz: carrierHz,
                frequency: frequency,
                wetness: wetness,
                volume: volume,
                transitionSeconds: transitionSeconds
            )
        )
    }

    func finishSession(transitionSeconds: Double, at date: Date = Date()) -> WaveSessionRecord? {
        guard let startedAt, let initialSettings else { return nil }

        record(
            kind: .stopPlayback,
            transitionSeconds: transitionSeconds,
            at: date
        )

        let record = WaveSessionRecord(
            id: UUID(),
            startedAt: startedAt,
            endedAt: date,
            durationSeconds: max(0, date.timeIntervalSince(startedAt)),
            initialSettings: initialSettings,
            events: events
        )
        clear()
        return record
    }

    private func clear() {
        startedAt = nil
        initialSettings = nil
        events = []
    }
}
