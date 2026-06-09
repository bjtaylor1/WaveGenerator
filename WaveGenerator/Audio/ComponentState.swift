import Foundation

nonisolated final class ComponentState {
    let mode: ComponentMode
    let minimumFrequency: Double
    var phase: Double = 0

    let frequency: RampedParameter
    let wetness: RampedParameter
    let volume: RampedParameter
    var pendingRemovalFrame: Int64?

    init(
        mode: ComponentMode,
        minimumFrequency: Double,
        initialFrequency: Double,
        initialWetness: Double,
        initialVolume: Double
    ) {
        self.mode = mode
        self.minimumFrequency = minimumFrequency
        self.frequency = RampedParameter(initialValue: initialFrequency)
        self.wetness = RampedParameter(initialValue: initialWetness)
        self.volume = RampedParameter(initialValue: initialVolume)
    }

    func amplitude(at frame: Int64, sampleRate: Double) -> Double {
        let hz = max(minimumFrequency, frequency.value(at: frame))
        phase += 2 * .pi * hz / sampleRate
        if phase >= 2 * .pi {
            phase.formTruncatingRemainder(dividingBy: 2 * .pi)
        }

        switch mode {
        case .bipolarSine:
            return sin(phase)
        case .unipolarPulse:
            let wetnessValue = min(1, max(0, wetness.value(at: frame)))
            let volumeValue = min(1, max(0, volume.value(at: frame)))
            let pulse = (sin(phase) + 1) * 0.5
            let envelope = wetnessValue + (1 - wetnessValue) * pulse
            return 1 + volumeValue * (envelope - 1)
        }
    }
}
