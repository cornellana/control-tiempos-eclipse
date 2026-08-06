/// EclipseCardView.swift — Displays computed local eclipse circumstances.
///
/// Shows contact times (in the device timezone), magnitude, totality duration,
/// and solar position at maximum. Adapts to partial eclipses (no C2/C3).
///
/// Between the kind badge and the contact times sits a row of external
/// verification links: xjubier.free.fr (am I inside the totality band?) and
/// peakfinder.com (is anything blocking my view of the Sun?). Each button
/// appears only when its URL is non-nil.
///
/// All labels use `LocalizedStringKey` so that the in-app language selector
/// (injected via `.environment(\.locale, ...)`) is respected at runtime.

import SwiftUI

struct EclipseCardView: View {

    let circumstances: EclipseCircumstances

    /// When non-nil, a link to Xavier Jubier's interactive eclipse map is shown.
    var xjubierURL: URL? = nil

    /// When non-nil, a link to PeakFinder's panorama — aimed at the Sun's position
    /// at maximum — is shown next to the xjubier one.
    var peakFinderURL: URL? = nil

    @Environment(\.openURL) private var openURL
    @State private var showHelp = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            kindBadge
            externalLinksRow
            contactsGrid
            additionalInfo
        }
        .padding()
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showHelp) { HelpSheet() }
    }

    // MARK: - Kind badge

    private var kindBadge: some View {
        HStack(alignment: .center, spacing: 8) {
            // Tipo de eclipse.
            Text(kindLabel)
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.gold, in: Capsule())

            Spacer()

            // Para eclipses parciales mostramos magnitud y porcentaje de área.
            // Para los demás tipos solo la magnitud técnica.
            VStack(alignment: .trailing, spacing: 2) {
                if let mag = circumstances.magnitude {
                    Text(String(format: "mag %.3f", mag))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if circumstances.kind == .partial, let osc = circumstances.obscuration {
                    Text(String(format: "%.1f%% area", osc * 100))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.gold)
                }
            }

            // Botón de ayuda.
            Button { showHelp = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.gold.opacity(0.60))
            }
            .accessibilityLabel(Text("Eclipse concepts help"))
        }
    }

    // MARK: - External links

    /// Fila con los enlaces de verificación externos.
    ///
    /// Viven en su propia fila y no dentro de `kindBadge`: con el badge de tipo, la
    /// magnitud y el botón de ayuda ya compitiendo por el ancho, dos cápsulas más
    /// dejaban la fila impracticable en un iPhone compacto.
    /// Uno a cada extremo de la fila: separarlos evita el toque equivocado con el pulgar
    /// y deja claro que son dos comprobaciones distintas, no una lista.
    @ViewBuilder
    private var externalLinksRow: some View {
        if xjubierURL != nil || peakFinderURL != nil {
            HStack(spacing: 10) {
                if let url = xjubierURL {
                    linkPill(icon: "globe", label: "xjubier.free.fr", url: url)
                        .tourCard(TourContent.step(5))
                }
                Spacer(minLength: 0)
                if let url = peakFinderURL {
                    linkPill(icon: "mountain.2", label: "peakfinder.com", url: url)
                        .tourCard(TourContent.step(25))
                }
            }
        }
    }

    /// Cápsula con borde dorado que abre una web externa en el navegador.
    private func linkPill(icon: String, label: LocalizedStringKey, url: URL) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(Color.gold.opacity(0.9))
            .padding(.vertical, 6)
            .padding(.horizontal, 11)
            .background(
                Capsule()
                    .stroke(Color.gold.opacity(0.4), lineWidth: 0.75)
            )
        }
    }

    // MARK: - Contacts grid

    private var contactsGrid: some View {
        VStack(spacing: 8) {
            contactRow(phase: .c1,  label: "C1 — First contact")
            contactRow(phase: .c2,  label: "C2 — Totality begins")
            contactRow(phase: .max, label: "MAX — Maximum eclipse")
            contactRow(phase: .c3,  label: "C3 — Totality ends")
            contactRow(phase: .c4,  label: "C4 — Last contact")
        }
    }

    @ViewBuilder
    private func contactRow(phase: EclipsePhase, label: LocalizedStringKey) -> some View {
        if let date = circumstances.contacts[phase] {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(date.formatted(date: .omitted, time: .standard))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Additional info

    @ViewBuilder
    private var additionalInfo: some View {
        let hasExtra = circumstances.totalityDurationSeconds != nil
                    || circumstances.sunAltitudeAtMax != nil
                    || circumstances.sunAzimuthAtMax  != nil
                    || (circumstances.kind == .annular && circumstances.obscuration != nil)
        if hasExtra {
            Divider().background(.secondary.opacity(0.3))
            VStack(spacing: 6) {
                if let dur = circumstances.totalityDurationSeconds {
                    infoRow(label: "Totality", value: formatDuration(dur))
                }
                // Para eclipses anulares el porcentaje de área cubierta es relevante
                // (cuánto disco solar queda oculto cuando la Luna pasa centrada).
                if circumstances.kind == .annular, let osc = circumstances.obscuration {
                    infoRow(label: "Coverage", value: String(format: "%.1f%%", osc * 100))
                }
                if let alt = circumstances.sunAltitudeAtMax {
                    infoRow(label: "Sun Altitude", value: String(format: "%.1f°", alt))
                }
                if let az = circumstances.sunAzimuthAtMax {
                    infoRow(label: "Sun Azimuth", value: String(format: "%.1f°", az))
                }
            }
        }
    }

    private func infoRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.gold)
        }
    }

    // MARK: - Helpers

    /// Badge label as `LocalizedStringKey` so `Text(kindLabel)` respects the
    /// in-app locale injected via `.environment(\.locale, ...)`.
    private var kindLabel: LocalizedStringKey {
        switch circumstances.kind {
        case .total:     return "TOTAL"
        case .annular:   return "ANNULAR"
        case .partial:   return "PARTIAL"
        case .hybrid:    return "HYBRID"
        case .simulated: return "SIMULATION"
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d m %02d s", s / 60, s % 60)
    }
}
