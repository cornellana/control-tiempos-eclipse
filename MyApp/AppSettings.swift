/// AppSettings.swift — Observable settings model backed by UserDefaults.

import AVFoundation
import Observation

// MARK: - VoiceLanguage

/// Language options for both the UI locale and the voice synthesiser (single selector).
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case spanish = "es-ES"
    case catalan = "ca-ES"
    case english = "en-GB"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spanish: return "Español (es-ES)"
        case .catalan: return "Català (ca-ES)"
        case .english: return "English (en-GB)"
        }
    }
}

// MARK: - AppSettings

/// Persists language, speech rate, speech volume, and the Claude API key in `UserDefaults`.
///
/// A single `language` property controls both the UI locale and the TTS voice.
/// Migrates automatically from the old split `uiLanguage` / `voiceLanguage` keys.
///
/// Declare once at the root and pass via `.environment(settings)`.
@Observable final class AppSettings {

    // MARK: Keys

    private enum Key {
        static let language         = "language"
        static let speechRate       = "speechRate"
        static let claudeApiKey     = "claudeApiKey"
        /// Diccionario idioma-rawValue → voice identifier (para voces premium/enhanced).
        static let voiceIdentifiers = "voiceIdentifiers"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: Properties

    /// Single language that controls both the UI locale and the TTS voice.
    var language: VoiceLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Key.language) }
    }

    /// SwiftUI locale derived from `language` — injected at the root via `.environment(\.locale, ...)`.
    var locale: Locale { Locale(identifier: language.rawValue) }

    /// Synthesis rate in the range `AVSpeechUtteranceMinimumSpeechRate`…`Maximum`.
    var speechRate: Float {
        didSet { UserDefaults.standard.set(speechRate, forKey: Key.speechRate) }
    }

    /// Anthropic API key used by `TranslationService` to auto-translate announcement texts.
    var claudeApiKey: String {
        didSet { UserDefaults.standard.set(claudeApiKey, forKey: Key.claudeApiKey) }
    }

    /// `false` hasta que el usuario termina la pantalla de bienvenida.
    ///
    /// `RootView` la consulta para decidir si muestra `WelcomeView` en vez del flujo
    /// normal. Se puede volver a poner a `false` desde Ajustes para rever la bienvenida.
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Map from `VoiceLanguage.rawValue` to the `AVSpeechSynthesisVoice.identifier`
    /// chosen by the user for that language.
    ///
    /// An absent entry means "use the system default voice for the language".
    /// Persisted as a dictionary in `UserDefaults`.
    var voiceIdentifiers: [String: String] {
        didSet {
            UserDefaults.standard.set(voiceIdentifiers as NSDictionary,
                                      forKey: Key.voiceIdentifiers)
        }
    }

    // MARK: - Voice helpers

    /// Returns the stored voice identifier for `lang`, or `nil` when none has been saved.
    ///
    /// A `nil` return means `SpeechService` will fall back to the language-default voice.
    ///
    /// - Parameter lang: The language whose stored identifier is requested.
    /// - Returns: An `AVSpeechSynthesisVoice.identifier` string, or `nil`.
    func selectedVoiceIdentifier(for lang: VoiceLanguage) -> String? {
        voiceIdentifiers[lang.rawValue]
    }

    /// Stores (or clears) the selected voice identifier for `lang`.
    ///
    /// Pass `nil` to revert to the system-default voice for that language.
    ///
    /// - Parameters:
    ///   - identifier: Voice identifier to persist, or `nil` to clear.
    ///   - lang:       The language this identifier applies to.
    func setVoiceIdentifier(_ identifier: String?, for lang: VoiceLanguage) {
        if let identifier {
            voiceIdentifiers[lang.rawValue] = identifier
        } else {
            voiceIdentifiers.removeValue(forKey: lang.rawValue)
        }
        // didSet on voiceIdentifiers persists the updated dictionary.
    }

    // MARK: Init

    init() {
        // Migrate from old split keys if the unified key is absent.
        let stored = UserDefaults.standard.string(forKey: Key.language)
            ?? UserDefaults.standard.string(forKey: "voiceLanguage")
            ?? UserDefaults.standard.string(forKey: "uiLanguage")
            ?? ""
        language = VoiceLanguage(rawValue: stored) ?? .spanish

        let rate = UserDefaults.standard.float(forKey: Key.speechRate)
        speechRate = rate > 0 ? rate : AVSpeechUtteranceDefaultSpeechRate

        claudeApiKey = UserDefaults.standard.string(forKey: Key.claudeApiKey) ?? ""

        let storedVoices = UserDefaults.standard.dictionary(forKey: Key.voiceIdentifiers)
        voiceIdentifiers = (storedVoices as? [String: String]) ?? [:]

        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding)
    }
}
