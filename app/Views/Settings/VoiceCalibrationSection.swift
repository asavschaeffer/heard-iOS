import SwiftUI

struct VoiceCalibrationSection: View {
    @ObservedObject var settings: ChatSettings
    @State private var prefixPadding: Double = 0
    @State private var silenceDuration: Double = 0

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Start Sensitivity: \(settings.vadStartSensitivityLow ? "LOW" : "HIGH")",
                    isOn: $settings.vadStartSensitivityLow
                )
                Text("How easily Gemini decides you started talking. LOW ignores quiet sounds like speaker bleed — better for preventing self-prompting. HIGH catches soft speech — better for interrupts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "End Sensitivity: \(settings.vadEndSensitivityLow ? "LOW" : "HIGH")",
                    isOn: $settings.vadEndSensitivityLow
                )
                Text("How quickly Gemini decides you stopped talking. LOW waits longer before ending your turn — lets you pause mid-sentence. HIGH ends your turn faster — snappier but may cut you off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Prefix Padding: \(Int(prefixPadding)) ms") {
                    Slider(value: $prefixPadding, in: 10...100, step: 10)
                }
                Text("Audio kept before detected speech starts. Higher values capture the beginning of words but also capture more speaker bleed. Lower values trim the start of your speech but reduce self-prompting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onAppear { prefixPadding = Double(settings.vadPrefixPaddingMs) }
            .onChange(of: prefixPadding) { _, newValue in
                settings.vadPrefixPaddingMs = Int(newValue)
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Silence Duration: \(Int(silenceDuration)) ms") {
                    Slider(value: $silenceDuration, in: 100...1000, step: 50)
                }
                Text("How long Gemini waits in silence before finalizing your turn. Shorter means faster responses and easier interrupts, but may cut you off mid-thought. Longer lets you breathe between sentences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onAppear { silenceDuration = Double(settings.vadSilenceDurationMs) }
            .onChange(of: silenceDuration) { _, newValue in
                settings.vadSilenceDurationMs = Int(newValue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Proactive Audio", isOn: $settings.vadProactiveAudio)
                Text("Lets Gemini speak up on its own without waiting for you. Can feel more natural but increases the chance of echo loops if AEC isn't suppressing speaker output fully.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Allow Interrupts", isOn: $settings.vadActivityHandlingInterrupts)
                Text("When ON, your speech interrupts Gemini mid-sentence (default). When OFF, Gemini finishes its response even if you start talking — useful if speaker bleed is causing false interrupts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Activity-Only Turns", isOn: $settings.vadTurnCoverageOnlyActivity)
                Text("When ON, only audio during detected speech is sent to the model (default). When OFF, all audio including silence and background noise is included — useful for ambient context but noisier.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Voice Calibration")
        } footer: {
            Text("Changes apply on next voice call")
        }
    }
}
