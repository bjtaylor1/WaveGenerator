import Foundation

enum ParameterEditor: Identifiable {
    case carrier(WaveChannel)
    case pulseFrequency(WaveChannel, PulseSettings.ID)
    case pulseWetness(WaveChannel, PulseSettings.ID)
    case pulseVolume(WaveChannel, PulseSettings.ID)

    var id: String {
        switch self {
        case let .carrier(channel):
            return "\(channel.rawValue)-carrier"
        case let .pulseFrequency(channel, id):
            return "\(channel.rawValue)-pulse-frequency-\(id)"
        case let .pulseWetness(channel, id):
            return "\(channel.rawValue)-pulse-wetness-\(id)"
        case let .pulseVolume(channel, id):
            return "\(channel.rawValue)-pulse-volume-\(id)"
        }
    }
}
