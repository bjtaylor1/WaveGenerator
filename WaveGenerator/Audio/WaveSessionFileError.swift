import Foundation

enum WaveSessionFileError: LocalizedError, Sendable {
    case unreadableFile
    case invalidSampleRate
    case invalidFrameCount
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The session file could not be read."
        case .invalidSampleRate:
            return "The session file does not contain a valid sample rate."
        case .invalidFrameCount:
            return "The session file does not contain a valid frame count."
        case .invalidAudioFormat:
            return "Could not create an audio format for the rendered WAV file."
        }
    }
}
