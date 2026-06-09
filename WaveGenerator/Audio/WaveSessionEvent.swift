import Foundation

struct WaveSessionEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: WaveSessionEventKind
    let elapsedSeconds: Double
    let occurredAt: Date
    let channel: WaveChannel?
    let pulseID: UUID?
    let pulseIndex: Int?
    let carrierHz: Double?
    let frequency: Double?
    let wetness: Double?
    let volume: Double?
    let transitionSeconds: Double?

    init(
        id: UUID = UUID(),
        kind: WaveSessionEventKind,
        elapsedSeconds: Double,
        occurredAt: Date,
        channel: WaveChannel? = nil,
        pulseID: UUID? = nil,
        pulseIndex: Int? = nil,
        carrierHz: Double? = nil,
        frequency: Double? = nil,
        wetness: Double? = nil,
        volume: Double? = nil,
        transitionSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.elapsedSeconds = elapsedSeconds
        self.occurredAt = occurredAt
        self.channel = channel
        self.pulseID = pulseID
        self.pulseIndex = pulseIndex
        self.carrierHz = carrierHz
        self.frequency = frequency
        self.wetness = wetness
        self.volume = volume
        self.transitionSeconds = transitionSeconds
    }
}
