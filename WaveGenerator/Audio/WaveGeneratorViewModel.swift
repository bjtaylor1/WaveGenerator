import Combine
import Foundation

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

    @Published private(set) var isQueueSaturated = false
    @Published private(set) var isApplyingSettings = false
    @Published private(set) var sessionHistory: [WaveSessionRecord] = []
    @Published private(set) var isFilePlaybackActive = false
    @Published private(set) var isStoppingPlayback = false
    @Published private(set) var isRenderingSessionWAV = false
    @Published private(set) var isValidatingSessionFile = false
    @Published private(set) var pendingSessionFilename: String?
    @Published private(set) var loadedSessionFile: LoadedSessionFile?
    @Published private(set) var filePlaybackRemainingText: String?
    @Published private(set) var lastRenderedWAVURL: URL?
    @Published var sessionHistoryErrorMessage: String?

    private let audioEngine = WaveAudioEngine()
    private var queueMonitorTask: Task<Void, Never>?
    private var filePlaybackTask: Task<Void, Never>?
    private var stopPlaybackTask: Task<Void, Never>?
    private let settingsStore = WaveSettingsStore()
    private let sessionHistoryStore = WaveSessionHistoryStore()
    private let sessionRecorder = WaveSessionRecorder()
    private var hasConfiguredAudioState = false

    init() {
        restoreSettings()
        sessionHistory = sessionHistoryStore.load()
    }

    var parameterControlsLocked: Bool {
        isApplyingSettings || isQueueSaturated || isFilePlaybackActive || isStoppingPlayback
    }

    var settingsSheetLocked: Bool {
        isPlaying || parameterControlsLocked
    }

    var sessionFileActionsLocked: Bool {
        isPlaying
            || isStoppingPlayback
            || isApplyingSettings
            || isQueueSaturated
            || isRenderingSessionWAV
            || isValidatingSessionFile
    }

    var playbackButtonTitle: String {
        if isStoppingPlayback {
            return "Stopping..."
        }

        if isFilePlaybackActive {
            return "Stop File"
        }

        return isPlaying ? "Stop Tone" : "Start Tone"
    }

    var playbackButtonDisabled: Bool {
        if isStoppingPlayback {
            return true
        }

        return !isPlaying && parameterControlsLocked
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
        guard isPlaying, !isStoppingPlayback else { return }

        let timeline = audioEngine.timelineSnapshot()
        let transitionFrameCount = audioEngine.durationFrames(for: transitionSeconds)
        guard audioEngine.stopTone(rampSeconds: transitionSeconds) else { return }
        isStoppingPlayback = true
        if let session = sessionRecorder.finishSession(
            timeline: timeline,
            transitionFrameCount: transitionFrameCount
        ) {
            sessionHistory = sessionHistoryStore.add(session)
        }

        stopPlaybackTask?.cancel()
        stopPlaybackTask = Task { [weak self] in
            await self?.finishStoppingPlayback(
                atFrame: timeline.framePosition + transitionFrameCount
            )
        }
    }

    func startPlayback() {
        guard !isPlaying, !isFilePlaybackActive, !isStoppingPlayback, !isApplyingSettings, !isQueueSaturated else { return }

        let timeline = audioEngine.timelineSnapshot()
        let transitionFrameCount = audioEngine.durationFrames(for: transitionSeconds)
        guard audioEngine.startTone(rampSeconds: transitionSeconds) else { return }

        sessionRecorder.beginSession(
            initialSettings: currentSettingsSnapshot(),
            timeline: timeline,
            transitionFrameCount: transitionFrameCount
        )
        isPlaying = true
    }

    func togglePlayback() {
        if isFilePlaybackActive {
            stopFilePlayback()
            return
        }

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
        let transitionFrameCount = audioEngine.durationFrames(for: durationSeconds)
        guard let acceptedTimeline = await retryUntilAcceptedWithTimeline({
            audioEngine.applyCarrierHz(
                carrier,
                channelIndex: engineChannelIndex(for: channel),
                durationSeconds: durationSeconds
            )
        }) else { return false }

        updateSettings(for: channel) { settings in
            settings.carrierHz = carrier
        }
        recordSessionEvent(
            kind: .carrierChanged,
            channel: channel,
            carrierHz: carrier,
            transitionFrameCount: transitionFrameCount,
            timeline: acceptedTimeline
        )

        return true
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
        let transitionFrameCount = audioEngine.durationFrames(for: durationSeconds)

        guard let acceptedTimeline = await retryUntilAcceptedWithTimeline({
            audioEngine.applyPulse(
                at: index,
                channelIndex: engineChannelIndex(for: channel),
                frequency: normalizedPulse.frequency,
                wetness: normalizedPulse.wetness,
                volume: normalizedPulse.volume,
                durationSeconds: durationSeconds
            )
        }) else { return false }

        updateSettings(for: channel) { settings in
            settings.pulses = normalizedPulses
            settings.selectedPulseID = normalizedPulses.contains(where: { $0.id == id })
                ? id
                : normalizedPulses.first?.id
        }
        recordSessionEvent(
            kind: .pulseChanged,
            channel: channel,
            pulseID: id,
            pulseIndex: index,
            frequency: normalizedPulse.frequency,
            wetness: normalizedPulse.wetness,
            volume: normalizedPulse.volume,
            transitionFrameCount: transitionFrameCount,
            timeline: acceptedTimeline
        )

        return true
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

        guard let acceptedTimeline = await retryUntilAcceptedWithTimeline({
            audioEngine.addPulse(
                channelIndex: engineChannelIndex(for: channel),
                frequency: newPulse.frequency,
                wetness: newPulse.wetness,
                targetVolume: newPulse.volume,
                durationSeconds: 0
            )
        }) else { return false }

        updateSettings(for: channel) { settings in
            settings.pulses = Self.normalizedPulses(settings.pulses + [newPulse])
            settings.selectedPulseID = newPulse.id
        }
        recordSessionEvent(
            kind: .pulseAdded,
            channel: channel,
            pulseID: newPulse.id,
            pulseIndex: settings.pulses.count,
            frequency: newPulse.frequency,
            wetness: newPulse.wetness,
            volume: newPulse.volume,
            transitionFrameCount: 0,
            timeline: acceptedTimeline
        )

        return true
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
        let transitionFrameCount = audioEngine.durationFrames(for: durationSeconds)
        guard let acceptedTimeline = await retryUntilAcceptedWithTimeline({
            audioEngine.removePulse(
                at: index,
                channelIndex: engineChannelIndex(for: channel),
                durationSeconds: durationSeconds
            )
        }) else { return false }

        recordSessionEvent(
            kind: .pulseRemoved,
            channel: channel,
            pulseID: pulse.id,
            pulseIndex: index,
            transitionFrameCount: transitionFrameCount,
            timeline: acceptedTimeline
        )

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

    func makeSessionExportDocument(for session: WaveSessionRecord) -> WaveSessionExportDocument? {
        do {
            sessionHistoryErrorMessage = nil
            return try WaveSessionExportDocument(session: session)
        } catch {
            sessionHistoryErrorMessage = error.localizedDescription
            return nil
        }
    }

    func setSessionHistoryExportError(_ error: Error) {
        sessionHistoryErrorMessage = error.localizedDescription
    }

    func loadSessionFile(at url: URL) async -> Bool {
        guard !sessionFileActionsLocked else { return false }

        let filename = url.lastPathComponent
        sessionHistoryErrorMessage = nil
        loadedSessionFile = nil
        pendingSessionFilename = filename
        isValidatingSessionFile = true
        defer {
            isValidatingSessionFile = false
            pendingSessionFilename = nil
        }

        do {
            let session = try await Task.detached {
                try WaveSessionFileLoader.load(from: url)
            }.value
            let validationErrors = await Task.detached {
                WaveSessionFileValidator.validationErrors(for: session)
            }.value

            guard validationErrors.isEmpty else {
                sessionHistoryErrorMessage = sessionFileValidationMessage(
                    filename: filename,
                    errors: validationErrors
                )
                return false
            }

            loadedSessionFile = LoadedSessionFile(
                filename: filename,
                session: session
            )
            return true
        } catch {
            sessionHistoryErrorMessage = error.localizedDescription
            return false
        }
    }

    func playHistorySession(_ session: WaveSessionRecord) async -> Bool {
        await playSession(WaveSessionExport(session: session))
    }

    func playLoadedSessionFile() async -> Bool {
        guard let loadedSessionFile else { return false }

        let started = await playSession(loadedSessionFile.session)
        if started {
            self.loadedSessionFile = nil
        }

        return started
    }

    func renderHistorySessionWAV(_ session: WaveSessionRecord) async -> Bool {
        await renderSessionWAV(WaveSessionExport(session: session))
    }

    func renderSessionFileWAV(at url: URL) async -> Bool {
        do {
            let session = try WaveSessionFileLoader.load(from: url)
            let validationErrors = WaveSessionFileValidator.validationErrors(for: session)
            guard validationErrors.isEmpty else {
                sessionHistoryErrorMessage = sessionFileValidationMessage(
                    filename: url.lastPathComponent,
                    errors: validationErrors
                )
                return false
            }

            return await renderSessionWAV(session)
        } catch {
            sessionHistoryErrorMessage = error.localizedDescription
            return false
        }
    }

    func stopFilePlayback() {
        guard isFilePlaybackActive else { return }

        filePlaybackRemainingText = nil
        filePlaybackTask?.cancel()
        filePlaybackTask = nil
        finishFilePlayback(restoreSettings: true, stopTone: true)
    }

    deinit {
        queueMonitorTask?.cancel()
        filePlaybackTask?.cancel()
        stopPlaybackTask?.cancel()
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

    private func retryUntilAcceptedWithTimeline(_ apply: () -> Bool) async -> WaveAudioTimelineSnapshot? {
        while !Task.isCancelled {
            let timeline = audioEngine.timelineSnapshot()
            if apply() {
                return timeline
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return nil
    }

    private func finishStoppingPlayback(atFrame targetFrame: Int64) async {
        while !Task.isCancelled,
              audioEngine.timelineSnapshot().framePosition < targetFrame {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard !Task.isCancelled else { return }

        isPlaying = false
        isStoppingPlayback = false
        stopPlaybackTask = nil
    }

    private func updateFilePlaybackRemaining(
        in session: WaveSessionExport,
        liveStartTimeline: WaveAudioTimelineSnapshot
    ) {
        let liveTimeline = audioEngine.timelineSnapshot()
        let totalLiveOffset = session.liveFrameOffset(
            for: session.renderDurationFrames,
            liveSampleRate: liveStartTimeline.sampleRate
        )
        let (targetFrame, overflow) = liveStartTimeline.framePosition.addingReportingOverflow(totalLiveOffset)
        guard !overflow, liveStartTimeline.sampleRate > 0 else {
            filePlaybackRemainingText = nil
            return
        }

        let remainingLiveFrames = max(0, targetFrame - liveTimeline.framePosition)
        filePlaybackRemainingText = WaveDurationFormatter.formatted(
            seconds: Double(remainingLiveFrames) / liveStartTimeline.sampleRate
        )
    }

    private func sessionFileValidationMessage(filename: String, errors: [String]) -> String {
        (
            ["Session file \(filename) has errors:"]
                + errors.map { "- \($0)" }
        ).joined(separator: "\n")
    }

    private func playSession(_ session: WaveSessionExport) async -> Bool {
        guard !isPlaying, !isStoppingPlayback, !isRenderingSessionWAV, !isApplyingSettings, !isQueueSaturated else {
            return false
        }

        sessionHistoryErrorMessage = nil
        let restoreSnapshot = currentSettingsSnapshot()
        await applySessionInitialSettingsToEngine(session)

        let startEvent = session.events.first { event in
            event.kind == .startPlayback
        }
        let startRampSeconds = session.seconds(forFrameCount: startEvent?.transitionFrameCount ?? 0)
        guard await retryUntilAccepted({
            audioEngine.startTone(rampSeconds: startRampSeconds)
        }) else {
            return false
        }

        let liveStartTimeline = audioEngine.timelineSnapshot()
        isFilePlaybackActive = true
        isPlaying = true
        updateFilePlaybackRemaining(
            in: session,
            liveStartTimeline: liveStartTimeline
        )
        filePlaybackTask?.cancel()
        filePlaybackTask = Task { [weak self] in
            await self?.runFilePlayback(
                session,
                liveStartTimeline: liveStartTimeline,
                restoreSnapshot: restoreSnapshot
            )
        }

        return true
    }

    private func runFilePlayback(
        _ session: WaveSessionExport,
        liveStartTimeline: WaveAudioTimelineSnapshot,
        restoreSnapshot: WaveGeneratorSettings
    ) async {
        let sortedEvents = session.events.sorted { lhs, rhs in
            lhs.frameOffset < rhs.frameOffset
        }

        for event in sortedEvents where event.kind != .startPlayback {
            await waitForSessionFrame(
                event.frameOffset,
                in: session,
                liveStartTimeline: liveStartTimeline
            )
            guard !Task.isCancelled else { return }
            await applySessionEventToEngine(event, in: session)
        }

        await waitForSessionFrame(
            session.renderDurationFrames,
            in: session,
            liveStartTimeline: liveStartTimeline
        )
        guard !Task.isCancelled else { return }

        if !sortedEvents.contains(where: { $0.kind == .stopPlayback }) {
            _ = await retryUntilAccepted {
                audioEngine.stopTone(rampSeconds: 0)
            }
        }

        finishFilePlayback(restoreSettings: restoreSnapshot, stopTone: false)
    }

    private func waitForSessionFrame(
        _ frameOffset: Int64,
        in session: WaveSessionExport,
        liveStartTimeline: WaveAudioTimelineSnapshot
    ) async {
        let liveOffset = session.liveFrameOffset(
            for: frameOffset,
            liveSampleRate: liveStartTimeline.sampleRate
        )
        let targetFrame = liveStartTimeline.framePosition + liveOffset

        while !Task.isCancelled,
              audioEngine.timelineSnapshot().framePosition < targetFrame {
            updateFilePlaybackRemaining(
                in: session,
                liveStartTimeline: liveStartTimeline
            )
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard !Task.isCancelled else { return }

        updateFilePlaybackRemaining(
            in: session,
            liveStartTimeline: liveStartTimeline
        )
    }

    private func applySessionEventToEngine(_ event: WaveSessionExportEvent, in session: WaveSessionExport) async {
        let durationSeconds = session.seconds(forFrameCount: event.transitionFrameCount ?? 0)

        switch event.kind {
        case .startPlayback:
            break
        case .stopPlayback:
            _ = await retryUntilAccepted {
                audioEngine.stopTone(rampSeconds: durationSeconds)
            }
        case .carrierChanged:
            guard let carrierHz = event.carrierHz else { return }
            _ = await retryUntilAccepted {
                audioEngine.applyCarrierHz(
                    carrierHz,
                    channelIndex: sessionEngineChannelIndex(for: event.channel, isStereo: session.isStereo),
                    durationSeconds: durationSeconds
                )
            }
        case .pulseChanged:
            guard let pulseIndex = event.pulseIndex else { return }
            _ = await retryUntilAccepted {
                audioEngine.applyPulse(
                    at: pulseIndex,
                    channelIndex: sessionEngineChannelIndex(for: event.channel, isStereo: session.isStereo),
                    frequency: event.frequency ?? 0,
                    wetness: event.wetness ?? 0,
                    volume: event.volume ?? 0,
                    durationSeconds: durationSeconds
                )
            }
        case .pulseAdded:
            _ = await retryUntilAccepted {
                audioEngine.addPulse(
                    channelIndex: sessionEngineChannelIndex(for: event.channel, isStereo: session.isStereo),
                    frequency: event.frequency ?? 0,
                    wetness: event.wetness ?? 0,
                    targetVolume: event.volume ?? 0,
                    durationSeconds: durationSeconds
                )
            }
        case .pulseRemoved:
            guard let pulseIndex = event.pulseIndex else { return }
            _ = await retryUntilAccepted {
                audioEngine.removePulse(
                    at: pulseIndex,
                    channelIndex: sessionEngineChannelIndex(for: event.channel, isStereo: session.isStereo),
                    durationSeconds: durationSeconds
                )
            }
        }
    }

    private func applySessionInitialSettingsToEngine(_ session: WaveSessionExport) async {
        if session.isStereo {
            await applyChannelSettingsToEngine(session.channelSettings(for: .left), channel: .left)
            await applyChannelSettingsToEngine(session.channelSettings(for: .right), channel: .right)
        } else {
            await applyChannelSettingsToEngine(session.channelSettings(for: .left), channel: .left)
        }

        _ = await retryUntilAccepted {
            audioEngine.setStereoEnabled(session.isStereo)
        }
    }

    private func applySettingsSnapshotToEngine(_ snapshot: WaveGeneratorSettings) async {
        let session = WaveSessionExport(
            session: WaveSessionRecord(
                id: UUID(),
                startedAt: Date(),
                sampleRate: audioEngine.timelineSnapshot().sampleRate,
                durationFrames: 0,
                initialSettings: snapshot,
                events: []
            )
        )

        await applySessionInitialSettingsToEngine(session)
    }

    private func applyChannelSettingsToEngine(_ settings: WaveChannelSettings, channel: WaveChannel) async {
        _ = await retryUntilAccepted {
            audioEngine.applyCarrierHz(
                settings.carrierHz,
                channelIndex: channel.engineChannelIndex,
                durationSeconds: 0
            )
        }
        _ = await retryUntilAccepted {
            audioEngine.removeAllPulses(channelIndex: channel.engineChannelIndex)
        }

        for pulse in settings.pulses {
            _ = await retryUntilAccepted {
                audioEngine.addPulse(
                    channelIndex: channel.engineChannelIndex,
                    frequency: pulse.frequency,
                    wetness: pulse.wetness,
                    targetVolume: pulse.volume,
                    durationSeconds: 0
                )
            }
        }
    }

    private func finishFilePlayback(restoreSettings snapshot: WaveGeneratorSettings, stopTone: Bool) {
        if stopTone {
            _ = audioEngine.stopTone(rampSeconds: 0.25)
        }

        isPlaying = false
        isFilePlaybackActive = false
        filePlaybackRemainingText = nil
        filePlaybackTask = nil
        Task {
            await applySettingsSnapshotToEngine(snapshot)
        }
    }

    private func finishFilePlayback(restoreSettings: Bool, stopTone: Bool) {
        if stopTone {
            _ = audioEngine.stopTone(rampSeconds: 0.25)
        }

        isPlaying = false
        isFilePlaybackActive = false
        filePlaybackRemainingText = nil
        filePlaybackTask = nil
        if restoreSettings {
            applyAllSettingsToEngine()
        }
    }

    private func renderSessionWAV(_ session: WaveSessionExport) async -> Bool {
        guard !isPlaying, !isRenderingSessionWAV else { return false }

        isRenderingSessionWAV = true
        sessionHistoryErrorMessage = nil
        defer { isRenderingSessionWAV = false }

        do {
            lastRenderedWAVURL = try await Task.detached {
                try WaveSessionOfflineRenderer.render(session)
            }.value
            return true
        } catch {
            sessionHistoryErrorMessage = error.localizedDescription
            return false
        }
    }

    private func sessionEngineChannelIndex(for channel: WaveChannel?, isStereo: Bool) -> Int {
        isStereo ? (channel ?? .left).engineChannelIndex : WaveChannel.left.engineChannelIndex
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
        settingsStore.save(currentSettingsSnapshot())
    }

    private func currentSettingsSnapshot() -> WaveGeneratorSettings {
        let normalizedMono = Self.normalizedSettings(monoSettings)
        return WaveGeneratorSettings(
            carrierHz: normalizedMono.carrierHz,
            transitionSeconds: transitionSeconds,
            pulses: normalizedMono.pulses,
            selectedPulseID: normalizedMono.selectedPulseID,
            stereo: isStereo,
            selectedChannel: selectedChannel,
            leftChannel: Self.normalizedSettings(leftSettings),
            rightChannel: Self.normalizedSettings(rightSettings)
        )
    }

    private func recordSessionEvent(
        kind: WaveSessionEventKind,
        channel: WaveChannel? = nil,
        pulseID: PulseSettings.ID? = nil,
        pulseIndex: Int? = nil,
        carrierHz: Double? = nil,
        frequency: Double? = nil,
        wetness: Double? = nil,
        volume: Double? = nil,
        transitionFrameCount: Int64? = nil,
        timeline: WaveAudioTimelineSnapshot
    ) {
        sessionRecorder.record(
            kind: kind,
            channel: channel,
            pulseID: pulseID,
            pulseIndex: pulseIndex,
            carrierHz: carrierHz,
            frequency: frequency,
            wetness: wetness,
            volume: volume,
            transitionFrameCount: transitionFrameCount,
            timeline: timeline
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
