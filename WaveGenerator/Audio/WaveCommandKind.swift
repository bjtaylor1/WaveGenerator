enum WaveCommandKind: Int32 {
    case setComponentFrequency = 0
    case setComponentWetness = 1
    case setMasterGain = 2
    case applyParameters = 3
    case addPulse = 4
    case removePulse = 5
    case setStereoEnabled = 6
    case removeAllPulses = 7
}
