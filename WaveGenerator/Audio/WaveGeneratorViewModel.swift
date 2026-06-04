import Combine
import Foundation

enum WaveChannel: String, CaseIterable, Identifiable, Codable {
    case left
    case right

    var id: Self { self }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var engineChannelIndex: Int {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }
}

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

    private enum CodingKeys: String, CodingKey {
        case id
        case frequency
        case wetness
        case volume
        case isRemoving
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        frequency = try container.decode(Double.self, forKey: .frequency)
        wetness = try container.decode(Double.self, forKey: .wetness)
        volume = try container.decode(Double.self, forKey: .volume)
        isRemoving = try container.decodeIfPresent(Bool.self, forKey: .isRemoving) ?? false
    }
}

private struct WaveChannelSettings: Equatable, Codable {
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

@MainActor
final class WaveGeneratorViewModel: ObservableObject {
    private static let pulseFrequencyRange: ClosedRange<Double> = 0...5

    @Published var isPlaying = false
    @Published private(set) var isStereo = false
    @Published var selectedChannel: WaveChannel = .left
    @Published private var monoSettings = WaveChannelSettings()
    @Published private var leftSettings = WaveChannelSettings()
    @Published private var rightSettings = WaveChannelSettings()
    @Published var transitionSeconds: Double = 15
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

    var parameterControlsLocked: Bool {
        isApplyingSettings || isQueueSaturated
    }

    var settingsSheetLocked: Bool {
        isPlaying || parameterControlsLocked
    }

    func carrierHz(for channel: WaveChannel) -> Double {
        channelSettings(for: channel).carrierHz
    }

    func pulses(for channel: WaveChannel) -> [PulseSettings] {
        channelSettings(for: channel).pulses
    }

    func selectedPulse(for channel: WaveChannel) -> PulseSettings? {
        let settings = channelSettings(for: channel)
        if let selectedPulseID = settings.selectedPulseID,
           let pulse = settings.pulses.first(where: { $0.id == selectedPulseID }) {
            return pulse
        }

        return settings.pulses.first
    }

    func selectedPulseIndex(for channel: WaveChannel) -> Int? {
        guard let selectedPulse = selectedPulse(for: channel) else { return nil }
        return pulses(for: channel).firstIndex(where: { $0.id == selectedPulse.id })
    }

    func setSelectedPulseID(_ id: PulseSettings.ID?, for channel: WaveChannel) {
        updateSettings(for: channel) { settings in
            settings.selectedPulseID = id
        }
    }

    func pulseFrequencyRange(for id: PulseSettings.ID, in channel: WaveChannel) -> ClosedRange<Double> {
        Self.pulseFrequencyRange
    }

    func setStereoEnabled(_ enabled: Bool) {
        guard !isPlaying, enabled != isStereo else { return }

        if enabled {
            leftSettings = monoSettings.copyWithFreshIDs()
            rightSettings = monoSettings.copyWithFreshIDs()
            selectedChannel = .left
        } else {
            monoSettings = channelSettings(for: selectedChannel).copyWithFreshIDs()
        }

        isStereo = enabled
        persistSettings()
        applyAllSettingsToEngine()
    }

    func configureAudio() {
        normalizeAllSettings()

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
        guard !isPlaying, !isApplyingSettings, !isQueueSaturated else { return }

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

    func applyCarrierHz(_ carrierHz: Double, channel: WaveChannel) async -> Bool {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let carrier = max(200, carrierHz)
        let durationSeconds = isPlaying ? transitionSeconds : 0
        let accepted = await retryUntilAccepted {
            audioEngine.applyCarrierHz(
                carrier,
                channelIndex: engineChannelIndex(for: channel),
                durationSeconds: durationSeconds
            )
        }

        if accepted {
            updateSettings(for: channel) { settings in
                settings.carrierHz = carrier
            }
        }

        return accepted
    }

    func applyPulse(
        id: PulseSettings.ID,
        channel: WaveChannel,
        frequency: Double,
        wetness: Double,
        volume: Double
    ) async -> Bool {
        let settings = channelSettings(for: channel)
        guard let index = settings.pulses.firstIndex(where: { $0.id == id }) else {
            return false
        }

        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let pulse = PulseSettings(
            id: id,
            frequency: clamp(frequency, in: Self.pulseFrequencyRange),
            wetness: min(1, max(0, wetness)),
            volume: min(1, max(0, volume)),
            isRemoving: settings.pulses[index].isRemoving
        )
        let normalizedPulses = Self.normalizedPulses(
            replacing: index,
            with: pulse,
            in: settings.pulses
        )
        let normalizedPulse = normalizedPulses[index]
        let currentPulse = settings.pulses[index]
        let isSilentTuning = currentPulse.volume == 0 && normalizedPulse.volume == currentPulse.volume
        let durationSeconds = isPlaying && !isSilentTuning ? transitionSeconds : 0

        let accepted = await retryUntilAccepted {
            audioEngine.applyPulse(
                at: index,
                channelIndex: engineChannelIndex(for: channel),
                frequency: normalizedPulse.frequency,
                wetness: normalizedPulse.wetness,
                volume: normalizedPulse.volume,
                durationSeconds: durationSeconds
            )
        }

        if accepted {
            updateSettings(for: channel) { settings in
                settings.pulses = normalizedPulses
                settings.selectedPulseID = normalizedPulses.contains(where: { $0.id == id })
                    ? id
                    : normalizedPulses.first?.id
            }
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

    func addPulse(to channel: WaveChannel) async -> Bool {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let settings = channelSettings(for: channel)
        let source = settings.pulses.last ?? PulseSettings()
        let newPulse = PulseSettings(
            frequency: source.frequency,
            wetness: source.wetness,
            volume: 0
        )

        let accepted = await retryUntilAccepted {
            audioEngine.addPulse(
                channelIndex: engineChannelIndex(for: channel),
                frequency: newPulse.frequency,
                wetness: newPulse.wetness,
                targetVolume: newPulse.volume,
                durationSeconds: 0
            )
        }

        if accepted {
            updateSettings(for: channel) { settings in
                settings.pulses = Self.normalizedPulses(settings.pulses + [newPulse])
                settings.selectedPulseID = newPulse.id
            }
        }

        return accepted
    }

    func removeSelectedPulse(from channel: WaveChannel) async -> Bool {
        let settings = channelSettings(for: channel)
        guard let pulse = selectedPulse(for: channel),
              let index = settings.pulses.firstIndex(where: { $0.id == pulse.id }) else {
            return false
        }

        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let durationSeconds = isPlaying ? transitionSeconds : 0
        let accepted = await retryUntilAccepted {
            audioEngine.removePulse(
                at: index,
                channelIndex: engineChannelIndex(for: channel),
                durationSeconds: durationSeconds
            )
        }

        guard accepted else { return false }

        if durationSeconds > 0 {
            updateSettings(for: channel) { settings in
                guard settings.pulses.indices.contains(index) else { return }
                settings.pulses[index].volume = 0
            }
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
        }

        let latestSettings = channelSettings(for: channel)
        guard let currentIndex = latestSettings.pulses.firstIndex(where: { $0.id == pulse.id }) else {
            return true
        }

        let updatedPulses = Self.normalizedPulses(removing: currentIndex, from: latestSettings.pulses)
        updateSettings(for: channel) { settings in
            settings.pulses = updatedPulses
            settings.selectedPulseID = updatedPulses.indices.contains(currentIndex)
                ? updatedPulses[currentIndex].id
                : updatedPulses.last?.id
        }

        if currentIndex == 0 {
            await applyCurrentPulsesToEngine(for: channel, durationSeconds: 0)
        }

        return true
    }

    func applyTransitionSeconds(_ seconds: Double) async -> Bool {
        guard !isPlaying else { return false }

        transitionSeconds = min(30, max(5, seconds))
        persistSettings()
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

    private func channelSettings(for channel: WaveChannel) -> WaveChannelSettings {
        guard isStereo else { return monoSettings }

        switch channel {
        case .left:
            return leftSettings
        case .right:
            return rightSettings
        }
    }

    private func updateSettings(
        for channel: WaveChannel,
        _ update: (inout WaveChannelSettings) -> Void
    ) {
        var settings = channelSettings(for: channel)
        update(&settings)
        settings = Self.normalizedSettings(settings)

        if isStereo {
            switch channel {
            case .left:
                leftSettings = settings
            case .right:
                rightSettings = settings
            }
        } else {
            monoSettings = settings
        }

        persistSettings()
    }

    private func engineChannelIndex(for channel: WaveChannel) -> Int {
        isStereo ? channel.engineChannelIndex : WaveChannel.left.engineChannelIndex
    }

    private func clamp(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func applyCurrentPulsesToEngine(for channel: WaveChannel, durationSeconds: Double) async {
        let settings = channelSettings(for: channel)
        for (index, pulse) in settings.pulses.enumerated() {
            _ = await retryUntilAccepted {
                audioEngine.applyPulse(
                    at: index,
                    channelIndex: engineChannelIndex(for: channel),
                    frequency: pulse.frequency,
                    wetness: pulse.wetness,
                    volume: pulse.volume,
                    durationSeconds: durationSeconds
                )
            }
        }
    }

    private func applyRestoredAudioState() {
        applyAllSettingsToEngine()
    }

    private func applyAllSettingsToEngine() {
        if isStereo {
            applySettingsToEngine(leftSettings, channel: .left)
            applySettingsToEngine(rightSettings, channel: .right)
        } else {
            applySettingsToEngine(monoSettings, channel: .left)
        }

        _ = audioEngine.setStereoEnabled(isStereo)
    }

    private func applySettingsToEngine(_ settings: WaveChannelSettings, channel: WaveChannel) {
        let channelIndex = channel.engineChannelIndex
        _ = audioEngine.applyCarrierHz(
            settings.carrierHz,
            channelIndex: channelIndex,
            durationSeconds: 0
        )
        _ = audioEngine.removeAllPulses(channelIndex: channelIndex)

        for pulse in settings.pulses {
            _ = audioEngine.addPulse(
                channelIndex: channelIndex,
                frequency: pulse.frequency,
                wetness: pulse.wetness,
                targetVolume: pulse.volume,
                durationSeconds: 0
            )
        }
    }

    private func restoreSettings() {
        guard let settings = settingsStore.load() else { return }

        let restoredMono = WaveChannelSettings(
            carrierHz: settings.carrierHz,
            pulses: settings.pulses,
            selectedPulseID: settings.selectedPulseID
        )

        monoSettings = Self.normalizedSettings(restoredMono)
        leftSettings = Self.normalizedSettings(settings.leftChannel ?? monoSettings.copyWithFreshIDs())
        rightSettings = Self.normalizedSettings(settings.rightChannel ?? monoSettings.copyWithFreshIDs())
        transitionSeconds = min(30, max(5, settings.transitionSeconds))
        isStereo = settings.stereo ?? false
        selectedChannel = settings.selectedChannel ?? .left
    }

    private func persistSettings() {
        let normalizedMono = Self.normalizedSettings(monoSettings)
        settingsStore.save(
            WaveGeneratorSettings(
                carrierHz: normalizedMono.carrierHz,
                transitionSeconds: transitionSeconds,
                pulses: normalizedMono.pulses,
                selectedPulseID: normalizedMono.selectedPulseID,
                stereo: isStereo,
                selectedChannel: selectedChannel,
                leftChannel: Self.normalizedSettings(leftSettings),
                rightChannel: Self.normalizedSettings(rightSettings)
            )
        )
    }

    private func normalizeAllSettings() {
        monoSettings = Self.normalizedSettings(monoSettings)
        leftSettings = Self.normalizedSettings(leftSettings)
        rightSettings = Self.normalizedSettings(rightSettings)
    }

    private static func normalizedSettings(_ settings: WaveChannelSettings) -> WaveChannelSettings {
        let normalizedPulses = normalizedPulses(settings.pulses)
        let selectedPulseID = normalizedPulses.contains(where: { $0.id == settings.selectedPulseID })
            ? settings.selectedPulseID
            : normalizedPulses.first?.id

        return WaveChannelSettings(
            carrierHz: max(200, settings.carrierHz),
            pulses: normalizedPulses,
            selectedPulseID: selectedPulseID
        )
    }

    private static func normalizedPulses(_ pulses: [PulseSettings]) -> [PulseSettings] {
        pulses.map { pulse in
            PulseSettings(
                id: pulse.id,
                frequency: clampFrequency(pulse.frequency),
                wetness: min(1, max(0, pulse.wetness)),
                volume: min(1, max(0, pulse.volume)),
                isRemoving: false
            )
        }
    }

    private static func normalizedPulses(
        replacing index: Int,
        with pulse: PulseSettings,
        in pulses: [PulseSettings]
    ) -> [PulseSettings] {
        guard pulses.indices.contains(index) else { return normalizedPulses(pulses) }

        var updatedPulses = pulses
        updatedPulses[index] = pulse
        return normalizedPulses(updatedPulses)
    }

    private static func normalizedPulses(removing index: Int, from pulses: [PulseSettings]) -> [PulseSettings] {
        guard pulses.indices.contains(index) else { return normalizedPulses(pulses) }

        var updatedPulses = pulses
        updatedPulses.remove(at: index)

        return normalizedPulses(updatedPulses)
    }

    private static func clampFrequency(_ frequency: Double) -> Double {
        min(Self.pulseFrequencyRange.upperBound, max(Self.pulseFrequencyRange.lowerBound, frequency))
    }
}

private struct WaveGeneratorSettings: Codable {
    var carrierHz: Double
    var transitionSeconds: Double
    var pulses: [PulseSettings]
    var selectedPulseID: PulseSettings.ID?
    var stereo: Bool?
    var selectedChannel: WaveChannel?
    var leftChannel: WaveChannelSettings?
    var rightChannel: WaveChannelSettings?
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
