import SwiftUI

struct SessionHistoryRow: View {
    let session: WaveSessionRecord
    let exportSession: (WaveSessionRecord) -> Void

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
                exportSession(session)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Export Session")
        }
    }
}
