import SwiftUI
import UniformTypeIdentifiers

struct SessionHistorySheet: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: WaveSessionExportDocument?
    @State private var exportFilename = "WaveGenerator-Session.json"
    @State private var isExporterPresented = false
    @State private var importMode: SessionFileImportMode?
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Files") {
                    Button {
                        importMode = .playback
                        isImporterPresented = true
                    } label: {
                        Label("Load Session File", systemImage: "doc.badge.plus")
                    }
                    .disabled(viewModel.sessionFileActionsLocked)

                    if viewModel.isValidatingSessionFile {
                        ProgressView("Checking session file")

                        if let pendingSessionFilename = viewModel.pendingSessionFilename {
                            Text(pendingSessionFilename)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let loadedSessionFile = viewModel.loadedSessionFile {
                        Button {
                            playLoadedSessionFile()
                        } label: {
                            Label("File loaded - click here to play it", systemImage: "play.circle")
                        }
                        .disabled(viewModel.sessionFileActionsLocked)

                        Text(loadedSessionFile.filename)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        importMode = .renderWAV
                        isImporterPresented = true
                    } label: {
                        Label("Render WAV From File", systemImage: "waveform")
                    }
                    .disabled(viewModel.sessionFileActionsLocked)

                    if viewModel.isRenderingSessionWAV {
                        ProgressView("Rendering WAV")
                    }

                    if let url = viewModel.lastRenderedWAVURL {
                        ShareLink(item: url) {
                            Label("Share Rendered WAV", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if viewModel.sessionHistory.isEmpty {
                    ContentUnavailableView("No Sessions", systemImage: "clock.arrow.circlepath")
                } else {
                    Section("History") {
                        ForEach(viewModel.sessionHistory) { session in
                            SessionHistoryRow(
                                session: session,
                                playSession: { session in
                                    play(session)
                                },
                                renderWAV: { session in
                                    renderWAV(session)
                                },
                                exportSession: { session in
                                    prepareExport(for: session)
                                },
                                actionsDisabled: viewModel.sessionFileActionsLocked
                            )
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
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
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

    private func play(_ session: WaveSessionRecord) {
        Task {
            let started = await viewModel.playHistorySession(session)
            if started {
                dismiss()
            }
        }
    }

    private func renderWAV(_ session: WaveSessionRecord) {
        Task {
            _ = await viewModel.renderHistorySessionWAV(session)
        }
    }

    private func playLoadedSessionFile() {
        Task {
            let started = await viewModel.playLoadedSessionFile()
            if started {
                dismiss()
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first, let importMode else { return }
            switch importMode {
            case .playback:
                Task {
                    _ = await viewModel.loadSessionFile(at: url)
                }
            case .renderWAV:
                Task {
                    _ = await viewModel.renderSessionFileWAV(at: url)
                }
            }
        case let .failure(error):
            viewModel.setSessionHistoryExportError(error)
        }
    }
}
