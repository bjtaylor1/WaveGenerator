import Foundation

nonisolated struct WaveGeneratorSettings: Codable, Sendable {
    var carrierHz: Double
    var transitionSeconds: Double
    var pulses: [PulseSettings]
    var selectedPulseID: PulseSettings.ID?
    var stereo: Bool?
    var selectedChannel: WaveChannel?
    var leftChannel: WaveChannelSettings?
    var rightChannel: WaveChannelSettings?
}
