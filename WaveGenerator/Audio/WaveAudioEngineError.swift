import Foundation

enum WaveAudioEngineError: Error, LocalizedError {
    case audioSessionSetup(step: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .audioSessionSetup(step, underlying):
            return "Audio session failed at \(step): \(underlying.localizedDescription)"
        }
    }
}
