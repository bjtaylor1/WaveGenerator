import SwiftUI
import UniformTypeIdentifiers

struct SessionHistorySheet: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: WaveSessionExportDocument?
    @State private var exportFilename = "WaveGenerator-Session.json"
    @State private var isExporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.sessionHistory.isEmpty {
                    ContentUnavailableView("No Sessions", systemImage: "clock.arrow.circlepath")
                } else {
                    ForEach(viewModel.sessionHistory) { session in
                        SessionHistoryRow(session: session) { session in
                            prepareExport(for: session)
                        }
                    }
                }

                if let message = viewModel.sessionHistoryErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                viewModel.setSessionHistoryExportError(error)
            }
        }
    }

    private func prepareExport(for session: WaveSessionRecord) {
        guard let document = viewModel.makeSessionExportDocument(for: session) else { return }

        exportDocument = document
        exportFilename = session.exportFilename
        isExporterPresented = true
    }
}
