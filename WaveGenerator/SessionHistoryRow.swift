import SwiftUI

struct SessionHistoryRow: View {
    let session: WaveSessionRecord
    let playSession: (WaveSessionRecord) -> Void
    let renderWAV: (WaveSessionRecord) -> Void
    let exportSession: (WaveSessionRecord) -> Void
    let actionsDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.body)

                Text("\(session.formattedDuration) - \(session.actionCount) actions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                playSession(session)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play Session")
            .disabled(actionsDisabled)

            Button {
                renderWAV(session)
            } label: {
                Image(systemName: "waveform")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Render WAV")
            .disabled(actionsDisabled)

            Button {
                exportSession(session)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Export Session")
            .disabled(actionsDisabled)
        }
    }
}
