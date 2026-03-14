import SwiftUI

struct VoiceSettingsSection: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        Section {
            Picker("Voice", selection: $settings.selectedVoice) {
                ForEach(GeminiVoice.allCases) { voice in
                    Text("\(voice.rawValue) — \(voice.description)")
                        .tag(voice.rawValue)
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Changes apply on next voice call")
        }
    }
}
