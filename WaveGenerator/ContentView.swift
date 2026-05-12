import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WaveGeneratorViewModel()
    @State private var activeEditor: ParameterEditor?

    private enum ParameterEditor: Identifiable {
        case transition
        case carrier
        case pulseFrequency(PulseSettings.ID)
        case pulseWetness(PulseSettings.ID)
        case pulseVolume(PulseSettings.ID)

        var id: String {
            switch self {
            case .transition:
                return "transition"
            case .carrier:
                return "carrier"
            case let .pulseFrequency(id):
                return "pulse-frequency-\(id)"
            case let .pulseWetness(id):
                return "pulse-wetness-\(id)"
            case let .pulseVolume(id):
                return "pulse-volume-\(id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    Button(viewModel.isPlaying ? "Stop Tone" : "Start Tone") {
                        viewModel.togglePlayback()
                    }

                    Toggle("Save WAV on Stop", isOn: $viewModel.saveWAVOnStop)
                        .disabled(viewModel.isPlaying || viewModel.isSavingRecording)

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

                Section("Transition") {
                    HStack {
                        Text("Transition")
                        Spacer()
                        Text("\(viewModel.transitionSeconds, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                        Button {
                            activeEditor = .transition
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Transition")
                    }
                }

                Section("Carrier") {
                    HStack {
                        Text("Carrier")
                        Spacer()
                        Text("\(viewModel.carrierHz, specifier: "%.0f") Hz")
                            .foregroundStyle(.secondary)
                        Button {
                            activeEditor = .carrier
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Carrier")
                    }
                }

                Section("Pulses") {
                    HStack {
                        Button {
                            Task {
                                await viewModel.removeSelectedPulse()
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove Pulse")
                        .disabled(viewModel.selectedPulse == nil || viewModel.isApplyingSettings || viewModel.isQueueSaturated)

                        Spacer()

                        if !viewModel.pulses.isEmpty {
                            Picker("Pulse", selection: pulseSelection) {
                                ForEach(Array(viewModel.pulses.enumerated()), id: \.element.id) { index, pulse in
                                    Text("\(index + 1)")
                                        .tag(Optional(pulse.id))
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Spacer()

                        Button {
                            Task {
                                await viewModel.addPulse()
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add Pulse")
                        .disabled(viewModel.isApplyingSettings || viewModel.isQueueSaturated)
                    }

                    if let pulse = viewModel.selectedPulse {
                        HStack {
                            Text("Frequency")
                            Spacer()
                            Text("\(pulse.frequency, specifier: "%.2f") Hz")
                                .foregroundStyle(.secondary)
                            Button {
                                activeEditor = .pulseFrequency(pulse.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit Pulse Frequency")
                            .disabled(pulse.isRemoving)
                        }

                        HStack {
                            Text("Wetness")
                            Spacer()
                            Text("\(pulse.wetness, specifier: "%.2f")")
                                .foregroundStyle(.secondary)
                            Button {
                                activeEditor = .pulseWetness(pulse.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit Pulse Wetness")
                            .disabled(pulse.isRemoving)
                        }

                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(pulse.volume, specifier: "%.2f")")
                                .foregroundStyle(.secondary)
                            Button {
                                activeEditor = .pulseVolume(pulse.id)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit Pulse Volume")
                            .disabled(pulse.isRemoving)
                        }
                    } else {
                        Text("Carrier only")
                            .foregroundStyle(.secondary)
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
            case .transition:
                SingleParameterSheet(
                    title: "Edit Transition",
                    valueLabel: "Transition",
                    unit: "s",
                    sliderRange: 5...30,
                    step: 1,
                    nudgeStep: 1,
                    initialValue: viewModel.transitionSeconds,
                    displayedValueFormat: "%.1f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyTransitionSeconds(value)
                }
            case .carrier:
                SingleParameterSheet(
                    title: "Edit Carrier",
                    valueLabel: "Carrier",
                    unit: "Hz",
                    sliderRange: 200...2000,
                    step: 1,
                    nudgeStep: 1,
                    initialValue: viewModel.carrierHz,
                    displayedValueFormat: "%.0f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyCarrierHz(value)
                }
            case let .pulseFrequency(id):
                let pulse = viewModel.pulses.first(where: { $0.id == id }) ?? PulseSettings(id: id)
                let frequencyRange = viewModel.pulseFrequencyRange(for: id)
                SingleParameterSheet(
                    title: "Edit Pulse Frequency",
                    valueLabel: "Frequency",
                    unit: "Hz",
                    sliderRange: frequencyRange,
                    step: 0.01,
                    nudgeStep: 0.01,
                    initialValue: pulse.frequency,
                    displayedValueFormat: "%.2f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyPulse(
                        id: id,
                        frequency: value,
                        wetness: pulse.wetness,
                        volume: pulse.volume
                    )
                }
            case let .pulseWetness(id):
                let pulse = viewModel.pulses.first(where: { $0.id == id }) ?? PulseSettings(id: id)
                SingleParameterSheet(
                    title: "Edit Pulse Wetness",
                    valueLabel: "Wetness",
                    unit: nil,
                    sliderRange: 0...1,
                    step: 0.01,
                    nudgeStep: 0.01,
                    initialValue: pulse.wetness,
                    displayedValueFormat: "%.2f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyPulse(
                        id: id,
                        frequency: pulse.frequency,
                        wetness: value,
                        volume: pulse.volume
                    )
                }
            case let .pulseVolume(id):
                let pulse = viewModel.pulses.first(where: { $0.id == id }) ?? PulseSettings(id: id)
                SingleParameterSheet(
                    title: "Edit Pulse Volume",
                    valueLabel: "Volume",
                    unit: nil,
                    sliderRange: 0...1,
                    step: 0.01,
                    nudgeStep: 0.01,
                    initialValue: pulse.volume,
                    displayedValueFormat: "%.2f",
                    viewModel: viewModel
                ) { value in
                    await viewModel.applyPulse(
                        id: id,
                        frequency: pulse.frequency,
                        wetness: pulse.wetness,
                        volume: value
                    )
                }
            }
        }
    }

    private var pulseSelection: Binding<PulseSettings.ID?> {
        Binding {
            viewModel.selectedPulse?.id
        } set: { id in
            viewModel.selectedPulseID = id
        }
    }
}

private struct SingleParameterSheet: View {
    let title: String
    let valueLabel: String
    let unit: String?
    let sliderRange: ClosedRange<Double>
    let step: Double
    let nudgeStep: Double
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
        nudgeStep: Double,
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
        self.nudgeStep = nudgeStep
        self.displayedValueFormat = displayedValueFormat
        self.viewModel = viewModel
        self.applyValue = applyValue
        let clamped = Self.normalize(
            value: initialValue,
            in: sliderRange,
            step: step
        )
        _draftValue = State(initialValue: clamped)
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

                    HStack {
                        Button {
                            nudge(by: -nudgeStep)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Decrease")

                        Spacer()

                        if let unit {
                            Text("\(draftValue, specifier: displayedValueFormat) \(unit)")
                                .font(.body.monospacedDigit())
                        } else {
                            Text("\(draftValue, specifier: displayedValueFormat)")
                                .font(.body.monospacedDigit())
                        }

                        Spacer()

                        Button {
                            nudge(by: nudgeStep)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Increase")
                    }
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

    private func nudge(by delta: Double) {
        let next = draftValue + delta
        draftValue = Self.normalize(value: next, in: sliderRange, step: step)
    }

    private static func normalize(value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let snapped = (clamped / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView()
}
