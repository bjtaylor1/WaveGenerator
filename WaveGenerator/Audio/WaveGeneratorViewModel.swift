import Foundation
import Combine

@MainActor
final class WaveGeneratorViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var carrierHz: Double = 500
    @Published var pulseHz: Double = 1
    @Published var wetness: Double = 0
    @Published var transitionSeconds: Double = 15

    @Published private(set) var isQueueSaturated = false
    @Published private(set) var isApplyingSettings = false

    private let audioEngine = WaveAudioEngine()
    private var queueMonitorTask: Task<Void, Never>?

    func configureAudio() {
        do {
            try audioEngine.startEngineIfNeeded()
            _ = audioEngine.applyParameters(
                carrierHz: carrierHz,
                pulseHz: pulseHz,
                wetness: wetness,
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

    func applyStagedSettings(
        carrierHz: Double,
        pulseHz: Double,
        wetness: Double
    ) async -> Bool {
        isApplyingSettings = true
        defer { isApplyingSettings = false }

        let carrier = max(200, carrierHz)
        let pulse = max(0, pulseHz)
        let wet = min(1, max(0, wetness))
        let durationSeconds = isPlaying ? transitionSeconds : 0

        while !Task.isCancelled {
            let accepted = audioEngine.applyParameters(
                carrierHz: carrier,
                pulseHz: pulse,
                wetness: wet,
                durationSeconds: durationSeconds
            )

            if accepted {
                self.carrierHz = carrier
                self.pulseHz = pulse
                self.wetness = wet
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return false
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
}
