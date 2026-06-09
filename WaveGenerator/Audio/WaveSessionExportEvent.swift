import Foundation

struct WaveSessionExportEvent: Codable {
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

    init(event: WaveSessionEvent) {
        kind = event.kind
        frameOffset = event.frameOffset
        channel = event.channel
        pulseID = event.pulseID
        pulseIndex = event.pulseIndex
        carrierHz = event.carrierHz
        frequency = event.frequency
        wetness = event.wetness
        volume = event.volume
        transitionFrameCount = event.transitionFrameCount
    }
}
