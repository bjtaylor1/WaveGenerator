import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WaveGeneratorViewModel()
    @State private var isEditorPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Button(viewModel.isPlaying ? "Stop Tone" : "Start Tone") {
                        viewModel.togglePlayback()
                    }

                    HStack {
                        Text("Transition")
                        Spacer()
                        Text("\(viewModel.transitionSeconds, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $viewModel.transitionSeconds, in: 5...30, step: 0.1)
                }

                Section("Wave") {
                    HStack {
                        Text("Carrier")
                        Spacer()
                        Text("\(viewModel.carrierHz, specifier: "%.0f") Hz")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Pulse")
                        Spacer()
                        Text("\(viewModel.pulseHz, specifier: "%.2f") Hz")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Wetness")
                        Spacer()
                        Text("\(viewModel.wetness, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }

                    Button("Edit Wave Settings") {
                        isEditorPresented = true
                    }

                    if viewModel.isQueueSaturated {
                        Text("Engine queue is busy; apply waits until it drains.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("WaveGenerator POC")
        }
        .onAppear {
            viewModel.configureAudio()
        }
        .sheet(isPresented: $isEditorPresented) {
            WaveSettingsSheet(viewModel: viewModel)
        }
    }
}

private struct WaveSettingsSheet: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftCarrierHz: Double
    @State private var draftPulseHz: Double
    @State private var draftWetness: Double

    init(viewModel: WaveGeneratorViewModel) {
        self.viewModel = viewModel
        _draftCarrierHz = State(initialValue: viewModel.carrierHz)
        _draftPulseHz = State(initialValue: viewModel.pulseHz)
        _draftWetness = State(initialValue: viewModel.wetness)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Temporary Edits") {
                    HStack {
                        Text("Carrier")
                        Spacer()
                        Text("\(draftCarrierHz, specifier: "%.0f") Hz")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draftCarrierHz, in: 200...1200, step: 1)

                    HStack {
                        Text("Pulse")
                        Spacer()
                        Text("\(draftPulseHz, specifier: "%.2f") Hz")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draftPulseHz, in: 0...20, step: 0.01)

                    HStack {
                        Text("Wetness")
                        Spacer()
                        Text("\(draftWetness, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draftWetness, in: 0...1, step: 0.01)
                }

                if viewModel.isQueueSaturated {
                    Section {
                        Text("Apply is disabled until the engine queue is free.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Wave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isApplyingSettings ? "Applying..." : "Apply") {
                        Task {
                            let applied = await viewModel.applyStagedSettings(
                                carrierHz: draftCarrierHz,
                                pulseHz: draftPulseHz,
                                wetness: draftWetness
                            )
                            if applied {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isApplyingSettings || viewModel.isQueueSaturated)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ContentView()
}
