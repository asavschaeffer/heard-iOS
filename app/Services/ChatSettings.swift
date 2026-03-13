import Foundation
import Combine

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

    init() {
        let defaults = UserDefaults.standard

        self.showReadReceipts = defaults.bool(forKey: Keys.showReadReceipts)

        // VAD defaults: register once so `bool(forKey:)` / `integer(forKey:)` return correct defaults
        defaults.register(defaults: [
            Keys.vadStartSensitivityLow: true,
            Keys.vadEndSensitivityLow: true,
            Keys.vadPrefixPaddingMs: 40,
            Keys.vadSilenceDurationMs: 300,
            Keys.vadProactiveAudio: false,
            Keys.vadActivityHandlingInterrupts: true,
            Keys.vadTurnCoverageOnlyActivity: true,
            Keys.selectedVoice: GeminiVoice.aoede.rawValue
        ])

        self.vadStartSensitivityLow = defaults.bool(forKey: Keys.vadStartSensitivityLow)
        self.vadEndSensitivityLow = defaults.bool(forKey: Keys.vadEndSensitivityLow)
        self.vadPrefixPaddingMs = defaults.integer(forKey: Keys.vadPrefixPaddingMs)
        self.vadSilenceDurationMs = defaults.integer(forKey: Keys.vadSilenceDurationMs)
        self.vadProactiveAudio = defaults.bool(forKey: Keys.vadProactiveAudio)
        self.vadActivityHandlingInterrupts = defaults.bool(forKey: Keys.vadActivityHandlingInterrupts)
        self.vadTurnCoverageOnlyActivity = defaults.bool(forKey: Keys.vadTurnCoverageOnlyActivity)
        self.selectedVoice = defaults.string(forKey: Keys.selectedVoice) ?? GeminiVoice.aoede.rawValue
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
        defaults.register(defaults: [
            Keys.vadStartSensitivityLow: true,
            Keys.vadEndSensitivityLow: true,
            Keys.vadPrefixPaddingMs: 40,
            Keys.vadSilenceDurationMs: 300,
            Keys.vadProactiveAudio: false,
            Keys.vadActivityHandlingInterrupts: true,
            Keys.vadTurnCoverageOnlyActivity: true,
            Keys.selectedVoice: GeminiVoice.aoede.rawValue
        ])
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
    }
}
