import Foundation

nonisolated struct WaveSessionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let sampleRate: Double
    let durationFrames: Int64
    let initialSettings: WaveGeneratorSettings
    let events: [WaveSessionEvent]

    var actionCount: Int {
        events.count
    }

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(durationFrames) / sampleRate
    }

    var formattedDuration: String {
        let totalSeconds = max(0, Int(durationSeconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "WaveGenerator-Session-\(formatter.string(from: startedAt)).json"
    }
}
