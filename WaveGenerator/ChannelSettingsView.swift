import SwiftUI

struct ChannelSettingsView: View {
    @ObservedObject var viewModel: WaveGeneratorViewModel
    let channel: WaveChannel
    @Binding var activeEditor: ParameterEditor?

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
                    HStack {
                        Text("Frequency")
                        Spacer()
                        Text("\(pulse.frequency, specifier: "%.2f") Hz")
                            .foregroundStyle(.secondary)
                        Button {
                            activeEditor = .pulseFrequency(channel, pulse.id)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit Pulse Frequency")
                        .disabled(viewModel.parameterControlsLocked || pulse.isRemoving)
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
