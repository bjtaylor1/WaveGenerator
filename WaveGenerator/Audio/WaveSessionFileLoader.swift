import Foundation

nonisolated struct WaveSessionFileLoader {
    nonisolated static func load(from url: URL) throws -> WaveSessionExport {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            throw WaveSessionFileError.unreadableFile
        }

        return try JSONDecoder().decode(WaveSessionExport.self, from: data)
    }
}
