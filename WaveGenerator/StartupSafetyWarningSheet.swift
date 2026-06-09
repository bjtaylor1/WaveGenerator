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
            .navigationTitle("Audio recommendations to remember:")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private static let warningMessage = """
    1. Use silent/do-not-disturb/silent mode to prevent notifications affecting output.

    2. Changing the phone's volume (down or up) while audio is playing can cause jolts.

    3. Become familiar with the characteristics of the app either by recording or listening etc before using it on output device/amplifier.
    """
}

#Preview {
    StartupSafetyWarningSheet { _ in }
}
