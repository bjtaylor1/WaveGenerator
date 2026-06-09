import SwiftUI

struct StartupSafetyWarningSheet: View {
    let acknowledge: (Bool) -> Void

    @State private var shouldDismissFutureWarnings = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(Self.warningMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Toggle("Don't show again", isOn: $shouldDismissFutureWarnings)
                }

                Section {
                    Button {
                        acknowledge(shouldDismissFutureWarnings)
                    } label: {
                        HStack {
                            Spacer()
                            Text("OK")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .navigationTitle("Audio safety")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private static let warningMessage = """
    1. Remember to put your phone in silent and/or do-not-disturb and/or airplane mode in order to prevent audible notifications causing a sudden spike to the output.

    2. Changing the phone's volume, either down or up, can cause a jolt to the audio output. It is recommended to turn the volume right down on the output device/amplifier while adjusting the phone's volume. The best setting is either maximum, or one or two clicks down from the maximum.
    """
}

#Preview {
    StartupSafetyWarningSheet { _ in }
}
