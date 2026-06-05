final class ChannelState {
    var components: [ComponentState]

    init() {
        self.components = [
            ComponentState(
                mode: .bipolarSine,
                minimumFrequency: 200,
                initialFrequency: 500,
                initialWetness: 0,
                initialVolume: 1
            ),
            ComponentState(
                mode: .unipolarPulse,
                minimumFrequency: 0,
                initialFrequency: 1,
                initialWetness: 0,
                initialVolume: 1
            ),
        ]
    }
}
