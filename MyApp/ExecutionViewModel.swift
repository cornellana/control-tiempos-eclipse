/// ExecutionViewModel.swift — Timer-driven state machine for the execution phase.
///
/// Resolves program events to absolute dates, fires a 0.25 s tick timer that
/// compares Date.now against each cue's fireDate (no accumulated drift), and
/// coordinates speech synthesis and haptics at the correct instant.
///
/// When `voiceLanguage` differs from a cue's `textLanguage`, `preTranslate(apiKey:)` is
/// called first (async, before starting the timer) to translate via the Claude API.
///
/// All public mutations happen on the main actor so SwiftUI observations are safe.

import Foundation
import UIKit
import Observation

// MARK: - Domain types

/// Execution state of a single scheduled cue.
enum CueState { case pending, spoken, skipped }

/// A program event resolved to an absolute fire time, ready for execution.
struct ScheduledCue: Identifiable {
    let id:           UUID
    let fireDate:     Date
    let message:      String   // original text in textLanguage
    let textLanguage: String   // BCP-47 code of message
    var state:        CueState
}

// MARK: - ExecutionViewModel

/// Observable state machine for Step 5 (execution).
///
/// - Create from `EclipseCircumstances` + `[ProgramEvent]` after Step 4.
/// - Call `await preTranslate(apiKey:)` if translation may be needed.
/// - Call `start()` once translation is done; call `stop()` when leaving.
/// - The tick timer runs on RunLoop.common to fire during scroll events.
@MainActor
@Observable final class ExecutionViewModel {

    // MARK: - Observed state (drives the UI)

    /// All cues ordered by fire time. Mutated in-place as cues are fired.
    private(set) var allCues: [ScheduledCue]

    /// Updated every tick (0.25 s); use to compute countdowns.
    private(set) var now: Date = .now

    /// Human-readable name of the eclipse phase containing `now`.
    private(set) var currentPhaseName: String = ""

    /// The next upcoming eclipse contact (nil after C4).
    private(set) var nextContactPhase: EclipsePhase?

    /// Absolute time of the next upcoming contact.
    private(set) var nextContactDate: Date?

    /// True while the pre-translation async pass is running.
    private(set) var isTranslating = false

    // MARK: - Convenience computed properties

    /// First cue still waiting to be spoken.
    var nextPendingCue: ScheduledCue? {
        allCues.first { $0.state == .pending }
    }

    /// Returns the text to display for a cue: the Claude-translated version if available,
    /// otherwise the original message. This is what the user reads on screen during execution.
    func displayMessage(for cue: ScheduledCue) -> String {
        translatedTexts[cue.id] ?? cue.message
    }

    // MARK: - Private state

    let circumstances: EclipseCircumstances

    private let speech:          SpeechService
    private let voiceLanguage:   String
    private let voiceIdentifier: String?   // AVSpeechSynthesisVoice.identifier, nil = idioma por defecto
    private let speechRate:      Float
    private var timer:         Timer?
    private let haptic = UINotificationFeedbackGenerator()

    /// Cache of Claude-translated texts keyed by cue UUID.
    /// Falls back to `cue.message` if the cue's id is absent (translation skipped or failed).
    private var translatedTexts: [UUID: String] = [:]

    // MARK: - Init

    /// - Parameters:
    ///   - circumstances:   Eclipse contacts used for cue resolution and phase display.
    ///   - events:          Raw program events from SwiftData; resolved to absolute dates here.
    ///   - voiceLanguage:   BCP-47 code for `AVSpeechSynthesisVoice` selection.
    ///   - speechRate:      AVSpeechUtterance rate (clamped internally).
    ///   - voiceIdentifier: Optional `AVSpeechSynthesisVoice.identifier` for a premium/enhanced
    ///                      voice; `nil` falls back to the language-default voice.
    init(circumstances: EclipseCircumstances,
         events: [ProgramEvent],
         voiceLanguage: String,
         speechRate: Float,
         voiceIdentifier: String? = nil) {

        self.circumstances   = circumstances
        self.voiceLanguage   = voiceLanguage
        self.voiceIdentifier = voiceIdentifier
        self.speechRate      = speechRate
        self.speech          = SpeechService()

        // Contactos presentes, en orden cronológico. Fijos durante toda la ejecución.
        self.orderedContacts = [EclipsePhase.c1, .c2, .max, .c3, .c4].compactMap { phase in
            guard let date = circumstances.contacts[phase] else { return nil }
            return (phase: phase, date: date)
        }

        // Etiquetas de fase en el idioma elegido en Ajustes, no en el del sistema.
        // Si el código no corresponde a ningún idioma soportado se cae a español, que es
        // el idioma de trabajo de Francisco.
        let lang = VoiceLanguage(rawValue: voiceLanguage) ?? .spanish
        self.eclipseCompleteLabel = AppLanguage.string("Eclipse Complete", language: lang)
        self.beforeEclipseLabel   = AppLanguage.string("Before Eclipse",   language: lang)
        self.partialPhaseLabel    = AppLanguage.string("Partial Phase",    language: lang)
        self.totalityLabel        = AppLanguage.string("Totality",         language: lang)

        let t = Date.now
        self.allCues = events.compactMap { event -> ScheduledCue? in
            guard let fireDate = event.resolvedDate(against: circumstances) else { return nil }
            return ScheduledCue(id:           UUID(),
                                fireDate:     fireDate,
                                message:      event.message,
                                textLanguage: event.textLanguage,
                                state:        fireDate <= t ? .skipped : .pending)
        }.sorted { $0.fireDate < $1.fireDate }

        self.now = t
        updatePhase(now: t)
    }

    // MARK: - Translation pre-pass

    /// Translates all pending cues whose `textLanguage` differs from `voiceLanguage`
    /// using the Claude API. Runs before `start()` is called from `Step5ExecutionView`.
    ///
    /// Cues that fail to translate silently fall back to their original `message`.
    /// This method is a no-op when `apiKey` is empty or all cues share the voice language.
    ///
    /// - Parameter apiKey: Anthropic API key from `AppSettings.claudeApiKey`.
    func preTranslate(apiKey: String) async {
        guard !apiKey.isEmpty else { return }

        let needsTranslation = allCues.filter {
            $0.state == .pending && $0.textLanguage != voiceLanguage
        }
        guard !needsTranslation.isEmpty else { return }

        isTranslating = true
        defer { isTranslating = false }

        // Capture value types so tasks don't reference self under @MainActor isolation.
        let targetLang = voiceLanguage

        var results: [UUID: String] = [:]

        await withTaskGroup(of: (UUID, String?).self) { group in
            for cue in needsTranslation {
                let cueId      = cue.id
                let message    = cue.message
                let sourceLang = cue.textLanguage
                group.addTask {
                    do {
                        let translated = try await TranslationService.translate(
                            message,
                            from: sourceLang,
                            to:   targetLang,
                            apiKey: apiKey
                        )
                        return (cueId, translated)
                    } catch {
                        // Fall back silently — original text will be used.
                        return (cueId, nil)
                    }
                }
            }

            for await (id, translated) in group {
                if let translated { results[id] = translated }
            }
        }

        translatedTexts.merge(results) { _, new in new }
    }

    // MARK: - Lifecycle

    /// Starts the tick timer, enables idle-timer prevention and audio session.
    /// Call after `await preTranslate(apiKey:)` if translation is required.
    func start() {
        speech.configureAudioSession()
        UIApplication.shared.isIdleTimerDisabled = true
        haptic.prepare()

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops the timer, stops speech, and re-enables the idle timer.
    func stop() {
        timer?.invalidate()
        timer = nil
        speech.stopAll()
        speech.deactivateAudioSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Tick

    /// Called every 0.25 s. Compares current time against each pending cue's fireDate.
    /// Ref: CLAUDE.md §3 — "nunca acumular intervalos; comparar Date.now contra el próximo instante".
    private func tick() {
        let t = Date.now
        now = t
        updatePhase(now: t)

        for i in allCues.indices {
            guard allCues[i].state == .pending else { continue }
            guard allCues[i].fireDate <= t     else { break }
            allCues[i].state = .spoken
            // Use translated text when available; fall back to original message.
            let text = translatedTexts[allCues[i].id] ?? allCues[i].message
            speech.speak(text,
                         languageCode:    voiceLanguage,
                         rate:            speechRate,
                         voiceIdentifier: voiceIdentifier)
            haptic.notificationOccurred(.success)
        }
    }

    // MARK: - Eclipse phase tracking

    /// Contactos conocidos ordenados cronológicamente.
    ///
    /// Se calcula una vez en el init: reconstruir este array en cada tick (4 veces por
    /// segundo) era trabajo repetido sobre datos que no cambian durante la ejecución.
    private let orderedContacts: [(phase: EclipsePhase, date: Date)]

    /// Updates the phase labels for `now`.
    ///
    /// Solo escribe en las propiedades observadas cuando el valor cambia realmente. Asignar
    /// `currentPhaseName` en cada tick invalidaba la cabecera y, con ella, toda la lista de
    /// cues superpuesta sobre el mapa, cuatro veces por segundo.
    private func updatePhase(now: Date) {
        guard let nextIdx = orderedContacts.firstIndex(where: { $0.date > now }) else {
            setPhaseName(eclipseCompleteLabel)
            if nextContactPhase != nil { nextContactPhase = nil }
            if nextContactDate  != nil { nextContactDate  = nil }
            return
        }

        let next = orderedContacts[nextIdx]
        if nextContactPhase != next.phase { nextContactPhase = next.phase }
        if nextContactDate  != next.date  { nextContactDate  = next.date }

        setPhaseName(nextIdx == 0
                     ? beforeEclipseLabel
                     : labelAfter(phase: orderedContacts[nextIdx - 1].phase))
    }

    /// Asigna `currentPhaseName` solo si difiere del valor actual.
    private func setPhaseName(_ name: String) {
        if currentPhaseName != name { currentPhaseName = name }
    }

    // MARK: - Localised phase labels
    //
    // Se resuelven una sola vez en el init, contra el bundle del idioma elegido DENTRO de
    // la app (AppLanguage). `String(localized:)` habría usado el idioma del sistema y dejaba
    // la cabecera en inglés con la interfaz en español. Cachearlas evita además consultar el
    // bundle dos veces por tick, cuatro veces por segundo.

    private let eclipseCompleteLabel: String
    private let beforeEclipseLabel:   String
    private let partialPhaseLabel:    String
    private let totalityLabel:        String

    private func labelAfter(phase: EclipsePhase) -> String {
        switch phase {
        case .c1:  return partialPhaseLabel
        case .c2:  return totalityLabel
        case .max: return circumstances.kind == .total || circumstances.kind == .annular
                        ? totalityLabel
                        : partialPhaseLabel
        case .c3:  return partialPhaseLabel
        case .c4:  return eclipseCompleteLabel
        }
    }
}
