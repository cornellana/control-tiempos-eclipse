/// VoiceCatalog.swift — Enumeration and quality-ranking of installed AVSpeechSynthesisVoice instances.
///
/// All voices must be installed by the user via iOS Settings → Accessibility →
/// Spoken Content → Voices. This type only enumerates what is already present
/// on the device — it cannot download or install voices programmatically.
///
/// Usage:
/// ```swift
/// let voices = VoiceCatalog.voices(for: "es-ES")  // sorted best-first
/// let best   = VoiceCatalog.bestVoice(for: "es-ES")
/// ```

import AVFoundation

// MARK: - VoiceOption

/// Quality tier of an installed voice, ordered worst-to-best.
///
/// Mirrors `AVSpeechSynthesisVoiceQuality` as a `Sendable` value so voice lists can be
/// built off the main actor and handed to SwiftUI without crossing isolation with
/// Objective-C reference types.
nonisolated enum VoiceQualityTier: Int, Sendable, Comparable {
    case standard = 0
    case enhanced = 1
    case premium  = 2

    /// - Parameter quality: Quality reported by `AVSpeechSynthesisVoice`.
    init(_ quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .premium:  self = .premium
        case .enhanced: self = .enhanced
        default:        self = .standard
        }
    }

    static func < (lhs: VoiceQualityTier, rhs: VoiceQualityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Snapshot of an installed voice, holding only the value data the UI needs.
///
/// Enumerating `AVSpeechSynthesisVoice.speechVoices()` costs roughly 60 ms, so the
/// result is captured once into these `Sendable` snapshots rather than being recomputed
/// whenever a SwiftUI body is re-evaluated.
struct VoiceOption: Identifiable, Sendable, Equatable {
    /// `AVSpeechSynthesisVoice.identifier` — the value persisted in `AppSettings`.
    let id: String
    /// Display name of the voice, e.g. "Mónica".
    let name: String
    /// Quality tier used for sorting and for the badge shown next to the name.
    let quality: VoiceQualityTier
}

/// Catalog of installed `AVSpeechSynthesisVoice` instances sorted by quality.
///
/// All methods are pure and stateless — safe to call from any thread. They are marked
/// `nonisolated` so they can run off the main actor even though the module defaults to
/// `@MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
nonisolated struct VoiceCatalog {

    // MARK: - Voice enumeration

    /// Returns value snapshots of every installed voice for `languageCode`, best-first.
    ///
    /// Prefer this over `voices(for:)` in SwiftUI: the result is `Sendable`, cheap to
    /// hold in `@State`, and lets the expensive enumeration run off the main actor.
    ///
    /// - Parameter languageCode: BCP-47 identifier, e.g. `"es-ES"`.
    /// - Returns: Sorted array of voice snapshots. Empty when none are installed.
    static func options(for languageCode: String) -> [VoiceOption] {
        voices(for: languageCode).map {
            VoiceOption(id: $0.identifier,
                        name: $0.name,
                        quality: VoiceQualityTier($0.quality))
        }
    }

    /// Returns all installed voices for a given BCP-47 language code, sorted by
    /// descending quality (`.premium` > `.enhanced` > `.default`), then alphabetically
    /// by name within the same quality tier.
    ///
    /// On the Simulator, premium/enhanced voices are typically absent; the list may
    /// contain only the compact default voice or be empty. Always test on a real device.
    ///
    /// - Parameter languageCode: BCP-47 identifier, e.g. `"es-ES"`, `"ca-ES"`, `"en-GB"`.
    /// - Returns: Sorted array of installed voices. May be empty if none are installed.
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == languageCode }
            .sorted {
                // Higher rawValue = higher quality (.premium = 2, .enhanced = 1, .default = 0).
                if $0.quality.rawValue != $1.quality.rawValue {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name < $1.name
            }
    }

    /// Returns the highest-quality installed voice for a language code, or `nil` if none.
    ///
    /// Equivalent to `voices(for:).first`.
    ///
    /// - Parameter languageCode: BCP-47 identifier, e.g. `"es-ES"`.
    /// - Returns: Best installed voice, or `nil` when no voice is found for the language.
    static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        voices(for: languageCode).first
    }

    // MARK: - Quality label

    /// Maps an `AVSpeechSynthesisVoiceQuality` value to a short parenthetical suffix
    /// suitable for display next to a voice name in a list (e.g. "(Premium)").
    ///
    /// This method returns a plain `String` for use in non-SwiftUI contexts such as
    /// document generation. In SwiftUI views, use the `qualityKey(_:)` helper instead
    /// so that the `.environment(\.locale, …)` value is respected.
    ///
    /// - Parameter quality: Quality level of the voice.
    /// - Returns: English parenthetical label: "(Premium)", "(Enhanced)", or "(Standard)".
    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:  return "(Premium)"
        case .enhanced: return "(Enhanced)"
        default:        return "(Standard)"
        }
    }
}
