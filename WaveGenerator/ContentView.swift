import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WaveGeneratorViewModel()
    @State private var activeEditor: ParameterEditor?
    @State private var isSettingsPresented = false

    enum ParameterEditor: Identifiable {
        case carrier(WaveChannel)
        case pulseFrequency(WaveChannel, PulseSettings.ID)
        case pulseWavelengthFactor(WaveChannel, PulseSettings.ID)
        case pulseWetness(WaveChannel, PulseSettings.ID)
        case pulseVolume(WaveChannel, PulseSettings.ID)

        var id: String {
            switch self {
            case let .carrier(channel):
                return "\(channel.rawValue)-carrier"
            case let .pulseFrequency(channel, id):
                return "\(channel.rawValue)-pulse-frequency-\(id)"
            case let .pulseWavelengthFactor(channel, id):
                return "\(channel.rawValue)-pulse-wavelength-factor-\(id)"
            case let .pulseWetness(channel, id):
                return "\(channel.rawValue)-pulse-wetness-\(id)"
            case let .pulseVolume(channel, id):
                return "\(channel.rawValue)-pulse-volume-\(id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isStereo {
                    TabView(selection: $viewModel.selectedChannel) {
                        ChannelSettingsView(
                            viewModel: viewModel,
                            channel: .left,
                            activeEditor: $activeEditor
                        )
                        .tabItem {
                            Label("Left", systemImage: "speaker.wave.2")
                        }
                        .tag(WaveChannel.left)

                        ChannelSettingsView(
                            viewModel: viewModel,
                            channel: .right,
                            activeEditor: $activeEditor
                        )
                        .tabItem {
                            Label("Right", systemImage: "speaker.wave.2")
                        }
                        .tag(WaveChannel.right)
                    }
                } else {
                    ChannelSettingsView(
                        viewModel: viewModel,
                        channel: .left,
                        activeEditor: $activeEditor
                    )
                }
            }
            .navigationTitle("WaveGenerator POC")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isPlaying ? "Stop Tone" : "Start Tone") {
                        viewModel.togglePlayback()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isPlaying && viewModel.parameterControlsLocked)
                }
            }
        }
        .onAppear {
            viewModel.configureAudio()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(viewModel: viewModel)
        }
        .sheet(item: $activeEditor) { editor in
            editorSheet(for: editor)
        }
    }

    @ViewBuilder
    private func editorSheet(for editor: ParameterEditor) -> some View {
        switch editor {
        case let .carrier(channel):
            SingleParameterSheet(
                title: viewModel.isStereo ? "Edit \(channel.title) Carrier" : "Edit Carrier",
                valueLabel: "Carrier",
                unit: "Hz",
                sliderRange: 200...2000,
                step: 1,
                nudgeStep: 1,
                initialValue: viewModel.carrierHz(for: channel),
                displayedValueFormat: "%.0f",
                viewModel: viewModel
            ) { value in
                await viewModel.applyCarrierHz(value, channel: channel)
            }
        case let .pulseFrequency(channel, id):
            let pulse = viewModel.pulses(for: channel).first(where: { $0.id == id }) ?? PulseSettings(id: id)
            let frequencyRange = viewModel.pulseFrequencyRange(for: id, in: channel)
            SingleParameterSheet(
                title: viewModel.isStereo ? "Edit \(channel.title) Pulse Frequency" : "Edit Pulse Frequency",
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
                    channel: channel,
                    frequency: value,
                    wavelengthFactor: pulse.wavelengthFactor,
                    wetness: pulse.wetness,
                    volume: pulse.volume
                )
            }
        case let .pulseWavelengthFactor(channel, id):
            let pulse = viewModel.pulses(for: channel).first(where: { $0.id == id }) ?? PulseSettings(id: id)
            SingleParameterSheet(
                title: viewModel.isStereo ? "Edit \(channel.title) Wavelength Factor" : "Edit Wavelength Factor",
                valueLabel: "Wavelength Factor",
                unit: "x",
                sliderRange: viewModel.pulseWavelengthFactorRange(for: id, in: channel),
                step: 1,
                nudgeStep: 1,
                initialValue: pulse.wavelengthFactor,
                displayedValueFormat: "%.0f",
                viewModel: viewModel
            ) { value in
                await viewModel.applyPulse(
                    id: id,
                    channel: channel,
                    frequency: pulse.frequency,
                    wavelengthFactor: value,
                    wetness: pulse.wetness,
                    volume: pulse.volume
                )
            }
        case let .pulseWetness(channel, id):
            let pulse = viewModel.pulses(for: channel).first(where: { $0.id == id }) ?? PulseSettings(id: id)
            SingleParameterSheet(
                title: viewModel.isStereo ? "Edit \(channel.title) Pulse Wetness" : "Edit Pulse Wetness",
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
                    channel: channel,
                    frequency: pulse.frequency,
                    wavelengthFactor: pulse.wavelengthFactor,
                    wetness: value,
                    volume: pulse.volume
                )
            }
        case let .pulseVolume(channel, id):
            let pulse = viewModel.pulses(for: channel).first(where: { $0.id == id }) ?? PulseSettings(id: id)
            SingleParameterSheet(
                title: viewModel.isStereo ? "Edit \(channel.title) Pulse Volume" : "Edit Pulse Volume",
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
                    channel: channel,
                    frequency: pulse.frequency,
                    wavelengthFactor: pulse.wavelengthFactor,
                    wetness: pulse.wetness,
                    volume: value
                )
            }
        }
    }
}

private struct ChannelSettingsView: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel
    let channel: WaveChannel
    @Binding var activeEditor: ContentView.ParameterEditor?

    private var pulses: [PulseSettings] {
        viewModel.pulses(for: channel)
    }

    private var selectedPulse: PulseSettings? {
        viewModel.selectedPulse(for: channel)
    }

    var body: some View {
        Form {
            Section(viewModel.isStereo ? "\(channel.title) Carrier" : "Carrier") {
                HStack {
                    Text("Carrier")
                    Spacer()
                    Text("\(viewModel.carrierHz(for: channel), specifier: "%.0f") Hz")
                        .foregroundStyle(.secondary)
                    Button {
                        activeEditor = .carrier(channel)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(viewModel.isStereo ? "Edit \(channel.title) Carrier" : "Edit Carrier")
                    .disabled(viewModel.parameterControlsLocked)
                }
            }

            Section(viewModel.isStereo ? "\(channel.title) Pulses" : "Pulses") {
                HStack {
                    Button {
                        Task {
                            await viewModel.removeSelectedPulse(from: channel)
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(viewModel.isStereo ? "Remove \(channel.title) Pulse" : "Remove Pulse")
                    .disabled(selectedPulse == nil || viewModel.parameterControlsLocked)

                    Spacer()

                    if !pulses.isEmpty {
                        Picker("Pulse", selection: pulseSelection) {
                            ForEach(Array(pulses.enumerated()), id: \.element.id) { index, pulse in
                                Text("\(index + 1)")
                                    .tag(Optional(pulse.id))
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(viewModel.parameterControlsLocked)
                    }

                    Spacer()

                    Button {
                        Task {
                            await viewModel.addPulse(to: channel)
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(viewModel.isStereo ? "Add \(channel.title) Pulse" : "Add Pulse")
                    .disabled(viewModel.parameterControlsLocked)
                }

                if let pulse = selectedPulse {
                    let usesWavelengthFactor = viewModel.pulseUsesWavelengthFactor(pulse.id, in: channel)
                    HStack {
                        Text(usesWavelengthFactor ? "Wavelength Factor" : "Frequency")
                        Spacer()
                        if usesWavelengthFactor {
                            Text("\(pulse.wavelengthFactor, specifier: "%.0f")x, \(pulse.frequency, specifier: "%.3f") Hz")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(pulse.frequency, specifier: "%.2f") Hz")
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            activeEditor = usesWavelengthFactor
                                ? .pulseWavelengthFactor(channel, pulse.id)
                                : .pulseFrequency(channel, pulse.id)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(usesWavelengthFactor ? "Edit Wavelength Factor" : "Edit Pulse Frequency")
                        .disabled(viewModel.parameterControlsLocked || pulse.isRemoving)
                    }

                    if usesWavelengthFactor {
                        HStack {
                            Text("Base Frequency")
                            Spacer()
                            Text("\(pulses.first?.frequency ?? 0, specifier: "%.2f") Hz")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Wetness")
                        Spacer()
                        Text("\(pulse.wetness, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                        Button {
                            activeEditor = .pulseWetness(channel, pulse.id)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Pulse Wetness")
                        .disabled(viewModel.parameterControlsLocked || pulse.isRemoving)
                    }

                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(pulse.volume, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                        Button {
                            activeEditor = .pulseVolume(channel, pulse.id)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Pulse Volume")
                        .disabled(viewModel.parameterControlsLocked || pulse.isRemoving)
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
    }

    private var pulseSelection: Binding<PulseSettings.ID?> {
        Binding {
            viewModel.selectedPulse(for: channel)?.id
        } set: { id in
            viewModel.setSelectedPulseID(id, for: channel)
        }
    }
}

private struct SettingsSheet: View {
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

private struct SingleParameterSheet: View {
    let title: String
    let valueLabel: String
    let unit: String?
    let sliderRange: ClosedRange<Double>
    let step: Double
    let nudgeStep: Double
    let displayedValueFormat: String
    let locksWhilePlaying: Bool
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
        locksWhilePlaying: Bool = false,
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
        self.locksWhilePlaying = locksWhilePlaying
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
                        .disabled(controlsLocked)

                    HStack {
                        Button {
                            nudge(by: -nudgeStep)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Decrease")
                        .disabled(controlsLocked)

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
                        .disabled(controlsLocked)
                    }
                }

                if locksWhilePlaying && viewModel.isPlaying {
                    Section {
                        Text("Settings are locked while the tone is playing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.isQueueSaturated {
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
                    .disabled(controlsLocked)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var controlsLocked: Bool {
        viewModel.parameterControlsLocked || (locksWhilePlaying && viewModel.isPlaying)
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
