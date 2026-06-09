import Foundation

struct LoadedSessionFile: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let session: WaveSessionExport

    var formattedDuration: String {
        WaveDurationFormatter.formatted(
            seconds: session.seconds(forFrameCount: session.renderDurationFrames)
        )
    }

    init(id: UUID = UUID(), filename: String, session: WaveSessionExport) {
        self.id = id
        self.filename = filename
        self.session = session
    }
}
