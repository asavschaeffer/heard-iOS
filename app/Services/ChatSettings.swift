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

    init() {
        let defaults = UserDefaults.standard

        self.showReadReceipts = defaults.bool(forKey: Keys.showReadReceipts)

        // VAD defaults: register once so `bool(forKey:)` / `integer(forKey:)` return correct defaults
        defaults.register(defaults: [
            Keys.vadStartSensitivityLow: true,
            Keys.vadEndSensitivityLow: true,
            Keys.vadPrefixPaddingMs: 40,
            Keys.vadSilenceDurationMs: 300,
            Keys.vadProactiveAudio: false
        ])

        self.vadStartSensitivityLow = defaults.bool(forKey: Keys.vadStartSensitivityLow)
        self.vadEndSensitivityLow = defaults.bool(forKey: Keys.vadEndSensitivityLow)
        self.vadPrefixPaddingMs = defaults.integer(forKey: Keys.vadPrefixPaddingMs)
        self.vadSilenceDurationMs = defaults.integer(forKey: Keys.vadSilenceDurationMs)
        self.vadProactiveAudio = defaults.bool(forKey: Keys.vadProactiveAudio)
    }

    func audioSetupProfile() -> GeminiAudioSetupProfile {
        GeminiAudioSetupProfile(
            startOfSpeechSensitivity: vadStartSensitivityLow ? "START_SENSITIVITY_LOW" : "START_SENSITIVITY_HIGH",
            endOfSpeechSensitivity: vadEndSensitivityLow ? "END_SENSITIVITY_LOW" : "END_SENSITIVITY_HIGH",
            prefixPaddingMs: vadPrefixPaddingMs,
            silenceDurationMs: vadSilenceDurationMs,
            includesProactivity: vadProactiveAudio
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
            Keys.vadProactiveAudio: false
        ])
        return GeminiAudioSetupProfile(
            startOfSpeechSensitivity: defaults.bool(forKey: Keys.vadStartSensitivityLow)
                ? "START_SENSITIVITY_LOW" : "START_SENSITIVITY_HIGH",
            endOfSpeechSensitivity: defaults.bool(forKey: Keys.vadEndSensitivityLow)
                ? "END_SENSITIVITY_LOW" : "END_SENSITIVITY_HIGH",
            prefixPaddingMs: defaults.integer(forKey: Keys.vadPrefixPaddingMs),
            silenceDurationMs: defaults.integer(forKey: Keys.vadSilenceDurationMs),
            includesProactivity: defaults.bool(forKey: Keys.vadProactiveAudio)
        )
    }

    private enum Keys {
        static let showReadReceipts = "showReadReceipts"
        static let vadStartSensitivityLow = "vadStartSensitivityLow"
        static let vadEndSensitivityLow = "vadEndSensitivityLow"
        static let vadPrefixPaddingMs = "vadPrefixPaddingMs"
        static let vadSilenceDurationMs = "vadSilenceDurationMs"
        static let vadProactiveAudio = "vadProactiveAudio"
    }
}
