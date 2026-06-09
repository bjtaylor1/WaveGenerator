nonisolated enum WaveChannel: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right

    nonisolated var id: Self { self }

    nonisolated var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    nonisolated var engineChannelIndex: Int {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }
}
