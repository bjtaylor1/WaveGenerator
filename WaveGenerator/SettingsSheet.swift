import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isEditingTransition = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Toggle("Stereo", isOn: stereoBinding)
                        .disabled(viewModel.settingsSheetLocked)

                    HStack {
                        Text("Transition")
                        Spacer()
                        Text("\(viewModel.transitionSeconds, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                        Button {
                            isEditingTransition = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Transition")
                        .disabled(viewModel.settingsSheetLocked)
                    }

                    if viewModel.isPlaying {
                        Text("Settings are locked while the tone is playing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Recording") {
                    Toggle("Save WAV on Stop", isOn: $viewModel.saveWAVOnStop)
                        .disabled(viewModel.settingsSheetLocked || viewModel.isSavingRecording)

                    if let url = viewModel.lastSavedRecordingURL {
                        ShareLink(item: url) {
                            Label("Share WAV", systemImage: "square.and.arrow.up")
                        }
                    }

                    if let recordingErrorMessage = viewModel.recordingErrorMessage {
                        Text(recordingErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
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
        .sheet(isPresented: $isEditingTransition) {
            SingleParameterSheet(
                title: "Edit Transition",
                valueLabel: "Transition",
                unit: "s",
                sliderRange: 5...30,
                step: 1,
                nudgeStep: 1,
                initialValue: viewModel.transitionSeconds,
                displayedValueFormat: "%.1f",
                locksWhilePlaying: true,
                viewModel: viewModel
            ) { value in
                await viewModel.applyTransitionSeconds(value)
            }
        }
    }

    private var stereoBinding: Binding<Bool> {
        Binding {
            viewModel.isStereo
        } set: { isEnabled in
            viewModel.setStereoEnabled(isEnabled)
        }
    }
}
