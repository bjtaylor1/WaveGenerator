enum WaveChannel: String, CaseIterable, Identifiable, Codable {
    case left
    case right

    var id: Self { self }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var engineChannelIndex: Int {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }
}
