/// EclipseCardView.swift — Displays computed local eclipse circumstances.
///
/// Shows contact times (in the device timezone), magnitude, totality duration,
/// and solar position at maximum. Adapts to partial eclipses (no C2/C3).
///
/// When `xjubierURL` is non-nil a verification button appears between the
/// kind badge and the contact times, opening xjubier.free.fr in Safari.
///
/// All labels use `LocalizedStringKey` so that the in-app language selector
/// (injected via `.environment(\.locale, ...)`) is respected at runtime.

import SwiftUI

struct EclipseCardView: View {

    let circumstances: EclipseCircumstances

    /// When non-nil, a "Verify on xjubier" button is shown between the
    /// eclipse-type badge and the contact times grid.
    var xjubierURL: URL? = nil

    @Environment(\.openURL) private var openURL
    @State private var showHelp = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            kindBadge
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

            // Botón xjubier — centrado entre el badge de tipo y la magnitud.
            if let url = xjubierURL {
                Button { openURL(url) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("xjubier.free.fr")
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
                .tourCard(TourContent.step(5))
            }

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
