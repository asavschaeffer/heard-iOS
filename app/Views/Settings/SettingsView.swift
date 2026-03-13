import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Chat") {
                    Toggle("Show Read Receipts", isOn: $settings.showReadReceipts)
                }

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

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            "Start Sensitivity: \(settings.vadStartSensitivityLow ? "LOW" : "HIGH")",
                            isOn: $settings.vadStartSensitivityLow
                        )
                        Text("How easily Gemini decides you started talking. LOW ignores quiet sounds like speaker bleed — better for preventing self-prompting. HIGH catches soft speech — better for interrupts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            "End Sensitivity: \(settings.vadEndSensitivityLow ? "LOW" : "HIGH")",
                            isOn: $settings.vadEndSensitivityLow
                        )
                        Text("How quickly Gemini decides you stopped talking. LOW waits longer before ending your turn — lets you pause mid-sentence. HIGH ends your turn faster — snappier but may cut you off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefix Padding: \(settings.vadPrefixPaddingMs) ms")
                        Slider(
                            value: Binding(
                                get: { Double(settings.vadPrefixPaddingMs) },
                                set: { settings.vadPrefixPaddingMs = Int($0) }
                            ),
                            in: 10...100,
                            step: 10
                        )
                        Text("Audio kept before detected speech starts. Higher values capture the beginning of words but also capture more speaker bleed. Lower values trim the start of your speech but reduce self-prompting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Silence Duration: \(settings.vadSilenceDurationMs) ms")
                        Slider(
                            value: Binding(
                                get: { Double(settings.vadSilenceDurationMs) },
                                set: { settings.vadSilenceDurationMs = Int($0) }
                            ),
                            in: 100...1000,
                            step: 50
                        )
                        Text("How long Gemini waits in silence before finalizing your turn. Shorter means faster responses and easier interrupts, but may cut you off mid-thought. Longer lets you breathe between sentences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Proactive Audio", isOn: $settings.vadProactiveAudio)
                        Text("Lets Gemini speak up on its own without waiting for you. Can feel more natural but increases the chance of echo loops if AEC isn't suppressing speaker output fully.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Allow Interrupts", isOn: $settings.vadActivityHandlingInterrupts)
                        Text("When ON, your speech interrupts Gemini mid-sentence (default). When OFF, Gemini finishes its response even if you start talking — useful if speaker bleed is causing false interrupts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Activity-Only Turns", isOn: $settings.vadTurnCoverageOnlyActivity)
                        Text("When ON, only audio during detected speech is sent to the model (default). When OFF, all audio including silence and background noise is included — useful for ambient context but noisier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice Calibration")
                } footer: {
                    Text("Changes apply on next voice call")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base System Prompt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $settings.baseSystemPrompt)
                            .frame(minHeight: 260)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live Audio Addendum")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $settings.liveAudioPrompt)
                            .frame(minHeight: 140)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }

                    Button("Reset Prompt Defaults") {
                        settings.resetPromptConfiguration()
                    }
                } header: {
                    Text("Beta Prompt Editing")
                } footer: {
                    Text("These fields map directly to the Gemini system instruction. Text chat changes apply on the next request; voice changes apply on the next voice call. Reset to defaults if tool calling or recipe formatting drifts.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(settings: ChatSettings())
}
