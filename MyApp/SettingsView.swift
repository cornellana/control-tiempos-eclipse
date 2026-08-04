/// SettingsView.swift — Language, voice speed, volume, API key, and data management settings.

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
// UIKit — UIApplication.shared.open para abrir Ajustes del sistema.
import UIKit

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    // Backup / Restore state
    @State private var showBackup        = false
    @State private var showRestorePicker = false
    @State private var pendingImport:    IdentifiableBackup? = nil
    @State private var fileError:        String?             = nil

    /// SpeechService local para la previsualización de voz en Ajustes.
    /// Se mantiene vivo como @State para que no se libere mientras habla.
    @State private var previewService: SpeechService? = nil

    /// Voces instaladas para el idioma actual, cacheadas fuera del `body`.
    ///
    /// `AVSpeechSynthesisVoice.speechVoices()` enumera el catálogo completo del sistema
    /// (~180 voces) y cuesta unos 60 ms por llamada. Invocarlo dentro del `body` lo
    /// ejecutaba en cada reevaluación —cada tick del slider de velocidad, cada tecla de
    /// la clave API—, bloqueando el hilo principal y hundiendo la fluidez a ~4 fps.
    /// Ahora se calcula una sola vez por idioma, fuera del hilo principal.
    @State private var voices: [VoiceOption] = []

    /// Tour guiado a pantalla completa, lanzado desde la sección de ayuda.
    @State private var showTour = false

    var body: some View {
        NavigationStack {
            @Bindable var settings = settings
            Form {
                // Single language selector — controls both UI locale and TTS voice.
                Section {
                    Picker("Language", selection: $settings.language) {
                        ForEach(VoiceLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Language")
                } footer: {
                    Text("Controls both the app interface and the synthesised voice.")
                }

                // Voz: selector de calidad, velocidad, volumen y guía de descarga.
                Section {
                    // Picker de voz — muestra las voces instaladas para el idioma actual.
                    // La opción "System default" (nil) usa AVSpeechSynthesisVoice(language:).
                    // La lista viene de `voices`, cacheada en @State: enumerar el catálogo
                    // aquí dentro costaría 60 ms en cada reevaluación del body.
                    let voiceBinding = Binding<String?>(
                        get: { settings.voiceIdentifiers[settings.language.rawValue] },
                        set: { settings.setVoiceIdentifier($0, for: settings.language) }
                    )
                    Picker("Synthesised voice", selection: voiceBinding) {
                        Text("System default").tag(nil as String?)
                        ForEach(voices) { voice in
                            voiceRow(voice).tag(voice.id as String?)
                        }
                    }
                    .pickerStyle(.menu)

                    // Botón de previsualización — pronuncia una frase de ejemplo.
                    Button {
                        playPreview(voiceIdentifier: settings.voiceIdentifiers[settings.language.rawValue])
                    } label: {
                        Label("Preview voice", systemImage: "play.circle")
                            .foregroundStyle(Color.gold)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(speedLabel(settings.speechRate))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $settings.speechRate,
                            in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate
                        )
                        .tint(Color.gold)
                    }

                } header: {
                    Text("Voice")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        // El volumen de voz usa el volumen de medios del sistema iOS.
                        // utterance.volume no funciona en iOS 26+; los botones laterales sí.
                        Text("Volume: tap Preview, then use the iPhone's side buttons to set the level. That level is preserved during execution.")
                        Text("Premium and Enhanced voices must be downloaded in iOS Settings → search «Voices».")
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                                .font(.footnote)
                                .foregroundStyle(Color.gold)
                        }
                    }
                }

                // Claude API key — used to auto-translate announcement texts at execution time.
                Section {
                    SecureField("API Key", text: $settings.claudeApiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Translation (Claude API)")
                } footer: {
                    Text("Optional. If the language of an announcement text differs from the app language, it is translated automatically before execution.")
                }

                // Program backup and restore.
                Section {
                    Button {
                        showBackup = true
                    } label: {
                        Label("Backup Programs…", systemImage: "arrow.up.doc")
                            .foregroundStyle(Color.gold)
                    }
                    Button {
                        showRestorePicker = true
                    } label: {
                        Label("Restore from File…", systemImage: "arrow.down.doc")
                            .foregroundStyle(Color.gold)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export saves programs to a .cteprog file you can share via AirDrop or Files. Restore imports programs from a backup file.")
                }

                // Ayuda: el tour completo y el recordatorio de la pulsación larga.
                Section {
                    Button {
                        showTour = true
                    } label: {
                        Label("View tutorial", systemImage: "questionmark.circle")
                            .foregroundStyle(Color.gold)
                    }
                } header: {
                    Text("Help")
                } footer: {
                    Text("At any time in the app, press and hold any button for half a second to see a card describing what it does.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .fullScreenCover(isPresented: $showTour) { GuidedTourView() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.gold)
                }
            }
        }
        // Backup — program selection sheet.
        .sheet(isPresented: $showBackup) {
            BackupSheet()
        }
        // Restore — system file picker for .cteprog files.
        .fileImporter(
            isPresented:          $showRestorePicker,
            allowedContentTypes:  [BackupService.contentType],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        // Restore — preview and confirmation sheet.
        // Uses .sheet(item:) so the RestoreSheet always receives a non-nil backup.
        .sheet(item: $pendingImport) { item in
            RestoreSheet(backup: item.backup)
        }
        .alert("Import Error", isPresented: Binding(
            get: { fileError != nil },
            set: { if !$0 { fileError = nil } }
        )) {
            Button("OK") { fileError = nil }
        } message: {
            Text(fileError ?? "")
        }
        .preferredColorScheme(.dark)
        // Enumerar las voces instaladas solo al abrir Ajustes y al cambiar de idioma,
        // nunca dentro del body.
        .task(id: settings.language) { await loadVoices(for: settings.language) }
        // Limpiar el synthesizer de preview al salir para que no interfiera
        // con el AVSpeechSynthesizer de la ejecución (paso 5).
        .onDisappear { cleanUpPreview() }
    }

    // MARK: - File import handler

    /// Parses the file chosen via `fileImporter` and prepares the restore sheet.
    ///
    /// The delay before presenting `RestoreSheet` is required because SwiftUI cannot
    /// present a new sheet while the file picker is still animating its dismissal.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped access is required for URLs returned by fileImporter.
            let needsAccess = url.startAccessingSecurityScopedResource()
            do {
                let backup = try BackupService.importFile(from: url)
                if needsAccess { url.stopAccessingSecurityScopedResource() }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    pendingImport = IdentifiableBackup(backup: backup)
                }
            } catch {
                if needsAccess { url.stopAccessingSecurityScopedResource() }
                fileError = error.localizedDescription
            }
        case .failure(let error):
            fileError = error.localizedDescription
        }
    }

    /// Maps the raw speech rate to a human-readable label.
    private func speedLabel(_ rate: Float) -> String {
        let pct = Int(((rate - AVSpeechUtteranceMinimumSpeechRate) /
                       (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)) * 100)
        return "\(pct) %"
    }

    // MARK: - Voice picker helpers

    /// Builds a picker row showing the voice name and its quality badge.
    ///
    /// Uses `LocalizedStringKey` for the quality suffix so the in-app locale
    /// (injected via `.environment(\.locale, …)`) is respected.
    @ViewBuilder
    private func voiceRow(_ voice: VoiceOption) -> some View {
        HStack(spacing: 4) {
            Text(voice.name)
            Text(qualityKey(voice.quality))
                .foregroundStyle(.secondary)
        }
    }

    /// Maps a voice quality tier to a `LocalizedStringKey` suffix
    /// so translations in `Localizable.xcstrings` are applied correctly.
    private func qualityKey(_ quality: VoiceQualityTier) -> LocalizedStringKey {
        switch quality {
        case .premium:  return "(Premium)"
        case .enhanced: return "(Enhanced)"
        case .standard: return "(Standard)"
        }
    }

    // MARK: - Voice loading

    /// Loads the installed voices for `language` off the main actor.
    ///
    /// Runs on a detached task because `AVSpeechSynthesisVoice.speechVoices()` takes
    /// around 60 ms; doing it on the main actor would stall the sheet presentation
    /// animation. Called from `.task(id:)`, so it re-runs only when the language changes.
    ///
    /// - Parameter language: Language whose installed voices should be listed.
    private func loadVoices(for language: VoiceLanguage) async {
        let code = language.rawValue
        let loaded = await Task.detached(priority: .userInitiated) {
            VoiceCatalog.options(for: code)
        }.value
        voices = loaded
    }

    // MARK: - Preview

    /// Returns the sample phrase in the language of the selected voice.
    ///
    /// Hardcoded per language rather than using `String(localized:locale:)` because
    /// the locale matching between "es-ES" and the xcstrings "es" key is unreliable.
    private func previewPhrase(for language: VoiceLanguage) -> String {
        switch language {
        case .spanish: return "El eclipse solar comienza en diez segundos."
        case .catalan: return "L'eclipsi solar comença en deu segons."
        case .english: return "The solar eclipse begins in ten seconds."
        }
    }


    /// Pronounces a short sample phrase using the currently selected voice settings.
    ///
    /// `previewService` is stored in `@State` to keep the `SpeechService` alive
    /// for the duration of the utterance (it would be deallocated otherwise).
    /// Any in-progress preview is stopped first to avoid having two
    /// `AVSpeechSynthesizer` instances active simultaneously, which can cause
    /// the audio session volume to behave unexpectedly in execution (step 5).
    private func playPreview(voiceIdentifier: String?) {
        // Detener cualquier preview activo antes de crear uno nuevo para evitar
        // que dos AVSpeechSynthesizer compartan la sesión de audio a la vez.
        previewService?.stopAll()
        previewService?.deactivateAudioSession()

        let svc = SpeechService()
        previewService = svc
        svc.configureAudioSession()
        // Frase hardcodeada por idioma para evitar que String(localized:locale:)
        // falle al hacer matching entre "es-ES" y la clave "es" del xcstrings.
        // El texto TTS no es texto visible, por lo que hardcodear es aceptable.
        let phrase = previewPhrase(for: settings.language)
        svc.speak(phrase,
                  languageCode:    settings.language.rawValue,
                  rate:            settings.speechRate,
                  voiceIdentifier: voiceIdentifier)
    }

    /// Detiene y libera el servicio de preview al cerrar Ajustes.
    ///
    /// Si el preview aún está hablando cuando el usuario entra en ejecución (paso 5),
    /// el `AVSpeechSynthesizer` del preview y el de ejecución coincidirían sobre la
    /// misma sesión de audio, lo que puede hacer que `utterance.volume` no se aplique
    /// correctamente al primer aviso.
    private func cleanUpPreview() {
        previewService?.stopAll()
        previewService?.deactivateAudioSession()
        previewService = nil
    }
}
