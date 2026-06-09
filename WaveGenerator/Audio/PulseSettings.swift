import Foundation

struct PulseSettings: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var frequency: Double
    var wetness: Double
    var volume: Double
    var isRemoving: Bool

    init(
        id: UUID = UUID(),
        frequency: Double = 1,
        wetness: Double = 0,
        volume: Double = 1,
        isRemoving: Bool = false
    ) {
        self.id = id
        self.frequency = frequency
        self.wetness = wetness
        self.volume = volume
        self.isRemoving = isRemoving
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PulseSettingsCodingKey.self)
        id = try container.decode(UUID.self, forKey: .id)
        frequency = try container.decode(Double.self, forKey: .frequency)
        wetness = try container.decode(Double.self, forKey: .wetness)
        volume = try container.decode(Double.self, forKey: .volume)
        isRemoving = try container.decodeIfPresent(Bool.self, forKey: .isRemoving) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PulseSettingsCodingKey.self)
        try container.encode(id, forKey: .id)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(wetness, forKey: .wetness)
        try container.encode(volume, forKey: .volume)
        try container.encode(isRemoving, forKey: .isRemoving)
    }
}
