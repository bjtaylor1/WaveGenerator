struct WaveRecordingSnapshot {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int

    var frameCount: Int {
        guard channelCount > 0 else { return 0 }
        return samples.count / channelCount
    }
}
