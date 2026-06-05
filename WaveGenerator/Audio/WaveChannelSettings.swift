import Foundation

struct WaveChannelSettings: Equatable, Codable {
    var carrierHz: Double
    var pulses: [PulseSettings]
    var selectedPulseID: PulseSettings.ID?

    init(
        carrierHz: Double = 500,
        pulses: [PulseSettings] = [PulseSettings()],
        selectedPulseID: PulseSettings.ID? = nil
    ) {
        self.carrierHz = carrierHz
        self.pulses = pulses
        self.selectedPulseID = selectedPulseID ?? pulses.first?.id
    }

    func copyWithFreshIDs() -> WaveChannelSettings {
        var selectedCopyID: PulseSettings.ID?
        let copiedPulses = pulses.map { pulse in
            let copiedID = UUID()
            if pulse.id == selectedPulseID {
                selectedCopyID = copiedID
            }

            return PulseSettings(
                id: copiedID,
                frequency: pulse.frequency,
                wetness: pulse.wetness,
                volume: pulse.volume,
                isRemoving: false
            )
        }

        return WaveChannelSettings(
            carrierHz: carrierHz,
            pulses: copiedPulses,
            selectedPulseID: selectedCopyID ?? copiedPulses.first?.id
        )
    }
}
