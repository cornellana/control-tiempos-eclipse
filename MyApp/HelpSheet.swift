/// HelpSheet.swift — Quick reference for solar eclipse concepts.
///
/// Accessible via the ⓘ button on the eclipse card (Step 3).
/// Explains contact points, measurements and eclipse types with a visual timeline.
///
/// All labels use `LocalizedStringKey` so that the in-app language selector
/// (injected via `.environment(\.locale, ...)`) is respected at runtime.

import SwiftUI

struct HelpSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        EclipseTimelineDiagram()
                        contactsSection
                        Divider().overlay(Color.gold.opacity(0.25))
                        measurementsSection
                        Divider().overlay(Color.gold.opacity(0.25))
                        typesSection
                    }
                    .padding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(Text("Eclipse Concepts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                        .foregroundStyle(Color.gold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Contact points

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Contact Points")
            row(tag: "C1", tagColor: .white,
                title: "First external contact",
                body:  "The Moon's outer limb first touches the Sun's outer limb. The eclipse begins. A solar filter is required from this moment on.")
            row(tag: "C2", tagColor: Color.gold,
                title: "Second contact — totality begins",
                body:  "The Moon is now fully in front of the Sun. Totality (or annularity) begins. Filters off for totality only.")
            row(tag: "MAX", tagColor: Color.gold,
                title: "Maximum eclipse",
                body:  "The Moon's centre is closest to the Sun's centre. Greatest coverage of the solar disk.")
            row(tag: "C3", tagColor: Color.gold,
                title: "Third contact — totality ends",
                body:  "The Moon starts to exit the solar disk. Replace filters immediately at this contact.")
            row(tag: "C4", tagColor: .white,
                title: "Fourth external contact",
                body:  "The Moon's outer limb leaves the Sun. The eclipse is completely over.")
        }
    }

    // MARK: - Measurements

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Measurements")
            row(tag: "mag", tagColor: Color.gray,
                title: "Magnitude",
                body:  "Fraction of the solar diameter covered at maximum. For total eclipses it exceeds 1.0 because the Moon appears larger than the Sun. The Raimat 2026 eclipse (only ~30 s of totality) has a magnitude barely above 1.0.")
            row(tag: "%", tagColor: Color.gold,
                title: "Coverage (area)",
                body:  "Fraction of the solar disk area covered, expressed as a percentage. 100% for totals, ~7% for annular eclipses (k² where k ≈ 0.27), and a variable value for partials. More intuitive than magnitude for judging how dark it will get.")
        }
    }

    // MARK: - Eclipse types

    private var typesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Eclipse Types")
            row(tag: "TOT", tagColor: Color.gold,
                title: "Total",
                body:  "The Moon completely covers the Sun. The solar corona becomes visible. Observer must be within the narrow path of totality (typically 100–200 km wide).")
            row(tag: "ANN", tagColor: .orange,
                title: "Annular",
                body:  "The Moon is near apogee and appears smaller than the Sun, leaving a bright ring of sunlight. Solar filters are required at all times — there is no totality.")
            row(tag: "PAR", tagColor: Color.gray,
                title: "Partial",
                body:  "The observer is in the penumbra (outside the path of totality). The Moon covers only part of the solar disk. Always use a certified solar filter.")
            row(tag: "HYB", tagColor: .purple,
                title: "Hybrid",
                body:  "Some locations along the path see totality while others see an annular eclipse. This occurs because Earth's curved surface moves some observers slightly closer to the Moon. Rare.")
        }
    }

    // MARK: - Reusable subviews

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.gold)
    }

    private func row(tag: String, tagColor: Color, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(tag)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(tagColor)
                .frame(width: 34, alignment: .center)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(tagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - EclipseTimelineDiagram

/// Canvas diagram showing the five contact points of a solar eclipse.
/// Not to scale: k_visual ≈ 0.42 (lunar radius enlarged for readability).
private struct EclipseTimelineDiagram: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eclipse Timeline (not to scale)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Canvas { context, size in
                let cx    = size.width / 2
                let cy    = size.height / 2
                let sunR  = size.height * 0.40     // solar radius (visual)
                let moonR = sunR * 0.42             // lunar radius (visual, ~k_visual)
                let pathY = cy + sunR * 0.18        // Moon path slightly below centre

                // ── Sun ─────────────────────────────────────────────────────
                let sunRect = CGRect(x: cx - sunR, y: cy - sunR,
                                     width: sunR * 2, height: sunR * 2)
                context.fill(Path(ellipseIn: sunRect),
                             with: .color(Color.gold.opacity(0.10)))
                context.stroke(Path(ellipseIn: sunRect),
                               with: .color(Color.gold.opacity(0.65)),
                               lineWidth: 1.5)

                // ── Moon path (dashed) ───────────────────────────────────────
                var dashLine = Path()
                dashLine.move(to:    CGPoint(x: 6, y: pathY))
                dashLine.addLine(to: CGPoint(x: size.width - 6, y: pathY))
                context.stroke(dashLine,
                               with: .color(Color.secondary.opacity(0.30)),
                               style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                // ── Moon at each contact ─────────────────────────────────────
                // Positions derived from standard contact geometry (solar radii):
                //   C1 / C4: Moon centre at ±(sunR + moonR) from Sun centre
                //   C2 / C3: Moon centre at ±(sunR − moonR) from Sun centre
                //   MAX:     Moon centre at 0
                let contacts: [(String, CGFloat, Bool)] = [
                    ("C1",  cx - (sunR + moonR), false),
                    ("C2",  cx - (sunR - moonR), true ),
                    ("MAX", cx,                   true ),
                    ("C3",  cx + (sunR - moonR), true ),
                    ("C4",  cx + (sunR + moonR), false),
                ]

                for (label, moonX, isInside) in contacts {
                    let moonRect = CGRect(x: moonX - moonR, y: pathY - moonR,
                                         width: moonR * 2, height: moonR * 2)
                    // Lunar disk
                    let fillGray: CGFloat = isInside ? 0.12 : 0.30
                    context.fill(Path(ellipseIn: moonRect),
                                 with: .color(Color(white: fillGray)))
                    context.stroke(Path(ellipseIn: moonRect),
                                   with: .color(Color.secondary.opacity(0.65)),
                                   lineWidth: 1.0)

                    // Label below the Moon
                    let labelStyle = isInside ? Color.gold : Color.gray
                    let labelText  = Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(labelStyle)
                    context.draw(labelText,
                                 at: CGPoint(x: moonX, y: pathY + moonR + 9),
                                 anchor: .center)
                }
            }
            .frame(height: 110)
        }
        .padding(12)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}
