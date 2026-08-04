/// Step4ProgramView.swift — Step 4: program editor.
///
/// Lists `ProgramEvent` records sorted by resolved time.
/// Each row shows the resolved local time next to the offset and message.
/// Supports tap-to-edit, swipe-to-delete, add, and delete-all.

import SwiftUI
import SwiftData
import CoreLocation
// UIKit — UIPrintInteractionController no tiene equivalente nativo en SwiftUI.
import UIKit

// MARK: - Step4ProgramView

struct Step4ProgramView: View {

    @Environment(FlowViewModel.self)  private var flow
    @Environment(AppSettings.self)    private var settings
    @Environment(\.modelContext)      private var modelContext
    @Query(sort: \ProgramEvent.sortIndex) private var events: [ProgramEvent]

    @State private var showAdd            = false
    @State private var editEvent:         ProgramEvent? = nil
    @State private var showDeleteAll      = false
    @State private var showSavedPrograms  = false
    /// Nombre del programa activo, persistido en UserDefaults para recordarlo entre sesiones.
    @AppStorage("currentProgramName") private var currentProgramName: String = ""

    // MARK: - Sorted events + contexto de fila

    /// Evento del programa emparejado con la fecha resuelta del evento anterior,
    /// necesaria para calcular el intervalo entre eventos consecutivos.
    private struct EventRow: Identifiable {
        var id: ObjectIdentifier { ObjectIdentifier(event) }
        let event: ProgramEvent
        let previousDate: Date?
    }

    private var sortedEvents: [ProgramEvent] {
        guard let circ = flow.effectiveCircumstances else { return events }
        return events.sorted {
            ($0.resolvedDate(against: circ) ?? .distantFuture) <
            ($1.resolvedDate(against: circ) ?? .distantFuture)
        }
    }

    /// Lista ordenada con cada evento y la fecha resuelta de su predecesor.
    private var eventRows: [EventRow] {
        var rows: [EventRow] = []
        var prevDate: Date? = nil
        for event in sortedEvents {
            rows.append(EventRow(event: event, previousDate: prevDate))
            prevDate = flow.effectiveCircumstances.flatMap { event.resolvedDate(against: $0) }
        }
        return rows
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle(currentProgramName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                // Izquierda: volver atrás + borrar programa (separados de los botones constructivos).
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button {
                            flow.step = .verification
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .foregroundStyle(Color.gold)
                        }
                        .tourCard(TourContent.step(15))
                        if !events.isEmpty {
                            Button(role: .destructive) {
                                showDeleteAll = true
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .tourCard(TourContent.step(16))
                        }
                    }
                }

                // Derecha: guardar/recuperar · imprimir · añadir evento.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showSavedPrograms = true
                        } label: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(Color.gold)
                        }
                        .tourCard(TourContent.step(17))
                        if !events.isEmpty {
                            Button {
                                printProgram()
                            } label: {
                                Image(systemName: "printer")
                                    .foregroundStyle(Color.gold)
                            }
                            .tourCard(TourContent.step(18))
                        }
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus").foregroundStyle(Color.gold)
                        }
                        .tourCard(TourContent.step(19))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                startExecutionButton
            }
        }
        .sheet(isPresented: $showAdd) {
            // Primer evento → C1 por defecto; resto → fase del último evento creado.
            EventEditorView(sortIndex: events.count,
                            defaultPhase: events.last?.phase ?? .c1)
                .environment(flow)
                .environment(settings)
        }
        .sheet(item: $editEvent) { ev in
            EventEditorView(event: ev)
                .environment(flow)
                .environment(settings)
        }
        .confirmationDialog(
            "Delete all events from the program?",
            isPresented: $showDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                for ev in events { modelContext.delete(ev) }
            }
        }
        .sheet(isPresented: $showSavedPrograms) {
            SavedProgramsSheet(currentEvents: events,
                               currentProgramName: $currentProgramName)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color.gold.opacity(0.6))
            Text("No events yet")
                .font(.title3)
                .foregroundStyle(.white)
            Text("Tap + to add your first timed announcement.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var eventList: some View {
        List {
            ForEach(eventRows) { row in
                Button {
                    editEvent = row.event
                } label: {
                    ProgramEventRow(
                        event:            row.event,
                        circumstances:    flow.effectiveCircumstances,
                        voiceLanguage:    settings.language.rawValue,
                        previousFireDate: row.previousDate
                    )
                }
                .buttonStyle(.plain)
                .tourCard(TourContent.step(20))
                .listRowBackground(Color.cardBackground)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        modelContext.delete(row.event)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editEvent = row.event
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var startExecutionButton: some View {
        Button {
            flow.advance()
        } label: {
            Text("Start Execution").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.gold)
        .controlSize(.large)
.tourCard(TourContent.step(21))
        .padding()
        .background(Color.appBackground)
    }
}

// MARK: - Print

extension Step4ProgramView {

    /// Genera el HTML del programa activo y abre el diálogo de impresión del sistema.
    ///
    /// Usa `UIMarkupTextPrintFormatter` para que el sistema renderice el HTML
    /// y gestione la paginación. Compatible con AirPrint y «Guardar como PDF».
    private func printProgram() {
        let formatter = UIMarkupTextPrintFormatter(markupText: buildPrintHTML())
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 28, bottom: 36, right: 28)

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = currentProgramName.isEmpty ? "Eclipse Program" : currentProgramName
        printInfo.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo      = printInfo
        controller.printFormatter = formatter
        controller.present(animated: true, completionHandler: nil)
    }

    /// Construye el documento HTML imprimible con las circunstancias del eclipse
    /// y la lista de eventos ordenada por tiempo absoluto resuelto.
    ///
    /// Usa `PrintL10n.forLanguage(_:)` para respetar el idioma seleccionado en
    /// AppSettings en lugar del locale del sistema.
    ///
    /// - Returns: Cadena HTML completa lista para `UIMarkupTextPrintFormatter`.
    private func buildPrintHTML() -> String {
        let l10n  = PrintL10n.forLanguage(settings.language)
        let circ  = flow.effectiveCircumstances
        let title = currentProgramName.isEmpty ? l10n.defaultTitle : currentProgramName

        func fmt(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .standard)
        }
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&",  with: "&amp;")
             .replacingOccurrences(of: "<",  with: "&lt;")
             .replacingOccurrences(of: ">",  with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func offsetLabel(_ ev: ProgramEvent) -> String {
            let a    = Swift.abs(ev.offsetSeconds)
            let sign = ev.offsetSeconds >= 0 ? "+" : "−"
            if a < 60 { return "\(sign)\(a)s" }
            let m = a / 60, s = a % 60
            return s == 0 ? "\(sign)\(m)m" : "\(sign)\(m)m\(s)s"
        }

        // Subtítulo: tipo de eclipse + fecha del máximo
        let kindStr: String = {
            switch circ?.kind {
            case .total:     return l10n.totalEclipse
            case .annular:   return l10n.annularEclipse
            case .partial:   return l10n.partialEclipse
            case .hybrid:    return l10n.hybridEclipse
            case .simulated: return l10n.simulation
            case nil:        return ""
            }
        }()
        let subtitle: String = {
            guard let maxDate = circ?.contacts[.max] else { return kindStr }
            return "\(kindStr) · \(maxDate.formatted(date: .long, time: .omitted))"
        }()

        // Coordenadas del lugar de observación
        let coordHTML: String = {
            guard let coord = flow.coordinate else { return "" }
            let latStr = String(format: "%.5f°", coord.latitude)
            let lonStr = String(format: "%.5f°", coord.longitude)
            let name   = flow.locationName.isEmpty ? "" : " · \(escape(flow.locationName))"
            return "<tr><td class='ph'>lat</td><td class='desc'>\(l10n.latitude)\(name)</td>"
                 + "<td class='tv'>\(latStr)</td></tr>"
                 + "<tr><td class='ph'>lon</td><td class='desc'>\(l10n.longitude)</td>"
                 + "<td class='tv'>\(lonStr)</td></tr>"
        }()

        // Tabla de circunstancias del eclipse
        let contactPhases: [(EclipsePhase, String)] = [
            (.c1,  l10n.c1Label),
            (.c2,  l10n.c2Label),
            (.max, l10n.maxLabel),
            (.c3,  l10n.c3Label),
            (.c4,  l10n.c4Label),
        ]
        var contactHTML = coordHTML
        if let circ {
            for (phase, label) in contactPhases {
                if let date = circ.contacts[phase] {
                    contactHTML += "<tr>"
                        + "<td class='ph'>\(phase.rawValue.uppercased())</td>"
                        + "<td class='desc'>\(label)</td>"
                        + "<td class='tv'>\(fmt(date))</td></tr>"
                }
            }
            if let mag = circ.magnitude {
                contactHTML += "<tr><td class='ph'>mag</td>"
                             + "<td class='desc'>\(l10n.magnitude)</td>"
                             + "<td class='tv'>\(String(format: "%.3f", mag))</td></tr>"
            }
            if let dur = circ.totalityDurationSeconds {
                let s = Int(dur)
                let durStr = s < 60 ? "\(s) s" : "\(s / 60) m \(String(format: "%02d", s % 60)) s"
                contactHTML += "<tr><td class='ph'>dur</td>"
                             + "<td class='desc'>\(l10n.totalityDuration)</td>"
                             + "<td class='tv'>\(durStr)</td></tr>"
            }
        }
        let circumstancesSection = contactHTML.isEmpty ? "" : """
            <p class="st">\(l10n.circumstancesTitle)</p>
            <table class="contacts"><tbody>\(contactHTML)</tbody></table>
        """

        // Tabla de eventos del programa
        var eventsHTML = ""
        for row in eventRows {
            let timeStr = circ.flatMap { row.event.resolvedDate(against: $0) }
                              .map { fmt($0) } ?? "—"
            eventsHTML += "<tr>"
                       + "<td class='ph'>\(row.event.phase.rawValue.uppercased())</td>"
                       + "<td class='off'>\(offsetLabel(row.event))</td>"
                       + "<td class='tv'>\(timeStr)</td>"
                       + "<td>\(escape(row.event.message))</td>"
                       + "</tr>"
        }
        let eventsSection = eventsHTML.isEmpty
            ? "<p style='color:#999;'>\(l10n.noEvents)</p>"
            : """
              <table>
                <thead><tr>
                  <th>\(l10n.phaseHeader)</th><th>\(l10n.offsetHeader)</th>
                  <th>\(l10n.timeHeader)</th><th>\(l10n.announcementHeader)</th>
                </tr></thead>
                <tbody>\(eventsHTML)</tbody>
              </table>
              """

        let generatedAt = Date.now.formatted(date: .abbreviated, time: .shortened)

        return """
        <!DOCTYPE html>
        <html lang="\(settings.language.rawValue)">
        <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: Helvetica Neue, Arial, sans-serif; font-size: 9pt; color: #1a1a1e; }
          h1   { font-size: 16pt; color: #b8985a; margin: 0 0 2px; }
          .sub { font-size: 8.5pt; color: #777; margin-bottom: 10px; }
          .st  { font-size: 7.5pt; font-weight: bold; text-transform: uppercase;
                 letter-spacing: 1px; color: #999; border-bottom: 1px solid #ddd;
                 padding-bottom: 2px; margin: 10px 0 5px; }
          table            { width: 100%; border-collapse: collapse; margin-bottom: 4px; }
          table.contacts td { padding: 2px 6px; font-size: 8.5pt; }
          td.ph  { font-weight: bold; color: #b8985a; font-family: monospace; width: 40px; }
          td.desc { color: #555; }
          td.tv  { font-family: monospace; text-align: right; }
          td.off { font-family: monospace; color: #888; font-size: 8pt; width: 50px; }
          thead th { background: #f5f5f8; padding: 4px 6px; font-size: 7.5pt;
                     text-transform: uppercase; color: #888; text-align: left; font-weight: normal; }
          tbody td { padding: 4px 6px; border-bottom: 1px solid #eee; vertical-align: top; }
          tbody tr:nth-child(odd) { background: #fafafa; }
          .footer { margin-top: 12px; font-size: 7.5pt; color: #bbb; text-align: center; }
        </style>
        </head>
        <body>
          <h1>\(escape(title))</h1>
          <div class="sub">\(escape(subtitle))</div>
          \(circumstancesSection)
          <p class="st">\(l10n.scheduleTitle)</p>
          \(eventsSection)
          <div class="footer">Control Tiempos Eclipse &nbsp;·&nbsp; \(generatedAt)</div>
        </body>
        </html>
        """
    }
}

// MARK: - PrintL10n

/// Cadenas localizadas del documento HTML imprimible.
///
/// Refleja el idioma seleccionado en AppSettings (no el locale del sistema),
/// igual que el resto de la interfaz.
private struct PrintL10n {
    let defaultTitle:       String
    let totalEclipse:       String
    let annularEclipse:     String
    let partialEclipse:     String
    let hybridEclipse:      String
    let simulation:         String
    let latitude:           String
    let longitude:          String
    let c1Label:            String
    let c2Label:            String
    let maxLabel:           String
    let c3Label:            String
    let c4Label:            String
    let magnitude:          String
    let totalityDuration:   String
    let circumstancesTitle: String
    let scheduleTitle:      String
    let phaseHeader:        String
    let offsetHeader:       String
    let timeHeader:         String
    let announcementHeader: String
    let noEvents:           String

    /// - Parameter lang: Idioma seleccionado en AppSettings.
    /// - Returns: Instancia con todas las cadenas en ese idioma.
    static func forLanguage(_ lang: VoiceLanguage) -> PrintL10n {
        switch lang {
        case .spanish:
            return PrintL10n(
                defaultTitle:       "Programa de Eclipse",
                totalEclipse:       "Eclipse Solar Total",
                annularEclipse:     "Eclipse Solar Anular",
                partialEclipse:     "Eclipse Solar Parcial",
                hybridEclipse:      "Eclipse Solar Híbrido",
                simulation:         "Simulación",
                latitude:           "Latitud",
                longitude:          "Longitud",
                c1Label:            "C1 — Primer contacto",
                c2Label:            "C2 — Comienza la totalidad",
                maxLabel:           "MAX — Máximo del eclipse",
                c3Label:            "C3 — Termina la totalidad",
                c4Label:            "C4 — Último contacto",
                magnitude:          "Magnitud",
                totalityDuration:   "Duración de la totalidad",
                circumstancesTitle: "Circunstancias del Eclipse",
                scheduleTitle:      "Programa de Avisos",
                phaseHeader:        "Fase",
                offsetHeader:       "Offset",
                timeHeader:         "Hora",
                announcementHeader: "Aviso",
                noEvents:           "Sin eventos en este programa."
            )
        case .catalan:
            return PrintL10n(
                defaultTitle:       "Programa d'Eclipsi",
                totalEclipse:       "Eclipsi Solar Total",
                annularEclipse:     "Eclipsi Solar Anular",
                partialEclipse:     "Eclipsi Solar Parcial",
                hybridEclipse:      "Eclipsi Solar Híbrid",
                simulation:         "Simulació",
                latitude:           "Latitud",
                longitude:          "Longitud",
                c1Label:            "C1 — Primer contacte",
                c2Label:            "C2 — Comença la totalitat",
                maxLabel:           "MAX — Màxim de l'eclipsi",
                c3Label:            "C3 — Acaba la totalitat",
                c4Label:            "C4 — Darrer contacte",
                magnitude:          "Magnitud",
                totalityDuration:   "Duració de la totalitat",
                circumstancesTitle: "Circumstàncies de l'Eclipsi",
                scheduleTitle:      "Programa d'Avisos",
                phaseHeader:        "Fase",
                offsetHeader:       "Offset",
                timeHeader:         "Hora",
                announcementHeader: "Avís",
                noEvents:           "Sense esdeveniments en aquest programa."
            )
        case .english:
            return PrintL10n(
                defaultTitle:       "Eclipse Program",
                totalEclipse:       "Total Solar Eclipse",
                annularEclipse:     "Annular Solar Eclipse",
                partialEclipse:     "Partial Solar Eclipse",
                hybridEclipse:      "Hybrid Solar Eclipse",
                simulation:         "Simulation",
                latitude:           "Latitude",
                longitude:          "Longitude",
                c1Label:            "C1 — First contact",
                c2Label:            "C2 — Totality begins",
                maxLabel:           "MAX — Maximum eclipse",
                c3Label:            "C3 — Totality ends",
                c4Label:            "C4 — Last contact",
                magnitude:          "Magnitude",
                totalityDuration:   "Totality duration",
                circumstancesTitle: "Eclipse Circumstances",
                scheduleTitle:      "Announcement Schedule",
                phaseHeader:        "Phase",
                offsetHeader:       "Offset",
                timeHeader:         "Time",
                announcementHeader: "Announcement",
                noEvents:           "No events in this program."
            )
        }
    }
}

// MARK: - ProgramEventRow

private struct ProgramEventRow: View {

    let event:            ProgramEvent
    let circumstances:    EclipseCircumstances?
    let voiceLanguage:    String
    /// Fecha resuelta del evento anterior en la lista (nil para el primero).
    let previousFireDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            // ── Línea 1: Fase · Texto · Hora de ocurrencia ──────────────────
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.phase.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(Color.gold)
                    .frame(width: 32, alignment: .leading)

                Text(event.message)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let date = resolvedDate {
                    Text(date.formatted(date: .omitted, time: .standard))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color.gold)
                }
            }

            // ── Línea 2: Offset desde fase · Gap desde evento anterior ───────
            HStack(spacing: 10) {
                // Offset del evento respecto a su fase de referencia, p.ej. "C2 +20s".
                Text(phaseOffsetLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Badge de traducción cuando el idioma del texto difiere del de la voz.
                if event.textLanguage != voiceLanguage {
                    Label("\(event.textLanguage) → \(voiceLanguage)",
                          systemImage: "character.bubble")
                        .font(.caption2)
                        .foregroundStyle(Color.gold.opacity(0.7))
                }

                Spacer()

                // Tiempo transcurrido desde el evento anterior de la lista.
                if let gap = gapFromPreviousLabel {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .semibold))
                        Text(gap)
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 40) // alineado con el texto, no con la fase
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var resolvedDate: Date? {
        circumstances.flatMap { event.resolvedDate(against: $0) }
    }

    /// "C2 +20s", "MAX −30s", "C1 +0s", etc.
    private var phaseOffsetLabel: String {
        "\(event.phase.rawValue.uppercased()) \(offsetFormatted)"
    }

    private var offsetFormatted: String {
        let abs  = Swift.abs(event.offsetSeconds)
        let sign = event.offsetSeconds >= 0 ? "+" : "−"
        if abs < 60  { return "\(sign)\(abs)s" }
        let m = abs / 60, s = abs % 60
        return s == 0 ? "\(sign)\(m)m" : "\(sign)\(m)m\(s)s"
    }

    /// Intervalo legible entre el evento anterior y este, p.ej. "45s" o "1m30s".
    /// Nil para el primer evento o cuando no hay fecha resuelta.
    private var gapFromPreviousLabel: String? {
        guard let prev = previousFireDate, let curr = resolvedDate else { return nil }
        let gap = curr.timeIntervalSince(prev)
        guard gap > 0 else { return nil }
        let total = Int(gap.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m\(s)s"
    }
}

// MARK: - EventEditorView

struct EventEditorView: View {

    @Environment(\.modelContext)     private var modelContext
    @Environment(\.dismiss)          private var dismiss
    @Environment(FlowViewModel.self) private var flow
    @Environment(AppSettings.self)   private var settings

    private let existingEvent: ProgramEvent?
    private let newSortIndex:  Int

    @State private var selectedPhase: EclipsePhase
    @State private var offsetText    = "0"
    @State private var message       = ""
    @State private var textLanguage  = "es-ES"

    // MARK: - Init

    /// Editing an existing event.
    init(event: ProgramEvent) {
        existingEvent = event
        newSortIndex  = event.sortIndex
        _selectedPhase = State(initialValue: event.phase)
    }

    /// Creating a new event.
    /// - Parameter defaultPhase: Fase preseleccionada — C1 para el primero,
    ///   la del último evento creado para los siguientes.
    init(sortIndex: Int, defaultPhase: EclipsePhase = .c1) {
        existingEvent  = nil
        newSortIndex   = sortIndex
        _selectedPhase = State(initialValue: defaultPhase)
    }

    // MARK: - Derived

    private var parsedOffset: Int { Int(offsetText) ?? 0 }

    private var resolvedDate: Date? {
        guard let circ = flow.effectiveCircumstances,
              let base = circ.contacts[selectedPhase] else { return nil }
        return base.addingTimeInterval(Double(parsedOffset))
    }

    private var availablePhases: [EclipsePhase] {
        guard let circ = flow.effectiveCircumstances else { return EclipsePhase.allCases }
        return EclipsePhase.allCases.filter { circ.contacts[$0] != nil }
    }

    private var canSave: Bool {
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                timingSection
                announcementSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(existingEvent == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { populateFromExisting() }
    }

    // MARK: - Form sections

    private var timingSection: some View {
        Section {
            // .menu style shows the selected value in the row and a dropdown on tap.
            Picker("Phase", selection: $selectedPhase) {
                ForEach(availablePhases, id: \.self) { phase in
                    Text(phase.rawValue.uppercased()).tag(phase)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Offset (s)")
                Spacer()
                TextField("0", text: $offsetText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            if let date = resolvedDate {
                HStack {
                    Text("Resolved time")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(date.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(Color.gold)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Timing")
        }
    }

    private var announcementSection: some View {
        Section {
            // TextEditor con altura fija — evita el recálculo de layout en cada keystroke
            // que causaba lag con TextField(axis:.vertical) + lineLimit dinámico.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .frame(minHeight: 72, maxHeight: 72)
                    .scrollContentBackground(.hidden)
                if message.isEmpty {
                    Text("e.g. Remove solar filter")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }

            // Language of the announcement text — used to auto-translate at execution time
            // if the voice language differs.
            Picker("Text Language", selection: $textLanguage) {
                ForEach(VoiceLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Announcement")
        } footer: {
            Text("If the text language differs from the voice language, texts are translated automatically before execution.")
        }
    }

    // MARK: - Helpers

    private func populateFromExisting() {
        if let ev = existingEvent {
            // selectedPhase ya está inicializado desde el init; los demás campos aquí.
            offsetText   = String(ev.offsetSeconds)
            message      = ev.message
            textLanguage = ev.textLanguage
        } else {
            // Idioma del texto por defecto = idioma de voz actual.
            textLanguage = settings.language.rawValue
        }
    }

    private func save() {
        if let ev = existingEvent {
            ev.phase         = selectedPhase
            ev.offsetSeconds = parsedOffset
            ev.message       = message
            ev.textLanguage  = textLanguage
        } else {
            modelContext.insert(ProgramEvent(
                phase:         selectedPhase,
                offsetSeconds: parsedOffset,
                message:       message,
                textLanguage:  textLanguage,
                sortIndex:     newSortIndex
            ))
        }
    }
}

// MARK: - SavedProgramsSheet

/// Sheet for managing named program snapshots.
///
/// Allows saving the current event list with a name and restoring any
/// previously saved program (which replaces the active events after confirmation).
fileprivate struct SavedProgramsSheet: View {

    /// Active program events passed from the parent (to save them).
    let currentEvents: [ProgramEvent]
    /// Nombre del programa activo, compartido con el padre via binding para persistirlo.
    @Binding var currentProgramName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Query(sort: \SavedProgram.name) private var savedPrograms: [SavedProgram]

    @State private var showSaveAlert      = false
    @State private var saveName           = ""
    @State private var programToLoad:     SavedProgram? = nil
    @State private var showLoadConfirm    = false
    @State private var showOverwriteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    // Guardar el programa activo — solo visible cuando hay eventos.
                    if !currentEvents.isEmpty {
                        Section {
                            Button {
                                // Pre-rellenar con el nombre activo; si nunca se guardó, proponer "Program".
                                saveName = currentProgramName.isEmpty ? "Program" : currentProgramName
                                showSaveAlert = true
                            } label: {
                                Label("Save current program…",
                                      systemImage: "bookmark.badge.plus")
                                    .foregroundStyle(Color.gold)
                            }
                            .listRowBackground(Color.cardBackground)
                        } footer: {
                            Text("\(currentEvents.count) event(s)")
                        }
                    }

                    // Lista de programas guardados.
                    Section {
                        if savedPrograms.isEmpty {
                            Text("No saved programs yet.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .listRowBackground(Color.cardBackground)
                        } else {
                            ForEach(savedPrograms) { program in
                                Button {
                                    programToLoad   = program
                                    showLoadConfirm = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(program.name)
                                            .font(.callout)
                                            .foregroundStyle(.white)
                                        HStack(spacing: 8) {
                                            Text("\(program.eventCount) events")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text("·")
                                                .foregroundStyle(.tertiary)
                                            Text(program.createdAt
                                                    .formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(Color.cardBackground)
                            }
                            .onDelete { indexSet in
                                indexSet.map { savedPrograms[$0] }.forEach {
                                    modelContext.delete($0)
                                }
                            }
                        }
                    } header: {
                        Text("Saved programs")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().foregroundStyle(Color.gold)
                }
            }
        }
        // Alert para poner nombre al programa que se guardará.
        .alert("Save Program", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCurrentProgram() }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("\(currentEvents.count) event(s) will be saved.")
        }
        // Confirmación antes de reemplazar el programa activo.
        .confirmationDialog(
            "Load \"\(programToLoad?.name ?? "")\"?",
            isPresented: $showLoadConfirm,
            titleVisibility: .visible
        ) {
            Button("Load — replace current program", role: .destructive) {
                if let prog = programToLoad { loadProgram(prog) }
            }
        } message: {
            Text("The current program (\(currentEvents.count) events) will be replaced.")
        }
        // Confirmación antes de sobrescribir un programa guardado con el mismo nombre.
        .confirmationDialog(
            "Replace \"\(saveName.trimmingCharacters(in: .whitespaces))\"?",
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) { overwriteProgram() }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("A saved program with this name already exists. Overwriting will replace it.")
        }
    }

    // MARK: - Actions

    private func saveCurrentProgram() {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Si ya existe un programa con ese nombre, pedir confirmación antes de sobrescribir.
        // Se difiere la presentación del confirmationDialog con Task para que SwiftUI termine
        // de cerrar el .alert antes de mostrar el nuevo diálogo (restricción del sistema).
        if savedPrograms.contains(where: { $0.name == trimmed }) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                showOverwriteConfirm = true
            }
            return
        }
        performSave(name: trimmed)
    }

    /// Elimina el programa existente con el mismo nombre y lo reemplaza por el actual.
    private func overwriteProgram() {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = savedPrograms.first(where: { $0.name == trimmed }) {
            modelContext.delete(existing)
        }
        performSave(name: trimmed)
    }

    /// Inserta un nuevo `SavedProgram` con el nombre dado y actualiza el nombre activo.
    private func performSave(name: String) {
        modelContext.insert(SavedProgram(name: name, events: currentEvents))
        currentProgramName = name
        saveName = ""
    }

    private func loadProgram(_ program: SavedProgram) {
        // Borrar todos los eventos activos.
        for ev in currentEvents { modelContext.delete(ev) }
        // Insertar copias de los eventos del programa guardado.
        for (i, snap) in program.decodedEvents.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            modelContext.insert(ProgramEvent(
                phase:         EclipsePhase(rawValue: snap.phaseRaw) ?? .c1,
                offsetSeconds: snap.offsetSeconds,
                message:       snap.message,
                textLanguage:  snap.textLanguage,
                sortIndex:     i
            ))
        }
        currentProgramName = program.name  // recordar el nombre del programa cargado
        dismiss()
    }
}
