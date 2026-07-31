/// SpeechService.swift — AVSpeechSynthesizer wrapper with audio session management.
///
/// Wraps AVSpeechSynthesizer in a simple queue-aware service.
/// The synthesizer naturally queues consecutive speak() calls without overlap.
/// Audio session category: `.playback`, mode: `.spokenAudio` (designed for TTS),
/// option `.duckOthers` so announcements are audible over ambient music.

import AVFoundation

/// Manages text-to-speech synthesis and AVAudioSession for the execution phase.
final class SpeechService {

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Audio session

    /// Activates the shared audio session for spoken-audio playback.
    ///
    /// `.spokenAudio` mode is specifically designed for TTS: it pauses other audio
    /// apps when speaking and resumes them afterward, producing cleaner output than
    /// the generic `.playback` mode.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Modo .default en lugar de .spokenAudio: en iOS 26+ el modo .spokenAudio
        // puede ignorar utterance.volume al normalizar el TTS internamente.
        // Con .default, utterance.volume se respeta y .duckOthers sigue activo.
        try? session.setCategory(.playback, mode: .default, options: .duckOthers)
        try? session.setActive(true)
    }

    /// Deactivates the audio session and notifies other apps.
    /// Call once when leaving execution.
    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: - Synthesis

    /// Enqueues `text` for synthesis using the best available voice for the language.
    ///
    /// Voice resolution priority:
    /// 1. `voiceIdentifier` → resolved via `AVSpeechSynthesisVoice(identifier:)`.
    ///    If the identifier is invalid or the voice was uninstalled, falls through to 2.
    /// 2. `AVSpeechSynthesisVoice(language: languageCode)` — system default for the language.
    ///
    /// If no voice is installed for `languageCode`, AVSpeechSynthesizer falls back
    /// to the system default voice and continues speaking without crashing.
    ///
    /// - Parameters:
    ///   - text:             The text to pronounce.
    ///   - languageCode:     BCP-47 code, e.g. "es-ES", "ca-ES", "en-GB".
    ///   - rate:             Speech rate (clamped to AVSpeechUtteranceRate valid range).
    ///   - volume:           Playback volume 0.0…1.0 (maps to user-chosen 0–100 %).
    ///   - voiceIdentifier:  Optional `AVSpeechSynthesisVoice.identifier` for a specific
    ///                       installed voice (premium/enhanced). `nil` uses the language default.
    func speak(_ text: String,
               languageCode: String,
               rate: Float,
               voiceIdentifier: String? = nil) {
        let utterance = AVSpeechUtterance(string: text)
        // Intentar resolver la voz específica elegida por el usuario; si no está disponible,
        // caer al selector por idioma (comportamiento original).
        if let identifier = voiceIdentifier,
           let specificVoice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = specificVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        }
        utterance.rate   = max(AVSpeechUtteranceMinimumSpeechRate,
                               min(rate, AVSpeechUtteranceMaximumSpeechRate))
        // utterance.volume ignorado en iOS 26+; el volumen lo controla MPVolumeView
        // (volumen hardware del sistema) desde los ajustes de la app.
        utterance.volume = 1.0
        // Small post-delay prevents consecutive utterances from running together.
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Stops all pending and in-progress utterances immediately.
    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
