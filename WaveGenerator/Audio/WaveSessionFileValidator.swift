import Foundation

nonisolated struct WaveSessionFileValidator {
    static func validationErrors(for session: WaveSessionExport) -> [String] {
        var errors: [String] = []

        validateSessionHeader(session, errors: &errors)
        validateSettings(session.initialSettings, isStereo: session.isStereo, errors: &errors)
        validateEvents(session.events, in: session, errors: &errors)

        return errors
    }

    private static func validateSessionHeader(_ session: WaveSessionExport, errors: inout [String]) {
        if session.formatVersion != 1 {
            errors.append("Unsupported format version \(session.formatVersion). This app understands version 1.")
        }

        if !session.sampleRate.isFinite || session.sampleRate <= 0 {
            errors.append("Sample rate must be greater than zero.")
        }

        if session.durationFrames < 0 {
            errors.append("Duration frame count must not be negative.")
        }

        if !session.events.contains(where: { $0.kind == .startPlayback }) {
            errors.append("No start playback command was found.")
        }
    }

    private static func validateSettings(
        _ settings: WaveGeneratorSettings,
        isStereo: Bool,
        errors: inout [String]
    ) {
        if isStereo {
            validateChannelSettings(settings.leftChannel, channelName: "left", errors: &errors)
            validateChannelSettings(settings.rightChannel, channelName: "right", errors: &errors)
        } else {
            let monoSettings = WaveChannelSettings(
                carrierHz: settings.carrierHz,
                pulses: settings.pulses,
                selectedPulseID: settings.selectedPulseID
            )
            validateChannelSettings(monoSettings, channelName: "mono", errors: &errors)
        }
    }

    private static func validateChannelSettings(
        _ settings: WaveChannelSettings?,
        channelName: String,
        errors: inout [String]
    ) {
        guard let settings else {
            errors.append("Missing \(channelName) channel settings.")
            return
        }

        if !settings.carrierHz.isFinite || settings.carrierHz < 200 {
            errors.append("\(channelName.capitalized) carrier frequency must be at least 200 Hz.")
        }

        for (index, pulse) in settings.pulses.enumerated() {
            validatePulse(pulse, label: "\(channelName) pulse \(index + 1)", errors: &errors)
        }

        if let selectedPulseID = settings.selectedPulseID,
           !settings.pulses.contains(where: { $0.id == selectedPulseID }) {
            errors.append("\(channelName.capitalized) selected pulse does not exist in the pulse list.")
        }
    }

    private static func validatePulse(_ pulse: PulseSettings, label: String, errors: inout [String]) {
        if !pulse.frequency.isFinite || pulse.frequency < 0 {
            errors.append("\(label.capitalized) frequency must not be negative.")
        }

        if !pulse.wetness.isFinite || pulse.wetness < 0 || pulse.wetness > 1 {
            errors.append("\(label.capitalized) wetness must be between 0 and 1.")
        }

        if !pulse.volume.isFinite || pulse.volume < 0 || pulse.volume > 1 {
            errors.append("\(label.capitalized) volume must be between 0 and 1.")
        }
    }

    private static func validateEvents(
        _ events: [WaveSessionExportEvent],
        in session: WaveSessionExport,
        errors: inout [String]
    ) {
        var pulseCounts = [
            WaveChannel.left.engineChannelIndex: session.channelSettings(for: .left).pulses.count,
            WaveChannel.right.engineChannelIndex: session.channelSettings(for: .right).pulses.count,
        ]

        let indexedEvents = events.enumerated().sorted { lhs, rhs in
            if lhs.element.frameOffset == rhs.element.frameOffset {
                return lhs.offset < rhs.offset
            }

            return lhs.element.frameOffset < rhs.element.frameOffset
        }

        for (index, event) in indexedEvents {
            let label = "Event \(index + 1) (\(event.kind.rawValue))"
            validateEventTiming(event, label: label, errors: &errors)

            switch event.kind {
            case .startPlayback, .stopPlayback:
                break
            case .carrierChanged:
                validateCarrierEvent(event, label: label, errors: &errors)
            case .pulseChanged:
                validatePulseChangeEvent(
                    event,
                    label: label,
                    pulseCounts: pulseCounts,
                    isStereo: session.isStereo,
                    errors: &errors
                )
            case .pulseAdded:
                validatePulseAddEvent(event, label: label, errors: &errors)
                let channelIndex = channelIndex(for: event.channel, isStereo: session.isStereo)
                pulseCounts[channelIndex, default: 0] += 1
            case .pulseRemoved:
                validatePulseRemoveEvent(
                    event,
                    label: label,
                    pulseCounts: pulseCounts,
                    isStereo: session.isStereo,
                    errors: &errors
                )
                if let pulseIndex = event.pulseIndex {
                    let channelIndex = channelIndex(for: event.channel, isStereo: session.isStereo)
                    if pulseCounts[channelIndex, default: 0] > pulseIndex {
                        pulseCounts[channelIndex, default: 0] -= 1
                    }
                }
            }
        }
    }

    private static func validateEventTiming(
        _ event: WaveSessionExportEvent,
        label: String,
        errors: inout [String]
    ) {
        if event.frameOffset < 0 {
            errors.append("\(label) has a negative frame offset.")
        }

        if let transitionFrameCount = event.transitionFrameCount,
           transitionFrameCount < 0 {
            errors.append("\(label) has a negative transition frame count.")
        }
    }

    private static func validateCarrierEvent(
        _ event: WaveSessionExportEvent,
        label: String,
        errors: inout [String]
    ) {
        guard let carrierHz = event.carrierHz else {
            errors.append("\(label) is missing a carrier frequency.")
            return
        }

        if !carrierHz.isFinite || carrierHz < 200 {
            errors.append("\(label) carrier frequency must be at least 200 Hz.")
        }
    }

    private static func validatePulseChangeEvent(
        _ event: WaveSessionExportEvent,
        label: String,
        pulseCounts: [Int: Int],
        isStereo: Bool,
        errors: inout [String]
    ) {
        validatePulseIndex(event, label: label, pulseCounts: pulseCounts, isStereo: isStereo, errors: &errors)
        validatePulseValues(event, label: label, errors: &errors)
    }

    private static func validatePulseAddEvent(
        _ event: WaveSessionExportEvent,
        label: String,
        errors: inout [String]
    ) {
        validatePulseValues(event, label: label, errors: &errors)
    }

    private static func validatePulseRemoveEvent(
        _ event: WaveSessionExportEvent,
        label: String,
        pulseCounts: [Int: Int],
        isStereo: Bool,
        errors: inout [String]
    ) {
        validatePulseIndex(event, label: label, pulseCounts: pulseCounts, isStereo: isStereo, errors: &errors)
    }

    private static func validatePulseIndex(
        _ event: WaveSessionExportEvent,
        label: String,
        pulseCounts: [Int: Int],
        isStereo: Bool,
        errors: inout [String]
    ) {
        guard let pulseIndex = event.pulseIndex else {
            errors.append("\(label) is missing a pulse index.")
            return
        }

        if pulseIndex < 0 {
            errors.append("\(label) has a negative pulse index.")
            return
        }

        let channelIndex = channelIndex(for: event.channel, isStereo: isStereo)
        if pulseIndex >= pulseCounts[channelIndex, default: 0] {
            errors.append("\(label) refers to pulse \(pulseIndex + 1), which does not exist.")
        }
    }

    private static func validatePulseValues(
        _ event: WaveSessionExportEvent,
        label: String,
        errors: inout [String]
    ) {
        guard let frequency = event.frequency else {
            errors.append("\(label) is missing a pulse frequency.")
            return
        }

        if !frequency.isFinite || frequency < 0 {
            errors.append("\(label) pulse frequency must not be negative.")
        }

        guard let wetness = event.wetness else {
            errors.append("\(label) is missing pulse wetness.")
            return
        }

        if !wetness.isFinite || wetness < 0 || wetness > 1 {
            errors.append("\(label) pulse wetness must be between 0 and 1.")
        }

        guard let volume = event.volume else {
            errors.append("\(label) is missing pulse volume.")
            return
        }

        if !volume.isFinite || volume < 0 || volume > 1 {
            errors.append("\(label) pulse volume must be between 0 and 1.")
        }
    }

    private static func channelIndex(for channel: WaveChannel?, isStereo: Bool) -> Int {
        isStereo ? (channel ?? .left).engineChannelIndex : WaveChannel.left.engineChannelIndex
    }
}
