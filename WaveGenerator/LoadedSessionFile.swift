import Foundation

struct LoadedSessionFile: Identifiable, Sendable {
    let id: UUID
    let filename: String
    let session: WaveSessionExport

    init(id: UUID = UUID(), filename: String, session: WaveSessionExport) {
        self.id = id
        self.filename = filename
        self.session = session
    }
}
