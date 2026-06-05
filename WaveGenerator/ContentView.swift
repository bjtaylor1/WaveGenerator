import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WaveGeneratorViewModel()
    @State private var activeEditor: ParameterEditor?
    @State private var isSettingsPresented = false

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
        .blur(radius: activeEditor == nil ? 0 : 3)
        .opacity(activeEditor == nil ? 1 : 0.65)
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
                    wetness: pulse.wetness,
                    volume: value
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
