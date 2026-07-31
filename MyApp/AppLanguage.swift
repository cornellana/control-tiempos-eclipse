/// AppLanguage.swift — Resolves imperative localized strings against the in-app language.
///
/// SwiftUI's declarative text already follows the in-app language selector: `Text("key")`
/// takes a `LocalizedStringKey` and honours the locale injected at the root with
/// `.environment(\.locale, settings.locale)`.
///
/// Imperative lookups do not. `String(localized:)` resolves against `Bundle.main`, whose
/// active localization comes from the *system* language list, ignoring the app's own
/// selector. That left the execution header and the stop button in English while the rest
/// of the interface was in Spanish — precisely the strings the photographer reads during
/// totality.
///
/// This type resolves each lookup against the `.lproj` bundle of the selected language.

import Foundation

// MARK: - AppLanguage

/// Looks up localized strings in the bundle of a specific `VoiceLanguage`.
///
/// Use it only where `LocalizedStringKey` is unavailable — view models, services, and any
/// other non-`View` context. Inside a `View`, prefer `Text("key", comment:)`, which already
/// respects the injected locale.
///
/// ## Usage
/// ```swift
/// let title = AppLanguage.string("Totality", language: .catalan)  // "Totalitat"
/// ```
enum AppLanguage {

    // MARK: - Bundle resolution

    /// Cache of `.lproj` bundles keyed by short language code ("es", "ca", "en").
    ///
    /// Loading a bundle touches the filesystem, so each language is resolved at most once.
    private static var bundleCache: [String: Bundle] = [:]

    /// Returns the localization bundle for `language`, or `Bundle.main` as a fallback.
    ///
    /// Falls back to `Bundle.main` when the `.lproj` folder is missing — an app compiled
    /// without that localization still shows text rather than raw keys.
    ///
    /// - Parameter language: Language whose bundle is requested.
    /// - Returns: The `.lproj` bundle for that language, or `Bundle.main`.
    static func bundle(for language: VoiceLanguage) -> Bundle {
        let code = language.bundleCode
        if let cached = bundleCache[code] { return cached }
        guard let path   = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        bundleCache[code] = bundle
        return bundle
    }

    // MARK: - Lookup

    /// Returns `key` translated into `language`.
    ///
    /// The lookup goes through the String Catalog (`Localizable.xcstrings`) compiled into
    /// the language's `.lproj` bundle. When the key is absent the key itself is returned,
    /// matching `NSLocalizedString` behaviour.
    ///
    /// - Parameters:
    ///   - key:      String Catalog key, e.g. `"Totality"`.
    ///   - language: Language to translate into.
    /// - Returns: The translated string, or `key` when no translation exists.
    static func string(_ key: String, language: VoiceLanguage) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: nil)
    }
}

// MARK: - VoiceLanguage bundle code

extension VoiceLanguage {

    /// Short code identifying the `.lproj` folder for this language.
    ///
    /// The project's localizations are `es`, `ca` and `en`, while `rawValue` carries the
    /// full BCP-47 tag ("es-ES") required by `AVSpeechSynthesisVoice`. This maps one to
    /// the other.
    var bundleCode: String {
        switch self {
        case .spanish: return "es"
        case .catalan: return "ca"
        case .english: return "en"
        }
    }
}
