import Foundation

final class RenderState {
    let sampleRate: Double
    var framePosition: Int64 = 0
    var isStereo = false
    var channels: [ChannelState]

    let masterGain = RampedParameter(initialValue: 0)

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.channels = [
            ChannelState(),
            ChannelState(),
        ]
    }
}
