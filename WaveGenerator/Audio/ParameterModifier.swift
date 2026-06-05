import Foundation

struct ParameterModifier {
    let startFrame: Int64
    let endFrame: Int64
    let startValue: Double
    let targetValue: Double

    func value(at frame: Int64) -> Double {
        guard endFrame > startFrame else { return targetValue }
        if frame <= startFrame { return startValue }
        if frame >= endFrame { return targetValue }

        let progress = Double(frame - startFrame) / Double(endFrame - startFrame)
        return startValue + (targetValue - startValue) * progress
    }
}
