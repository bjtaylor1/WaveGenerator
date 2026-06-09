import Foundation

struct WaveSessionEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: WaveSessionEventKind
    let frameOffset: Int64
    let channel: WaveChannel?
    let pulseID: UUID?
    let pulseIndex: Int?
    let carrierHz: Double?
    let frequency: Double?
    let wetness: Double?
    let volume: Double?
    let transitionFrameCount: Int64?

    init(
        id: UUID = UUID(),
        kind: WaveSessionEventKind,
        frameOffset: Int64,
        channel: WaveChannel? = nil,
        pulseID: UUID? = nil,
        pulseIndex: Int? = nil,
        carrierHz: Double? = nil,
        frequency: Double? = nil,
        wetness: Double? = nil,
        volume: Double? = nil,
        transitionFrameCount: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.frameOffset = frameOffset
        self.channel = channel
        self.pulseID = pulseID
        self.pulseIndex = pulseIndex
        self.carrierHz = carrierHz
        self.frequency = frequency
        self.wetness = wetness
        self.volume = volume
        self.transitionFrameCount = transitionFrameCount
    }
}
