import Foundation
import Combine

struct PulseSettings: Identifiable, Equatable {
    let id: UUID
    var frequency: Double
    var wetness: Double
    var volume: Double
    var isRemoving: Bool

    init(
        id: UUID = UUID(),
        frequency: Double = 1,
        wetness: Double = 0,
        volume: Double = 1,
        isRemoving: Bool = false
    ) {
        self.id = id
        self.frequency = frequency
        self.wetness = wetness
        self.volume = volume
        self.isRemoving = isRemoving
    }
}

@MainActor
final class WaveGeneratorViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var carrierHz: Double = 500
    @Published var pulses: [PulseSettings] = [PulseSettings()]
    @Published var selectedPulseID: PulseSettings.ID?
    @Published var transitionSeconds: Double = 15

    @Published private(set) var isQueueSaturated = false
    @Published private(set) var isApplyingSettings = false

    private let audioEngine = WaveAudioEngine()
    private var queueMonitorTask: Task<Void, Never>?

    var selectedPulse: PulseSettings? {
        if let selectedPulseID,
           let pulse = pulses.first(where: { $0.id == selectedPulseID }) {
            return pulse
        }

        return pulses.first
    }

    func configureAudio() {
        if selectedPulseID == nil {
            selectedPulseID = pulses.first?.id
        }

        do {
            try audioEngine.startEngineIfNeeded()
            _ = audioEngine.applyParameters(
                carrierHz: carrierHz,
                pulseHz: pulses.first?.frequency ?? 1,
                wetness: pulses.first?.wetness ?? 0,
                pulseVolume: pulses.first?.volume ?? 1,
                durationSeconds: 0.01
            )
            startQueueMonitor()
        } catch {
            let nsError = error as NSError
            print("Audio engine start failed: \(error)")
            print("NSError domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            _ = audioEngine.startTone(rampSeconds: transitionSeconds)
        } else {
            _ = audioEngine.stopTone(rampSeconds: transitionSeconds)
        }
    }

    func applyCarrierHz(_ carrierHz: Double) async -> Bool {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let carrier = max(200, carrierHz)
        let durationSeconds = isPlaying ? transitionSeconds : 0

        let accepted = await retryUntilAccepted {
            audioEngine.applyCarrierHz(carrier, durationSeconds: durationSeconds)
        }

        if accepted {
            self.carrierHz = carrier
        }

        return accepted
    }

    func applyPulse(
        id: PulseSettings.ID,
        frequency: Double,
        wetness: Double,
        volume: Double
    ) async -> Bool {
        guard let index = pulses.firstIndex(where: { $0.id == id }) else {
            return false
        }

        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let pulse = PulseSettings(
            id: id,
            frequency: max(0, frequency),
            wetness: min(1, max(0, wetness)),
            volume: min(1, max(0, volume)),
            isRemoving: pulses[index].isRemoving
        )
        let currentPulse = pulses[index]
        let isSilentTuning = currentPulse.volume == 0 && pulse.volume == currentPulse.volume
        let durationSeconds = isPlaying && !isSilentTuning ? transitionSeconds : 0

        let accepted = await retryUntilAccepted {
            audioEngine.applyPulse(
                at: index,
                frequency: pulse.frequency,
                wetness: pulse.wetness,
                volume: pulse.volume,
                durationSeconds: durationSeconds
            )
        }

        if accepted, let currentIndex = pulses.firstIndex(where: { $0.id == id }) {
            pulses[currentIndex] = pulse
        }

        return accepted
    }

    func addPulse() async -> Bool {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let source = pulses.last ?? PulseSettings()
        let newPulse = PulseSettings(
            frequency: source.frequency,
            wetness: source.wetness,
            volume: 0
        )

        let accepted = await retryUntilAccepted {
            audioEngine.addPulse(
                frequency: newPulse.frequency,
                wetness: newPulse.wetness,
                targetVolume: newPulse.volume,
                durationSeconds: 0
            )
        }

        if accepted {
            pulses.append(newPulse)
            selectedPulseID = newPulse.id
        }

        return accepted
    }

    func removeSelectedPulse() async -> Bool {
        guard let pulse = selectedPulse,
              let index = pulses.firstIndex(where: { $0.id == pulse.id }) else {
            return false
        }

        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let durationSeconds = isPlaying ? transitionSeconds : 0
        let accepted = await retryUntilAccepted {
            audioEngine.removePulse(at: index, durationSeconds: durationSeconds)
        }

        guard accepted else { return false }

        pulses[index].volume = 0
        pulses[index].isRemoving = true
        if durationSeconds > 0 {
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
        }

        if let currentIndex = pulses.firstIndex(where: { $0.id == pulse.id }) {
            pulses.remove(at: currentIndex)
        }

        selectedPulseID = pulses.indices.contains(index)
            ? pulses[index].id
            : pulses.last?.id

        return true
    }

    func applyTransitionSeconds(_ seconds: Double) async -> Bool {
        transitionSeconds = min(30, max(5, seconds))
        return true
    }

    deinit {
        queueMonitorTask?.cancel()
    }

    private func startQueueMonitor() {
        queueMonitorTask?.cancel()
        queueMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.isQueueSaturated = self.audioEngine.isCommandQueueFull()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func retryUntilAccepted(_ apply: () -> Bool) async -> Bool {
        while !Task.isCancelled {
            if apply() {
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
    }
}
