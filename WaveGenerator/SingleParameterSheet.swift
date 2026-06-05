import SwiftUI

struct SingleParameterSheet: View {
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
