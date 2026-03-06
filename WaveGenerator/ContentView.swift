import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WaveGeneratorViewModel()
    @State private var activeEditor: ParameterEditor?

    private enum ParameterEditor: String, Identifiable {
        case carrier
        case pulse
        case wetness

        var id: String { rawValue }
    }

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
                    Button("Edit Carrier") {
                        activeEditor = .carrier
                    }

                    HStack {
                        Text("Pulse")
                        Spacer()
                        Text("\(viewModel.pulseHz, specifier: "%.2f") Hz")
                            .foregroundStyle(.secondary)
                    }
                    Button("Edit Pulse") {
                        activeEditor = .pulse
                    }

                    HStack {
                        Text("Wetness")
                        Spacer()
                        Text("\(viewModel.wetness, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Button("Edit Wetness") {
                        activeEditor = .wetness
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
        .sheet(item: $activeEditor) { editor in
            switch editor {
            case .carrier:
                SingleParameterSheet(
                    title: "Edit Carrier",
                    valueLabel: "Carrier",
                    unit: "Hz",
                    sliderRange: 200...1200,
                    step: 1,
                    initialValue: viewModel.carrierHz,
                    displayedValueFormat: "%.0f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyStagedSettings(
                        carrierHz: value,
                        pulseHz: viewModel.pulseHz,
                        wetness: viewModel.wetness
                    )
                }
            case .pulse:
                SingleParameterSheet(
                    title: "Edit Pulse",
                    valueLabel: "Pulse",
                    unit: "Hz",
                    sliderRange: 0...20,
                    step: 0.01,
                    initialValue: viewModel.pulseHz,
                    displayedValueFormat: "%.2f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyStagedSettings(
                        carrierHz: viewModel.carrierHz,
                        pulseHz: value,
                        wetness: viewModel.wetness
                    )
                }
            case .wetness:
                SingleParameterSheet(
                    title: "Edit Wetness",
                    valueLabel: "Wetness",
                    unit: nil,
                    sliderRange: 0...1,
                    step: 0.01,
                    initialValue: viewModel.wetness,
                    displayedValueFormat: "%.2f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyStagedSettings(
                        carrierHz: viewModel.carrierHz,
                        pulseHz: viewModel.pulseHz,
                        wetness: value
                    )
                }
            }
        }
    }
}

private struct SingleParameterSheet: View {
    let title: String
    let valueLabel: String
    let unit: String?
    let sliderRange: ClosedRange<Double>
    let step: Double
    let displayedValueFormat: String
    @ObservedObject var viewModel: WaveGeneratorViewModel
    let applyValue: (Double) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draftValue: Double

    init(
        title: String,
        valueLabel: String,
        unit: String?,
        sliderRange: ClosedRange<Double>,
        step: Double,
        initialValue: Double,
        displayedValueFormat: String,
        viewModel: WaveGeneratorViewModel,
        applyValue: @escaping (Double) async -> Bool
    ) {
        self.title = title
        self.valueLabel = valueLabel
        self.unit = unit
        self.sliderRange = sliderRange
        self.step = step
        self.displayedValueFormat = displayedValueFormat
        self.viewModel = viewModel
        self.applyValue = applyValue
        _draftValue = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Temporary Edit") {
                    HStack {
                        Text(valueLabel)
                        Spacer()
                        if let unit {
                            Text("\(draftValue, specifier: displayedValueFormat) \(unit)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(draftValue, specifier: displayedValueFormat)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $draftValue, in: sliderRange, step: step)
                }

                if viewModel.isQueueSaturated {
                    Section {
                        Text("Apply is disabled until the engine queue is free.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
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
                            let applied = await applyValue(draftValue)
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
