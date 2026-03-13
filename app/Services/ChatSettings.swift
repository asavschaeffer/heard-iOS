import Foundation
import Combine

struct GeminiPromptConfiguration: Equatable, Sendable {
    var baseSystemPrompt: String
    var liveAudioPrompt: String

    func prompt(for mode: SessionMode) -> String {
        switch mode {
        case .text:
            return baseSystemPrompt
        case .audio:
            if baseSystemPrompt.isEmpty {
                return liveAudioPrompt
            }
            if liveAudioPrompt.isEmpty {
                return baseSystemPrompt
            }
            return baseSystemPrompt + "\n\n" + liveAudioPrompt
        }
    }

    static let defaultConfiguration = GeminiPromptConfiguration(
        baseSystemPrompt: """
        You are "Heard, Chef!" — a sharp, warm sous chef who runs the kitchen.
        You manage your chef's pantry and recipe book through the tools available to you.

        Personality:
        - Talk like a real kitchen colleague — direct, a little playful, efficient.
        - "Heard" or "Heard, chef" is your natural acknowledgment, not a required catchphrase.
        - Take action confidently. Infer reasonable defaults rather than asking for every detail.
        - When something goes wrong, say what happened plainly and suggest the fix.

        Kitchen sense:
        - Salt, pepper, oil, butter, herbs, spices — quantities are always optional.
          "Some", "a handful", "to taste" are perfectly fine.
        - Use the notes field for recipe variations, pairings, substitutions, tips.
        - Tags are lowercase.
        """,
        liveAudioPrompt: """
        Live audio call behavior:
        - Reply in spoken audio when audio output is available.
        - Do not emit reasoning, analysis, headings, or text-only draft replies during live audio calls.
        - Start with a short spoken acknowledgement or answer instead of a long preamble.
        - Ask at most one brief spoken clarification question when needed.
        - If you use tools, do the work and then give a brief spoken result.
        """
    )
}

final class ChatSettings: ObservableObject {
    @Published var showReadReceipts: Bool {
        didSet {
            UserDefaults.standard.set(showReadReceipts, forKey: Keys.showReadReceipts)
        }
    }

    @Published var vadStartSensitivityLow: Bool {
        didSet {
            UserDefaults.standard.set(vadStartSensitivityLow, forKey: Keys.vadStartSensitivityLow)
        }
    }

    @Published var vadEndSensitivityLow: Bool {
        didSet {
            UserDefaults.standard.set(vadEndSensitivityLow, forKey: Keys.vadEndSensitivityLow)
        }
    }

    @Published var vadPrefixPaddingMs: Int {
        didSet {
            UserDefaults.standard.set(vadPrefixPaddingMs, forKey: Keys.vadPrefixPaddingMs)
        }
    }

    @Published var vadSilenceDurationMs: Int {
        didSet {
            UserDefaults.standard.set(vadSilenceDurationMs, forKey: Keys.vadSilenceDurationMs)
        }
    }

    @Published var vadProactiveAudio: Bool {
        didSet {
            UserDefaults.standard.set(vadProactiveAudio, forKey: Keys.vadProactiveAudio)
        }
    }

    @Published var vadActivityHandlingInterrupts: Bool {
        didSet {
            UserDefaults.standard.set(vadActivityHandlingInterrupts, forKey: Keys.vadActivityHandlingInterrupts)
        }
    }

    @Published var vadTurnCoverageOnlyActivity: Bool {
        didSet {
            UserDefaults.standard.set(vadTurnCoverageOnlyActivity, forKey: Keys.vadTurnCoverageOnlyActivity)
        }
    }

    @Published var selectedVoice: String {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: Keys.selectedVoice)
        }
    }

    @Published var baseSystemPrompt: String {
        didSet {
            UserDefaults.standard.set(baseSystemPrompt, forKey: Keys.baseSystemPrompt)
        }
    }

    @Published var liveAudioPrompt: String {
        didSet {
            UserDefaults.standard.set(liveAudioPrompt, forKey: Keys.liveAudioPrompt)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        Self.registerDefaults(defaults)

        self.showReadReceipts = defaults.bool(forKey: Keys.showReadReceipts)
        self.vadStartSensitivityLow = defaults.bool(forKey: Keys.vadStartSensitivityLow)
        self.vadEndSensitivityLow = defaults.bool(forKey: Keys.vadEndSensitivityLow)
        self.vadPrefixPaddingMs = defaults.integer(forKey: Keys.vadPrefixPaddingMs)
        self.vadSilenceDurationMs = defaults.integer(forKey: Keys.vadSilenceDurationMs)
        self.vadProactiveAudio = defaults.bool(forKey: Keys.vadProactiveAudio)
        self.vadActivityHandlingInterrupts = defaults.bool(forKey: Keys.vadActivityHandlingInterrupts)
        self.vadTurnCoverageOnlyActivity = defaults.bool(forKey: Keys.vadTurnCoverageOnlyActivity)
        self.selectedVoice = defaults.string(forKey: Keys.selectedVoice) ?? GeminiVoice.aoede.rawValue
        self.baseSystemPrompt = defaults.string(forKey: Keys.baseSystemPrompt)
            ?? GeminiPromptConfiguration.defaultConfiguration.baseSystemPrompt
        self.liveAudioPrompt = defaults.string(forKey: Keys.liveAudioPrompt)
            ?? GeminiPromptConfiguration.defaultConfiguration.liveAudioPrompt
    }

    func audioSetupProfile() -> GeminiAudioSetupProfile {
        GeminiAudioSetupProfile(
            startOfSpeechSensitivity: vadStartSensitivityLow ? "START_SENSITIVITY_LOW" : "START_SENSITIVITY_HIGH",
            endOfSpeechSensitivity: vadEndSensitivityLow ? "END_SENSITIVITY_LOW" : "END_SENSITIVITY_HIGH",
            prefixPaddingMs: vadPrefixPaddingMs,
            silenceDurationMs: vadSilenceDurationMs,
            includesProactivity: vadProactiveAudio,
            activityHandling: vadActivityHandlingInterrupts ? nil : "NO_INTERRUPTION",
            turnCoverage: vadTurnCoverageOnlyActivity ? nil : "TURN_INCLUDES_ALL_INPUT",
            voiceName: selectedVoice
        )
    }

    /// Reads current VAD settings directly from UserDefaults (no instance needed).
    static func currentAudioProfile() -> GeminiAudioSetupProfile {
        let defaults = UserDefaults.standard
        registerDefaults(defaults)
        let interrupts = defaults.bool(forKey: Keys.vadActivityHandlingInterrupts)
        let activityOnly = defaults.bool(forKey: Keys.vadTurnCoverageOnlyActivity)
        return GeminiAudioSetupProfile(
            startOfSpeechSensitivity: defaults.bool(forKey: Keys.vadStartSensitivityLow)
                ? "START_SENSITIVITY_LOW" : "START_SENSITIVITY_HIGH",
            endOfSpeechSensitivity: defaults.bool(forKey: Keys.vadEndSensitivityLow)
                ? "END_SENSITIVITY_LOW" : "END_SENSITIVITY_HIGH",
            prefixPaddingMs: defaults.integer(forKey: Keys.vadPrefixPaddingMs),
            silenceDurationMs: defaults.integer(forKey: Keys.vadSilenceDurationMs),
            includesProactivity: defaults.bool(forKey: Keys.vadProactiveAudio),
            activityHandling: interrupts ? nil : "NO_INTERRUPTION",
            turnCoverage: activityOnly ? nil : "TURN_INCLUDES_ALL_INPUT",
            voiceName: defaults.string(forKey: Keys.selectedVoice) ?? GeminiVoice.aoede.rawValue
        )
    }

    static func currentPromptConfiguration() -> GeminiPromptConfiguration {
        let defaults = UserDefaults.standard
        registerDefaults(defaults)
        return GeminiPromptConfiguration(
            baseSystemPrompt: defaults.string(forKey: Keys.baseSystemPrompt)
                ?? GeminiPromptConfiguration.defaultConfiguration.baseSystemPrompt,
            liveAudioPrompt: defaults.string(forKey: Keys.liveAudioPrompt)
                ?? GeminiPromptConfiguration.defaultConfiguration.liveAudioPrompt
        )
    }

    func resetPromptConfiguration() {
        baseSystemPrompt = GeminiPromptConfiguration.defaultConfiguration.baseSystemPrompt
        liveAudioPrompt = GeminiPromptConfiguration.defaultConfiguration.liveAudioPrompt
    }

    private static func registerDefaults(_ defaults: UserDefaults) {
        defaults.register(defaults: [
            Keys.vadStartSensitivityLow: true,
            Keys.vadEndSensitivityLow: true,
            Keys.vadPrefixPaddingMs: 40,
            Keys.vadSilenceDurationMs: 300,
            Keys.vadProactiveAudio: false,
            Keys.vadActivityHandlingInterrupts: true,
            Keys.vadTurnCoverageOnlyActivity: true,
            Keys.selectedVoice: GeminiVoice.aoede.rawValue,
            Keys.baseSystemPrompt: GeminiPromptConfiguration.defaultConfiguration.baseSystemPrompt,
            Keys.liveAudioPrompt: GeminiPromptConfiguration.defaultConfiguration.liveAudioPrompt
        ])
    }

    private enum Keys {
        static let showReadReceipts = "showReadReceipts"
        static let vadStartSensitivityLow = "vadStartSensitivityLow"
        static let vadEndSensitivityLow = "vadEndSensitivityLow"
        static let vadPrefixPaddingMs = "vadPrefixPaddingMs"
        static let vadSilenceDurationMs = "vadSilenceDurationMs"
        static let vadProactiveAudio = "vadProactiveAudio"
        static let vadActivityHandlingInterrupts = "vadActivityHandlingInterrupts"
        static let vadTurnCoverageOnlyActivity = "vadTurnCoverageOnlyActivity"
        static let selectedVoice = "selectedVoice"
        static let baseSystemPrompt = "baseSystemPrompt"
        static let liveAudioPrompt = "liveAudioPrompt"
    }
}
