import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WaveSessionExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(session: WaveSessionRecord) throws {
        data = try WaveSessionHistoryStore.exportData(for: session)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
