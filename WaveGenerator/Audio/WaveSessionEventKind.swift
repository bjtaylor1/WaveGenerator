enum WaveSessionEventKind: String, Codable {
    case startPlayback
    case stopPlayback
    case carrierChanged
    case pulseChanged
    case pulseAdded
    case pulseRemoved
}
