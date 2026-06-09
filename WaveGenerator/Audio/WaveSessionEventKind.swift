enum WaveSessionEventKind: String, Codable, Sendable {
    case startPlayback
    case stopPlayback
    case carrierChanged
    case pulseChanged
    case pulseAdded
    case pulseRemoved
}
