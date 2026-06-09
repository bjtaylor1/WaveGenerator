struct WaveSessionExport: Codable {
    let formatVersion: Int
    let sampleRate: Double
    let durationFrames: Int64
    let initialSettings: WaveGeneratorSettings
    let events: [WaveSessionExportEvent]

    init(session: WaveSessionRecord) {
        formatVersion = 1
        sampleRate = session.sampleRate
        durationFrames = session.durationFrames
        initialSettings = session.initialSettings
        events = session.events.map { event in
            WaveSessionExportEvent(event: event)
        }
    }
}
