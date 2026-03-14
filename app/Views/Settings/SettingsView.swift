import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        NavigationStack {
            Form {
                PromptEditingSection(settings: settings)
                ChatSettingsSection(settings: settings)
                VoiceSettingsSection(settings: settings)
                VoiceCalibrationSection(settings: settings)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(settings: ChatSettings())
}
