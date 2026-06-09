import Foundation

nonisolated final class RampedParameter {
    private(set) var settledValue: Double
    private var activeModifier: ParameterModifier?

    init(initialValue: Double) {
        self.settledValue = initialValue
    }

    func value(at frame: Int64) -> Double {
        guard let modifier = activeModifier else {
            return settledValue
        }

        let value = modifier.value(at: frame)
        if frame >= modifier.endFrame {
            settledValue = modifier.targetValue
            activeModifier = nil
        }

        return value
    }

    func scheduleTransition(
        frame nowFrame: Int64,
        targetValue: Double,
        durationFrames: Int64
    ) {
        guard durationFrames > 0 else {
            settledValue = targetValue
            activeModifier = nil
            return
        }

        let clampedDuration = max(1, durationFrames)
        let startValue = value(at: nowFrame)

        activeModifier = ParameterModifier(
            startFrame: nowFrame,
            endFrame: nowFrame + clampedDuration,
            startValue: startValue,
            targetValue: targetValue
        )
    }
}
