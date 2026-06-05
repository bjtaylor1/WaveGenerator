import Foundation

final class WaveSettingsStore {
    private let key = "WaveGenerator.settings.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WaveGeneratorSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(WaveGeneratorSettings.self, from: data)
    }

    func save(_ settings: WaveGeneratorSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
