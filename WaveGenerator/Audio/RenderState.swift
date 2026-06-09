import Foundation
import Synchronization

nonisolated final class RenderState {
    let sampleRate: Double
    var isStereo = false
    var channels: [ChannelState]

    let masterGain = RampedParameter(initialValue: 0)
    private let framePositionStorage = Atomic<Int64>(0)

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.channels = [
            ChannelState(),
            ChannelState(),
        ]
    }

    var framePosition: Int64 {
        get {
            framePositionStorage.load(ordering: .relaxed)
        }
        set {
            framePositionStorage.store(newValue, ordering: .relaxed)
        }
    }
}
