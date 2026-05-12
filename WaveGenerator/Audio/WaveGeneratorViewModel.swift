import Combine
import Foundation

struct PulseSettings: Identifiable, Equatable, Codable {
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
    @Published var carrierHz: Double = 500 {
        didSet { persistSettings() }
    }
    @Published var pulses: [PulseSettings] = [PulseSettings()] {
        didSet { persistSettings() }
    }
    @Published var selectedPulseID: PulseSettings.ID? {
        didSet { persistSettings() }
    }
    @Published var transitionSeconds: Double = 15 {
        didSet { persistSettings() }
    }
    @Published var saveWAVOnStop = false {
        didSet {
            guard !isPlaying else {
                saveWAVOnStop = oldValue
                return
            }

            audioEngine.setRecordingEnabled(saveWAVOnStop)
            if saveWAVOnStop {
                lastSavedRecordingURL = nil
                recordingErrorMessage = nil
            }
        }
    }

    @Published private(set) var isQueueSaturated = false
    @Published private(set) var isApplyingSettings = false
    @Published private(set) var isSavingRecording = false
    @Published private(set) var lastSavedRecordingURL: URL?
    @Published private(set) var recordingErrorMessage: String?

    private let audioEngine = WaveAudioEngine()
    private var queueMonitorTask: Task<Void, Never>?
    private let settingsStore = WaveSettingsStore()
    private var hasConfiguredAudioState = false

    init() {
        restoreSettings()
    }

    var selectedPulse: PulseSettings? {
        if let selectedPulseID,
           let pulse = pulses.first(where: { $0.id == selectedPulseID }) {
            return pulse
        }

        return pulses.first
    }

    func pulseFrequencyRange(for id: PulseSettings.ID) -> ClosedRange<Double> {
        guard let index = pulses.firstIndex(where: { $0.id == id }) else {
            return 0.01...20
        }

        return pulseFrequencyRange(at: index)
    }

    func configureAudio() {
        if selectedPulseID == nil {
            selectedPulseID = pulses.first?.id
        }

        do {
            try audioEngine.startEngineIfNeeded()
            if !hasConfiguredAudioState {
                applyRestoredAudioState()
                hasConfiguredAudioState = true
            }
            startQueueMonitor()
        } catch {
            let nsError = error as NSError
            print("Audio engine start failed: \(error)")
            print("NSError domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
        }
    }

    func stopPlayback() {
        guard isPlaying else { return }

        isPlaying = false
        _ = audioEngine.stopTone(rampSeconds: transitionSeconds)

        if saveWAVOnStop {
            Task { [transitionSeconds] in
                let delay = UInt64(max(0, transitionSeconds) * 1_000_000_000)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                await saveLastMinuteRecording()
                saveWAVOnStop = false
            }
        }
    }

    func startPlayback() {
        guard !isPlaying else { return }

        isPlaying = true
        _ = audioEngine.startTone(rampSeconds: transitionSeconds)
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
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
            frequency: clamp(frequency, in: pulseFrequencyRange(at: index)),
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

    func saveLastMinuteRecording() async {
        guard !isSavingRecording else { return }

        isSavingRecording = true
        recordingErrorMessage = nil
        defer { isSavingRecording = false }

        do {
            lastSavedRecordingURL = try audioEngine.saveLastMinuteWAV()
        } catch {
            recordingErrorMessage = error.localizedDescription
        }
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

    private func pulseFrequencyRange(at index: Int) -> ClosedRange<Double> {
        let lowerBound = pulses.indices.contains(index + 1)
            ? max(0.01, pulses[index + 1].frequency)
            : 0.01
        let upperBound = index > 0
            ? max(lowerBound, pulses[index - 1].frequency)
            : 20

        return lowerBound...upperBound
    }

    private func clamp(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func applyRestoredAudioState() {
        _ = audioEngine.applyCarrierHz(carrierHz, durationSeconds: 0)

        if let firstPulse = pulses.first {
            _ = audioEngine.applyPulse(
                at: 0,
                frequency: firstPulse.frequency,
                wetness: firstPulse.wetness,
                volume: firstPulse.volume,
                durationSeconds: 0
            )
        } else {
            _ = audioEngine.removePulse(at: 0, durationSeconds: 0)
        }

        for pulse in pulses.dropFirst() {
            _ = audioEngine.addPulse(
                frequency: pulse.frequency,
                wetness: pulse.wetness,
                targetVolume: pulse.volume,
                durationSeconds: 0
            )
        }
    }

    private func restoreSettings() {
        guard let settings = settingsStore.load() else { return }

        carrierHz = max(200, settings.carrierHz)
        transitionSeconds = min(30, max(5, settings.transitionSeconds))
        pulses = Self.normalizedPulses(settings.pulses)
        selectedPulseID = pulses.contains(where: { $0.id == settings.selectedPulseID })
            ? settings.selectedPulseID
            : pulses.first?.id
    }

    private func persistSettings() {
        settingsStore.save(
            WaveGeneratorSettings(
                carrierHz: carrierHz,
                transitionSeconds: transitionSeconds,
                pulses: Self.normalizedPulses(pulses),
                selectedPulseID: selectedPulseID
            )
        )
    }

    private static func normalizedPulses(_ pulses: [PulseSettings]) -> [PulseSettings] {
        var previousFrequency = 20.0
        return pulses.map { pulse in
            let frequency = min(previousFrequency, max(0.01, pulse.frequency))
            previousFrequency = frequency
            return PulseSettings(
                id: pulse.id,
                frequency: frequency,
                wetness: min(1, max(0, pulse.wetness)),
                volume: min(1, max(0, pulse.volume)),
                isRemoving: false
            )
        }
    }
}

private struct WaveGeneratorSettings: Codable {
    var carrierHz: Double
    var transitionSeconds: Double
    var pulses: [PulseSettings]
    var selectedPulseID: PulseSettings.ID?
}

private final class WaveSettingsStore {
    private let key = "WaveGenerator.settings.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WaveGeneratorSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(WaveGeneratorSettings.self, from: data)
    }

    func save(_ settings: WaveGeneratorSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
