/// ProgramEvent.swift — SwiftData model for a timed announcement in the eclipse program.

import SwiftData
import Foundation

/// A single timed announcement, defined relative to an eclipse phase.
///
/// Stored persistently with SwiftData. Resolved to an absolute `Date` at runtime
/// by `resolvedDate(against:)` using the actual or simulated eclipse circumstances.
@Model final class ProgramEvent {

    // MARK: - Stored properties

    /// Raw value of the reference `EclipsePhase`.
    var phaseRaw: String

    /// Seconds relative to the reference phase. Negative = before the phase.
    var offsetSeconds: Int

    /// Text spoken aloud by `AVSpeechSynthesizer` at the resolved time.
    var message: String

    /// BCP-47 language code of the `message` text (e.g. "es-ES", "ca-ES", "en-GB").
    /// Used by `ExecutionViewModel` to detect when auto-translation is required
    /// (i.e. when `textLanguage != voiceLanguage`).
    /// Defaults to "es-ES" for backward compatibility with pre-existing records.
    var textLanguage: String = "es-ES"

    /// Stable position index used for display ordering.
    var sortIndex: Int

    // MARK: - Init

    /// - Parameters:
    ///   - phase:        Reference eclipse phase.
    ///   - offsetSeconds: Signed offset in seconds from the phase.
    ///   - message:      Text to be spoken.
    ///   - textLanguage: BCP-47 code of the message language (default "es-ES").
    ///   - sortIndex:    Position for stable list ordering.
    init(phase: EclipsePhase,
         offsetSeconds: Int,
         message: String,
         textLanguage: String = "es-ES",
         sortIndex: Int) {
        self.phaseRaw      = phase.rawValue
        self.offsetSeconds = offsetSeconds
        self.message       = message
        self.textLanguage  = textLanguage
        self.sortIndex     = sortIndex
    }

    // MARK: - Computed helpers

    /// The reference eclipse phase, derived from the stored raw value.
    var phase: EclipsePhase {
        get { EclipsePhase(rawValue: phaseRaw) ?? .c1 }
        set { phaseRaw = newValue.rawValue }
    }

    /// Resolves this event to an absolute UTC `Date` using real or simulated circumstances.
    ///
    /// Returns `nil` when the reference phase is absent in the circumstances
    /// (e.g., C2 for a partial eclipse).
    ///
    /// - Parameter circumstances: Eclipse circumstances for the observer.
    /// - Returns: Absolute `Date` of the event, or `nil` if the phase is unavailable.
    func resolvedDate(against circumstances: EclipseCircumstances) -> Date? {
        guard let base = circumstances.contacts[phase] else { return nil }
        return base.addingTimeInterval(Double(offsetSeconds))
    }
}
