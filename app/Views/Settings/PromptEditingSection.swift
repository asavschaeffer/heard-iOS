import SwiftUI

struct PromptEditingSection: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        Section {
            NavigationLink("Base System Prompt") {
                PromptEditorView(
                    title: "System Prompt",
                    text: $settings.baseSystemPrompt,
                    defaultText: GeminiPromptConfiguration.defaultConfiguration.baseSystemPrompt
                )
            }

            NavigationLink("Live Audio Addendum") {
                PromptEditorView(
                    title: "Audio Addendum",
                    text: $settings.liveAudioPrompt,
                    defaultText: GeminiPromptConfiguration.defaultConfiguration.liveAudioPrompt
                )
            }
        } header: {
            Text("Prompts")
        } footer: {
            Text("These fields map directly to the Gemini system instruction. Text chat changes apply on the next request; voice changes apply on the next voice call.")
        }
    }
}
