import Foundation

final class WaveSessionHistoryStore {
    private let key = "WaveGenerator.sessionHistory.v1"
    private let maxSessions: Int
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, maxSessions: Int = 50) {
        self.defaults = defaults
        self.maxSessions = maxSessions
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [WaveSessionRecord] {
        guard let data = defaults.data(forKey: key),
              let sessions = try? decoder.decode([WaveSessionRecord].self, from: data) else {
            return []
        }

        return limited(sessions)
    }

    func add(_ session: WaveSessionRecord) -> [WaveSessionRecord] {
        let sessions = limited([session] + load())
        save(sessions)
        return sessions
    }

    func save(_ sessions: [WaveSessionRecord]) {
        guard let data = try? encoder.encode(limited(sessions)) else { return }
        defaults.set(data, forKey: key)
    }

    static func exportData(for session: WaveSessionRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(session)
    }

    private func limited(_ sessions: [WaveSessionRecord]) -> [WaveSessionRecord] {
        Array(
            sessions
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(maxSessions)
        )
    }
}
